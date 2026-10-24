"""Verify cache sharing without building or writing product artifacts."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "script" / "build_paths.sh"


class BuildPathTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / "main source"
        self.root.mkdir()
        self.copy_script(self.root)
        self.git(self.root, "init", "--quiet")
        self.git(self.root, "config", "user.name", "Build Path Test")
        self.git(self.root, "config", "user.email", "build-path@example.invalid")
        self.git(self.root, "add", ".")
        self.git(self.root, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                 "commit", "--quiet", "-m", "Fixture")
        self.cache = Path(self.directory.name) / "cache"
        self.cache.mkdir()

    def copy_script(self, root):
        (root / "script").mkdir()
        shutil.copyfile(SCRIPT, root / "script" / "build_paths.sh")

    def git(self, root, *arguments):
        subprocess.run(["git", "-C", str(root), *arguments], check=True,
                       capture_output=True, text=True)

    def paths(self, root=None, **overrides):
        environment = dict(os.environ)
        for name in ["DUST3D_BUILD_ROOT", "DUST3D_UI_QA_OUTPUT_DIR"]:
            environment.pop(name, None)
        environment.update(TMPDIR=str(self.cache), **overrides)
        command = ('set -euo pipefail\nsource "$1"\n'
                   'printf "%s\\n" "$DUST3D_BUILD_ROOT" "$DUST3D_BINARY_DIR" '
                   '"${DUST3D_UI_QA_OUTPUT_DIR-}"\n')
        output = subprocess.check_output(
            ["bash", "-c", command, "paths", str((root or self.root) / "script" / "build_paths.sh")],
            env=environment, text=True)
        return output.splitlines()

    def test_should_share_default_cache_and_artifacts_across_linked_worktrees(self):
        linked = Path(self.directory.name) / "linked source"
        self.git(self.root, "worktree", "add", "--quiet", "--detach", str(linked))
        first = self.paths()
        second = self.paths(linked)
        self.assertEqual(first, second)
        self.assertEqual(first[2], str(Path(first[0]) / "ui-qa"))
        self.assertFalse(Path(first[0]).exists(), "Path discovery must not create a cache")

    def test_should_preserve_explicit_shared_root_and_artifact_override(self):
        shared = self.cache / "shared build"
        artifacts = self.cache / "retained evidence"
        result = self.paths(DUST3D_BUILD_ROOT=str(shared), DUST3D_UI_QA_OUTPUT_DIR=str(artifacts))
        self.assertEqual(result[0], str(shared))
        self.assertTrue(result[1].startswith(str(shared / "build") + os.sep))
        self.assertEqual(result[2], str(artifacts))
        self.assertFalse(shared.exists())

    def test_should_put_default_artifacts_under_explicit_shared_root(self):
        shared = self.cache / "shared build"
        result = self.paths(DUST3D_BUILD_ROOT=str(shared))
        self.assertEqual(result[2], str(shared / "ui-qa"))

    def test_should_keep_unrelated_repositories_separate_without_an_override(self):
        other = Path(self.directory.name) / "unrelated"
        other.mkdir()
        self.copy_script(other)
        self.git(other, "init", "--quiet")
        self.assertNotEqual(self.paths()[0], self.paths(other)[0])

    def test_should_use_stable_fallback_when_git_metadata_is_unavailable(self):
        loose = Path(self.directory.name) / "source archive"
        loose.mkdir()
        self.copy_script(loose)
        first = self.paths(loose)
        self.assertEqual(first, self.paths(loose))
        self.assertEqual(first[2], str(Path(first[0]) / "ui-qa"))
        self.assertFalse(Path(first[0]).exists())

    def test_should_canonicalize_repository_aliases(self):
        alias = Path(self.directory.name) / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        self.assertEqual(self.paths(), self.paths(alias))
