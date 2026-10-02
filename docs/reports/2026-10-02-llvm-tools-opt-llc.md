# opt and llc, 23.1.1-anti.4

The tools archive of each of the six hosts now holds `opt` and `llc` beside `llvm-mc`,
seven tools in all. All twelve archives come from recipe commit `26b62fa`, one build of
the pinned LLVM 23.1.1 source, and lie in `build/dist` under the tag `23.1.1-anti.4`.
Nothing is published. `./r`, the last section, publishes them.

## Recipe

- `hosts.toml` names `opt` and `llc` in `tools`, after `llvm-mc`. The build, the
  library check, the check for the build path, the version check and `scripts/pack.sh`
  read that list, so both tools are built, linked, checked and packed as the other five
  are.
- `LLVM_TARGETS_TO_BUILD` stays `X86;AArch64`. `pins/llvm-version` stays `23.1.1`.
  `pins/build-number` moves to 4.
- The version check also refuses an `llc` that registers no `x86-64` or no `aarch64`
  target. It runs on every host, on the VMs for Linux and Windows.
- The new step `check-codegen` runs `checks/hello.ll` through
  `opt -passes='default<O2>' -o hello.bc hello.ll` and
  `llc -O2 -filetype=obj -mtriple=<triple> -o hello.o hello.bc` for the six triples, and
  `llvm-readobj --file-header` of the same host reads each object. The build runs it for
  every host whose tools run on the build machine. `tests/test-codegen.sh` covers the
  step.
- `tests/test-files.sh` refuses a README whose first paragraph leaves out a tool of
  `hosts.toml`.

## Hosts

All six build on the Mac. Sizes are in bytes, as shipped. The Linux tools are linked with
`-s`, the macOS tools with `-Wl,-S`, and the Windows tools carry no debug directory and
no symbol table.

| Host | `opt` | `llc` | `llvm-mc` | Tools archive, anti.3 | Tools archive, anti.4 | Growth |
|---|---|---|---|---|---|---|
| `linux-x86_64` | 60,208,064 | 60,284,800 | 12,221,168 | 26,271,712 | 58,191,964 | 31,920,252 |
| `linux-arm64` | 57,083,424 | 57,145,656 | 12,211,024 | 23,635,156 | 51,805,188 | 28,170,032 |
| `macos-arm64` | 66,357,296 | 66,406,528 | 12,424,768 | 25,034,028 | 54,399,068 | 29,365,040 |
| `macos-x86_64` | 69,790,040 | 69,841,864 | 12,446,864 | 28,161,820 | 61,923,716 | 33,761,896 |
| `windows-x86_64` | 52,609,536 | 52,738,560 | 12,049,408 | 25,795,084 | 54,842,416 | 29,047,332 |
| `windows-arm64` | 46,550,016 | 46,665,728 | 11,697,664 | 22,577,824 | 47,595,952 | 25,018,128 |

Each tools archive about doubles, 177,282,680 bytes over the six. `opt` and `llc` each
link the optimizer and both back ends of LLVM statically, and xz shares nothing between
the two files. The clang archives stay within 10 KB of anti.3.

## Verification

| Host | Format | Libraries of `opt` and `llc` | Codegen check |
|---|---|---|---|
| `linux-x86_64` | `elf64-x86-64` | none, no `INTERP`, as `llvm-mc` | not run, tools on the Linux VM |
| `linux-arm64` | `elf64-littleaarch64` | none, no `INTERP`, as `llvm-mc` | not run, tools on the Linux VM |
| `macos-arm64` | `mach-o arm64`, `minos 11.0` | `libSystem.B.dylib`, `libc++.1.dylib`, as `llvm-mc` | six of six |
| `macos-x86_64` | `mach-o 64-bit x86-64`, `minos 11.0` | `libSystem.B.dylib`, `libc++.1.dylib`, as `llvm-mc` | six of six, Rosetta |
| `windows-x86_64` | `coff-x86-64` | ADVAPI32, KERNEL32, ntdll, as `llvm-mc` | not run, tools on the Windows VM |
| `windows-arm64` | `coff-arm64` | ADVAPI32, KERNEL32, ntdll, as `llvm-mc` | not run, tools on the Windows VM |

- `ldd` on the Linux VM prints `not a dynamic executable` for `llvm-mc`, `opt` and `llc`
  of both Linux hosts.
- Every host prints `LLVM version 23.1.1` for `opt` and `llc`, and its `llc` registers
  `x86-64` and `aarch64`. `linux-x86_64` ran under qemu-x86_64 on the Linux VM and
  `windows-x86_64` under x64 emulation on the Windows VM. `llc --version` of
  `macos-arm64` lists `aarch64`, `aarch64_32`, `aarch64_be`, `arm64`, `arm64_32`, `x86`
  and `x86-64`.
- The codegen check passed in the build of both macOS hosts, and again on the tools
  unpacked from their archives:

```text
hello.o for x86_64-unknown-linux-gnu: elf64-x86-64
hello.o for aarch64-unknown-linux-gnu: elf64-littleaarch64
hello.o for x86_64-apple-macos: Mach-O 64-bit x86-64
hello.o for arm64-apple-macos: Mach-O arm64
hello.o for x86_64-pc-windows-msvc: COFF-x86-64
hello.o for aarch64-pc-windows-msvc: COFF-ARM64
```

- At `default<O2>`, `opt` inlines `@sum` into `@main` and folds its loop, so `@main`
  calls `puts` and returns 0.
- Each tools archive lists `VERSION`, `bin/` with `llc`, `lld`, `llvm-ar`, `llvm-mc`,
  `llvm-objdump`, `llvm-readobj` and `opt`, `.exe` on Windows, and `licenses/`.
  `VERSION` reads `llvm 23.1.1`, `build 4`, `recipe 26b62fa…`.
- `lld`, `llvm-mc`, `llvm-ar`, `llvm-objdump` and `llvm-readobj` of `macos-arm64` are
  byte for byte those of anti.3.
- `sh tests/run.sh` passes all 12 tests.

## Choices

- The codegen check runs the tools of a host that runs on the build machine. RUNNER
  copies a tool and passes its arguments, so `hello.ll` and `hello.bc` would not reach
  the VM. The build of a Linux or Windows host says so in its log. The version check
  still runs `opt` and `llc` of those hosts on the VMs.
- `checks/` is a new directory. It holds `hello.ll`, the input of the step.

## Open question: the clang of macOS

clang of both macOS hosts differs from anti.3 in about 112 bytes: its `LC_UUID` and its
`HOST_LINK_VERSION`, the ld64 version that LLVM's configure reads from the build machine
and builds into clang. anti.3 was configured on 2026-09-19 against `ld-classic`, ld64
1267. The Xcode of this Mac now has no `ld-classic`, so configure took `ld` 27037.1. The
clang of Linux and Windows is byte for byte that of anti.3. Every clang printed
`clang version 23.1.1` and passed its checks.

The work order says nothing else about the release changes, so Eddie decides before
`./r`:

1. Publish as built, with 27037.1 in the macOS clang.
2. Pin `HOST_LINK_VERSION=1267` for the macOS hosts in the recipe. That is a new recipe
   commit, so `./c` builds every host again, and the twelve unpublished anti.4 archives
   in `build/dist` are deleted first, since `scripts/pack.sh` never writes over one.
3. Build the macOS hosts against an Xcode that still carries `ld-classic`.

## Sizes, options

These are measurements, not changes. Nothing below is in the recipe.

- A full `strip` of the macOS `opt` and `llc` takes each from about 66 MB to 55 MB on
  arm64, and from about 70 MB to 58 MB on x86_64. `strip -x` keeps the symbols that the
  plugins of `opt` resolve against and gives about 57 MB and 61 MB.
- The multicall build `LLVM_TOOL_LLVM_DRIVER_BUILD` does not help. `opt` and `llc` of
  23.1.1 do not take part in it.

## Not done

- The codegen check of the Linux and Windows hosts on their own machines.
- The antic side: `tools/llvm-pin` with the new tag and six digests,
  `tools/check-llvm.cmake` with seven tools, the runtime archive `bin/`,
  `pack-anti.cmake` and the `pinned_tools` test. It follows once the release exists.
- `main` holds the recipe and this report, and neither is pushed. `./r` pushes the tag
  on `26b62fa`.

## Publishing

Eddie runs, from the top of the repository:

```sh
./r
```

`./r` finds each of the six hosts packed from its build at `26b62fa` and runs
`scripts/release.sh`. That writes `SHA256SUMS` of the twelve archives, signs it with
`keys/private/release-key.enc.pem`, whose passphrase openssl asks for, tags `26b62fa` as
`23.1.1-anti.4`, pushes the tag and uploads the 14 files to a draft that it publishes
after the last one.
