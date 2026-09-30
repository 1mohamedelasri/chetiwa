#!/usr/bin/env python3
"""Exercise provisioning against fake CLIs; no cloud access or credentials."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("provision-alert-store.sh")


class RetentionProvisioningTest(unittest.TestCase):
    def invoke(self, database="(default)", database_available=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "calls.jsonl"
            stub = """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with open(os.environ['CHETIWA_TEST_CALLS'], 'a') as log:
    log.write(json.dumps([Path(sys.argv[0]).name, *sys.argv[1:]]) + '\\n')
if sys.argv[1:4] == ['firestore', 'databases', 'describe']:
    sys.exit(int(os.environ['CHETIWA_TEST_DATABASE_EXIT']))
"""
            for name in ("gcloud", "firebase"):
                binary = root / name
                binary.write_text(stub)
                binary.chmod(0o755)
            env = dict(os.environ)
            env.update(
                PATH=str(root) + os.pathsep + env["PATH"],
                CHETIWA_TEST_CALLS=str(log),
                CHETIWA_TEST_DATABASE_EXIT="0" if database_available else "1",
            )
            result = subprocess.run(
                ["bash", str(SCRIPT), "test-project", "worker@example.invalid", database],
                env=env,
                capture_output=True,
                text=True,
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_only_approved_metric_ttl_is_changed(self):
        result, calls = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        ttl_calls = [call for call in calls if call[1:4] == ["firestore", "fields", "ttls"]]
        self.assertEqual(len(ttl_calls), 1, ttl_calls)
        self.assertIn("--collection-group=alertRunMetrics", ttl_calls[0])
        self.assertIn("--enable-ttl", ttl_calls[0])
        self.assertIn("--project=test-project", ttl_calls[0])
        self.assertIn("--database=(default)", ttl_calls[0])
        self.assertTrue(any(call[:2] == ["firebase", "deploy"] for call in calls))

    def test_missing_database_prevents_all_mutations(self):
        result, calls = self.invoke(database_available=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1:4], ["firestore", "databases", "describe"])

    def test_unsupported_database_makes_no_cloud_calls(self):
        result, calls = self.invoke(database="other")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
