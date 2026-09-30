#!/usr/bin/env python3
"""Exercise the remote deployment controller with real patching and fake Docker.

Run: python3 deploy/librewxr/test-coordinate-deploy.py
No network, Docker daemon or production credentials are used. The tiny source
fixture reconstructs patch contexts; compile subprocesses are mocked because
numerical correctness/compilation are validated separately against full source.
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
OLD = 'sha256:' + '1' * 64
NEW = 'sha256:' + '2' * 64
IMAGE = 'librewxr-librewxr'
PACKAGE = '/usr/local/lib/python3.12/site-packages/librewxr/data/nowcast.py'
VARIANTS = ('float32', 'sparse', 'chunked', 'row-clamp')
PATCHES = dict(zip(VARIANTS, ('chetiwa-float32-coordinate-grids.patch',
                            'chetiwa-sparse-coordinate-grids.patch',
                            'chetiwa-chunked-nowcast-remap.patch',
                            'chetiwa-row-clamp-nowcast.patch')))


def original_hunks(patch):
    hunks = []
    for line in patch.splitlines(keepends=True):
        if line.startswith('@@'):
            hunks.append('')
        elif hunks and line[:1] in (' ', '-'):
            hunks[-1] += line[1:]
    return hunks


def mock_tool(tool, args):
    # This process shares a pipeline with curl; it must not rewrite the mock
    # Docker state concurrently. Delegate health JSON parsing to real Python.
    if tool == 'python3':
        if args[0] == '-':
            return 0
        os.execv(sys.executable, [sys.executable, *args])
    state_path = Path(os.environ['COORDINATE_TEST_STATE'])
    state = json.loads(state_path.read_text())
    state['events'].append([tool, *args])
    status = 0
    output = ''
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
                output = IMAGE
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
            if state['mode'] == 'retag-failure' and args[3] == IMAGE and args[2].startswith('chetiwa-librewxr-coordinate:'):
                status = 15
            else:
                state['tags'][args[3]] = state['tags'].get(args[2], args[2])
        elif args[:2] == ['image', 'inspect']:
            output = state['tags'][args[-1]]
        elif args[0] == 'exec':
            if args[2] == 'python':
                output = PACKAGE
            elif args[2] == 'sha256sum':
                content = state['original'] if state['running'] == OLD else state['candidate']
                output = hashlib.sha256(content.encode()).hexdigest() + '  ' + args[3]
            else:
                raise AssertionError(args)
        elif args[0] == 'build':
            assert '--pull=false' in args and '--network=none' in args
            dockerfile = Path(args[-1], 'Dockerfile').read_text().splitlines()
            assert state['tags'][dockerfile[0].split()[1]] == OLD
            assert len(dockerfile) == 3 and all(line.startswith('COPY nowcast.py ') for line in dockerfile[1:])
            assert PACKAGE in dockerfile[-1]
            if state['mode'] == 'build-failure':
                status = 8
            elif state['mode'] == 'signal':
                os.kill(os.getppid(), signal.SIGTERM)
                status = 143
            else:
                state['tags'][args[args.index('--tag') + 1]] = NEW
                state['candidate'] = Path(args[-1], 'nowcast.py').read_text()
        elif args[0] == 'run':
            assert args[1:6] == ['--rm', '--network', 'none', '--entrypoint', 'python']
            assert hashlib.sha256(state['candidate'].encode()).hexdigest() == args[-1]
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
    variant = 'float32'

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='coordinate-deploy-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.remote = self.root / 'librewxr'
        self.source = self.remote / 'src/librewxr/data/nowcast.py'
        self.source.parent.mkdir(parents=True)
        self.stage = self.root / 'staging'
        self.stage.mkdir()
        patch = (HERE / 'chetiwa-float32-coordinate-grids.patch').read_text()
        # Real git applies all original hunk contexts; no production source is
        # required by the harness and no image build is actually executed.
        float_hunks = original_hunks(patch)
        chunked_patch = (HERE / 'chetiwa-chunked-nowcast-remap.patch').read_text()
        chunk_hunks = original_hunks(chunked_patch)
        row_patch = (HERE / PATCHES['row-clamp']).read_text()
        row_hunks = original_hunks(row_patch)
        marker = '    map_y = ys - steps * flow[..., 1]\n'
        remap_tail = chunk_hunks[-1].split(marker, 1)[1]
        # The first two row-clamp hunks precede the old remap context. Preserve
        # their actual docstring and upscale/clamp lines, not marker comments.
        self.original = '\n'.join([chunk_hunks[0], *float_hunks[:-1],
                                   *row_hunks[:2], float_hunks[-1].rstrip()]) + '\n' + remap_tail
        self.source.write_text(self.original)
        self.source.chmod(0o640)
        (self.remote / 'docker-compose.yml').write_text('services: {}\n')
        (self.remote / '.env').write_text('# existing resource/region/frame settings\nKEEP_EXISTING_PROFILE=1\n')
        self.runtime_config = {name: (self.remote / name).read_bytes()
                               for name in ('.env', 'docker-compose.yml')}
        (self.stage / 'patch.diff').write_text(patch)
        (self.stage / 'sparse.diff').write_text((HERE / 'chetiwa-sparse-coordinate-grids.patch').read_text())
        (self.stage / 'chunked.diff').write_text(chunked_patch)
        (self.stage / 'row-clamp.diff').write_text(row_patch)
        subprocess.run(['git', 'init', '-q', str(self.remote)], check=True)
        for predecessor in VARIANTS[:VARIANTS.index(self.variant)]:
            subprocess.run(['git', '-C', str(self.remote), 'apply', str(HERE / PATCHES[predecessor])], check=True)
        self.original = self.source.read_text()
        (self.stage / 'patch.diff').write_text((HERE / PATCHES[self.variant]).read_text())
        self.source.chmod(0o640)
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
        script = (HERE / 'deploy-float32-coordinate-grids.sh').read_text()
        self.remote_script = script.split("<<'REMOTE_COORDINATE_DEPLOY'\n", 1)[1].split('\nREMOTE_COORDINATE_DEPLOY', 1)[0]
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        COORDINATE_TEST_STATE=str(self.state_file))

    def run_deploy(self, mode='success', variant=None):
        state = self.state()
        state['mode'] = mode
        self.state_file.write_text(json.dumps(state))
        result = subprocess.run(['bash', '-s', '--', str(self.remote), str(self.stage), '20260919T110000Z-123', '2', variant or self.variant],
                                input=self.remote_script, text=True, env=self.env, capture_output=True, timeout=30)
        for name, content in self.runtime_config.items():
            self.assertEqual((self.remote / name).read_bytes(), content)
        return result

    def state(self):
        return json.loads(self.state_file.read_text())

    def assert_rollback(self, result, *, restarts):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.source.read_text(), self.original)
        self.assertEqual(self.source.stat().st_mode & 0o777, 0o640)
        state = self.state()
        self.assertEqual(state['running'], OLD)
        self.assertEqual(state['tags'][IMAGE], OLD)
        self.assertFalse((self.remote / '.chetiwa-coordinate-deploy.lock').exists())
        up = [e for e in state['events'] if e[:2] == ['docker', 'compose'] and 'up' in e]
        self.assertEqual(len(up), restarts)
        self.assertEqual(result.stderr.count('restoring the exact previous'), 1)
        backup = self.root / 'librewxr-coordinate-backups/20260919T110000Z-123/nowcast.py'
        self.assertEqual(backup.read_text(), self.original)
        self.assertEqual(backup.stat().st_mode & 0o777, 0o640)

    def test_success_and_idempotence(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotEqual(self.source.read_text(), self.original)
        self.assertEqual(self.state()['running'], NEW)
        before = len(self.state()['events'])
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('no build or restart', result.stdout)
        new_events = self.state()['events'][before:]
        self.assertFalse(any(e[:2] == ['docker', 'build'] or 'up' in e for e in new_events))

    def test_build_failure_keeps_running_container(self):
        self.assert_rollback(self.run_deploy('build-failure'), restarts=0)

    def test_health_failure_restores_image_and_source(self):
        self.assert_rollback(self.run_deploy('health-failure'), restarts=2)

    def test_partial_restart_failure_restores_image_and_source(self):
        self.assert_rollback(self.run_deploy('restart-failure'), restarts=2)

    def test_signal_uses_single_exit_rollback(self):
        self.assert_rollback(self.run_deploy('signal'), restarts=0)

    def test_candidate_validation_failure_keeps_running_container(self):
        self.assert_rollback(self.run_deploy('candidate-validation-failure'), restarts=0)

    def test_retag_failure_keeps_running_container(self):
        self.assert_rollback(self.run_deploy('retag-failure'), restarts=0)

    def test_stale_image_tag_rollback_restores_running_image(self):
        state = self.state()
        state['tags'][IMAGE] = 'sha256:' + '3' * 64
        self.state_file.write_text(json.dumps(state))
        self.assert_rollback(self.run_deploy('health-failure'), restarts=2)

    def test_mismatched_source_refused_without_mutations(self):
        self.source.write_text(self.original + '# unrelated pending source edit\n')
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Source and running image differ', result.stderr)
        self.assertFalse(any(e[:2] == ['docker', 'build'] or 'up' in e for e in self.state()['events']))
        self.assertEqual(self.state()['running'], OLD)

    def test_existing_lock_refused(self):
        (self.remote / '.chetiwa-coordinate-deploy.lock').mkdir()
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state()['events'], [])
        self.assertTrue((self.remote / '.chetiwa-coordinate-deploy.lock').exists())

    def assert_installed_successor(self, controller, successor):
        for variant in VARIANTS[VARIANTS.index(self.variant):VARIANTS.index(successor) + 1]:
            subprocess.run(['git', '-C', str(self.remote), 'apply', str(HERE / PATCHES[variant])], check=True)
        (self.stage / 'patch.diff').write_text((HERE / PATCHES[controller]).read_text())
        self.original = self.source.read_text()
        state = self.state()
        state['original'] = self.original
        self.state_file.write_text(json.dumps(state))
        result = self.run_deploy(variant=controller)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('no build or restart', result.stdout)
        self.assertFalse(any(e[:2] == ['docker', 'build'] or 'up' in e for e in self.state()['events']))
        self.assertEqual(self.source.read_text(), self.original)

    def test_original_controller_accepts_installed_successor(self):
        self.assert_installed_successor('float32', VARIANTS[max(1, VARIANTS.index(self.variant))])

    def test_sparse_controller_accepts_installed_chunked_successor(self):
        self.assert_installed_successor('sparse', VARIANTS[max(2, VARIANTS.index(self.variant))])

    def test_chunked_controller_accepts_installed_row_clamp(self):
        self.assert_installed_successor('chunked', 'row-clamp')

    def test_original_controller_accepts_installed_row_clamp(self):
        self.assert_installed_successor('float32', 'row-clamp')

    def test_sparse_controller_accepts_installed_row_clamp(self):
        self.assert_installed_successor('sparse', 'row-clamp')


class SparseDeploymentTests(DeploymentTests):
    variant = 'sparse'


class ChunkedDeploymentTests(DeploymentTests):
    variant = 'chunked'


class RowClampDeploymentTests(DeploymentTests):
    variant = 'row-clamp'

    def test_missing_chunked_prerequisite_refused_without_mutation(self):
        subprocess.run(['git', '-C', str(self.remote), 'apply', '-R',
                        str(HERE / PATCHES['chunked'])], check=True)
        self.original = self.source.read_text()
        state = self.state()
        state['original'] = self.original
        self.state_file.write_text(json.dumps(state))
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.source.read_text(), self.original)
        self.assertEqual(self.state()['running'], OLD)
        self.assertFalse(any(e[:2] == ['docker', 'build'] or 'up' in e for e in self.state()['events']))


class FullSourcePatchTests(unittest.TestCase):
    def test_full_profile_rolls_back_coordinate_patches_in_reverse_order(self):
        script = (HERE / 'deploy-production-profile.sh').read_text()
        rollback = script.split('rollback() {', 1)[1].split('trap rollback', 1)[0]
        positions = [rollback.index(PATCHES[variant]) for variant in reversed(VARIANTS)]
        self.assertEqual(positions, sorted(positions))

    def test_validated_full_source_apply_compile_and_exact_reverse(self):
        source = HERE.parents[1] / 'tmp/production-audit/nowcast.chunked.py'
        if not source.exists():
            self.skipTest('Offline vendor snapshot is not present; controller fixture tests still run')
        original = source.read_bytes()
        self.assertEqual(hashlib.sha256(original).hexdigest(),
                         '6bf045f8af719232d0d76316654ee9b49592d91dfd8f22955e71d3bf1a5dc5c1')
        with tempfile.TemporaryDirectory(prefix='row-clamp-full-source-') as directory:
            root = Path(directory)
            target = root / 'src/librewxr/data/nowcast.py'
            target.parent.mkdir(parents=True)
            target.write_bytes(original)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            patch = str(HERE / PATCHES['row-clamp'])
            for options in [('--check',), (), ('-R', '--check')]:
                subprocess.run(['git', '-C', directory, 'apply', *options, patch], check=True)
            compile(target.read_bytes(), str(target), 'exec')
            subprocess.run(['git', '-C', directory, 'apply', '-R', patch], check=True)
            self.assertEqual(target.read_bytes(), original)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--mock':
        sys.exit(mock_tool(sys.argv[2], sys.argv[3:]))
    unittest.main()
