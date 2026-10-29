"""Exercise destructive-retention boundaries using disposable fixtures only."""

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "storage", Path(__file__).resolve().parents[1] / "scripts/maintain-dev-storage.py")
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()

    def tearDown(self):
        self.temp.cleanup()

    def artifact(self, name, modified, size=8192):
        path = self.root / name
        path.mkdir()
        (path / "report").write_bytes(b"x" * size)
        os.utime(path, (modified, modified))
        return path

    def test_keep_newest_three(self):
        paths = [self.artifact(str(i), 100 + i) for i in range(5)]
        self.assertEqual(set(storage.retention(paths, count=3)), set(paths[:2]))

    def test_byte_budget_and_expiration(self):
        old = self.artifact("old", 1)
        first = self.artifact("first", 100)
        second = self.artifact("second", 101)
        budget = storage.allocated_size(second)
        self.assertEqual(set(storage.retention([old, first, second], count=3,
                                              budget=budget, age=10, now=105)), {old, first})

    def test_running_job_is_never_expired(self):
        path = self.artifact("active", 1)
        (path / ".active").write_text(str(os.getpid()))
        self.assertEqual(storage.retention([path], count=0, budget=0, age=0), [])

    def test_finished_job_can_be_expired(self):
        path = self.artifact("finished", 1)
        (path / ".active").write_text("99999999")
        with patch.object(storage.os, "kill", side_effect=ProcessLookupError):
            self.assertEqual(storage.retention([path], count=0), [path])

    def test_cache_budget_is_enforced_only_when_builds_are_idle(self):
        repo = self.root / "repo"
        build = repo / "build"
        build.mkdir(parents=True)
        caches = []
        for name, modified in (("DerivedData-ios", 100), ("DerivedData-mac", 101)):
            path = build / name
            path.mkdir()
            os.utime(path, (modified, modified))
            caches.append(path)
        with patch.object(storage, "allocated_size", return_value=3 * storage.GIB):
            self.assertEqual(storage.plan(repo, self.root / "backups", busy=True), [])
            actions = storage.plan(repo, self.root / "backups", busy=False)
        self.assertEqual([entry[0] for entry in actions], [caches[0]])
        (caches[0] / ".active").write_text(str(os.getpid()))
        with patch.object(storage, "allocated_size", return_value=3 * storage.GIB):
            actions = storage.plan(repo, self.root / "backups", busy=False)
        self.assertEqual([entry[0] for entry in actions], [caches[1]])

    def test_invalid_owner_is_preserved(self):
        path = self.artifact("active", 1)
        (path / ".active").write_text("invalid")
        self.assertEqual(storage.retention([path], count=0), [])

    def test_symlinked_ancestor_is_rejected(self):
        outside = self.root / "outside"
        outside.mkdir()
        link = self.root / "link"
        link.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            storage.safe_path(link / "report", self.root)
        with self.assertRaises(ValueError):
            storage.safe_path(link / "report", link)

    def test_unowned_reports_are_preserved(self):
        owned = self.artifact("owned", 1)
        (owned / storage.UI_MARKER).touch()
        self.artifact("personal", 2)
        (self.root / "alias").symlink_to(owned, target_is_directory=True)
        self.assertEqual(storage.owned_directories(self.root, storage.UI_MARKER), [owned])

    def test_only_valid_bgmori_backups_are_candidates(self):
        valid = self.root / "20261029-020334.abc123"
        wrong = self.root / "20261029-020335.abc124"
        for path, bundle in [(valid, "com.yaron.bgmori"), (wrong, "other.app")]:
            info = path / "Bgmori.app/Contents/Info.plist"
            info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({"CFBundleIdentifier": bundle}))
        (self.root / "personal-backup").mkdir()
        self.assertEqual(storage.backup_directories(self.root), [valid])

    def test_dry_run_preserves_and_apply_removes_only_target(self):
        target = self.artifact("target", 1)
        personal = self.artifact("personal", 2)
        actions = [(target, self.root, "fixture")]
        with contextlib.redirect_stdout(io.StringIO()):
            storage.apply_actions(actions, self.root / "separate-repo", False)
            self.assertTrue(target.exists())
            storage.apply_actions(actions, self.root / "separate-repo", True)
        self.assertFalse(target.exists())
        self.assertTrue(personal.exists())

    def test_tracked_files_cannot_be_deleted(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        target = self.artifact("target", 1)
        subprocess.run(["git", "-C", str(self.root), "add", "target"], check=True)
        with self.assertRaises(ValueError):
            storage.apply_actions([(target, self.root, "fixture")], self.root, True)
        self.assertTrue(target.exists())

    def test_removing_artifact_does_not_follow_internal_symlinks(self):
        target = self.artifact("target", 1)
        personal = self.artifact("personal", 2)
        (target / "alias").symlink_to(personal, target_is_directory=True)
        with contextlib.redirect_stdout(io.StringIO()):
            storage.apply_actions([(target, self.root, "fixture")], self.root / "repo", True)
        self.assertTrue((personal / "report").exists())

    def ui_fixture(self, name, exit_code):
        repo = self.root / name
        for directory in ("scripts", "tests", "Bgmori", "Native", "bin"):
            (repo / directory).mkdir(parents=True)
        shutil.copyfile(Path(__file__).resolve().parents[1] / "scripts/test-shell-ui.sh",
                        repo / "scripts/test-shell-ui.sh")
        (repo / "scripts/build-ech-library.sh").touch()
        (repo / "tests/ShellUITests.swift").touch()
        commands = {
            "python3": '#!/bin/bash\nif [[ "$1" == scripts/maintain-dev-storage.py ]]; then exit 0; fi\n'
                       + f'exec {shlex.quote(sys.executable)} "$@"\n',
            "ditto": "#!/bin/bash\nexit 0\n",
            "ruby": "#!/bin/bash\nexit 0\n",
            "xcodegen": "#!/bin/bash\nexit 0\n",
            "xcodebuild": '#!/bin/bash\nprevious=""\nfor argument in "$@"; do\n'
                          'if [[ "$previous" == -resultBundlePath ]]; then mkdir -p "$argument"; fi\n'
                          'previous="$argument"\ndone\n' + f'exit {exit_code}\n',
        }
        for name, content in commands.items():
            path = repo / "bin" / name
            path.write_text(content)
            path.chmod(0o755)
        env = dict(os.environ, PATH=str(repo / "bin") + os.pathsep + os.environ["PATH"])
        env.pop("BGMORI_UI_RESULT_DIR", None)
        return repo, env

    def test_ui_exit_always_removes_temporary_work_and_preserves_failure(self):
        for code in (0, 23):
            with self.subTest(code=code):
                repo, env = self.ui_fixture(f"ui-{code}", code)
                result = subprocess.run(["bash", "scripts/test-shell-ui.sh", "all"],
                                        cwd=repo, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertEqual(list((repo / "build/tmp").iterdir()), [])
                runs = list((repo / "build/ui-results").iterdir())
                self.assertEqual(len(runs), 1)
                self.assertFalse((runs[0] / ".active").exists())
                self.assertTrue((runs[0] / "ios.xcresult").is_dir())
                self.assertEqual((runs[0] / "mac.xcresult").exists(), code == 0)

    def test_ui_rejects_report_destination_outside_managed_root(self):
        repo, env = self.ui_fixture("outside-ui", 0)
        destination = self.root / "personal-reports"
        env["BGMORI_UI_RESULT_DIR"] = str(destination)
        result = subprocess.run(["bash", "scripts/test-shell-ui.sh", "ios"],
                                cwd=repo, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be a new direct child", result.stderr)
        self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
