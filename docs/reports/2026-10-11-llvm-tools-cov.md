# llvm-cov, 23.1.1-anti.8

The recipe now builds `llvm-cov` and packs it into the tools archive of every host, nine
tools in all. antic measures the coverage of its own tests with it and does not ship it
in the Anti package. Recipe commit `6cc1b86` holds the change, and `pins/build-number`
is 8. No archive of anti.8 exists yet. Eddie builds and publishes the release with the
commands of the last section.

## Recipe

- `hosts.toml` names `llvm-cov` in `tools`, after `llvm-profdata`. The build, the library
  check, the stack check, the check for the build path, the version check and
  `scripts/pack.sh` read that list. `llvm-cov` is built, linked, checked and packed as the
  other eight are: static against musl on Linux, `minos 11.0` on macOS, the xwin CRT and
  SDK on Windows.
- `checks/hello.c` is the new fixture, the C form of `checks/hello.ll`. Its two functions
  span 14 lines. `sum(10)` is 45, so a run never reaches the two lines of the branch in
  `main`.
- The new step `check-coverage` proves that the built `llvm-cov` reads a profile:
  - The release clang compiles `checks/hello.c` with
    `-fprofile-instr-generate -fcoverage-mapping`, against the macOS SDK, linked by
    `ld64.lld` of the release.
  - The program runs with `LLVM_PROFILE_FILE` set and writes `hello.profraw`.
  - `llvm-profdata` of the host merges it into `hello.profdata`.
  - `llvm-cov report` of the host must name `hello.c` with 14 lines, 2 of them missed.
- `coverage_lines` and `coverage_missed_lines` hold the two counts once, in
  `build-llvm.cmake`.
- The build runs `check-coverage` after `check-codegen`, for each host that runs on the
  build machine. Those are `macos-arm64` and, through Rosetta, `macos-x86_64`. The files
  go into `build/<host>/coverage`.
- `tests/test-coverage.sh` covers the step with the `llvm-profdata` and `llvm-cov` of the
  release. It refuses an `llvm-cov` that fails, a missing one and one that reports no file.
  It refuses an `llvm-profdata` that fails and a missing one. It refuses a profile of
  another hash, and a host of another system.
- `tests/test-pack.sh` expects `bin/llvm-cov` in the tools archive of Linux and
  `bin/llvm-cov.exe` in that of Windows. `tests/test-toml.sh` expects the nine names.
  `tests/test-version.sh` refuses an `llvm-cov` that reports another version.
- `pins/build-number` moves to 8. `pins/llvm-version` stays `23.1.1`, and
  `darwin_link_version` stays 1267.
- The README names `llvm-cov` in its opening and under Changes. It says that Anti ships
  the other eight tools. The notes of the GitHub release in `scripts/release.sh` read
  `The nine LLVM tools`.

## The profile that llvm-cov drops

`llvm-cov report` exits 0 when the hash of a function in the profile does not match the
program. It prints `warning: 1 functions have mismatched data` and drops that function.
With a profile of `main` under another hash it reports the 7 lines of `sum` alone, all 7
missed. `check-coverage` reads both counts of the row of `hello.c`, so it refuses that
case. `tests/test-coverage.sh` holds it.

## Hosts

The build tree of each of the six hosts stood under `build/`, configured by the anti.7
build. `cmake --build build/<host>/llvm --target llvm-cov` built the one new target in
each, 14 steps and under 3 seconds a host. No configure ran again. Sizes are in bytes, as
built there. The release build decides the bytes that ship.

| Host | `llvm-cov` | SHA-256 |
|---|---|---|
| `linux-x86_64` | 5,676,920 | `7799bac493b8f3693aaaf1196af9cd2096a580e97474de1d0664bd04b27766c8` |
| `linux-arm64` | 5,541,160 | `1851bc345cb9c1f06ea80b565e40a26c94dbfb67b5e51b0b237f4f1a9d782db7` |
| `macos-arm64` | 5,943,616 | `268277fc2b95065f1a28af10453740ed2d38ebe37355cfd1deb6f4c1b08e99c2` |
| `macos-x86_64` | 6,093,408 | `9b2cffb3e63cb5f19ff1856eace85567063a7c7ab26c281d604d6070c0f40928` |
| `windows-x86_64` | 5,457,408 | `d718e98d3b4404fe179e1d11ad27e6bde4f54fd64a46cb2eb08ee438c344f2b7` |
| `windows-arm64` | 4,957,696 | `80dc91387848f24720fbd1c23a6f62b29709fc8299506b0942342e253a089c95` |

## Verification

All checks ran on the Mac, `macos-arm64`, on the six trees above, each through `STEP` of
the recipe at `6cc1b86`. The logs are `build/logs/anti8-cov-<host>.log`,
`build/logs/anti8-cov-checks.log`, `build/logs/anti8-cov-remote.log` and
`build/logs/anti8-cov-remote-report.log`.

- `check-libraries` passed on all six hosts and printed
  `no library outside the system set` for `llvm-cov`. On Linux it is static and has no
  `INTERP`. On macOS it names `libSystem.B.dylib` and `libc++.1.dylib` and records
  `minos 11.0`. On Windows it imports ADVAPI32, CRYPT32, KERNEL32, WINHTTP and ntdll, the
  set of `llvm-profdata`.
- `check-stack` passed on both Linux hosts and printed
  `llvm-cov: a thread stack of 8388608 bytes`.
- No `llvm-cov` holds the path of the build tree.
- `check-version` passed on all six hosts and printed `llvm-cov: LLVM version 23.1.1`.
  The Linux and Windows tools ran on the test VMs, `linux-x86_64` under qemu-x86_64 and
  `windows-x86_64` under x64 emulation.
- `check-codegen` passed on both macOS hosts, as before.
- `check-coverage` passed on both macOS hosts and printed:

```text
-- llvm-cov report counts 14 lines of hello.c, 2 of them missed, from the profile that llvm-profdata merges
```

- The `llvm-cov` of `macos-x86_64` ran under Rosetta and read the arm64 program.
- The `llvm-cov` of the two Linux and the two Windows trees ran `report` on the test VMs.
  Each read `hello` and `hello.profdata` of `build/macos-arm64/coverage`, copied to the
  VM. Each printed the row of `hello.c` with 14 lines and 2 missed.
- On Windows that row names the path of `hello.c` twice in a row, with backslashes. The
  program records a POSIX path, and `llvm-cov` on Windows appears to read it as relative.
  That cause is a guess from the output. The counts are those of the other hosts.
- `sh tests/run.sh` passes all 16 tests.
- `python3 ../antic/tools/docs-style/check_docs.py` reports nothing on `README.md`,
  `docs/memory/release-state.md` and this report.

The build of `llvm-cov` printed two kinds of warning, both known from the other tools:

- `macos-x86_64`: `ld64.lld` ignores `libclang_rt.osx.a` of the release, which holds arm64
  alone. The anti.7 log holds the same line for each of the nine binaries.
- Both Windows hosts: 12 times `-Wclang-cl-pch`, since the tool defines `LLVM_BUILD_STATIC`
  after the precompiled header. `llvm-profdata` printed the same in the anti.6 log.

## Choices

- `check-coverage` is a step of its own, beside `check-codegen`. It compiles and runs a
  program of the build machine, which `check-codegen` does not. anti.6 put the profile
  check of `llvm-profdata` inside `check-codegen`.
- The task named `checks/hello` as the source. The directory held `hello.ll` and
  `hello.proftext`, and clang writes a coverage mapping from C source alone. The new
  `checks/hello.c` is that source.
- The program is one of the build machine, arm64, for both macOS hosts. The release
  carries `libclang_rt.profile_osx.a` for arm64 alone, and an x86_64 link fails on
  `__llvm_profile_runtime`. `llvm-cov` reads the program of any processor.
- The profile runtime of the check is that of the release, as the task asks. The profile
  runtimes that the clang archives ship have `check-profile`.
- The Linux and Windows hosts get no `check-coverage` in the build. `RUNNER` passes a
  tool its arguments and no files, as the DESIGN comment of `check_codegen` says. The run
  on the VMs above was by hand.
- The README keeps `The eight LLVM tools that Anti ships` and names `llvm-cov` as a ninth
  that Anti does not ship. `tests/test-files.sh` requires the opening to name every tool
  of `hosts.toml`, and it does.
- Every option of `llvm-cov` keeps upstream's default, and the recipe pins none with a
  test. It reads zlib-compressed coverage through the pinned zlib. `LLVM_ENABLE_CURL` and
  `LLVM_ENABLE_HTTPLIB` stay OFF, so it fetches nothing through debuginfod.
- The proof built one target in each standing tree and ran the checks through `STEP`. A
  run of the recipe for a host removes `build/<host>/recipe` and configures again, which
  is the release build. The six stamps still name `e9e1888`.
- No contradiction between the task and the README, `docs/memory/` or the reports came
  up.

## Not done

- The release build. `./c` and `./r` are Eddie's, and no archive or tag of anti.8 exists.
- The `diff -r` of each anti.8 archive against its anti.7 archive, which
  `docs/memory/build-gotchas.md` describes. It follows the build. `VERSION` and
  `bin/llvm-cov` of the tools archives should differ, and nothing else.
- The antic side, once the release exists: `tools/llvm-pin` and `tools/clang-pin` take the
  tag `23.1.1-anti.8` and its twelve digests. antic fetches `llvm-cov` for its coverage
  measurement and keeps it out of the Anti package.
- A coverage run of a program that antic compiles. The runs above use a C program.
- A run of the x86_64 tools on real x86_64 hardware. They ran under qemu-x86_64, Rosetta
  and x64 emulation.

## Publishing

`main` is pushed with the recipe and this report. Eddie runs, from the top of the
repository:

```sh
export REMOTE_SSH_OPTIONS="-o UserKnownHostsFile=$PWD/build/vm_known_hosts -o BatchMode=yes"
./c > build/logs/anti8-c.log 2>&1
./r
```

`./c` builds the builtins and the six hosts, and stops at the first failure. Each stamp
names the commit that is `HEAD` then. Its recipe is that of `6cc1b86`, since the later
commits touch `docs/` alone. `./r` packs each host into `build/dist` and runs
`scripts/release.sh`. That writes `SHA256SUMS` of the twelve archives and signs it with
`keys/private/release-key.enc.pem`, whose passphrase openssl asks for. It tags the commit
of the stamps as `23.1.1-anti.8` and pushes the tag. It then uploads the 14 files to a
draft, which it publishes after the last one.
