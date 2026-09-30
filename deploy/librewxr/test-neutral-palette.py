#!/usr/bin/env python3
"""Palette/presentation regression against complete saved LibreWXR source.

Requires NumPy and Pillow in an existing runtime (do not install on the host).
By default reads the Sept 30 audit snapshots; override with --source-root and
--candidate-root. No server requests occur. Git patch/reverse checks run when
git is installed; isolated Linux image runs all numerical/presentation tests.
"""
import argparse
import ast
import hashlib
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import types
import unittest

import numpy as np
from PIL import Image, ImageFilter

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=REPO / 'tmp/radar-accuracy-2026-09-30/live-source')
parser.add_argument('--candidate-root', type=Path, default=REPO / 'tmp/radar-accuracy-2026-09-30/neutral-palette/candidate')
args, remaining = parser.parse_known_args()
sys.argv = [sys.argv[0], *remaining]
FILES = ('colors/schemes.py', 'tiles/renderer.py')
OLD = {name: (args.source_root / name).read_text() for name in FILES}
NEW = {name: (args.candidate_root / name).read_text() for name in FILES}
COLORS = [(0, 0, 0, 0), (216, 220, 222, 90), (185, 190, 193, 125),
          (135, 142, 146, 160), (83, 91, 95, 190), (225, 155, 152, 195),
          (214, 91, 85, 215), (188, 38, 32, 230), (132, 0, 0, 240)]
EXPECTED = np.repeat(np.array(COLORS, dtype=np.uint8), [73, 12, 12, 12, 12, 12, 12, 20, 91], axis=0)
# A deterministic CSV tests the actual loader, column mapping and snow handling
# without requiring or replacing the bundled upstream color_table.csv.
CSV = 'dbz,' + ','.join('scheme' + str(i) for i in range(17)) + '\n' + '\n'.join(
    str(row) + ',' + ','.join('#%02x%02x%02x%02x' %
        ((row + col) % 256, (row * 3 + col) % 256, (row + col * 5) % 256, (row * 7) % 256)
        for col in range(17)) for row in range(256))


def module(source):
    mod = types.ModuleType('palette_validation')
    exec(compile(source, '<full-schemes-source>', 'exec'), mod.__dict__)
    mod.files = lambda package: types.SimpleNamespace(joinpath=lambda name: types.SimpleNamespace(read_text=lambda: CSV))
    return mod


def function_asts(source):
    return {node.name: ast.dump(node, include_attributes=False) for node in ast.parse(source).body
            if isinstance(node, (ast.FunctionDef, ast.ClassDef))}


def renderer(source, schemes):
    selected = [node for node in ast.parse(source).body
                if isinstance(node, ast.FunctionDef) and node.name in ('present_tile', '_encode_image', '_transparent_tile')]
    # Execute the real PNG encoder from the same complete saved source.
    png_module = types.ModuleType('png_validation')
    exec(compile((args.source_root / 'tiles/png_palette.py').read_text(), '<png-source>', 'exec'), png_module.__dict__)
    namespace = dict(np=np, Image=Image, ImageFilter=ImageFilter, io=io,
                     colorize=schemes.colorize, encode_png=png_module.encode_png,
                     settings=types.SimpleNamespace(webp_quality=100), _TRANSPARENT_TILE_BYTES={})
    tree = ast.Module(body=[ast.ImportFrom(module='__future__', names=[ast.alias(name='annotations')], level=0), *selected], type_ignores=[])
    exec(compile(ast.fix_missing_locations(tree), '<actual-present-functions>', 'exec'), namespace)
    return namespace['present_tile']


def geometry(values, *, pad=0, blur=0, snow=False):
    values = np.array(values, dtype=np.uint8)
    values.flags.writeable = False
    mask = np.indices(values.shape).sum(axis=0) % 2 == 0 if snow else None
    if mask is not None:
        mask.flags.writeable = False
    return types.SimpleNamespace(values=values, snow_mask=mask, tile_size=values.shape[0] - pad * 2,
                                 pad=pad, blur_radius=blur, is_transparent=False)


def pixels(output):
    with Image.open(io.BytesIO(output)) as image:
        return np.asarray(image.convert('RGBA'))


class PaletteRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old = module(OLD[FILES[0]])
        cls.new = module(NEW[FILES[0]])
        cls.old_render = staticmethod(renderer(OLD[FILES[1]], cls.old))
        cls.new_render = staticmethod(renderer(NEW[FILES[1]], cls.new))

    def test_all_256_rain_and_snow_entries(self):
        for snow in (False, True):
            actual = self.new.get_lut(15, snow=snow)
            self.assertEqual(actual.dtype, np.uint8)
            np.testing.assert_array_equal(actual, EXPECTED)

    def test_alpha_increases_and_red_starts_above_28_dbz(self):
        lut = self.new.get_lut(15)
        self.assertTrue(np.all(np.diff(lut[:, 3].astype(int)) >= 0))
        self.assertTrue(np.all(lut[:73, 3] == 0))
        self.assertTrue(np.all(lut[73:121, 0] < lut[73:121, 1]))
        self.assertTrue(np.all(lut[121:, 0] > lut[121:, 1]))

    def test_all_legacy_256_entry_luts_unchanged(self):
        for scheme in (*range(15), 255):
            for snow in (False, True):
                with self.subTest(scheme=scheme, snow=snow):
                    np.testing.assert_array_equal(self.old.get_lut(scheme, snow=snow), self.new.get_lut(scheme, snow=snow))

    def test_raw_data_and_raw_palette_unchanged(self):
        values = np.arange(256, dtype=np.uint8).reshape(16, 16)
        values.flags.writeable = False
        before = values.tobytes()
        for snow in (False, True):
            np.testing.assert_array_equal(self.new.colorize(values, 15, snow=snow), EXPECTED[values])
            np.testing.assert_array_equal(self.old.colorize(values, 255, snow=snow), self.new.colorize(values, 255, snow=snow))
        self.assertEqual(values.tobytes(), before)

    def test_prior_neutral_crisp_function_restored_under_new_id(self):
        original_patch = (HERE / 'chetiwa-crisp-palette-upgrade.patch').read_text()
        added = ''.join(line[1:] for line in original_patch.splitlines(keepends=True)
                        if line.startswith('+') and not line.startswith('+++'))
        historical = added.split('    new_rain[14] =', 1)[0].replace('def _chetiwa_crisp_lut(', 'def _chetiwa_neutral_lut(')
        self.assertEqual(function_asts(historical)['_chetiwa_neutral_lut'], function_asts(NEW[FILES[0]])['_chetiwa_neutral_lut'])

    def test_only_expected_source_changes(self):
        for name in FILES:
            compile(NEW[name], name, 'exec')
        old = function_asts(OLD[FILES[0]])
        new = function_asts(NEW[FILES[0]])
        self.assertEqual(set(new) - set(old), {'_chetiwa_neutral_lut'})
        for name in old.keys() - {'_load_color_table'}:
            self.assertEqual(old[name], new[name], name)
        expected_renderer = OLD[FILES[1]].replace(
            '# Scheme 14 keeps the geometry\'s bilinear sampling but deliberately skips',
            '# Schemes 14/15 keep the geometry\'s bilinear sampling but deliberately skip').replace(
            'if color_scheme != 14:', 'if color_scheme not in (14, 15):')
        self.assertEqual(NEW[FILES[1]], expected_renderer)

    def test_all_legacy_rendered_pixels_unchanged(self):
        for scheme in (*range(15), 255):
            for snow in (False, True):
                for pad, blur in ((0, 0), (0, 0.49), (2, 0.5), (2, 2.0)):
                    with self.subTest(scheme=scheme, snow=snow, pad=pad, blur=blur):
                        geom = geometry(np.arange(400).reshape(20, 20) % 256, pad=pad, blur=blur, snow=snow)
                        before = geom.values.tobytes()
                        np.testing.assert_array_equal(pixels(self.old_render(geom, scheme, 'png')),
                                                      pixels(self.new_render(geom, scheme, 'png')))
                        self.assertEqual(geom.values.tobytes(), before)

    def test_neutral_is_exact_lut_without_post_color_blur_and_preserves_crop(self):
        for snow in (False, True):
            for pad, blur in ((0, 0), (0, 0.49), (2, 0.5), (2, 2.0)):
                with self.subTest(snow=snow, pad=pad, blur=blur):
                    geom = geometry(np.arange(400).reshape(20, 20) % 256, pad=pad, blur=blur, snow=snow)
                    expected = EXPECTED[geom.values]
                    if pad:
                        expected = expected[pad:-pad, pad:-pad]
                    np.testing.assert_array_equal(pixels(self.new_render(geom, 15, 'png')), expected)

    def test_other_palette_still_receives_gaussian_blur(self):
        geom = geometry(np.indices((20, 20)).sum(axis=0) % 2 * 200, blur=2)
        for scheme in (7, 13, 255):
            self.assertFalse(np.array_equal(pixels(self.new_render(geom, scheme, 'png')), self.new.colorize(geom.values, scheme)))

    def test_transparent_and_lossless_webp_paths(self):
        geom = geometry(np.arange(256).reshape(16, 16))
        np.testing.assert_array_equal(pixels(self.new_render(geom, 15, 'webp'))[..., 3], EXPECTED[geom.values][..., 3])
        geom.is_transparent = True
        for fmt in ('png', 'webp'):
            self.assertTrue(np.all(pixels(self.new_render(geom, 15, fmt)) == 0))

    @unittest.skipUnless(shutil.which('git'), 'git unavailable in isolated image; host validates full patch/reverse')
    def test_patch_applies_reverses_both_warm_and_neutral_legacy_14(self):
        for variant in ('warm', 'neutral'):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory(prefix='neutral-full-source-') as directory:
                root = Path(directory)
                subprocess.run(['git', 'init', '-q', directory], check=True)
                for name in FILES:
                    target = root / 'src/librewxr' / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(OLD[name])
                git = ['git', '-C', directory, 'apply']
                if variant == 'neutral':
                    subprocess.run([*git, '-R', '--include=src/librewxr/colors/schemes.py',
                                    str(HERE / 'chetiwa-visible-light-rain-palette.patch')], check=True)
                original = {name: (root / 'src/librewxr' / name).read_bytes() for name in FILES}
                baseline = module(original[FILES[0]])
                patch = str(HERE / 'chetiwa-neutral-rain-palette.patch')
                for options in (('--check',), (), ('-R', '--check')):
                    subprocess.run([*git, *options, patch], check=True)
                patched = module((root / 'src/librewxr' / FILES[0]).read_bytes())
                for scheme in (*range(15), 255):
                    for snow in (False, True):
                        np.testing.assert_array_equal(baseline.get_lut(scheme, snow=snow), patched.get_lut(scheme, snow=snow))
                for name in FILES:
                    content = (root / 'src/librewxr' / name).read_bytes()
                    compile(content, name, 'exec')
                    if variant == 'warm':
                        self.assertEqual(content.decode(), NEW[name])
                np.testing.assert_array_equal(patched.get_lut(15), EXPECTED)
                subprocess.run([*git, '-R', patch], check=True)
                for name in FILES:
                    self.assertEqual((root / 'src/librewxr' / name).read_bytes(), original[name])


if __name__ == '__main__':
    for name in FILES:
        print(name, 'baseline', hashlib.sha256(OLD[name].encode()).hexdigest(),
              'candidate', hashlib.sha256(NEW[name].encode()).hexdigest(), flush=True)
    print('NumPy', np.__version__, 'Pillow', Image.__version__, flush=True)
    unittest.main()
