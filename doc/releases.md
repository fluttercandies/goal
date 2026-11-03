# Native releases

The **Native binaries** workflow builds standalone executables from
`bin/goal.dart`. Pull requests, pushes to `main`, and manual workflow runs
only produce downloadable Actions artifacts. Only a push of a `v*` tag can
publish a GitHub Release, after every required build and smoke test passes.

## Targets and verification

| Asset target | Build host | Verification |
| --- | --- | --- |
| `windows-x64` | `windows-2022`, x64 SDK | Unit tests and executable smoke test |
| `windows-arm64` | `windows-11-arm`, arm64 SDK | Unit tests and executable smoke test |
| `macos-x64` | `macos-15-intel`, x64 SDK | Unit tests and executable smoke test |
| `macos-arm64` | `macos-15`, arm64 SDK | Unit tests and executable smoke test |
| `linux-x64` | `ubuntu-22.04`, x64 SDK | Unit tests and executable smoke test |
| `linux-arm64` | Cross-compiled on `ubuntu-22.04` | Packaged binary smoke-tested on `ubuntu-22.04-arm` without installing Dart |
| `linux-arm32` | Cross-compiled on `ubuntu-22.04` | Compilation and executable architecture checks only |
| `linux-riscv64` | Cross-compiled on `ubuntu-22.04` | Compilation and executable architecture checks only |

The smoke test uses a temporary `GOAL_HOME`, checks help and error exit
codes, and writes and reads a ledger across separate executable invocations.
ARM32 and RISC-V64 binaries are not runtime-tested in this workflow; verify
them on the intended hardware before relying on them. No emulation or
self-hosted runner is required.

Dart supports cross-compiling native executables **to Linux**. Windows and
macOS use matching native runners and SDKs. Linux ARM32 uses Dart's `arm`
target (ARMv7); it is named `arm32` in release assets. Windows x64 means
64-bit x86: 32-bit x86/IA32 native AOT executables are not supported. There
is no Windows x86/IA32 artifact. See the official
[Dart compile documentation](https://dart.dev/tools/dart-compile#exe) and
[hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

Linux executables require glibc and the platform libraries used by the
Dart runtime; these are not static or musl/Alpine builds. The x64 build
is smoke-tested on Ubuntu 22.04, and the arm64 build on Ubuntu 22.04 ARM.
The workflow does not claim compatibility with every Linux distribution.
Windows and macOS artifacts are unsigned; no signing credentials are used.

## Reproducibility and assets

`DART_VERSION` in `.github/workflows/release.yml` pins the release SDK.
Update it deliberately and let the full matrix pass before tagging. The
prepare job resolves dependencies once and shares its `pubspec.lock` with
every build. Each build runs `dart pub get --enforce-lockfile`. The project
does not commit a lockfile, so separate workflow runs can resolve newer
compatible dependencies; builds within a run share the exact resolution.

Each archive contains:

- `goal` or `goal.exe`
- `LICENSE`, both READMEs, and `CHANGELOG.md`
- This release guide (`doc/releases.md`)
- The resolved `pubspec.lock`
- `build-info.json` with the package version, target, Dart SDK, and commit

Asset names are `goal-<version>-<os>-<arch>.zip` for Windows and
`goal-<version>-<os>-<arch>.tar.gz` for macOS/Linux. Unix archives preserve
the executable bit. Packaging checks the PE, Mach-O, or ELF architecture
to reject mislabeled binaries. The publish job verifies all eight archive
checksums before collecting them in `SHA256SUMS`.

For example, after downloading one archive and `SHA256SUMS`:

```bash
# Linux
sha256sum --ignore-missing --check SHA256SUMS
# macOS: compare this digest with that archive's SHA256SUMS entry
shasum -a 256 goal-<version>-macos-arm64.tar.gz
```

```powershell
# Windows: compare this digest with that archive's SHA256SUMS entry
Get-FileHash .\goal-<version>-windows-x64.zip -Algorithm SHA256
```

Checksums detect corrupted downloads; they are not an independent signature.

## Publishing

1. Merge the release workflow and ensure the desired `main` commit passes CI.
2. Update `pubspec.yaml` and `CHANGELOG.md` for the release and merge them.
3. Push a tag exactly matching the package version, such as `v1.1.0` for
   `version: 1.1.0`. Prereleases such as `v1.2.0-rc.1` must likewise match.
4. The workflow builds every target, creates a draft release, uploads all
   eight archives and `SHA256SUMS`, then publishes it. Versions containing
   a prerelease suffix are marked as prereleases.

A tag/version mismatch fails before compilation. If upload or publication
fails, the release remains a draft and rerunning that tag's workflow can
resume it, replacing same-name draft assets. An already published release
is never overwritten: use a new version and tag for changed binaries.
`workflow_dispatch` is build-only even when invoked for a tag.

Read-only permissions are the default. Only the tag-gated publish job has
`contents: write`, using the automatically provided `GITHUB_TOKEN`. Pull
requests cannot publish releases or access a release write token. Actions
are pinned to commit SHAs and checkout does not persist credentials.

## Testing the tooling locally

The packaging helpers need only Python 3's standard library:

```bash
python -m unittest discover -s tool -p 'test_*.py' -v
python tool/release.py metadata
```

For a native Linux x64 smoke build, with the pinned Dart SDK installed:

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
mkdir -p build
dart compile exe bin/goal.dart -o build/goal
python tool/release.py smoke build/goal
python tool/release.py package linux-x64 --sdk 3.13.7
```

The helper unit tests cover version and tag validation, all eight executable
headers, archive contents and Unix permissions, checksums, missing assets,
and smoke-test isolation/error handling. Header fixtures are not compiled
Dart executables; actual compiler/runtime validation happens in Actions.
