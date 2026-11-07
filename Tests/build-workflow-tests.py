"""Behavioral checks of fail-closed packaging; never invokes a real signer/compiler."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BuildWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="snap-assist-build-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for directory in ("scripts", "Resources", "fake-product", "dist/release/SnapAssist.app"):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "Resources/Info.plist", self.root / "Resources/Info.plist")
        shutil.copyfile(ROOT / "LICENSE", self.root / "LICENSE")
        binary = self.root / "fake-product/SnapAssist"
        binary.write_text("fixture\n")
        binary.chmod(0o700)
        (self.root / "dist/release/SnapAssist.app/previous-verified-output").write_text("keep")
        self.trace = self.root / "trace"
        compiler = self.root / "mock-compiler"
        compiler.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$REVIEW_TRACE"\n'
                            'case " $* " in *" --show-bin-path "*) printf "%s\\n" "$REVIEW_PRODUCT" ;; esac\n')
        signer = self.root / "mock-signer"
        signer.write_text('#!/bin/bash\nexit "${REVIEW_SIGN_EXIT:-1}"\n')
        for mock in (compiler, signer): mock.chmod(0o700)
        script = (ROOT / "scripts/build-app.sh").read_text()
        script = script.replace("/usr/bin/xcrun", shlex.quote(str(compiler)))
        script = script.replace("/usr/bin/codesign", shlex.quote(str(signer)))
        (self.root / "scripts/build-app.sh").write_text(script)
        (self.root / "scripts/verify-app.sh").write_text('#!/bin/bash\nexit 1\n')
        (self.root / "scripts/install-app.sh").write_text('#!/bin/bash\ntouch "$REVIEW_INSTALLED"\n')
        self.env = os.environ.copy()
        self.env.update(SIGN_IDENTITY="fixture", EXPECTED_TEAM_ID="ABCDEFGHIJ",
                        REVIEW_TRACE=str(self.trace), REVIEW_PRODUCT=str(self.root / "fake-product"),
                        REVIEW_INSTALLED=str(self.root / "installed"))

    def build(self, *arguments):
        return subprocess.run(["/bin/bash", str(self.root / "scripts/build-app.sh"), *arguments],
                              env=self.env, capture_output=True, text=True)

    def assert_previous_preserved(self):
        self.assertEqual((self.root / "dist/release/SnapAssist.app/previous-verified-output").read_text(), "keep")
        self.assertFalse((self.root / "installed").exists())

    def test_signing_failure_never_installs_or_replaces_previous_output(self):
        result = self.build("release", "install")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Verified release", result.stdout)
        self.assert_previous_preserved()
        calls = self.trace.read_text().splitlines()
        self.assertEqual(len(calls), 2)
        self.assertTrue(all("--arch arm64" in call for call in calls))

    def test_verification_failure_never_installs_or_replaces_previous_output(self):
        self.env["REVIEW_SIGN_EXIT"] = "0"
        self.assertNotEqual(self.build("release", "install").returncode, 0)
        self.assert_previous_preserved()

    def test_missing_identity_stops_before_compilation(self):
        self.env.pop("SIGN_IDENTITY")
        self.assertNotEqual(self.build("release").returncode, 0)
        self.assertFalse(self.trace.exists())

    def test_ad_hoc_identity_is_rejected_before_compilation(self):
        self.env["SIGN_IDENTITY"] = "-"
        self.assertNotEqual(self.build("release").returncode, 0)
        self.assertFalse(self.trace.exists())

    def test_invalid_configuration_is_rejected_before_compilation(self):
        self.assertNotEqual(self.build("intel").returncode, 0)
        self.assertFalse(self.trace.exists())


if __name__ == "__main__":
    unittest.main()
