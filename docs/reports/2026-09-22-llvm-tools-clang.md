# The pinned compiler, 23.1.1-anti.2

Each of the six hosts now has a clang archive beside its tools archive. All twelve come
from recipe commit `c621652`, one build of the pinned LLVM 23.1.1 source. Release
`23.1.1-anti.2` holds them with `SHA256SUMS` and its signature, and antic pins it.

## Recipe

- `clang` joins `LLVM_ENABLE_PROJECTS`, and the build adds `clang` and
  `clang-resource-headers`. clang is static and checked like the tools. There is no
  `clang++`.
- `STEP=builtins` builds compiler-rt from the same source for all six targets. They
  replace the builtins of Alpine's `compiler-rt` package.
- The macOS hosts take `deployment-target = "11.0"` from `hosts.toml` into CMake and
  `MACOSX_DEPLOYMENT_TARGET`. The library check reads `minos` with `otool -l` and
  refuses any other value.

## Hosts

All six build on the Mac. Windows cross-built again. Sizes are in bytes.

| Host | Tools archive | Clang archive | Clang unpacked | clang binary |
|---|---|---|---|---|
| `linux-x86_64` | 26,274,336 | 29,361,240 | 130,630,084 | 108,735,104 |
| `linux-arm64` | 23,631,020 | 26,329,364 | 125,674,620 | 103,779,640 |
| `macos-arm64` | 25,032,548 | 28,283,196 | 148,385,584 | 126,496,800 |
| `macos-x86_64` | 28,165,664 | 31,605,924 | 151,631,872 | 129,743,088 |
| `windows-x86_64` | 25,795,328 | 27,937,600 | 118,671,632 | 96,782,848 |
| `windows-arm64` | 22,576,360 | 24,568,716 | 108,506,896 | 86,618,112 |

## Verification of clang

| Host | Format, libraries | Runs on |
|---|---|---|
| `linux-x86_64` | `elf64-x86-64`, none | Linux VM, qemu-x86_64 |
| `linux-arm64` | `elf64-littleaarch64`, none | Linux VM |
| `macos-arm64` | `mach-o arm64`, `minos 11.0`, libSystem and libc++ | the Mac |
| `macos-x86_64` | `mach-o 64-bit x86-64`, `minos 11.0`, libSystem and libc++ | the Mac, Rosetta |
| `windows-x86_64` | `coff-x86-64`, system DLLs | Windows VM, x64 emulation |
| `windows-arm64` | `coff-arm64`, system DLLs | Windows VM |

Every clang prints `clang version 23.1.1`, and the five tools of both macOS hosts
record `minos 11.0`. The builtins check their format per target. The archived clang
linked static musl programs that ran on the Linux VM, and ASan and UBSan programs on the
Mac that caught their faults.

## Choices

- The macOS builtins lie in `lib/clang/23/lib/darwin/`, one universal archive, because
  clang 23 reads them there. The other four targets use `lib/clang/23/lib/<triple>/`.
- The musl targets also get `clang_rt.crtbegin.o` and `clang_rt.crtend.o`, which clang
  takes when it links for musl.
- macOS also gets the ASan and UBSan runtimes, because antic runs its sanitizer builds
  on the Mac with this clang. Linux and Windows have none.
- On Linux, clang compiles for glibc by default and for musl with `--target`.
- `version.dll` joins the system set of Windows, because clang.exe imports it.

## Release

`./c` builds every host and `./r` publishes. `./r` signs with
`keys/private/release-key.enc.pem` and checks against `keys/public/release.pem`, which
the site serves at `keys/release.pem`. It published the 14 files on 2026-09-19 and found
each download identical. The tag names `c621652`.

## Checks of the release

- A fresh clone of antic downloaded both archives of `macos-arm64` from the release and
  checked each against its pin and the signature. Its cache names
  `build/clang/bin/clang` as `CMAKE_C_COMPILER`. The full suite passed 408 of 408, and
  ASan and UBSan passed 407 of 407 each.
- The LLVM step of `install.sh` took the tools of `23.1.1-anti.2` on the Mac and the
  Linux VM, and that of `install.ps1` on the Windows VM, for all six hosts. The x86_64
  ones ran under Rosetta, qemu and x64 emulation. Each `llvm-mc` printed 23.1.1. A copy
  of each installer with another key refused the release and installed nothing.

## Not done

- Release `23.1.1-anti.1` is still published. Nothing pins it, so it goes next.
- `23.1.1-anti.3` adds the sanitizer runtimes of Linux and Windows.
