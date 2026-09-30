#!/usr/bin/env python3
"""Offline capacity-report regression tests; no Docker or network calls."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('capacity_check', Path(__file__).with_name('capacity-check.py'))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


def recording():
    start = 1800000000
    psi = {key: {'avg10': 0.0, 'total': 100} for key in ('some', 'full')}
    ident = {'id': 'container-a', 'image': 'image-a', 'pid': 12, 'started': 'start-a',
             'restarts': 0, 'running': True, 'dockerLimit': 5632 * check.MIB}
    samples = []
    for offset in range(0, 901, 10):
        newest = start if offset < 700 else start + 600
        samples.append({'type': 'sample', 'at': start + offset, 'monotonic': 10000 + offset,
                        'boot': 'boot-a', 'identity': copy.deepcopy(ident),
                        'memory': {'current': 2000 * check.MIB, 'max': 5632 * check.MIB,
                                   'peak': 2200 * check.MIB, 'swap.current': 50 * check.MIB,
                                   'events': {k: 10 for k in check.EVENT_KEYS},
                                   'pressure': copy.deepcopy(psi), 'ioPressure': copy.deepcopy(psi)},
                        'host': {'MemTotal': 7800 * check.MIB, 'MemAvailable': 2500 * check.MIB,
                                 'pswpin': 0, 'pswpout': 0, 'pressure': copy.deepcopy(psi)},
                        'frames': {'past': [newest - 1800 + n * 600 for n in range(4)],
                                   'nowcast': [newest + 600 + n * 600 for n in range(6)],
                                   'generated': start + (700 if offset >= 700 else 0)}})
    return [{'type': 'start', 'schema': 1, 'interval': 10}, *samples,
            {'type': 'phases', 'events': [{'at': start + offset, 'kind': kind} for kind, offset in
             [('ifs_start', 300), ('ifs_done', 500), ('nowcast_done', 650), ('refresh_done', 680)]]},
            {'type': 'complete'}]


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.rows = recording()

    def report(self):
        return check.assess(self.rows, 5632)

    def test_complete_clean_window_is_only_memory_pass(self):
        result = self.report()
        self.assertEqual(result['memoryScreen'], 'pass')
        self.assertFalse(result['productionReady'])

    def test_absolute_historical_events_do_not_count_as_new_pressure(self):
        self.assertEqual(self.report()['memoryEventsDelta']['max'], 0)

    def test_small_host_not_failed_by_prospective_upgrade_budget(self):
        for sample in self.rows[1:-2]:
            sample['memory']['max'] = 3072 * check.MIB
            sample['identity']['dockerLimit'] = 3072 * check.MIB
            sample['host']['MemTotal'] = 3814 * check.MIB
            sample['host']['MemAvailable'] = 800 * check.MIB
        result = check.assess(self.rows, 3072)
        self.assertEqual(result['memoryScreen'], 'pass')
        self.assertEqual(result['hostBudgetInformation']['remainingAfterLimitsMiB'], 358)

    def test_new_limit_events_fail_even_without_hourly_evidence(self):
        self.rows[-3]['memory']['events']['max'] += 1
        self.rows[-2]['events'] = []
        result = self.report()
        self.assertEqual(result['memoryScreen'], 'fail')
        self.assertTrue(result['missingCoverage'])

    def test_missing_hourly_refresh_is_not_a_pass(self):
        self.rows[-2]['events'] = []
        self.assertEqual(self.report()['memoryScreen'], 'incomplete')

    def test_missing_completion_is_rejected(self):
        self.rows.pop()
        with self.assertRaises(ValueError):
            self.report()

    def test_restart_cannot_erase_previous_pressure(self):
        self.rows[-3]['identity']['restarts'] = 1
        with self.assertRaisesRegex(ValueError, 'changed'):
            self.report()

    def test_counter_reset_is_rejected(self):
        self.rows[-3]['memory']['events']['max'] = 0
        with self.assertRaisesRegex(ValueError, 'reset'):
            self.report()

    def test_missing_measurement_is_rejected(self):
        del self.rows[2]['memory']['pressure']['some']['total']
        with self.assertRaises(KeyError):
            self.report()

    def test_sparse_samples_are_rejected(self):
        del self.rows[5:15]
        with self.assertRaisesRegex(ValueError, 'Gap'):
            self.report()

    def test_clock_jump_is_rejected(self):
        self.rows[-3]['at'] += 8
        with self.assertRaisesRegex(ValueError, 'Clock'):
            self.report()

    def test_missing_final_forecast_is_incomplete(self):
        self.rows[-3]['frames']['nowcast'].pop()
        self.assertEqual(self.report()['memoryScreen'], 'incomplete')

    def test_brief_single_expiry_transition_is_reported_and_allowed(self):
        next_frames = copy.deepcopy(self.rows[71]['frames'])
        next_frames['nowcast'].pop()
        for sample in self.rows[65:71]:
            sample['frames'] = copy.deepcopy(next_frames)
        result = self.report()
        self.assertEqual(result['memoryScreen'], 'pass')
        self.assertEqual(len(result['frameTransitions']), 1)
        self.assertEqual(result['frameTransitions'][0]['samples'], 6)
        self.assertTrue(result['frameTransitions'][0]['accepted'])

    def test_persistent_transition_cannot_pass(self):
        next_frames = copy.deepcopy(self.rows[71]['frames'])
        next_frames['nowcast'].pop()
        for sample in self.rows[59:71]:
            sample['frames'] = copy.deepcopy(next_frames)
            sample['frames']['generated'] = sample['at']
        result = self.report()
        self.assertEqual(result['memoryScreen'], 'incomplete')
        self.assertFalse(result['frameTransitions'][0]['accepted'])

    def test_malformed_frames_do_not_discard_known_kernel_failure(self):
        self.rows[-3]['memory']['events']['max'] += 3129
        self.rows[5]['frames'] = {'past': []}
        result = self.report()
        self.assertEqual(result['memoryScreen'], 'fail')
        self.assertEqual(result['memoryEventsDelta']['max'], 3129)
        self.assertTrue(result['missingCoverage'])

    def test_malformed_frames_prevent_clean_memory_pass(self):
        self.rows[5]['frames']['nowcast'] = []
        result = self.report()
        self.assertEqual(result['memoryScreen'], 'incomplete')

    def test_shifted_forecast_is_not_a_tolerated_transition(self):
        self.rows[5]['frames']['nowcast'] = self.rows[5]['frames']['nowcast'][1:]
        self.assertEqual(self.report()['memoryScreen'], 'incomplete')

    def test_changed_cgroup_limit_is_rejected(self):
        self.rows[-3]['memory']['max'] = 3072 * check.MIB
        with self.assertRaisesRegex(ValueError, 'limits'):
            self.report()

    def test_no_settling_interval_is_incomplete(self):
        self.rows[-2]['events'][-1]['at'] = self.rows[-3]['at'] - 10
        self.assertEqual(self.report()['memoryScreen'], 'incomplete')

    def test_pressure_and_swap_growth_fail(self):
        self.rows[-3]['memory']['pressure']['some']['avg10'] = 19.55
        self.rows[-3]['memory']['swap.current'] += 800 * check.MIB
        result = self.report()
        self.assertEqual(result['memoryScreen'], 'fail')
        self.assertEqual(result['radarSwapGrowthMiB'], 800)

    def test_nan_measurement_is_rejected(self):
        self.rows[5]['memory']['pressure']['some']['avg10'] = float('nan')
        with self.assertRaises(ValueError):
            self.report()

    def test_logs_only_emit_recognized_timestamps_and_categories(self):
        output = '\n'.join([
            '2026-09-30T10:00:00.123456789Z [ifs] Fetching ECMWF IFS: private field',
            '2026-09-30T10:00:20.123Z PRIVATE_TOKEN_DO_NOT_EMIT',
            '2026-09-30T10:01:00.123Z [ifs] ECMWF IFS updated: private field'])
        with patch.object(check.subprocess, 'run') as run:
            run.return_value.returncode = 0
            run.return_value.stdout = output
            events = check.phase_events('radar', 0, 10)
        self.assertEqual([e['kind'] for e in events], ['ifs_start', 'ifs_done'])
        self.assertNotIn('private', str(events))
        self.assertNotIn('TOKEN', str(events))


if __name__ == '__main__':
    unittest.main()
