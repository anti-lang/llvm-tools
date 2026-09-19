#!/bin/sh
# Build the compiler-rt builtins and every host of hosts.toml on this
# machine, all that ./r packs and publishes.
#
#   ./c
#
# The recipe runs every tool it builds. A Linux or Windows tool runs over
# ssh on the machine that LINUX_REMOTE or WINDOWS_REMOTE names, which
# default to the test VMs of the owner. REMOTE_SSH_OPTIONS passes options
# to ssh and scp. The first build that fails stops the run.
. "$(dirname "$0")/scripts/common.sh"

[ "$#" -eq 0 ] || die "usage: ./c"
# DESIGN: the owner accepts, for every build of this repository, the
# licence terms of the Microsoft CRT and Windows SDK that xwin downloads.
export ACCEPT_LICENSE=yes
export LINUX_REMOTE="${LINUX_REMOTE:-eddie@192.168.60.131}"
export WINDOWS_REMOTE="${WINDOWS_REMOTE:-eddie@192.168.60.132}"
for target in builtins $(toml_sections "$root/hosts.toml"); do
    printf 'c: building %s\n' "$target"
    "$root/scripts/build.sh" "$target"
done
printf 'c: built the builtins and every host. ./r packs and publishes them.\n'
