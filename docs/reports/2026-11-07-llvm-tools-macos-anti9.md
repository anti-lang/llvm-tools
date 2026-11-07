# The macOS hosts of 23.1.1-anti.9

Eddie decided on 2026-11-07 to release `23.1.1-anti.9` for `macos-arm64` and
`macos-x86_64` alone, the tools and clang of each, four archives. Linux and Windows
follow as `23.1.1-anti.10` once the test VMs are back. The recipe of anti.9 adds
`llvm-objcopy`, `llvm-strip` and `dsymutil` to the tools archives, for antic's T211. The
four archives lie in `build/dist`, packed from recipe commit `6c15f30`. Nothing is
signed, tagged or published.

## Scripts

Commit `6c15f30` lets `./r` and `scripts/release.sh` take the hosts of a release on the
command line. Without a host both cover the six hosts of `hosts.toml`, as before.

- `release_hosts` of `scripts/common.sh` refuses a host that `hosts.toml` lacks and a
  host named twice, before anything else runs.
- `./r` packs the named hosts and passes them to `scripts/release.sh`.
- `SHA256SUMS`, its signature, the check that every archive names one recipe commit, the
  uploads and the readback cover the named hosts alone. An archive of another host in
  `build/dist` plays no part.
- The notes name the hosts and count the tools from `hosts.toml`. They read "The 12 LLVM
  tools and clang of LLVM 23.1.1 for macos-arm64 and macos-x86_64". Before, they named nine
  tools and six hosts, stale since anti.9 added three tools.
- The title adds "for macos-arm64 and macos-x86_64" when a release covers some of the
  hosts. A release of all six keeps the title `LLVM 23.1.1, anti build 9`.
- A published tag is still never replaced, and every other check is unchanged. A
  `DESIGN:` comment in `scripts/release.sh` gives Eddie's decision as the reason.

`tests/test-commands.sh` and `tests/test-release.sh` gained the cases first, and both
failed before the change. `sh tests/run.sh` then passed all 18 tests.

## Builds

`pack.sh` refused the first macOS builds of `5945739`, since the builtins stamp named
`b0ef666`. The recipe stamps `HEAD`, so a builtins build after `6c15f30` could not name
`5945739`. On Eddie's choice the builtins and both macOS hosts were built again at
`6c15f30`, each tree removed first. Each stamp names `6c15f30` and reads `clean=yes`,
and every check passed.

| Build | Log in `build/logs/` |
|---|---|
| builtins | `anti9-6c15f30-builtins.log` |
| `macos-arm64` | `anti9-6c15f30-macos-arm64.log` |
| `macos-x86_64` | `anti9-6c15f30-macos-x86_64.log` |

- The 77 files of the builtins install match those of the `b0ef666` build byte for byte.
- The twelve tools and clang of each host match by SHA-256 the binaries of the earlier
  build in the scratchpad copy `llvm-tools-anti9-reused`.
- Unpacked, each archive matches its anti.8 archive, except `VERSION` and the three new
  tools of the tools archives.

## Archives

Each `VERSION` reads `llvm 23.1.1`, `build 9` and
`recipe 6c15f301ba8f33622449b82126fef61fa193d5e2`. Sizes are in bytes.

| Archive | Size | SHA-256 |
|---|---|---|
| `llvm-tools-23.1.1-anti.9-macos-arm64.tar.xz` | 67,469,784 | `bdc961c0238abd95403d283824e61f2806b37236a09993f57c3f271f1c1a42fb` |
| `clang-23.1.1-anti.9-macos-arm64.tar.xz` | 31,052,100 | `3bf04f820847de508c85a5c352465e6a480dc63691295bea8d94e94e236c33d9` |
| `llvm-tools-23.1.1-anti.9-macos-x86_64.tar.xz` | 76,806,928 | `050c3f82f7cb5cc96dcb342fdab9312e392d6a2d98e20e1f68498e0a8c94a43d` |
| `clang-23.1.1-anti.9-macos-x86_64.tar.xz` | 34,365,224 | `185b05d1ab5792073e73ac0bfff291297b72eee5bd65ac1b6fbebfa0baff83b3` |

The pack logs are `build/logs/pack-anti9-6c15f30-macos-arm64.log` and
`build/logs/pack-anti9-6c15f30-macos-x86_64.log`.

## Not done

- The release itself. Signing needs Eddie's passphrase.
- The four Linux and Windows hosts. Their trees stand at `b0ef666` and need the VMs.
  They become anti.10.
- The antic side: `tools/llvm-pin` and `tools/clang-pin` of the macOS hosts take the tag
  and the digests above once the release exists.

## Publishing

`main` holds the scripts and this report and is not pushed. Eddie runs, from the top of
the repository:

```sh
./r macos-arm64 macos-x86_64
```

`./r` finds both hosts packed from their builds and runs
`scripts/release.sh macos-arm64 macos-x86_64`. That writes `SHA256SUMS` of the four
archives and signs it with `keys/private/release-key.enc.pem`, whose passphrase openssl
asks for. It tags `6c15f30` as `23.1.1-anti.9`, pushes the tag and uploads the six files
to a draft, which it publishes after the last one. `./r` pushes the tag alone, so push
`main` after the release:

```sh
git push origin main
```
