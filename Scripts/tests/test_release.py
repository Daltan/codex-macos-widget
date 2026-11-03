import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release", Path(__file__).parents[1] / "release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def testVersionBumpsNormalizeLegacyAndResetComponents(self):
        self.assertEqual(release.bump_version("1.0", "minor"), "1.1.0")
        self.assertEqual(release.bump_version("1.9.9", "patch"), "1.9.10")
        self.assertEqual(release.bump_version("1.9.9", "minor"), "1.10.0")
        self.assertEqual(release.bump_version("1.9.9", "major"), "2.0.0")
        for invalid in ["v1.0.0", "1.0.0-beta", "1", "../1.0", "1.0.0\n"]:
            with self.assertRaises(ValueError):
                release.version_tuple(invalid)

    def testMismatchedAppWidgetVersionsAreRejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Config").mkdir()
            for name, build in zip(release.PLISTS, [4, 5]):
                (root / name).write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.0", "CFBundleVersion": str(build)}))
            with self.assertRaisesRegex(RuntimeError, "do not match"):
                release.versions(root)

    def testHashReadbackRejectsMissingExtraAndChangedAssets(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            artifact = directory / "app.zip"
            artifact.write_bytes(b"verified release")
            expected = {artifact.name: release.digest(artifact)}
            release.check_hashes(directory, expected)
            artifact.write_bytes(b"wrong release")
            with self.assertRaisesRegex(RuntimeError, "Checksum mismatch"):
                release.check_hashes(directory, expected)
            artifact.unlink()
            with self.assertRaisesRegex(RuntimeError, "Unexpected artifact set"):
                release.check_hashes(directory, expected)
            artifact.write_bytes(b"verified release")
            (directory / "extra.txt").touch()
            with self.assertRaisesRegex(RuntimeError, "Unexpected artifact set"):
                release.check_hashes(directory, expected)

    def testExistingTagCannotBeMoved(self):
        with patch.object(release, "git", side_effect=["v1.1.0", "old-commit"]), patch.object(release, "push") as push:
            with self.assertRaisesRegex(RuntimeError, "different commit"):
                release.ensure_tag("v1.1.0", "new-commit")
            push.assert_not_called()

    def testRemoteAnnotatedTagMustPeelToBuiltCommit(self):
        with patch.object(release, "git", side_effect=["v1.1.0", "built", "tag-object\trefs/tags/v1.1.0\nother\trefs/tags/v1.1.0^{}"]), patch.object(release, "push"):
            with self.assertRaisesRegex(RuntimeError, "does not resolve"):
                release.ensure_tag("v1.1.0", "built")

    def testCachedArtifactsCannotBeReusedForAnotherCommit(self):
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary)
            (state / "manifest.json").write_text(json.dumps({"commit": "old", "version": "1.1.0", "build": 5}))
            with self.assertRaisesRegex(RuntimeError, "source changed"):
                release.build_artifacts(state, "1.1.0", 5, "new")


if __name__ == "__main__":
    unittest.main()
