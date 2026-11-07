# llvm-tools

The eight LLVM tools that Anti ships, `llvm-mc`, `lld`, `opt`, `llc`, `llvm-ar`,
`llvm-objdump`, `llvm-readobj` and `llvm-profdata`, and the clang that builds Anti, for
every host from the pinned LLVM source. A ninth tool, `llvm-cov`, measures the coverage
of Anti's own tests, and Anti does not ship it. `llvm-objcopy` and `llvm-strip`
strip the debug information of a program that was linked once with `-g`, and `dsymutil`
writes the dSYM of a macOS program from it. The compiler that builds them is clang of
the pinned LLVM release. Each host gets two archives, published as assets of a GitHub
release: the tools, and clang with its built-in headers, the compiler-rt builtins of all
six targets, the sanitizer runtimes and the profile runtimes. `antic` downloads the
archives of its host and nothing else from LLVM.

## Releases

A release tag is `<version>-anti.<build>`, as in `23.1.1-anti.2`: the LLVM version,
whose build it is, and a counter of the rebuilds of that version. A rebuild of the same
LLVM version with a changed recipe takes the next build number in `pins/build-number`.
An archive under a published tag is never replaced.

Each release holds these files.

| File | Contents |
|---|---|
| `llvm-tools-<version>-anti.<build>-<host>.tar.xz` | `bin/` with the twelve tools, `licenses/`, `VERSION` |
| `clang-<version>-anti.<build>-<host>.tar.xz` | `bin/clang`, `lib/clang/23/` with the built-in headers, the builtins, the sanitizer runtimes, `libunwind.a` and the profile runtimes, `licenses/`, `VERSION` |
| `SHA256SUMS` | The SHA-256 digest of each archive |
| `SHA256SUMS.sig` | An ECDSA P-256 signature over the SHA-256 digest of `SHA256SUMS` |

`VERSION` names the LLVM version, the build number and the commit of the recipe. Every
archive under one tag comes from one commit.

The builtins lie where clang looks for them: `lib/clang/23/lib/<triple>/` for the two
musl and the two MSVC targets, and one universal `lib/clang/23/lib/darwin/libclang_rt.osx.a`
for both macOS processors. The musl targets also get `clang_rt.crtbegin.o` and
`clang_rt.crtend.o`. On Linux, clang compiles for glibc by default and for musl with
`--target`. There is no `clang++`, because nothing Anti ships is C++.

The sanitizer runtimes of ASan and UBSan lie beside the builtins. macOS has both for
both processors. Linux has the static ones for `x86_64-unknown-linux-gnu` and
`aarch64-unknown-linux-gnu`, built against glibc 2.35 of Ubuntu 22.04, so they run on
that glibc and every newer one. `windows-x86_64` has both, with ASan as a DLL.
`windows-arm64` has UBSan alone, since compiler-rt 23.1.1 builds no ASan for Windows on
arm64.

`libunwind.a`, LLVM's unwinder, lies beside the sanitizer runtimes of
`x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu`. ASan there calls
`_Unwind_Backtrace` and `_Unwind_GetIP`, which glibc leaves to GCC's `libgcc_s`. It is
static, built from the same source against the same glibc 2.35, and needs nothing outside
libc. macOS and Windows have none, since ASan there unwinds with the unwinder of the
system.

The profile runtime of compiler-rt lies beside the builtins of each target that Anti
links: `libclang_rt.profile.a` for the two musl and the two glibc targets,
`clang_rt.profile.lib` for the two MSVC targets, and one universal
`lib/clang/23/lib/darwin/libclang_rt.profile_osx.a` for both macOS processors. A program
that `-fprofile-generate` instruments calls `__llvm_profile_*` from it to write its
counters at exit, and `llvm-profdata merge` turns the `.profraw` files into the
`.profdata` file that `opt` reads. Each is static and built as the other runtimes of its
target are: musl against the musl sysroot, glibc against glibc 2.35, Windows through the
CRT and SDK of xwin, and macOS against the SDK.

`llvm-cov` reads the coverage of a program that clang compiles with
`-fprofile-instr-generate -fcoverage-mapping`. The program writes a `.profraw` file at
exit, `llvm-profdata merge` turns it into a `.profdata` file, and `llvm-cov report` and
`llvm-cov show` count the lines that the run reached. Antic measures its own tests that
way. The Anti package holds no `llvm-cov`.

`llvm-strip` is `llvm-objcopy` under another name. The build of LLVM makes it a symbolic
link, and llvm-objcopy strips when its file name names strip. The archive holds it as a
regular file with the same bytes, so it unpacks on Windows as well.

The hosts are `linux-x86_64`, `linux-arm64`, `macos-arm64`, `macos-x86_64`,
`windows-x86_64` and `windows-arm64`. The Linux binaries link musl, libc++ and zlib
statically and name no shared library. Each asks for a thread stack of 8 MiB in its
`PT_GNU_STACK` header, which musl gives every thread it starts. The macOS binaries name
`libSystem` and `libc++` of the system and record macOS 11.0 as their `minos`. `dsymutil`
also names `CoreFoundation`, which LLVM 23.1.1 links into it on macOS with no option to
drop it, and which every macOS holds. Their
clang records ld64 1267 as its default linker version, the one of `23.1.1-anti.3`, which
the recipe pins rather than read from the Xcode of the build machine. The Windows
binaries link the CRT statically and import system DLLs alone.

## Changes

- `23.1.1-anti.9`: the tools archives carry `llvm-objcopy` and `llvm-strip`, which
  strip the debug information of a program, and `dsymutil`, which writes the dSYM of a
  macOS program.
- `23.1.1-anti.8`: the tools archives carry `llvm-cov`, which reports the coverage of a
  program from the profile that `llvm-profdata` merges.
- `23.1.1-anti.7`: every Linux binary asks for a thread stack of 8 MiB, so ThinLTO in
  `ld.lld` no longer overflows the small default stack of musl.
- `23.1.1-anti.6`: the tools archives carry `llvm-profdata`, and the clang archives the
  profile runtime of every target, the two parts of profile-guided optimisation.
- `23.1.1-anti.5`: the clang archives carry `libunwind.a` beside the sanitizer runtimes
  of Linux on glibc, the unwinder that ASan calls there.
- `23.1.1-anti.4`: the tools archives carry `opt` and `llc` beside `llvm-mc`, the
  optimizer and the code generator of the same source.
- `23.1.1-anti.3`: the clang archives carry the sanitizer runtimes of Linux on glibc and
  of Windows beside those of macOS.

## Signing key

`SHA256SUMS.sig` is signed by the release key of `release@anti-lang.com`, an ECDSA
P-256 key that signs nothing else. Its public key in PEM form is `keys/public/release.pem`
in this repository and https://anti-lang.com/keys/release.pem on the site. The SHA-256
digest of the public key in DER form is its fingerprint:

```text
7e64c56e26a42946823a66aa1f30bf686b6b5dbd0dc0e2c165a080540ffc3eca
```

openssl checks a download, and macOS, Linux and Git for Windows carry it. The first
command prints the fingerprint above.

```sh
openssl pkey -pubin -in release.pem -outform DER | openssl dgst -sha256
openssl dgst -sha256 -binary -out SHA256SUMS.sha256 SHA256SUMS
openssl pkeyutl -verify -pubin -inkey release.pem -in SHA256SUMS.sha256 -sigfile SHA256SUMS.sig
shasum -a 256 -c --ignore-missing SHA256SUMS
```

## Layout

| Path | Contents |
|---|---|
| `c` | Builds the builtins and every host |
| `r` | Packs every host and publishes the release |
| `build-llvm.cmake` | The recipe, which builds one host |
| `checks/hello.ll` | The module that `opt` and `llc` compile for the six triples |
| `checks/hello.proftext` | The profile of `hello.ll` that `llvm-profdata` merges and `opt` applies |
| `checks/hello.c` | The program whose coverage `llvm-cov` reports |
| `hosts.toml` | Per host: triple, build machine, sysroot kind, CMake options |
| `pins/llvm-version` | The LLVM version |
| `pins/source.sha256` | The SHA-256 digest of the LLVM source archive |
| `pins/release.toml` | Per build machine: the LLVM release archive, its digest and its attestation |
| `pins/sysroot.toml` | The musl packages, the macOS SDK and the xwin versions |
| `pins/zlib.toml` | The zlib source |
| `pins/build-number` | The build number of the next release |
| `scripts/build.sh` | Runs the recipe for one host, or for the builtins, on this machine |
| `scripts/pack.sh` | Packs the tools and clang of one host with the licences |
| `scripts/release.sh` | Tags, signs and uploads a release |
| `scripts/run-remote.sh` | Runs a tool of another system over ssh, for the version check |
| `scripts/common.sh` | The TOML readers and names that the scripts share |
| `licenses/` | The licence texts that the archives carry |
| `keys/public/release.pem` | The public key that verifies `SHA256SUMS.sig` |
| `keys/private/` | The private release key, encrypted, which git ignores |
| `tests/` | The tests of the recipe and the scripts |
| `docs/reports/` | The report of each release |
| `docs/memory/` | The state of the releases, open decisions and gotchas of the build |

Everything the recipe downloads and builds stays under `build/`.

## Building a release

The recipe needs CMake 3.25 or newer, Ninja, `gh` for the Sigstore attestation of the
release archive, and `xwin` 0.10.0 for the Windows hosts. Run the builds on the machine
that `hosts.toml` names for each host.

The recipe runs every tool it builds. A Linux or Windows tool runs over ssh on the
machine that `LINUX_REMOTE` or `WINDOWS_REMOTE` names. `./c` sets them to
`eddie@192.168.60.131` and `eddie@192.168.60.132` unless they are set. The Linux
machine needs `qemu-x86_64` through binfmt when its processor is arm64.
`REMOTE_SSH_OPTIONS` passes options to ssh and scp. `opt` and `llc` of a host that runs
on the build machine also compile `checks/hello.ll` for the six triples, and its
`llvm-readobj` checks the format of each object. Its `llvm-profdata` merges
`checks/hello.proftext`, and its `opt` must apply that profile to `hello.ll`. The release
clang compiles `checks/hello.c` with `-fprofile-instr-generate -fcoverage-mapping`, and
the program runs. `llvm-profdata` of the host merges its profile, and `llvm-cov report`
of the host must count the 14 lines of `hello.c`, 2 of them missed.

Commit the recipe first, because `scripts/pack.sh` refuses a build of uncommitted files.
Then build and publish:

```sh
./c
./r
```

`./c` builds the builtins, then each host of `hosts.toml` with `scripts/build.sh`, and
stops at the first failure. It accepts the licence terms of the Microsoft CRT and Windows
SDK, which xwin downloads.

`./r` packs each host with `scripts/pack.sh`, then runs `scripts/release.sh`. A host
whose two archives come from its build is not packed again, so `./r` can run again after
a failure. `scripts/release.sh` writes `SHA256SUMS`, signs it with
`keys/private/release-key.enc.pem` and checks the signature against
`keys/public/release.pem`. openssl asks for the passphrase of the key. The script then
tags the recipe commit and uploads each file, with a line each, to a draft that it
publishes after the last one. It downloads each file again and prints `same` or
`DIFFERS` for each. It needs `gh` logged in to an account that can write releases of
`anti-lang/llvm-tools`.

## Tests

```sh
sh tests/run.sh
```

The tests of the library checks link small programs with the release clang, so they
run after the first build has unpacked it.

## Licence

The recipe and the scripts are under the Apache License 2.0 with LLVM Exceptions, in
`LICENSE`, the licence of LLVM itself. The archives carry the LLVM licence and, for
Linux, the musl licence in `licenses/`.
