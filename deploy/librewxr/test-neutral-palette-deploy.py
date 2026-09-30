#!/usr/bin/env python3
"""Offline controller fault injection: real git patching, fake Docker and health.

Run with Python 3. No Docker daemon, network or production credentials are used.
Hunk-context fixtures deliberately mock compilation; the companion palette
regression validates real complete source with NumPy/Pillow separately.
"""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
FILES = ('colors/schemes.py', 'tiles/renderer.py')
OLD = 'sha256:' + '1' * 64
NEW = 'sha256:' + '2' * 64
IMAGE = 'librewxr-librewxr'
PACKAGE = '/usr/local/lib/python3.12/site-packages/librewxr'
RELEASE = '20260930T210000Z-123'
PATCH = HERE / 'chetiwa-neutral-rain-palette.patch'


def fixtures(patch):
    result, name, hunks = {}, None, None
    for line in patch.splitlines(keepends=True):
        if line.startswith('--- a/src/librewxr/'):
            name = line.strip().removeprefix('--- a/src/librewxr/')
            hunks = result[name] = []
        elif line.startswith('@@'):
            hunks.append('')
        elif name and not line.startswith('+++') and hunks and line[:1] in (' ', '-'):
            hunks[-1] += line[1:]
    return {name: '\n'.join(hunks) for name, hunks in result.items()}


def mock_tool(tool, args):
    if tool == 'python3':
        if args[0] == '-':
            return 0  # Full-module compilation is tested in the companion suite.
        os.execv(sys.executable, [sys.executable, *args])
    state_path = Path(os.environ['PALETTE_TEST_STATE'])
    state = json.loads(state_path.read_text())
    state['events'].append([tool, *args])
    status, output = 0, ''
    if tool == 'curl':
        if state['mode'] == 'health-failure' and state['running'] == NEW:
            status = 22
        else:
            output = '{"radar":{"past":[{"time":1,"path":"/frame"}]}}'
    elif tool == 'sleep':
        pass
    elif tool == 'docker':
        if args[0] == 'compose':
            command = args[args.index('single') + 1:]
            if command == ['config', '--quiet']:
                pass
            elif command == ['config', '--images']:
                output = 'other-image' if state['mode'] == 'wrong-topology' else IMAGE
            elif command == ['ps', '-q', 'librewxr']:
                output = 'radar-container'
            elif command == ['up', '-d', '--no-build', '--pull', 'never', '--no-deps', '--force-recreate', 'librewxr']:
                state['running'] = state['tags'][IMAGE]
                if state['mode'] == 'restart-failure' and state['running'] == NEW:
                    status = 13
            else:
                raise AssertionError(f'Unexpected Compose mutation: {command}')
        elif args[0] == 'inspect':
            output = {'{{.State.Running}}': 'true', '{{.Config.Image}}': IMAGE,
                      '{{.Image}}': state['running']}[args[2]]
        elif args[:2] == ['image', 'tag']:
            if state['mode'] == 'retag-failure' and args[2:4] == [NEW, IMAGE]:
                status = 15
            else:
                state['tags'][args[3]] = state['tags'].get(args[2], args[2])
        elif args[:2] == ['image', 'inspect']:
            output = state['tags'][args[-1]]
        elif args[0] == 'exec':
            if args[2] == 'python':
                output = PACKAGE if 'find_spec' in args[-1] else 'a' * 64
            elif args[2] == 'sha256sum':
                name = next(name for name in FILES if args[3].endswith('/' + name))
                content = state['original' if state['running'] == OLD else 'candidate'][name]
                if args[3] == state.get('mismatch'):
                    content += '# unrelated image edit\n'
                output = hashlib.sha256(content.encode()).hexdigest() + '  ' + args[3]
            else:
                raise AssertionError(args)
        elif args[0] == 'build':
            assert '--pull=false' in args and '--network=none' in args
            dockerfile = Path(args[-1], 'Dockerfile').read_text().splitlines()
            base = dockerfile[0].split()[1]
            assert base.startswith('chetiwa-librewxr-palette-rollback:')
            assert state['tags'][base] == OLD  # Even if original mutable tag is stale.
            assert dockerfile[1:] == [f'COPY {name} {root}/{name}'
                                     for name in FILES for root in ('/app/src/librewxr', PACKAGE)]
            if state['mode'] == 'build-failure':
                status = 8
            elif state['mode'] == 'signal':
                os.kill(os.getppid(), signal.SIGTERM)
                status = 143
            else:
                state['tags'][args[args.index('--tag') + 1]] = NEW
                state['candidate'] = {name: Path(args[-1], name).read_text() for name in FILES}
        elif args[0] == 'run':
            assert args[1:7] == ['--rm', '--network', 'none', '--entrypoint', 'python', NEW]
            assert args[-4] == PACKAGE and args[-1] == 'a' * 64
            for name, digest in zip(FILES, args[-3:-1]):
                assert hashlib.sha256(state['candidate'][name].encode()).hexdigest() == digest
            if state['mode'] == 'candidate-validation-failure':
                status = 17
        else:
            raise AssertionError(args)
    else:
        raise AssertionError(tool)
    state_path.write_text(json.dumps(state))
    if output:
        print(output)
    return status


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='neutral-palette-deploy-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.remote = self.root / 'librewxr'
        self.original = fixtures(PATCH.read_text())
        self.sources = {name: self.remote / 'src/librewxr' / name for name in FILES}
        for name, source in self.sources.items():
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(self.original[name])
            source.chmod(0o640)
        self.stage = self.root / 'staging'
        self.stage.mkdir()
        (self.stage / 'patch.diff').write_bytes(PATCH.read_bytes())
        self.preserved = {'.env': '# existing region/frame/resource settings\n',
                          'docker-compose.yml': 'services: {}\n',
                          'src/librewxr/other-module.py': '# keep all other modules\n'}
        for name, content in self.preserved.items():
            (self.remote / name).write_text(content)
        subprocess.run(['git', 'init', '-q', str(self.remote)], check=True)
        self.state_file = self.root / 'state.json'
        self.state_file.write_text(json.dumps({'mode': 'success', 'tags': {IMAGE: OLD},
                                             'running': OLD, 'original': self.original, 'events': []}))
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for tool in ('docker', 'curl', 'sleep', 'python3'):
            shim = self.bin / tool
            shim.write_text('#!' + sys.executable + '\nimport runpy,sys\n'
                           + 'sys.argv=[' + repr(str(Path(__file__).resolve())) + ', "--mock", '
                           + repr(tool) + '] + sys.argv[1:]\n'
                           + 'runpy.run_path(sys.argv[0],run_name="__main__")\n')
            shim.chmod(0o755)
        script = (HERE / 'deploy-neutral-rain-palette.sh').read_text()
        self.remote_script = script.split("<<'REMOTE_PALETTE_DEPLOY'\n", 1)[1].split('\nREMOTE_PALETTE_DEPLOY', 1)[0]
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        PALETTE_TEST_STATE=str(self.state_file))

    def state(self):
        return json.loads(self.state_file.read_text())

    def run_deploy(self, mode='success'):
        state = self.state()
        state['mode'] = mode
        self.state_file.write_text(json.dumps(state))
        result = subprocess.run(['bash', '-s', '--', str(self.remote), str(self.stage), RELEASE, '2'],
                                input=self.remote_script, text=True, env=self.env, capture_output=True, timeout=30)
        for name, content in self.preserved.items():
            self.assertEqual((self.remote / name).read_text(), content)
        return result

    def mutations(self):
        return [e for e in self.state()['events'] if e[:2] in (['docker', 'build'], ['docker', 'image']) or 'up' in e]

    def assert_rollback(self, result, restarts=0):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        for name, source in self.sources.items():
            self.assertEqual(source.read_text(), self.original[name])
            self.assertEqual(source.stat().st_mode & 0o777, 0o640)
            backup = self.root / 'librewxr-palette-backups' / RELEASE / name
            self.assertEqual(backup.read_text(), self.original[name])
            self.assertEqual(backup.stat().st_mode & 0o777, 0o640)
        self.assertEqual((self.root / 'librewxr-palette-backups' / RELEASE).stat().st_mode & 0o777, 0o700)
        state = self.state()
        self.assertEqual(state['running'], OLD)
        self.assertEqual(state['tags'][IMAGE], OLD)
        self.assertFalse((self.remote / '.chetiwa-coordinate-deploy.lock').exists())
        self.assertEqual(sum('up' in e for e in state['events']), restarts)
        self.assertEqual(result.stderr.count('restoring the exact previous'), 1)

    def test_success_and_idempotence(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.state()['running'], NEW)
        for name, source in self.sources.items():
            self.assertNotEqual(source.read_text(), self.original[name])
        before = len(self.state()['events'])
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('no build or restart', result.stdout)
        self.assertFalse(any(e[:2] == ['docker', 'build'] or 'up' in e for e in self.state()['events'][before:]))

    def test_build_failure(self):
        self.assert_rollback(self.run_deploy('build-failure'))

    def test_health_failure(self):
        self.assert_rollback(self.run_deploy('health-failure'), 2)

    def test_partial_restart_failure(self):
        self.assert_rollback(self.run_deploy('restart-failure'), 2)

    def test_signal(self):
        self.assert_rollback(self.run_deploy('signal'))

    def test_candidate_validation_failure(self):
        self.assert_rollback(self.run_deploy('candidate-validation-failure'))

    def test_retag_failure(self):
        self.assert_rollback(self.run_deploy('retag-failure'))

    def test_stale_image_tag_rollback_restores_running_id(self):
        state = self.state()
        state['tags'][IMAGE] = 'sha256:' + '3' * 64
        self.state_file.write_text(json.dumps(state))
        self.assert_rollback(self.run_deploy('health-failure'), 2)

    def test_mismatched_source_refused(self):
        for name, source in self.sources.items():
            with self.subTest(name=name):
                source.write_text(self.original[name] + '# unrelated edit\n')
                result = self.run_deploy()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Source and running image differ', result.stderr)
                self.assertEqual(self.mutations(), [])
                source.write_text(self.original[name])

    def test_mismatched_installed_and_image_source_copies_refused(self):
        for name in FILES:
            for root in (PACKAGE, '/app/src/librewxr'):
                with self.subTest(name=name, root=root):
                    state = self.state()
                    state['mismatch'] = root + '/' + name
                    self.state_file.write_text(json.dumps(state))
                    result = self.run_deploy()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('Source and running image differ', result.stderr)
                    self.assertEqual(self.mutations(), [])

    def test_existing_coordinate_lock_refused(self):
        (self.remote / '.chetiwa-coordinate-deploy.lock').mkdir()
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state()['events'], [])
        self.assertTrue((self.remote / '.chetiwa-coordinate-deploy.lock').exists())

    def test_wrong_topology_refused(self):
        self.assertNotEqual(self.run_deploy('wrong-topology').returncode, 0)
        self.assertEqual(self.mutations(), [])

    def test_missing_crisp_prerequisite_refused(self):
        name = FILES[1]
        self.original[name] = self.original[name].replace('if color_scheme != 14:', 'if color_scheme != 13:')
        self.sources[name].write_text(self.original[name])
        state = self.state()
        state['original'] = self.original
        self.state_file.write_text(json.dumps(state))
        self.assertNotEqual(self.run_deploy().returncode, 0)
        self.assertEqual(self.mutations(), [])
        self.assertEqual(self.sources[name].read_text(), self.original[name])


class ReplayOrderTests(unittest.TestCase):
    def test_full_profile_stages_applies_and_rolls_back_neutral_in_order(self):
        script = (HERE / 'deploy-production-profile.sh').read_text()
        self.assertIn('"$script_dir/chetiwa-neutral-rain-palette.patch"', script)
        rollback = script.split('rollback() {', 1)[1].split('trap rollback', 1)[0]
        for earlier in ('chetiwa-crisp-presentation.patch', 'chetiwa-crisp-palette-upgrade.patch',
                        'chetiwa-visible-light-rain-palette.patch'):
            self.assertLess(rollback.index(PATCH.name), rollback.index(earlier))
        apply = script.split('trap rollback', 1)[1]
        self.assertLess(apply.index('chetiwa-visible-light-rain-palette.patch'), apply.index(PATCH.name))
        self.assertIn("apply -R --check '$staging_dir/chetiwa-neutral-rain-palette.patch'", apply)

    def test_bootstrap_applies_after_crisp(self):
        script = (HERE / 'install-on-hetzner.sh').read_text()
        self.assertLess(script.index('chetiwa-crisp-palette-upgrade.patch'), script.index(PATCH.name))


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--mock':
        sys.exit(mock_tool(sys.argv[2], sys.argv[3:]))
    unittest.main()
