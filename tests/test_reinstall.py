"""Exercise deletion guards without deleting a real Waydroid environment."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('mwi_state', Path(__file__).resolve().parents[1] / 'lib/state.py')
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)


class ReinstallTests(unittest.TestCase):
    def setUp(self):
        self.home = Path('/mwi-test/home').absolute()
        self.data = self.home / '.local/share/waydroid'
        self.work = self.home / '.local/state/mwi'
        self.report = self.work / 'logs/reinstall.json'
        self.wd = Path('/mwi-test/system/waydroid').absolute()
        self.image = Path('/mwi-test/images').absolute()
        self.targets = [self.wd, self.data, self.image]
        self.patches = [
            patch.object(state, 'WD', self.wd), patch.object(state, 'IMAGE', self.image),
            patch.dict(sys.modules, {'pwd': SimpleNamespace(getpwuid=lambda uid: SimpleNamespace(pw_dir=str(self.home)))}),
            patch.object(state, 'no_symlink_parents'),
            patch.object(state.subprocess, 'run', return_value=SimpleNamespace(stdout='{"filesystems": []}')),
            patch.object(state, 'remove_path'), patch.object(state, 'atomic_bytes'),
            patch.object(Path, 'exists', return_value=True),
        ]
        self.mocks = [p.start() for p in self.patches]
        for p in self.patches:
            self.addCleanup(p.stop)
        self.guard, self.mounts, self.remove, self.write = self.mocks[3:7]

    def run_reinstall(self, data=None, uid=1000, work=None):
        state.reinstall(str(data or self.data), uid, str(self.report), str(work or self.work))

    def test_deletes_only_three_validated_targets_and_reports_progress(self):
        self.run_reinstall()
        self.assertEqual([call.args[0] for call in self.remove.call_args_list], self.targets)
        self.assertEqual(self.guard.call_count, 3)
        records = [json.loads(call.args[1]) for call in self.write.call_args_list]
        self.assertEqual(len(records), 4)
        self.assertTrue(all(not item['deleted'] for item in records[0]))
        self.assertTrue(all(item['deleted'] for item in records[-1]))

    def test_rejects_other_users_and_home_directory(self):
        for data, uid in [(Path('/other/waydroid'), 1000), (self.home, 1000), (self.data, 0)]:
            with self.subTest(data=data, uid=uid), self.assertRaises(ValueError):
                self.run_reinstall(data, uid)
        self.remove.assert_not_called()

    def test_mount_on_last_target_blocks_all_deletions(self):
        self.mounts.return_value.stdout = json.dumps({'filesystems': [{'target': '/', 'children': [{'target': str(self.image / 'mounted path')}]}]})
        with self.assertRaises(ValueError):
            self.run_reinstall()
        self.remove.assert_not_called()

    def test_symlink_on_last_target_blocks_all_deletions(self):
        self.guard.side_effect = [None, None, ValueError('symlink')]
        with self.assertRaises(ValueError):
            self.run_reinstall()
        self.remove.assert_not_called()

    def test_mount_query_failure_blocks_deletion(self):
        self.mounts.side_effect = subprocess.CalledProcessError(1, 'findmnt')
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_reinstall()
        self.remove.assert_not_called()

    def test_cache_inside_data_blocks_deletion(self):
        with self.assertRaises(ValueError):
            self.run_reinstall(work=self.data / 'cache')
        self.remove.assert_not_called()

    def test_report_failure_blocks_deletion(self):
        self.write.side_effect = OSError('disk full')
        with self.assertRaises(OSError):
            self.run_reinstall()
        self.remove.assert_not_called()

    def test_missing_targets_are_skipped(self):
        self.mocks[7].return_value = False
        self.run_reinstall()
        self.remove.assert_not_called()
        self.assertEqual(json.loads(self.write.call_args.args[1]), [])


if __name__ == '__main__':
    unittest.main()
