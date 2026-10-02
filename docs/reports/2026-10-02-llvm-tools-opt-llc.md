# opt and llc, 23.1.1-anti.4

The tools archive of each of the six hosts now holds `opt` and `llc` beside `llvm-mc`,
seven tools in all. All twelve archives come from recipe commit `449dca5`, one build of
the pinned LLVM 23.1.1 source, and lie in `build/dist` under the tag `23.1.1-anti.4`.
Beside `opt` and `llc`, every file of every archive is byte for byte that of anti.3, but
`VERSION`. The recipe now pins the ld64 version that the macOS clang records, which a
change of Xcode on the build machine had moved. `./r`, the last section, publishes them.

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
- The LLVM configure of both macOS hosts takes `-DHOST_LINK_VERSION=1267`, and the step
  `check-link-version` refuses a built clang that records another version or none. The
  next section gives the reason.

## The ld64 version of the macOS clang

clang's configure reads the version of ld64 on the build machine and builds it into
clang as the default of `-mlinker-version`, which decides the flags that clang passes to
ld64 and reaches cc1 as `-target-linker-version`. anti.3 was configured on 2026-09-19
against `ld-classic`, ld64 1267. The Xcode of the build machine now has no `ld-classic`,
so the first anti.4 build, at `26b62fa`, took `ld` 27037.1, and the clang of both macOS
hosts differed from that of anti.3 in its UUID and that version.

The recipe now decides the version, not the Xcode of the build machine.
`darwin_link_version` in `build-llvm.cmake` holds 1267, the version that the clang of
anti.3 recorded, and the LLVM configure of both macOS hosts takes it as
`HOST_LINK_VERSION`. The step
`check-link-version` reads the version from the cc1 line of `clang -### -c -x c -` and
refuses any other, or none, so the next upgrade of Xcode stops the build before a
release. The Linux and Windows clang record none, since clang's configure reads ld64 on a
macOS build alone.

- Both macOS builds print `Host linker version: 1267` and
  `clang: records the ld64 version 1267`. The check refuses the clang of the first anti.4
  build: `records the ld64 version 27037.1, and the pin is 1267`.
- `clang -### -o t t.o -target arm64-apple-macos` prints the same link line with the new
  clang of `macos-arm64` as with the anti.3 clang in `antic/build/deps/clang`, whose bytes
  are those of the anti.3 archive. Only the install directory differs:

```text
"/usr/bin/ld" "-demangle" "-lto_library" "<clang>/lib/libLTO.dylib" "-dynamic" "-arch" "arm64" "-platform_version" "macos" "26.0.0" "26.0.0" "-mllvm" "-enable-linkonceodr-outlining" "-o" "t" "t.o" "-lSystem" "<clang>/lib/clang/23/lib/darwin/libclang_rt.osx.a"
```

- The clang of 27037.1 prints that link line as well. The version shows in the cc1 line,
  which the check reads.
- compiler-rt reads the ld64 version as well, still 27037.1 in its log, and passes it to
  its lit tests alone. The recipe builds no tests, and the builtins and sanitizer runtimes
  are byte for byte those of anti.3.

## Hosts

All six build on the Mac. Sizes are in bytes, as shipped. The Linux tools are linked with
`-s`, the macOS tools with `-Wl,-S`, and the Windows tools carry no debug directory and
no symbol table.

| Host | `opt` | `llc` | `llvm-mc` | Tools archive, anti.3 | Tools archive, anti.4 | Growth |
|---|---|---|---|---|---|---|
| `linux-x86_64` | 60,208,064 | 60,284,800 | 12,221,168 | 26,271,712 | 58,190,076 | 31,918,364 |
| `linux-arm64` | 57,083,424 | 57,145,656 | 12,211,024 | 23,635,156 | 51,820,800 | 28,185,644 |
| `macos-arm64` | 66,357,296 | 66,406,528 | 12,424,768 | 25,034,028 | 54,392,536 | 29,358,508 |
| `macos-x86_64` | 69,790,040 | 69,841,864 | 12,446,864 | 28,161,820 | 61,934,492 | 33,772,672 |
| `windows-x86_64` | 52,609,536 | 52,738,560 | 12,049,408 | 25,795,084 | 54,878,132 | 29,083,048 |
| `windows-arm64` | 46,550,016 | 46,665,728 | 11,697,664 | 22,577,824 | 47,576,592 | 24,998,768 |

Each tools archive about doubles, 177,317,004 bytes over the six. `opt` and `llc` each
link the optimizer and both back ends of LLVM statically, and xz shares nothing between
the two files. The clang archives hold the bytes of anti.3 but `VERSION`, and differ in
size from those by a few KB of xz output.

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
  `VERSION` reads `llvm 23.1.1`, `build 4`, `recipe 449dca5…`.
- On every host, `lld`, `llvm-mc`, `llvm-ar`, `llvm-objdump` and `llvm-readobj` are byte
  for byte those of anti.3, and each clang archive differs from that of anti.3 in
  `VERSION` alone. `opt` and `llc` are byte for byte those of the first anti.4 build.
- `sh tests/run.sh` passes all 12 tests.

## Choices

- The codegen check runs the tools of a host that runs on the build machine. RUNNER
  copies a tool and passes its arguments, so `hello.ll` and `hello.bc` would not reach
  the VM. The build of a Linux or Windows host says so in its log. The version check
  still runs `opt` and `llc` of those hosts on the VMs.
- `checks/` is a new directory. It holds `hello.ll`, the input of the step.

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
  on `449dca5`.
- The archives of the first build, at `26b62fa`, lie in `build/dist-26b62fa`, unpublished.

## Publishing

Eddie runs, from the top of the repository:

```sh
./r
```

`./r` finds each of the six hosts packed from its build at `449dca5` and runs
`scripts/release.sh`. That writes `SHA256SUMS` of the twelve archives, signs it with
`keys/private/release-key.enc.pem`, whose passphrase openssl asks for, tags `449dca5` as
`23.1.1-anti.4`, pushes the tag and uploads the 14 files to a draft that it publishes
after the last one.
