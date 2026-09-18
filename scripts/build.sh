#!/bin/sh
# Run the recipe for one host on this machine.
#
#   scripts/build.sh <host>
#
# The recipe runs every tool for its version check. A tool of another
# system runs over ssh on the machine in LINUX_REMOTE or WINDOWS_REMOTE,
# as user@machine, through scripts/run-remote.sh. Set ACCEPT_LICENSE to
# yes to pass it to the recipe of a Windows host.
. "$(dirname "$0")/common.sh"

[ "$#" -eq 1 ] || die "usage: scripts/build.sh <host>"
host=$1
require_host "$host"

set -- -DHOST="$host"
case $host in
    linux-*) remote=${LINUX_REMOTE:-} ;;
    windows-*) remote=${WINDOWS_REMOTE:-} ;;
    *) remote="" ;;
esac
if [ -n "$remote" ]; then
    set -- "$@" "-DRUNNER=$root/scripts/run-remote.sh;$remote"
fi
if [ "${ACCEPT_LICENSE:-}" = yes ]; then
    set -- "$@" -DACCEPT_LICENSE=yes
fi
exec cmake "$@" -P "$root/build-llvm.cmake"
