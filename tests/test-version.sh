#!/bin/sh
# The recipe runs every tool with --version and refuses one that reports a
# version other than the pin. lld answers under each of its three flavors.
. "$(dirname "$0")/lib.sh"

version=$(cat "$root/pins/llvm-version")

# Write the five tools into directory $1 as scripts that report version $2.
tools_reporting() {
    mkdir -p "$1"
    for tool in llvm-mc llvm-ar llvm-objdump llvm-readobj; do
        printf '#!/bin/sh\necho "LLVM version %s"\n' "$2" > "$1/$tool"
    done
    printf '#!/bin/sh\necho "LLD %s (compatible with GNU linkers)"\n' "$2" \
        > "$1/lld"
    printf '#!/bin/sh\necho "clang version %s (https://github.com/llvm/llvm-project)"\n' \
        "$2" > "$1/clang"
    chmod +x "$1"/*
}

tools_reporting "$work/right" "$version"
recipe "$root" -DHOST=macos-arm64 -DSTEP=check-version -DBIN="$work/right" \
    >/dev/null || fail "tools that report $version were refused"

tools_reporting "$work/wrong" "$version"
printf '#!/bin/sh\necho "LLVM version 1.2.3"\n' > "$work/wrong/llvm-ar"
expect_refusal "llvm-ar reports 1.2.3" recipe "$root" -DHOST=macos-arm64 \
    -DSTEP=check-version -DBIN="$work/wrong"

tools_reporting "$work/old-clang" "$version"
printf '#!/bin/sh\necho "clang version 22.1.3"\n' > "$work/old-clang/clang"
expect_refusal "clang reports 22.1.3" recipe "$root" -DHOST=macos-arm64 \
    -DSTEP=check-version -DBIN="$work/old-clang"

# lld runs once per flavor, so a driver that fails for one is refused.
tools_reporting "$work/flavor" "$version"
printf '#!/bin/sh\n[ "$2" = link ] && exit 1\necho "LLD %s"\n' "$version" \
    > "$work/flavor/lld"
expect_refusal "lld -flavor link" recipe "$root" -DHOST=macos-arm64 \
    -DSTEP=check-version -DBIN="$work/flavor"

# The tools of another operating system run through RUNNER alone.
expect_refusal "RUNNER" recipe "$root" -DHOST=linux-x86_64 \
    -DSTEP=check-version -DBIN="$work/right"
recipe "$root" -DHOST=linux-x86_64 -DSTEP=check-version -DBIN="$work/right" \
    -DRUNNER=env >/dev/null || fail "a tool run through RUNNER was refused"
finished=yes
