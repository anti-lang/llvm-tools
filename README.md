# llvm-tools

The five LLVM tools that Anti ships, `llvm-mc`, `lld`, `llvm-ar`, `llvm-objdump` and
`llvm-readobj`, and the clang that builds Anti, for every host from the pinned LLVM
source. The compiler that builds them is clang of the pinned LLVM release. Each host
gets two archives, published as assets of a GitHub release: the tools, and clang with
its built-in headers and the compiler-rt builtins of all six targets. `antic` downloads
the archives of its host and nothing else from LLVM.

## Releases

A release tag is `<version>-anti.<build>`, as in `23.1.1-anti.2`: the LLVM version,
whose build it is, and a counter of the rebuilds of that version. A rebuild of the same
LLVM version with a changed recipe takes the next build number in `pins/build-number`.
An archive under a published tag is never replaced.

Each release holds these files.

| File | Contents |
|---|---|
| `llvm-tools-<version>-anti.<build>-<host>.tar.xz` | `bin/` with the five tools, `licenses/`, `VERSION` |
| `clang-<version>-anti.<build>-<host>.tar.xz` | `bin/clang`, `lib/clang/23/` with the built-in headers and the builtins, `licenses/`, `VERSION` |
| `SHA256SUMS` | The SHA-256 digest of each archive |
| `SHA256SUMS.sig` | An ECDSA P-256 signature over the SHA-256 digest of `SHA256SUMS` |

`VERSION` names the LLVM version, the build number and the commit of the recipe. Every
archive under one tag comes from one commit.

The builtins lie where clang looks for them: `lib/clang/23/lib/<triple>/` for the two
musl and the two MSVC targets, and one universal `lib/clang/23/lib/darwin/libclang_rt.osx.a`
for both macOS processors. The musl targets also get `clang_rt.crtbegin.o` and
`clang_rt.crtend.o`. On Linux, clang compiles for glibc by default and for musl with
`--target`. There is no `clang++`, because nothing Anti ships is C++.

The hosts are `linux-x86_64`, `linux-arm64`, `macos-arm64`, `macos-x86_64`,
`windows-x86_64` and `windows-arm64`. The Linux binaries link musl, libc++ and zlib
statically and name no shared library. The macOS binaries name `libSystem` and `libc++`
of the system and record macOS 11.0 as their `minos`. The Windows binaries link the CRT
statically and import system DLLs
alone.

## Signing key

`SHA256SUMS.sig` is signed by the release key of `release@anti-lang.com`, an ECDSA
P-256 key that signs nothing else. Its public key in PEM form is `keys/release.pem` in
this repository and https://anti-lang.com/keys/release.pem on the site. The SHA-256
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
| `build-llvm.cmake` | The recipe, which builds one host |
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
| `keys/release.pem` | The public key that verifies `SHA256SUMS.sig` |
| `tests/` | The tests of the recipe and the scripts |
| `docs/reports/` | The report of each release |

Everything the recipe downloads and builds stays under `build/`.

## Building a release

The recipe needs CMake 3.25 or newer, Ninja, `gh` for the Sigstore attestation of the
release archive, and `xwin` 0.10.0 for the Windows hosts. Run the builds on the machine
that `hosts.toml` names for each host.

The recipe runs every tool it builds. A Linux or Windows tool runs over ssh on the
machine that `LINUX_REMOTE` or `WINDOWS_REMOTE` names. The Linux machine needs
`qemu-x86_64` through binfmt when its processor is arm64. `REMOTE_SSH_OPTIONS` passes
options to ssh and scp.

```sh
export LINUX_REMOTE=eddie@192.168.60.131 WINDOWS_REMOTE=eddie@192.168.60.132
ACCEPT_LICENSE=yes scripts/build.sh builtins
scripts/build.sh macos-arm64
scripts/build.sh macos-x86_64
scripts/build.sh linux-x86_64
scripts/build.sh linux-arm64
ACCEPT_LICENSE=yes scripts/build.sh windows-x86_64
ACCEPT_LICENSE=yes scripts/build.sh windows-arm64
```

`ACCEPT_LICENSE=yes` accepts the licence terms of the Microsoft CRT and Windows SDK,
which xwin downloads. Commit the recipe before the builds that go into a release,
because `scripts/pack.sh` refuses a build of uncommitted files. Then pack each host and
publish.

```sh
for host in linux-x86_64 linux-arm64 macos-arm64 macos-x86_64 windows-x86_64 windows-arm64; do
    scripts/pack.sh "$host"
done
scripts/release.sh
```

`scripts/release.sh` needs `gh` logged in to an account that can write releases of
`anti-lang/llvm-tools`. `RELEASE_KEY` names the private key, and the script signs with
it. The key stays off the development machine, so `SHA256SUMS.sig` can also come from
the machine that holds it. A run without either writes `SHA256SUMS`, stops and prints
the two commands that sign it there.

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
