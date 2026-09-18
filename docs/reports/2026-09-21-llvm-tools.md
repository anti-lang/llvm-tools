# LLVM tools 23.1.1-1

Release `23.1.1-1` holds the five tools for six hosts, built from recipe commit
`9ca585f`. `antic` pins it and passes all 404 tests with the downloaded tools.

## Recipe as built

- Compiler: `LLVM-23.1.1-macOS-ARM64.tar.xz`, SHA-256
  `64220f1c99132ef7e580447781b84f96fbba6862a43a8f6522b423052cd67502`. Its Sigstore
  attestation passes `gh attestation verify` for workflow `release-binaries.yml` at
  `refs/tags/llvmorg-23.1.1`. `llvm-tblgen` of the release serves every host.
- Source: `llvm-project-23.1.1.src.tar.xz`, SHA-256
  `ebe9be46fe8756d58c5b198ffad0fa2a766257add81a4dc52179bfacc7888ee6`.
- LLVM: Release, `lld`, `X86;AArch64`, zlib 1.3.1 built from source and linked in.
  zstd, libxml2, libedit, ICU, libpfm, Z3, curl, httplib, assertions and the VCS
  revision are off. `-ffile-prefix-map=<build>=.`, and a check refuses a tool that
  holds the build path.
- Linux: musl 1.2.6 and linux-headers 7.0.0 of Alpine 3.24. compiler-rt builtins,
  libunwind, libc++abi and libc++ are built from the same source. Linked `-static -s`.
- macOS: SDK 26.5 of the Command Line Tools with its libc++ headers, macOS 11.0 at
  least, `ld64.lld`, `-Wl,-S`.
- Windows: `WinMsvc.cmake` of the LLVM source with clang-cl and lld-link, xwin 0.10.0
  with CRT 14.44.17.14 and SDK 10.0.26100, tree digest
  `8d6540d83493909af67305354303d51ac0930c25d2793e909d8671133c6bd266`, `/MT`.

## Hosts

Every host builds on the Mac, and none needs the Windows VM to build. Each tool runs
on the machine in the last column for the version check.

| Host | Build | Tools run on | Archive bytes |
|---|---|---|---|
| `linux-x86_64` | cross, musl | Linux VM, arm64, qemu-x86_64 | 26,297,024 |
| `linux-arm64` | cross, musl | Linux VM, Ubuntu 26.04 | 23,617,664 |
| `macos-arm64` | native | the Mac | 25,024,344 |
| `macos-x86_64` | `CMAKE_OSX_ARCHITECTURES=x86_64` | the Mac, Rosetta | 28,162,640 |
| `windows-x86_64` | cross, xwin | Windows VM, arm64, x64 emulation | 25,786,940 |
| `windows-arm64` | cross, xwin | Windows VM, Windows 11 build 26200 | 22,581,036 |

## Verification

| Host | Format | Shared libraries named |
|---|---|---|
| `linux-*` | `elf64-x86-64`, `elf64-littleaarch64` | none, no `INTERP` |
| `macos-*` | `mach-o arm64`, `mach-o 64-bit x86-64` | `libSystem.B.dylib`, `libc++.1.dylib` |
| `windows-*` | `coff-x86-64`, `coff-arm64` | ADVAPI32, KERNEL32, ntdll, OLEAUT32 in lld, CRYPT32 and WINHTTP in llvm-objdump |

Every host prints the same seven lines:

```text
lld -flavor gnu: LLD 23.1.1 (compatible with GNU linkers)
lld -flavor darwin: LLD 23.1.1
lld -flavor link: LLD 23.1.1
llvm-mc: LLVM version 23.1.1
llvm-ar: LLVM version 23.1.1
llvm-objdump: LLVM version 23.1.1
llvm-readobj: LLVM version 23.1.1
```

`SHA256SUMS.sig` verifies with `gpgv` against the key served at
`https://anti-lang.com/keys/release.asc`. In `antic`, all 12 cross links and all 120
assembly tests pass with the downloaded tools, 2 and 20 per target.

## Deviations and choices

- `ldd` runs on Linux alone, so `llvm-objdump --private-headers` reads `NEEDED` and
  `INTERP` of the Linux tools. macOS uses `otool -L`.
- The Windows system set is the six DLLs the tools import.
- SDK 26.5 instead of 27.0, because `ld64.lld` 23.1.1 refuses `arm64e.x1` in 27.0.
- Added beyond the layout: `pins/sysroot.toml`, `pins/zlib.toml`, `pins/build-number`,
  `keys/release.asc`, `scripts/common.sh`, `scripts/run-remote.sh` and `tests/`.
- `ACCEPT_LICENSE=yes` accepted the Microsoft terms for xwin, as the work order asks.
- The `antic` installers check `SHA256SUMS.sig` where `gpgv` exists. A Mac has no
  GnuPG, and there the pinned digest alone checks the archive. `get-llvm.cmake`
  requires `gpgv`.
- `antic` `docs/decisions.md` says macos-x86_64 gets no LLVM build. The work order asks
  for six archives, so it has one, and the entry now says so.

## Not done

Nothing of the work order.
