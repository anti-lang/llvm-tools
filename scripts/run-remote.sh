#!/bin/sh
# Run a tool on another machine over ssh, for the version check of a host
# that this machine cannot run.
#
#   scripts/run-remote.sh <user@machine> <tool> [arguments]
#
# Copies <tool> to llvm-tools-check/<digest>/ in the home directory of the
# remote user and runs it there with the arguments. The exit status of the
# tool comes back. REMOTE_SSH_OPTIONS holds options for both ssh and scp.
# scripts/build.sh passes run-remote.sh to the recipe as RUNNER.
set -eu

[ "$#" -ge 2 ] || {
    echo "usage: scripts/run-remote.sh <user@machine> <tool> [arguments]" >&2
    exit 2
}
target=$1
tool=$2
shift 2
name=$(basename "$tool")
options=${REMOTE_SSH_OPTIONS:-}

# DESIGN: a copy is never written over. Windows may still hold the last run
# of a tool open, and a copy onto it fails. The directory is named by the
# digest of the tool, so a second run finds the same bytes in place.
digest=$(shasum -a 256 "$tool" | cut -c1-16)
# cmd.exe reads a slash in a command name as a switch, so a Windows tool
# takes a backslash, and the remote shell is cmd.exe.
case $name in
    *.exe)
        path="llvm-tools-check\\$digest\\$name"
        there="if exist $path echo there"
        make="mkdir llvm-tools-check\\$digest"
        ;;
    *)
        path="llvm-tools-check/$digest/$name"
        there="test -e $path && echo there"
        make="mkdir -p llvm-tools-check/$digest"
        ;;
esac
found=$(ssh $options "$target" "$there" 2>/dev/null | tr -d '\r' || true)
if [ "$found" != there ]; then
    ssh $options "$target" "$make" >/dev/null 2>&1 || true
    scp -q $options "$tool" "$target:llvm-tools-check/$digest/$name"
fi
exec ssh $options "$target" "$path $*"
