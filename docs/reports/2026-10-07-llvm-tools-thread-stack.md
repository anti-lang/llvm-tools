# The thread stack, 23.1.1-anti.7

Every static musl binary of both Linux hosts, the eight tools and clang, now asks for a
thread stack of 8 MiB in its `PT_GNU_STACK` header. musl reads that size at start and
gives it to every thread the program creates. Before, the header asked for none, and
musl gave each thread its small default. The ThinLTO link of antic's
`tests/bench/ablate/mixed_work.anti` crashed the linux-arm64 `ld.lld` of anti.6 there,
in a worker thread 504 frames deep. All twelve archives come from recipe commit
`e9e1888`, one build of the pinned LLVM 23.1.1 source. They lie in `build/dist` under
the tag `23.1.1-anti.7`. Besides `VERSION` and the nine binaries of each Linux host,
every file of every archive is byte for byte that of anti.6. `./r`, the last section,
publishes them.

## Recipe

- `musl_thread_stack` holds the size, 8388608 bytes, once. It is the stack LLVM gives
  its threads on Apple, and the most musl takes from the header.
- `write_toolchain` adds `-Wl,-z,stack-size=${musl_thread_stack}` to
  `CMAKE_EXE_LINKER_FLAGS_INIT` of the Linux hosts, beside `-static -s`. The runtimes
  toolchain, zlib and the macOS and Windows hosts are unchanged.
- The new step `check-stack` refuses a Linux binary whose `PT_GNU_STACK` asks for less
  than `musl_thread_stack`, and one without the header. `llvm-readobj --program-headers`
  of the release reads it, since the binaries need not run on the Mac. It refuses a host
  that is not Linux. The build runs it after `check-libraries` for both Linux hosts.
- `tests/test-stack.sh` links static programs with the release clang. 8 MiB and 16 MiB
  pass. 4 MiB, no size, the form of anti.6, and `-z nognustack` are refused, and so is
  a macOS host.
- `pins/build-number` moves to 7. `pins/llvm-version` stays `23.1.1`. The README states
  the stack and lists anti.7 under Changes.

## The crash, before and after

antic fixed the cause it met on 2026-10-07 in `45e8bcee`. The runtime bitcode of musl
carried the triple `aarch64-unknown-linux-musl` beside the program's
`aarch64-unknown-linux-gnu`, and ThinLTO recursed deeply on it. To reproduce, the thin
runtime bitcode of linux-arm64 at `armv8.0` was compiled again with the old triple and
put into a copy of the runtime directory of anti-linux. antic then linked `mixed_work`
with `--lto thin`, three times with each `ld.lld`:

| `ld.lld` | `PT_GNU_STACK` size | Result |
|---|---:|---|
| anti.6 | 0 | `ld.lld ended by signal 11`, 3 of 3 |
| anti.7 | 8,388,608 | linked, and the program printed `615670597359`, 3 of 3 |

## Hosts

The twelve archives of anti.7:

```text
de70eee754a49dde5eb2c13fc8485dabfc7580be28a8b2078403b6ea2ddf4b47  clang-23.1.1-anti.7-linux-arm64.tar.xz
7ae5230595a587045d0bc24226873a57b22de9047d2639fe1d21627384050c69  clang-23.1.1-anti.7-linux-x86_64.tar.xz
404fdb3b48e27c2a75ccc0c55c3f25a50ee4b8f5e2b11314e60556df249a5aa7  clang-23.1.1-anti.7-macos-arm64.tar.xz
ce4ae9cedbac8744404b01d025b260300064673946d1890dbb2e98389fbbdce9  clang-23.1.1-anti.7-macos-x86_64.tar.xz
3a4a3fbdb4184961b25c0dcc62f63d4d09e34c817bbecd618c1caef3f013ce3b  clang-23.1.1-anti.7-windows-arm64.tar.xz
1a8fe9d71490bd4305ffa26ba6ede51ffe0f9f2c21ba39256dddcc8354bee5af  clang-23.1.1-anti.7-windows-x86_64.tar.xz
5099148b8f5f4bd21ad820bb201a110eb8d804738bcd0351510998367733e8b6  llvm-tools-23.1.1-anti.7-linux-arm64.tar.xz
0d14304c46608d284920db1fce8dc4c78d76744c908d6736b358ca79e2323be4  llvm-tools-23.1.1-anti.7-linux-x86_64.tar.xz
d4ae1fa0264a1442bf2f5e1d02f95bdf37b89ee881089e562ded0d3af2ddab3a  llvm-tools-23.1.1-anti.7-macos-arm64.tar.xz
1b5ded447883adb599556ff13a2c7da1ad335060eb7f98d1107b3af341309791  llvm-tools-23.1.1-anti.7-macos-x86_64.tar.xz
0e92ddbb9b8cd8bd2eaa78c32da42d9bc1a5b8d03d7537852fc51b8016d351e5  llvm-tools-23.1.1-anti.7-windows-arm64.tar.xz
08b43f95f228a048ddd48bcf6bac5d7df940aeebc838f05abb50523d27a79462  llvm-tools-23.1.1-anti.7-windows-x86_64.tar.xz
```

## Verification

The build ran on the Mac, `macos-arm64`, with its log in `build/logs/anti7-c.log`. The
version checks of the Linux and Windows hosts ran on the test VMs.

- The stack check printed `a thread stack of 8388608 bytes` for each of the nine
  binaries of both Linux hosts, 18 lines. The library check, the check for the build
  path and the version check passed on all six hosts, and both macOS builds printed
  `clang: records the ld64 version 1267`.
- `diff -r` of each anti.7 archive against its anti.6 archive reports `VERSION` alone for
  the four macOS and Windows hosts. For the two Linux hosts it reports `VERSION` and
  `bin/` of all eight tools in the tools archive, and `VERSION` and `bin/clang` in the
  clang archive. Nothing else differs.
- Each of those 18 binaries differs from its anti.6 copy in one byte, the size field of
  `PT_GNU_STACK`, which reads 8388608.
- Each `VERSION` reads `llvm 23.1.1`, `build 7`, `recipe e9e1888…`.
- `sh tests/run.sh` passes all 15 tests.

## Choices

- The size is 8 MiB, the stack LLVM gives its threads on Apple. musl caps the size it
  takes from the header at 8 MiB, so a larger request would give no more.
- The header sets the default of every thread, those of LLVM's thread pool and any
  other, so no source of LLVM is patched. The main thread keeps the stack of the
  system.
- The recipe pins no build option with a test. `check-stack` refuses a binary that lost
  the flag, as `check-libraries` refuses one that lost `-static`.

## Not done

- The antic side, once the release exists: `tools/llvm-pin` and `tools/clang-pin` of
  antic take the tag `23.1.1-anti.7` and the twelve digests above. antic's report of
  2026-10-07 names that step.
- `main` holds the recipe and this report, and neither is pushed. `./r` pushes the tag
  on `e9e1888`.

## Publishing

Eddie runs, from the top of the repository:

```sh
./r
```

`./r` finds each of the six hosts packed from its build at `e9e1888` and runs
`scripts/release.sh`. That writes `SHA256SUMS` of the twelve archives and signs it with
`keys/private/release-key.enc.pem`, whose passphrase openssl asks for. It tags `e9e1888`
as `23.1.1-anti.7` and pushes the tag. It then uploads the 14 files to a draft, which it
publishes after the last one.
