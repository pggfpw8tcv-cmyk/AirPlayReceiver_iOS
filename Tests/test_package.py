import importlib.util
import os
import plistlib
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/package_ipa.py"


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.exists(), "IPA packager must exist")
        spec = importlib.util.spec_from_file_location("package_ipa", SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "Receiver.app"
        self.app.mkdir()
        self.info = {"CFBundleExecutable": "Receiver", "CFBundleIdentifier": "dev.receiver.test",
                     "CFBundlePackageType": "APPL", "CFBundleSupportedPlatforms": ["iPhoneOS"]}
        self.write_info()
        self.binary()

    def write_info(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def binary(self, cpu=0x0100000C, platform=2, signed=False):
        commands = struct.pack("<6I", 0x32, 24, platform, 0x100000, 0x120000, 0)
        if signed:
            commands += struct.pack("<4I", 0x1D, 16, 72, 0)
        header = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 2 if signed else 1, len(commands), 0, 0)
        path = self.app / "Receiver"
        path.write_bytes(header + commands)
        path.chmod(0o755)

    def test_payload_and_executable_permissions(self):
        output = self.root / "Receiver.ipa"
        self.module.package(self.app, output)
        with zipfile.ZipFile(output) as archive:
            self.assertIn("Payload/Receiver.app/Info.plist", archive.namelist())
            entry = archive.getinfo("Payload/Receiver.app/Receiver")
            self.assertTrue((entry.external_attr >> 16) & 0o111)
            self.assertEqual(archive.read(entry), (self.app / "Receiver").read_bytes())

    def test_missing_binary_rejected(self):
        (self.app / "Receiver").unlink()
        with self.assertRaises(ValueError):
            self.module.package(self.app, self.root / "bad.ipa")

    def test_simulator_rejected(self):
        self.binary(platform=7)
        with self.assertRaises(ValueError):
            self.module.package(self.app, self.root / "bad.ipa")

    def test_wrong_architecture_rejected(self):
        self.binary(cpu=0x01000007)
        with self.assertRaises(ValueError):
            self.module.package(self.app, self.root / "bad.ipa")

    def test_signed_binary_rejected(self):
        self.binary(signed=True)
        with self.assertRaises(ValueError):
            self.module.package(self.app, self.root / "bad.ipa")

    def test_path_traversal_executable_rejected(self):
        self.info["CFBundleExecutable"] = "../Receiver"
        self.write_info()
        with self.assertRaises(ValueError):
            self.module.package(self.app, self.root / "bad.ipa")

    def test_symlink_rejected(self):
        os.symlink("/etc/passwd", self.app / "escaped")
        with self.assertRaises(ValueError):
            self.module.package(self.app, self.root / "bad.ipa")

    def test_truncated_commands_rejected(self):
        with (self.app / "Receiver").open("r+b") as f:
            f.truncate(40)
        with self.assertRaises(ValueError):
            self.module.package(self.app, self.root / "bad.ipa")


if __name__ == "__main__":
    unittest.main()
