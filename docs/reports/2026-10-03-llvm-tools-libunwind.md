# libunwind, 23.1.1-anti.5

Every clang archive now holds `libunwind.a`, LLVM's unwinder, beside the sanitizer
runtimes of `x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu`. The ASan runtime
of `--memory-checks` programs on Linux calls `_Unwind_Backtrace` and `_Unwind_GetIP`
from it. All twelve archives come from recipe commit `5563e5c`, one build of the pinned
LLVM 23.1.1 source. They lie in `build/dist` under the tag `23.1.1-anti.5`. Besides the
two `libunwind.a`, every file of every archive is byte for byte that of anti.4, except
`VERSION`. `./r`, the last section, publishes them.

## Recipe

- The new function `build_unwind` in `build-llvm.cmake` builds the runtime `libunwind`
  of the pinned source as a static library. The builtins step runs it for each host after
  `build_sanitizers`.
- The compiler is the release clang that builds compiler-rt, through the same runtimes
  toolchain file. The sysroot is the glibc 2.35 tree of the sanitizer runtimes, and the
  target is `<arch>-unknown-linux-gnu`.
- `LIBUNWIND_INSTALL_LIBRARY_DIR` puts the library in
  `lib/clang/23/lib/<arch>-unknown-linux-gnu/`. antic's `CMakeLists.txt` reads
  `libclang_rt.asan.a` from that directory of the resource directory.
  `LIBUNWIND_INSTALL_HEADERS=OFF` keeps the headers out of the tree.
- libunwind has a build directory of its own, `build/builtins/<host>-unwind`. The
  configure of the sanitizer runtimes stays as it was, and their bytes stay those of
  anti.4.
- The probes for libdl and libpthread are off. The next section gives the reason.
- The new step `check-unwind` refuses a `libunwind.a` on three grounds. The archive must
  define `_Unwind_Backtrace` and `_Unwind_GetIP`. Every name it leaves undefined must be
  defined by `libc.so.6` or `libc_nonshared.a` of the glibc sysroot. No member may ask the
  linker for a library. The builtins step runs it for both targets after
  `check-builtins`.
- `check-builtins` also refuses a tree without `libunwind.a` of either glibc target, or
  one of the other format. `tests/test-builtins.sh` covers that, and the new
  `tests/test-unwind.sh` covers `check-unwind`.
- `builtins_lib` now names `build/builtins/install/lib/clang/23/lib` once. The three
  places that spelled it out read it.
- `pins/build-number` moves to 5. `pins/llvm-version` stays `23.1.1`.
  `darwin_link_version` stays 1267, and both macOS builds print
  `clang: records the ld64 version 1267`.

## The links that libunwind asked for

A first build with upstream's options gave a `libunwind.a` whose member
`libunwind.cpp.o` carries a `.deplibs` section naming `dl` and `pthread`. lld reads it and
adds `-ldl -lpthread` to every link that takes the member.

The configure probes for both libraries with `check_library_exists`. The try-compiles of
the runtimes build static libraries and link nothing, so the probe passes for any library
name. libunwind then defines `_LIBUNWIND_LINK_DL_LIB` and `_LIBUNWIND_LINK_PTHREAD_LIB`,
and its sources emit `#pragma comment(lib, ...)` for each.

glibc 2.34 and newer hold `dladdr`, `dlsym`, `dl_iterate_phdr` and the pthread
functions in `libc.so.6`. The recipe sets `LIBUNWIND_HAS_DL_LIB=OFF` and
`LIBUNWIND_HAS_PTHREAD_LIB=OFF`, which skips both probes. `check-unwind` refused the
first build with `asks the linker for the library dl;pthread`, and passes the shipped one.

## Hosts

Both glibc targets get `libunwind.a`, and every clang archive carries both copies.
Every clang archive already carries the runtimes of all six targets in one
`lib/clang/23/lib` tree, so the macOS and Windows archives hold the two copies too. A
clang of any host finds them when it links for a glibc target.

No macOS or Windows target gets a `libunwind.a` of its own. Their compiler-rt is not
built against the glibc sysroot as that of Linux is:

- macOS: compiler-rt builds the ASan and UBSan dylibs with the Darwin builtins against
  the macOS SDK. ASan there unwinds with the unwinder of `libSystem`.
- Windows: compiler-rt builds the sanitizer runtimes through `WinMsvc.cmake` against the
  xwin CRT and SDK. ASan there unwinds with the stack walker of Windows.

Sizes are in bytes, as shipped. The SHA-256 digest is that of the file in every one of the
six clang archives.

| Target | `libunwind.a` | SHA-256 |
|---|---|---|
| `x86_64-unknown-linux-gnu` | 137,622 | `014ef378c0aea16dac092ff84a641a1dbf708a29a14d81b8832e444166e254dd` |
| `aarch64-unknown-linux-gnu` | 145,794 | `cca5cf64cc6a2bdef5334a5818d685786ac31421aa9056c489580d9ea13f8d74` |

| Host | Clang archive, anti.4 | Clang archive, anti.5 | Growth |
|---|---|---|---|
| `linux-x86_64` | 31,893,256 | 31,964,636 | 71,380 |
| `linux-arm64` | 28,866,716 | 28,936,004 | 69,288 |
| `macos-arm64` | 30,824,768 | 30,882,556 | 57,788 |
| `macos-x86_64` | 34,133,616 | 34,196,960 | 63,344 |
| `windows-x86_64` | 30,462,592 | 30,522,700 | 60,108 |
| `windows-arm64` | 27,089,220 | 27,164,136 | 74,916 |

The tools archives differ from those of anti.4 in `VERSION` alone, and in size by a few
KB of xz output.

## Verification

All checks ran on the Mac, `macos-arm64`, except the run of the stack walk on the Linux
VM.

- `llvm-nm` of both libraries lists `T _Unwind_Backtrace` and `T _Unwind_GetIP`.
- The names that each library needs from outside itself are all in libc. x86_64 needs
  `__assert_fail`, `abort`, `dl_iterate_phdr`, `dladdr`, `dlsym`, `fflush`, `fprintf`,
  `free`, `fwrite`, `getenv`, `malloc`, `memcpy` and `memset`. It also needs
  `pthread_rwlock_rdlock`, `pthread_rwlock_unlock`, `pthread_rwlock_wrlock`, `snprintf`
  and `stderr`. aarch64 needs the same names and `__errno_location`, `getauxval` and
  `syscall`.
- `check-unwind` on the copies in the `linux-x86_64` clang archive prints:

```text
-- x86_64: libunwind.a defines _Unwind_Backtrace;_Unwind_GetIP, and libc defines the 36 names it needs
-- aarch64: libunwind.a defines _Unwind_Backtrace;_Unwind_GetIP, and libc defines the 40 names it needs
```

- The counts of 36 and 40 include the names that one member of the archive takes from
  another.
- Neither library holds a `.deplibs` section or the path of the build tree.
- A C program that walks its stack with `_Unwind_Backtrace` and `_Unwind_GetIP` linked
  against `crt1.o`, `crti.o`, `libunwind.a`, `libc.so.6`, `libc_nonshared.a` and
  `crtn.o`. The link used the release clang and lld with the glibc sysroot. Each
  binary names `libc.so.6` alone. On the Linux VM both print `frames 5` and exit 0,
  aarch64 natively and x86_64 under qemu-x86_64.
- The clang of the `macos-arm64` archive resolves
  `--target=<arch>-unknown-linux-gnu -print-file-name=libunwind.a` to
  `lib/clang/23/lib/<arch>-unknown-linux-gnu/libunwind.a` of its own archive.
- The two `libunwind.a` in each of the six clang archives have the same digests.
- `diff -r` of each anti.5 archive against its anti.4 archive reports `VERSION` and,
  for the clang archives, the two `libunwind.a`. Nothing else differs.
- The version check passed on every host, on the VMs for Linux and Windows. The codegen
  check passed six of six on both macOS hosts. Each `VERSION` reads `llvm 23.1.1`,
  `build 5`, `recipe 5563e5c…`.
- `sh tests/run.sh` passes all 13 tests.

## Choices

- `LIBUNWIND_ENABLE_ASSERTIONS` keeps upstream's default, ON. The library then compiles
  with `-D_DEBUG -UNDEBUG` and calls `__assert_fail` of glibc on a broken unwind table.
  The musl runtimes that link the tools build libunwind with the same default. Setting it
  OFF drops the assertions. That is a build option for Eddie to decide, and the recipe
  pins nothing about it.
- `LIBUNWIND_USE_COMPILER_RT=ON` and `LIBUNWIND_ENABLE_SHARED=OFF` match the libunwind
  of the musl runtimes. The first changes only the link of a shared library, which is
  not built.
- The log line of `check-unwind` prints the two names as a CMake list, joined by `;`.
  The text is cosmetic and is left for a later recipe change.
- This repository has no `CLAUDE.md` of its own. The README and this report follow the
  rules of the earlier reports.

## Not done

- The antic side. `tools/llvm-pin` needs the new tag and its six digests. The runtime
  archive needs `libunwind.a` copied beside the ASan files of both glibc targets. The
  Linux link of `--memory-checks` needs it, and `MEMCHECK_OPTIONS` needs
  `fast_unwind_on_fatal=1`. That follows once the release exists.
- An ASan program of antic linked with this `libunwind.a`. The stack walk above tests
  the two functions alone.
- `main` holds the recipe and this report, and neither is pushed. `./r` pushes the tag on
  `5563e5c`.

## Publishing

Eddie runs, from the top of the repository:

```sh
./r
```

`./r` finds each of the six hosts packed from its build at `5563e5c` and runs
`scripts/release.sh`. That writes `SHA256SUMS` of the twelve archives and signs it with
`keys/private/release-key.enc.pem`, whose passphrase openssl asks for. It tags `5563e5c`
as `23.1.1-anti.5` and pushes the tag. It then uploads the 14 files to a draft, which it
publishes after the last one.
