import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import release


def executable_header(target):
    data = bytearray(128)
    system, arch = target.split("-", 1)
    if system == "linux":
        data[:4] = b"\x7fELF"
        data[4:6] = bytes([1 if arch == "arm32" else 2, 1])
        machine = {"x64": 62, "arm64": 183, "arm32": 40, "riscv64": 243}[arch]
        struct.pack_into("<H", data, 18, machine)
    elif system == "macos":
        data[:4] = b"\xcf\xfa\xed\xfe"
        struct.pack_into("<I", data, 4, 0x01000007 if arch == "x64" else 0x0100000C)
    else:
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 60, 64)
        data[64:68] = b"PE\0\0"
        struct.pack_into("<H", data, 68, 0x8664 if arch == "x64" else 0xAA64)
    return data


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "pubspec.yaml").write_text("name: goal\nversion: 1.1.0\n")
        (self.root / "build").mkdir()
        for filename in ("LICENSE", "README.md", "README.zh-CN.md",
                         "CHANGELOG.md", "pubspec.lock", "doc/releases.md"):
            (self.root / filename).parent.mkdir(parents=True, exist_ok=True)
            (self.root / filename).write_text(f"{filename}\n", encoding="utf-8")

    def test_version_and_matching_tag(self):
        self.assertEqual(release.version(self.root, "v1.1.0"), "1.1.0")
        for tag in ("1.1.0", "v1.0.0", "v1.1.0/../../unexpected"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.version(self.root, tag)

    def test_prerelease_and_build_versions(self):
        for value in ("1.2.3-rc.1", "0.0.1+build.7", "2.0.0-beta+build.1"):
            with self.subTest(version=value):
                (self.root / "pubspec.yaml").write_text(f"version: {value}\n")
                self.assertEqual(release.version(self.root, f"v{value}"), value)

    def test_invalid_versions_are_rejected(self):
        for value in ("", "1.2", "01.2.3", "1.2.3-01", "1.2.3/../file"):
            with self.subTest(version=value), self.assertRaises(ValueError):
                (self.root / "pubspec.yaml").write_text(f"version: {value}\n")
                release.version(self.root)

    def test_all_architectures_and_archives(self):
        for target in release.TARGETS:
            with self.subTest(target=target):
                executable = "goal.exe" if target.startswith("windows-") else "goal"
                binary = self.root / "build" / executable
                binary.write_bytes(executable_header(target))
                archive = release.package(self.root, target, "3.13.7")
                digest = hashlib.sha256(archive.read_bytes()).hexdigest()
                self.assertEqual(archive.with_name(archive.name + ".sha256").read_text(),
                                 f"{digest}  {archive.name}\n")
                if archive.suffix == ".zip":
                    with zipfile.ZipFile(archive) as handle:
                        names = handle.namelist()
                        info = json.loads(handle.read("build-info.json"))
                        self.assertEqual(handle.read(executable), binary.read_bytes())
                else:
                    with tarfile.open(archive) as handle:
                        names = handle.getnames()
                        info = json.load(handle.extractfile("build-info.json"))
                        self.assertEqual(handle.extractfile(executable).read(), binary.read_bytes())
                        self.assertEqual(handle.getmember(executable).mode, 0o755)
                self.assertEqual(info["target"], target)
                self.assertEqual(info["version"], "1.1.0")
                self.assertEqual(set(names), {
                    executable, "LICENSE", "README.md", "README.zh-CN.md",
                    "CHANGELOG.md", "pubspec.lock", "doc/releases.md", "build-info.json"})
        directory = self.root / "build" / "release"
        release.checksums(directory, "1.1.0")
        self.assertEqual(len((directory / "SHA256SUMS").read_text().splitlines()), 8)
        (directory / release.archive_name("1.1.0", "linux-x64")).write_bytes(b"tampered")
        with self.assertRaises(ValueError):
            release.checksums(directory, "1.1.0")

    def test_mislabeled_or_invalid_binaries_are_rejected(self):
        binary = self.root / "build" / "goal"
        for source in release.TARGETS:
            binary.write_bytes(executable_header(source))
            for target in release.TARGETS:
                if source != target:
                    with self.subTest(source=source, target=target), self.assertRaises(ValueError):
                        release.verify_binary(binary, target)
        for payload in (b"", b"MZ", b"\x7fELF", b"not a binary"):
            binary.write_bytes(payload)
            for target in release.TARGETS:
                with self.subTest(target=target), self.assertRaises(ValueError):
                    release.verify_binary(binary, target)

    def test_incomplete_asset_set_is_rejected(self):
        with self.assertRaises(FileNotFoundError):
            release.checksums(self.root, "1.1.0")

    def test_smoke_uses_isolated_ledger_and_checks_error_exit(self):
        binary = self.root / "build" / "goal"
        binary.write_bytes(b"fixture")
        responses = ["goal init", "ok", "ok", "ok", json.dumps({"goals": [{
            "title": "release smoke test", "status": "done"}]}), ""]

        def run(args, **kwargs):
            self.assertEqual(args[0], str(binary.resolve()))
            self.assertNotEqual(kwargs["cwd"], str(self.root))
            self.assertEqual(kwargs["env"]["GOAL_HOME"], str(Path(kwargs["cwd"]) / "ledger"))
            return subprocess.CompletedProcess(args, 2 if args[1] == "not-a-command" else 0,
                                               stdout=responses.pop(0), stderr="")

        with patch("release.subprocess.run", side_effect=run) as runner:
            release.smoke(binary)
            self.assertEqual(runner.call_count, 6)

    def test_smoke_propagates_failed_command(self):
        binary = self.root / "build" / "goal"
        binary.write_bytes(b"fixture")
        result = subprocess.CompletedProcess([], 1, stdout="", stderr="failed")
        with patch("release.subprocess.run", return_value=result), self.assertRaises(ValueError):
            release.smoke(binary)


if __name__ == "__main__":
    unittest.main()
