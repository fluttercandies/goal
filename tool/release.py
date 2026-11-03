"""Standard-library helpers for native release packaging and smoke tests."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile
import zipfile


TARGETS = (
    "windows-x64", "windows-arm64", "macos-x64", "macos-arm64",
    "linux-x64", "linux-arm64", "linux-arm32", "linux-riscv64",
)
SEMVER = re.compile(
    r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)


def version(root=Path("."), tag=None):
    match = re.search(r"^version:\s*(\S+)\s*$",
                      (root / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
    if not match or not SEMVER.fullmatch(match[1]):
        raise ValueError("pubspec.yaml must contain a valid semantic version")
    value = match[1]
    prerelease = SEMVER.fullmatch(value)[4]
    if prerelease and any(part.isdigit() and len(part) > 1 and part[0] == "0"
                          for part in prerelease.split(".")):
        raise ValueError("Numeric prerelease identifiers cannot have leading zeroes")
    if tag is not None and tag != f"v{value}":
        raise ValueError(f"Tag {tag!r} must match pubspec.yaml version v{value}")
    return value


def verify_binary(binary, target):
    """Reject mislabeled assets before they can be uploaded."""
    data = binary.read_bytes()
    os_name, arch = target.split("-", 1)
    if os_name == "linux":
        expected = {"x64": (2, 62), "arm64": (2, 183),
                    "arm32": (1, 40), "riscv64": (2, 243)}[arch]
        valid = (len(data) >= 20 and data[:4] == b"\x7fELF" and data[5] == 1
                 and (data[4], struct.unpack_from("<H", data, 18)[0]) == expected)
    elif os_name == "macos":
        expected = {"x64": 0x01000007, "arm64": 0x0100000C}[arch]
        valid = (len(data) >= 8 and data[:4] == b"\xcf\xfa\xed\xfe"
                 and struct.unpack_from("<I", data, 4)[0] == expected)
    else:
        expected = {"x64": 0x8664, "arm64": 0xAA64}[arch]
        offset = struct.unpack_from("<I", data, 60)[0] if len(data) >= 64 else 0
        valid = (data[:2] == b"MZ" and offset >= 64 and len(data) >= offset + 6
                 and data[offset:offset + 4] == b"PE\0\0"
                 and struct.unpack_from("<H", data, offset + 4)[0] == expected)
    if not valid:
        raise ValueError(f"{binary} is not a {target} executable")


def archive_name(release_version, target):
    extension = "zip" if target.startswith("windows-") else "tar.gz"
    return f"goal-{release_version}-{target}.{extension}"


def package(root, target, sdk):
    release_version = version(root)
    executable = "goal.exe" if target.startswith("windows-") else "goal"
    binary = root / "build" / executable
    verify_binary(binary, target)
    output = root / "build" / "release"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / archive_name(release_version, target)
    with tempfile.TemporaryDirectory() as directory:
        stage = Path(directory)
        shutil.copyfile(binary, stage / executable)
        (stage / executable).chmod(0o755)
        for filename in ("LICENSE", "README.md", "README.zh-CN.md",
                         "CHANGELOG.md", "pubspec.lock", "doc/releases.md"):
            (stage / filename).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / filename, stage / filename)
        (stage / "build-info.json").write_text(json.dumps({
            "version": release_version, "target": target, "dart_sdk": sdk,
            "commit": os.environ.get("GITHUB_SHA", "local"),
        }, indent=2) + "\n", encoding="utf-8")
        files = sorted(path for path in stage.rglob("*") if path.is_file())
        if target.startswith("windows-"):
            with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as handle:
                for path in files:
                    handle.write(path, path.relative_to(stage).as_posix())
        else:
            with tarfile.open(archive, "w:gz") as handle:
                for path in files:
                    handle.add(path, arcname=path.relative_to(stage).as_posix())
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_name(archive.name + ".sha256").write_text(
        f"{digest}  {archive.name}\n", encoding="utf-8")
    return archive


def checksums(directory, release_version):
    lines = []
    for target in TARGETS:
        archive = directory / archive_name(release_version, target)
        expected = f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n"
        if archive.with_name(archive.name + ".sha256").read_text() != expected:
            raise ValueError(f"Checksum mismatch: {archive.name}")
        lines.append(expected)
    (directory / "SHA256SUMS").write_text("".join(sorted(lines)), encoding="utf-8")


def smoke(binary):
    binary = binary.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="goal-release-smoke-") as directory:
        env = dict(os.environ, GOAL_HOME=str(Path(directory) / "ledger"))

        def run(*args, expected_code=0):
            result = subprocess.run(
                [str(binary), *args], cwd=directory, env=env, capture_output=True,
                text=True, encoding="utf-8", timeout=30, check=False)
            if result.returncode != expected_code:
                raise ValueError(f"goal {args}: exit {result.returncode}\n"
                                 f"{result.stdout}\n{result.stderr}")
            return result.stdout

        if "goal init" not in run("--help"):
            raise ValueError("The executable did not print goal's help")
        run("init")
        run("add", "release smoke test", "-p1")
        run("set", "1", "done", "native binary works")
        goals = json.loads(run("render", "--json"))["goals"]
        if (len(goals) != 1 or goals[0]["title"] != "release smoke test"
                or goals[0]["status"] != "done"):
            raise ValueError("The executable did not persist the expected ledger")
        run("not-a-command", expected_code=2)
    print(f"Native smoke test passed: {binary}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("metadata")
    package_parser = commands.add_parser("package")
    package_parser.add_argument("target", choices=TARGETS)
    package_parser.add_argument("--sdk", required=True)
    smoke_parser = commands.add_parser("smoke")
    smoke_parser.add_argument("binary", type=Path)
    checksum_parser = commands.add_parser("checksums")
    checksum_parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    if args.command == "metadata":
        tag = (os.environ["GITHUB_REF_NAME"]
               if os.environ.get("GITHUB_REF_TYPE") == "tag" else None)
        value = version(tag=tag)
        result = f"version={value}\nprerelease={str(SEMVER.fullmatch(value)[4] is not None).lower()}\n"
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
                output.write(result)
        print(result, end="")
    elif args.command == "package":
        print(package(Path("."), args.target, args.sdk))
    elif args.command == "smoke":
        smoke(args.binary)
    else:
        checksums(args.directory, version())


if __name__ == "__main__":
    main()
