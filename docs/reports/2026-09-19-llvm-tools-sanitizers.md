# The sanitizer runtimes, 23.1.1-anti.3

Release `23.1.1-anti.3` adds the sanitizer runtimes of Linux and Windows to the clang
archives, beside those of macOS. All twelve archives come from recipe commit `75d7cf4`:
the source and recipe of `23.1.1-anti.2`, with the runtimes added. `./r` published them on
2026-09-19 and found every download identical. Release `23.1.1-anti.1` and its tag are
deleted. The toolchain is frozen at this release.

## Runtimes

| Target | ASan | UBSan |
|---|---|---|
| macOS, arm64 and x86_64 | dylib, as before | dylib, as before |
| `x86_64-unknown-linux-gnu` | static | static |
| `aarch64-unknown-linux-gnu` | static | static |
| `x86_64-pc-windows-msvc` | DLL | static |
| `aarch64-pc-windows-msvc` | none | static |

- The Linux runtimes build against glibc 2.35 and the kernel headers of Ubuntu 22.04,
  three packages of the jammy release pocket per processor. `pins/sysroot.toml` pins them,
  and antic pins the same ones. A runtime built against that glibc runs on every newer one.
- Linux gets the static runtimes, clang's default, and the symbol lists that clang passes
  to the linker. The shared ones would link against GCC's runtime, which the glibc sysroot
  does not hold. antic's `docs/toolchain-later.md` keeps them as one line.
- compiler-rt 23.1.1 builds ASan for Windows on x86 alone, so `windows-arm64` has UBSan
  alone. It built with no patch and reported its fault on the Windows VM.
- compiler-rt adds UBSan whenever it builds a sanitizer, so the recipe names ASan alone.

## Checks

- The step `check-builtins` checks every runtime by name and format. The tests
  `test-builtins` and `test-glibc` cover the check and the glibc sysroot.
- On the Linux VM, the archived clang of `linux-arm64` linked ASan and UBSan programs that
  reported their faults. antic's ASan and UBSan suites there pass 363 of 363 each with them.
- UBSan reported on `windows-arm64` natively and on `windows-x86_64` under x64 emulation.
- The ASan runtimes of x86_64 Linux and x86_64 Windows are built as upstream builds them
  and are unverified on real hardware. Under qemu-user and under x64 emulation their
  allocator stops, as it is known to there. The first release-day run of the workflow on
  `ubuntu-24.04` and `windows-2025` verifies them, and the note in the README comes off.

## Sizes

Each clang archive grew by 2.5 to 2.9 MB. The tools archives are unchanged.

| Host | Clang archive, anti.2 | Clang archive, anti.3 |
|---|---|---|
| `linux-x86_64` | 29,361,240 | 31,886,512 |
| `linux-arm64` | 26,329,364 | 28,861,844 |
| `macos-arm64` | 28,283,196 | 30,824,080 |
| `macos-x86_64` | 31,605,924 | 34,141,888 |
| `windows-x86_64` | 27,937,600 | 30,464,348 |
| `windows-arm64` | 24,568,716 | 27,101,268 |

## Scripts

`./c` builds the builtins and every host, and `./r` packs, signs and publishes with the
key in `keys/private`. `./r` prints each upload, download and comparison on a line.

## Not done

- ASan on real x86_64 hardware, on the first release day.
- ASan for Windows on arm64, which compiler-rt does not build.
