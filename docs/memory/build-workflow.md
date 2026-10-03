# Running a build

- Commit the recipe first. `scripts/pack.sh` refuses a build whose stamp names a
  commit that differs from `HEAD` in `build-llvm.cmake`, `hosts.toml` or `pins/`.
  Commits that touch only `docs/`, `tests/` or `README.md` keep a build packable.
- `./c` builds the builtins and the six hosts in one run. The version checks of the
  Linux and Windows hosts run on the test VMs over ssh. Set `REMOTE_SSH_OPTIONS` to
  `-o UserKnownHostsFile=$PWD/build/vm_known_hosts -o BatchMode=yes`. Run it in the
  background with a log in `build/logs/`.
- After `./c`, run `scripts/pack.sh <host>` for each host. It writes the archives to
  `build/dist` and publishes nothing. The xz step of twelve archives takes longer than
  10 minutes. `./r` then finds every host packed. Only Eddie runs `./r`, since it asks
  for the passphrase of the release key.
- This repository has no `CLAUDE.md`. The README is the guide, and each release has a
  report in `docs/reports/` that ends with the publish command.
