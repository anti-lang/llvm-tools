#!/bin/sh
# The recipe refuses a Linux tool whose PT_GNU_STACK asks for a thread
# stack below 8 MiB, the size musl then gives every thread. Each case links
# a small static program with the release clang.
. "$(dirname "$0")/lib.sh"

bin=$(release_bin)
clang="$bin/clang"
tools="$(recipe "$root" -DSTEP=tools) $(recipe "$root" -DSTEP=compiler)"

# Fill directory $1 with the tools of hosts.toml and clang, each a copy of
# file $2.
binaries() {
    mkdir -p "$1"
    for tool in $tools; do
        cp "$2" "$1/$tool"
    done
}

check() {
    recipe "$root" -DHOST="$1" -DSTEP=check-stack -DBIN="$2"
}

printf 'int main(void) { return 0; }\n' > "$work/alone.c"
elf="--target=aarch64-unknown-linux-musl -nostdlib -fuse-ld=lld -Wl,-e,main -static"

# Link a program into directory $1 with the linker options that follow.
link() {
    dir=$1
    shift
    "$clang" $elf "$@" -o "$work/program-$dir" "$work/alone.c"
    binaries "$work/$dir" "$work/program-$dir"
}

link stack-8m -Wl,-z,stack-size=8388608
link stack-16m -Wl,-z,stack-size=16777216
link stack-4m -Wl,-z,stack-size=4194304
link stack-none
link no-header -Wl,-z,nognustack

check linux-arm64 "$work/stack-8m" >/dev/null ||
    fail "a tool with a thread stack of 8 MiB was refused"
check linux-arm64 "$work/stack-16m" >/dev/null ||
    fail "a tool with a thread stack of 16 MiB was refused"
expect_refusal "a thread stack of 4194304 bytes" check linux-arm64 "$work/stack-4m"
# lld writes PT_GNU_STACK with a size of 0 when no size is asked for, as
# the tools of 23.1.1-anti.6 have it.
expect_refusal "a thread stack of 0 bytes" check linux-arm64 "$work/stack-none"
expect_refusal "has no PT_GNU_STACK" check linux-arm64 "$work/no-header"
# The check reads the binaries of a Linux host alone.
expect_refusal "links no musl" check macos-arm64 "$work/stack-8m"
finished=yes
