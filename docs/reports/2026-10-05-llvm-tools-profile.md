# The profiler, 23.1.1-anti.6

Every tools archive now holds `llvm-profdata`, eight tools in all. Every clang archive
holds the profile runtime of compiler-rt for the seven targets that antic links. These
are the two parts of profile-guided optimisation that antic's step `pgo` needs, as
`antic/docs/reports/2026-10-05-llvm-opt-pgo.md` lists them. All twelve archives come
from recipe commit `b9af7ef`, one build of the pinned LLVM 23.1.1 source. They lie in
`build/dist` under the tag `23.1.1-anti.6`. Besides `llvm-profdata` and the seven
runtimes, every file of every archive is byte for byte that of anti.5, except `VERSION`.
`./r`, the last section, publishes them.

## Recipe

- `hosts.toml` names `llvm-profdata` in `tools`, after `llvm-readobj`. The build, the
  library check, the check for the build path, the version check and `scripts/pack.sh`
  read that list. `llvm-profdata` is built, linked, checked and packed as the other seven
  are: static against musl on Linux, `minos 11.0` on macOS, the xwin CRT and SDK on
  Windows. It reads compressed profiles through the pinned zlib.
- The new function `build_profile` builds the profile runtime of the pinned compiler-rt.
  The builtins step runs it for each host after `build_unwind`. Each build has a
  directory of its own, so the builtins, the sanitizer runtimes and libunwind keep the
  bytes of anti.5:
  - `build/builtins/linux-<arch>-profile` builds `<arch>-unknown-linux-musl` against the
    musl sysroot of the host, as the builtins are built.
  - `build/builtins/linux-<arch>-profile-glibc` builds `<arch>-unknown-linux-gnu` against
    the glibc 2.35 sysroot, as the sanitizer runtimes are built.
  - `build/builtins/windows-<arch>-profile` builds `<arch>-pc-windows-msvc` through
    `WinMsvc.cmake` with the xwin CRT and SDK.
  - `build/builtins/macos-arm64-profile` builds one universal
    `darwin/libclang_rt.profile_osx.a` for arm64 and x86_64 against the macOS SDK, as the
    Darwin builtins are built.
- Each build turns every runtime of compiler-rt off but the profile runtime, and installs
  the component `install-profile` alone.
- The new step `check-profile` refuses a profile runtime on four grounds. It must define
  `__llvm_profile_runtime` and `__llvm_profile_write_file`, for arm64 and x86_64 alike on
  Darwin. On Linux every name it needs from outside must be one that the C library of its
  sysroot or the linker defines. For glibc the C library is `libc.so.6` with
  `libc_nonshared.a`, for musl `libc.a`. On Linux no member may ask the linker for a
  library. No runtime may hold the path of the build tree. The builtins step runs it for
  all seven after `check-unwind`. `tests/test-profile.sh` covers it.
- `check-builtins` refuses a tree without the profile runtime of any of the seven
  targets, or one of the other format. `tests/test-builtins.sh` covers that.
- `check-codegen` merges `checks/hello.proftext` with `llvm-profdata merge`. `opt` then
  runs `default<O2>` with `-pgo-kind=pgo-instr-use-pipeline -profile-file=hello.profdata`
  on `checks/hello.ll`, and `opt -passes=verify` must accept the result. The result must
  also carry the entry count of `@main` from the profile. `opt` drops a profile whose hash
  does not match with a warning and status 0, and the check refuses that case.
  `tests/test-codegen.sh` covers it with a profile of another hash.
- `check-version` covers `llvm-profdata` through the list of tools, and
  `tests/test-version.sh` refuses one that reports another version.
- `checks/hello.proftext` is the new fixture. It holds the profile of one run of
  `@main`, two counters under the hash of `@main` after `default<O2>` inlines `@sum`.
- `refuse_dependent_libraries` holds the `.deplibs` check that `check-unwind` had inline,
  and both steps call it. `build_root_regex` moves up beside `prefix_map`, so the tool
  check and `check-profile` read one definition.
- `tests/test-libraries.sh` and `tests/test-pack.sh` read the tools from the recipe
  instead of a list of their own.
- `pins/build-number` moves to 6. `pins/llvm-version` stays `23.1.1`.
  `darwin_link_version` stays 1267, and both macOS builds print
  `clang: records the ld64 version 1267`.

## The probes and the names of the linker

compiler-rt's `lib/profile` calls no `check_library_exists`. Its four probes are
`CHECK_CXX_SOURCE_COMPILES` of atomics, `fcntl` locks, `flock` and `uname`. They compile
against the headers of the sysroot and need no link, so the try-compiles of the runtimes
give the answer of the sysroot. The `check_library_exists` calls of `config-ix.cmake`
pass for any library, as `docs/memory/build-gotchas.md` says. They feed the link
libraries of shared runtimes alone, and the profile runtime is static. No shipped runtime holds a `.deplibs`
section.

The first `check-profile` refused the Linux runtimes for `__ehdr_start`. The runtime reads
the build ID of the program through it, a strong hidden reference that lld and GNU ld
define. `profile_linker_names` names it, and the check accepts it as defined by the
linker. The section bounds `__start___llvm_prf_*` and `__stop___llvm_prf_*` are weak
references, which the check leaves out. `tests/test-profile.sh` holds both cases.

## Hosts

Sizes are in bytes, as shipped. Each runtime has the same SHA-256 digest in all six clang
archives.

| Target | File | Size | SHA-256 |
|---|---|---|---|
| `x86_64-unknown-linux-musl` | `libclang_rt.profile.a` | 169,428 | `2ca43fb5e8cf785f572fcc15f1c09dd9ec1abfd82e248f9fb9cc44d1f0d8bfe3` |
| `aarch64-unknown-linux-musl` | `libclang_rt.profile.a` | 175,748 | `fd95b05434db1161d8f38ab36723ab73725d04e0309f17c8677197f4278037b8` |
| `x86_64-unknown-linux-gnu` | `libclang_rt.profile.a` | 169,540 | `2b95a9c9991171c8ee31ad8bb9df8c017736414a680be752c8afceac229e0349` |
| `aarch64-unknown-linux-gnu` | `libclang_rt.profile.a` | 175,788 | `3aed4497f3caa83891947e17e8b9dd02b9fb7c7b2b9514d597dcb202061682bc` |
| `x86_64-pc-windows-msvc` | `clang_rt.profile.lib` | 152,882 | `7753d4b1280faad4dc69df3317e5dbb700f47a5e822e17712e96c13945fd386c` |
| `aarch64-pc-windows-msvc` | `clang_rt.profile.lib` | 151,522 | `b8b387c66d9ad22cafb75418f3f2aa8902274287fde1a769894f223ca73bfa7c` |
| `darwin`, arm64 and x86_64 | `libclang_rt.profile_osx.a` | 228,104 | `fe96d8fe3b6e4432808f88c397f1ab5c659737f9a3136bb4ab07a520692fb3e6` |

| Host | `llvm-profdata` | SHA-256 |
|---|---|---|
| `linux-x86_64` | 6,768,800 | `69c70ce60e6a70e764c4c8a21b7c8c8060556c07218ee083301a87ec4143519a` |
| `linux-arm64` | 6,510,904 | `da7dca45ecb1d11200a97432b7b5aa5ab9628970f55e63463278ad79a1dade55` |
| `macos-arm64` | 7,170,992 | `f37859532ae43aed730eede56cd19808422a9422413c015577ce43924d6cb929` |
| `macos-x86_64` | 7,458,392 | `ad002ec747a94bba32e20e0a47cbacd03fd991d02eb2eaff6ee9c345f00799b2` |
| `windows-x86_64` | 6,462,976 | `45c16117df0a3f5dde64f8542213f65359f9775b4db2873fbae87ea5d4014e66` |
| `windows-arm64` | 5,870,592 | `fd6f783eeceb8654d21c013e6dc8de0406b710c43b5068ff58f323163409c1b6` |

| Host | Tools, anti.5 | Tools, anti.6 | Growth | Clang, anti.5 | Clang, anti.6 | Growth |
|---|---|---|---|---|---|---|
| `linux-x86_64` | 58,207,088 | 59,504,208 | 1,297,120 | 31,964,636 | 32,123,632 | 158,996 |
| `linux-arm64` | 51,819,892 | 53,010,396 | 1,190,504 | 28,936,004 | 29,099,632 | 163,628 |
| `macos-arm64` | 54,411,340 | 56,111,556 | 1,700,216 | 30,882,556 | 31,063,076 | 180,520 |
| `macos-x86_64` | 61,933,048 | 63,882,332 | 1,949,284 | 34,196,960 | 34,367,592 | 170,632 |
| `windows-x86_64` | 54,855,680 | 56,460,784 | 1,605,104 | 30,522,700 | 30,704,892 | 182,192 |
| `windows-arm64` | 47,578,316 | 48,903,092 | 1,324,776 | 27,164,136 | 27,337,428 | 173,292 |

The twelve archives of anti.6:

```text
895a36019c07062e750561cb2ab837bee560aa68a7c315b641f48d603e83c6cc  clang-23.1.1-anti.6-linux-arm64.tar.xz
9b278a22d17cab47e40514e5ba383af885d9ac89a3e1f934efe658ee7ce987dd  clang-23.1.1-anti.6-linux-x86_64.tar.xz
b9ca89f46a72f2b23e7790d3ffcd2d65705c066156432085070f7637ee336bd7  clang-23.1.1-anti.6-macos-arm64.tar.xz
8c90332bcf820a237b5d95573ac70771402daa12b1bffd7d9a0a2b9698a066e0  clang-23.1.1-anti.6-macos-x86_64.tar.xz
10da478ecc2c5e4ebe7bc8280a9c26e6c391679385b5150269deb69cb6a6f525  clang-23.1.1-anti.6-windows-arm64.tar.xz
c3b7575943993667a5d3c80a65fc6c623b1450c514e1459ac9f5ad3f901698da  clang-23.1.1-anti.6-windows-x86_64.tar.xz
dcb364a8b8b1c03e5228c3ac8051bcb4366f48ed84f755322b2da9be0f5a007b  llvm-tools-23.1.1-anti.6-linux-arm64.tar.xz
7142333e32df8cb9e75ca04be18d7893f0486569cd65d28b7389e935944dfe26  llvm-tools-23.1.1-anti.6-linux-x86_64.tar.xz
88d265e9fd43d717ab66bb5a16690a843d102c234d227c1b0e50ce559f8e16af  llvm-tools-23.1.1-anti.6-macos-arm64.tar.xz
e304feb3e2e257a6d924d6bb9565369dc10e4c922140f1824bfca868c67dc274  llvm-tools-23.1.1-anti.6-macos-x86_64.tar.xz
8e07ae5d17b0d0dcff3828b2eec4c228d51a9fe829507665f02dc1ef9b273261  llvm-tools-23.1.1-anti.6-windows-arm64.tar.xz
597f6b31edf3502b6feaafceb64e6cdb724de1f7ba72ba8176db011ca9483b57  llvm-tools-23.1.1-anti.6-windows-x86_64.tar.xz
```

## Verification

The build ran on the Mac, `macos-arm64`, with its log in `build/logs/anti6-c.log`. The
version checks of the Linux and Windows hosts ran on the test VMs.

- The builtins step printed, for the seven runtimes:

```text
-- x86_64-unknown-linux-musl: libclang_rt.profile.a defines __llvm_profile_runtime and __llvm_profile_write_file, and libc defines the 43 names it takes from outside
-- aarch64-unknown-linux-musl: libclang_rt.profile.a defines __llvm_profile_runtime and __llvm_profile_write_file, and libc defines the 43 names it takes from outside
-- x86_64-unknown-linux-gnu: libclang_rt.profile.a defines __llvm_profile_runtime and __llvm_profile_write_file, and libc defines the 43 names it takes from outside
-- aarch64-unknown-linux-gnu: libclang_rt.profile.a defines __llvm_profile_runtime and __llvm_profile_write_file, and libc defines the 43 names it takes from outside
-- x86_64-pc-windows-msvc: clang_rt.profile.lib defines __llvm_profile_runtime and __llvm_profile_write_file
-- aarch64-pc-windows-msvc: clang_rt.profile.lib defines __llvm_profile_runtime and __llvm_profile_write_file
-- darwin: libclang_rt.profile_osx.a defines __llvm_profile_runtime and __llvm_profile_write_file
```

- The 43 names are those of the C library: `atexit`, `calloc`, `fopen`, `fcntl`, `fork`,
  `mmap`, `madvise`, `prctl`, `uname` and their kin. musl needs `atoi`, glibc `strtol`.
  The aarch64 runtimes need no outline-atomics helper.
- Each host printed `llvm-profdata: LLVM version 23.1.1`, `linux-x86_64` under
  qemu-x86_64 and `windows-x86_64` under x64 emulation. Its library check printed
  `no library outside the system set`. On Linux it is static and has no `INTERP`. On
  macOS it names `libSystem.B.dylib` and `libc++.1.dylib` and records `minos 11.0`. On
  Windows it imports ADVAPI32, CRYPT32, KERNEL32, WINHTTP and ntdll.
- Both macOS builds printed
  `opt applies the profile of hello.proftext that llvm-profdata merges to hello.ll, and
  the module verifies`. The step passed again on the tools unpacked from both macOS
  archives.
- No shipped runtime and no `llvm-profdata` holds the path of the build tree. No Linux
  runtime holds a `.deplibs` section.
- The clang of the `macos-arm64` archive resolves `-print-file-name` of the runtime to
  `lib/clang/23/lib/<triple>/` of its own archive for the musl, glibc and MSVC targets.
  On macOS it links `lib/clang/23/lib/darwin/libclang_rt.profile_osx.a`.
- `diff -r` of each anti.6 archive against its anti.5 archive reports `VERSION` and
  `bin/llvm-profdata` for the tools archives. It reports `VERSION` and the seven runtimes
  for the clang archives. Nothing else differs.
- Each `VERSION` reads `llvm 23.1.1`, `build 6`, `recipe b9af7ef…`.
- `sh tests/run.sh` passes all 14 tests.

### End to end

A C program with a loop was compiled with `-O1 -fprofile-generate` by the clang of the
`macos-arm64` archive. It was linked by the lld of the `macos-arm64` tools archive with
the profile runtime of its target, from the same clang archive. Each run printed
`sum 45`, exited 0 and wrote its `.profraw`. A shipped `llvm-profdata` merged each one,
and `llvm-profdata show --counts` printed `main` with the hash `0x0209aa3e1d398548` and
the block counts `[10, 1]`.

| Target | Link | Ran on | Merged with |
|---|---|---|---|
| macOS arm64 | clang driver, ld64 | the Mac | `llvm-profdata` of `macos-arm64` |
| macOS x86_64 | clang driver, ld64 | the Mac, Rosetta | `llvm-profdata` of `macos-x86_64`, Rosetta |
| `aarch64-unknown-linux-gnu` | by path, as below | the Linux VM | `llvm-profdata` of `linux-arm64` |
| `x86_64-unknown-linux-gnu` | by path, as below | the Linux VM, qemu-x86_64 | `llvm-profdata` of `linux-x86_64`, qemu-x86_64 |
| `aarch64-unknown-linux-musl` | clang driver, `-static -rtlib=compiler-rt` | the Linux VM | `llvm-profdata` of `linux-arm64` |
| `x86_64-unknown-linux-musl` | clang driver, `-static -rtlib=compiler-rt` | the Linux VM, qemu-x86_64 | `llvm-profdata` of `linux-x86_64`, qemu-x86_64 |
| `aarch64-pc-windows-msvc` | clang-cl, `/winsysroot`, lld-link | the Windows VM | `llvm-profdata.exe` of `windows-arm64` |
| `x86_64-pc-windows-msvc` | clang-cl, `/winsysroot`, lld-link | the Windows VM, x64 emulation | `llvm-profdata.exe` of `windows-x86_64`, x64 emulation |

- The glibc sysroot holds no GCC, so the glibc links name `crt1.o`, `crti.o`, the object,
  `libclang_rt.profile.a`, `libc.so.6`, `libc_nonshared.a` and `crtn.o` by path, with
  `-u __llvm_profile_runtime`. Each binary names `libc.so.6` alone.
- The musl binaries are static, `not a dynamic executable` for `ldd`.
- On Windows the profile also counts `printf` and `__local_stdio_printf_options`, the
  inline functions of the UCRT headers.
- ld64 warned on both macOS links that it ignores `-lto_library`, since the clang archive
  carries no `libLTO.dylib`. It also warned that it reduces the alignment of
  `__llvm_prf_cnts`, `__llvm_prf_data` and `__llvm_prf_bits` from 0x4000 to 0x1000. Both
  programs ran and wrote their profiles.

## Choices

Every option of the profile runtime and of `llvm-profdata` keeps upstream's default. The
recipe pins none of them with a test. These are the ones that decide what ships.

- `COMPILER_RT_BUILD_PROFILE` is ON, upstream's default. The recipe sets it ON in the
  profile builds, which turn every other runtime of compiler-rt off.
- `COMPILER_RT_PROFILE_BAREMETAL` keeps upstream's default, OFF. The runtime therefore
  carries the file I/O, the merge of an existing profile, value profiling and the gcov
  runtime `GCDAProfiling.c`.
- `COMPILER_RT_BUILD_PROFILE_ROCM` keeps upstream's default, ON on Linux and Windows. It
  builds `clang_rt.profile_rocm` only when the same build holds the sanitizer libraries,
  and the profile builds hold none. No `profile_rocm` is built or shipped. It collects
  device profiles of HIP programs on ROCm, which antic does not compile.
- On Windows compiler-rt builds the profile runtime with the static CRT, `/MT`, whatever
  the build asks for. Its objects name `libcmt.lib`, `oldnames.lib` and `uuid.lib` as
  default libraries. A program linked against the DLL CRT, `/MD`, would get both CRTs.
- `llvm-profdata` reads zlib-compressed profiles through the pinned zlib.
  `LLVM_ENABLE_ZSTD` is OFF for every tool, so it cannot read zstd-compressed ones.
  `LLVM_ENABLE_CURL` and `LLVM_ENABLE_HTTPLIB` are OFF, so it fetches nothing through
  debuginfod. These options are those of anti.5, and the recipe changes none of them.
- `check-codegen` runs `opt` with `-pgo-kind=pgo-instr-use-pipeline -profile-file`, the
  form that `opt` takes. antic may pass the profile another way.
- `check-profile` accepts `__ehdr_start` as a name that the linker defines. The previous
  section gives the reason.
- This repository has no `CLAUDE.md` of its own. The README and this report follow the
  rules of the earlier reports.

## Not done

- The antic side, once the release exists:
  - `tools/llvm-pin` and `tools/clang-pin` take the tag `23.1.1-anti.6` and the twelve
    digests above.
  - `tools/get-llvm.cmake` names `llvm-profdata` among the tools it installs.
  - `tools/check-llvm.cmake` checks its version, and the test `pinned_tools` checks it as
    it checks `opt` and `llc`.
  - The runtime archive carries the profile runtime of each target and level that antic
    links, from `lib/clang/23/lib/` of the clang archive.
- An instrumented program of antic's own. The runs above use a C program.
- A run of the x86_64 runtimes on real x86_64 hardware. They ran under qemu-x86_64,
  Rosetta and x64 emulation.
- `main` holds the recipe and this report, and neither is pushed. `./r` pushes the tag on
  `b9af7ef`.

## Publishing

Eddie runs, from the top of the repository:

```sh
./r
```

`./r` finds each of the six hosts packed from its build at `b9af7ef` and runs
`scripts/release.sh`. That writes `SHA256SUMS` of the twelve archives and signs it with
`keys/private/release-key.enc.pem`, whose passphrase openssl asks for. It tags `b9af7ef`
as `23.1.1-anti.6` and pushes the tag. It then uploads the 14 files to a draft, which it
publishes after the last one.
