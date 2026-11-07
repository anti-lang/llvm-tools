#!/bin/sh
# The recipe runs every tool with --version and refuses one that reports a
# version other than the pin. lld answers under each of its three flavors,
# and llc must list the back ends of x86-64 and aarch64.
. "$(dirname "$0")/lib.sh"

version=$(cat "$root/pins/llvm-version")

# Write llc into directory $1 as a script that reports version $2 and the
# registered targets that follow.
llc_reporting() {
    dir=$1
    reported=$2
    shift 2
    {
        printf '#!/bin/sh\necho "LLVM (http://llvm.org/):"\n'
        printf 'echo "  LLVM version %s"\necho "  Registered Targets:"\n' "$reported"
        for target in "$@"; do
            printf 'echo "    %s - the %s back end"\n' "$target" "$target"
        done
    } > "$dir/llc"
    chmod +x "$dir/llc"
}

# Write the twelve tools into directory $1 as scripts that report version $2.
tools_reporting() {
    mkdir -p "$1"
    for tool in llvm-mc opt llvm-ar llvm-objdump llvm-readobj llvm-profdata llvm-cov \
                llvm-objcopy llvm-strip dsymutil; do
        printf '#!/bin/sh\necho "LLVM version %s"\n' "$2" > "$1/$tool"
    done
    llc_reporting "$1" "$2" aarch64 aarch64_32 arm64 x86 x86-64
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

tools_reporting "$work/old-opt" "$version"
printf '#!/bin/sh\necho "LLVM version 22.1.3"\n' > "$work/old-opt/opt"
expect_refusal "opt reports 22.1.3" recipe "$root" -DHOST=macos-arm64 \
    -DSTEP=check-version -DBIN="$work/old-opt"

tools_reporting "$work/old-profdata" "$version"
printf '#!/bin/sh\necho "LLVM version 22.1.3"\n' > "$work/old-profdata/llvm-profdata"
expect_refusal "llvm-profdata reports 22.1.3" recipe "$root" -DHOST=macos-arm64 \
    -DSTEP=check-version -DBIN="$work/old-profdata"

tools_reporting "$work/old-cov" "$version"
printf '#!/bin/sh\necho "LLVM version 22.1.3"\n' > "$work/old-cov/llvm-cov"
expect_refusal "llvm-cov reports 22.1.3" recipe "$root" -DHOST=macos-arm64 \
    -DSTEP=check-version -DBIN="$work/old-cov"

# tools_reporting sets tool, so the loop names its tool stale.
for stale in llvm-objcopy llvm-strip dsymutil; do
    tools_reporting "$work/old-$stale" "$version"
    printf '#!/bin/sh\necho "LLVM version 22.1.3"\n' > "$work/old-$stale/$stale"
    expect_refusal "$stale reports 22.1.3" recipe "$root" -DHOST=macos-arm64 \
        -DSTEP=check-version -DBIN="$work/old-$stale"
done

# An llc without the back end of either target that antic compiles for is
# refused.
for missing in x86-64 aarch64; do
    tools_reporting "$work/no-$missing" "$version"
    if [ "$missing" = x86-64 ]; then
        llc_reporting "$work/no-$missing" "$version" aarch64 arm64 x86
    else
        llc_reporting "$work/no-$missing" "$version" aarch64_32 arm64 x86 x86-64
    fi
    expect_refusal "llc registers no $missing" recipe "$root" -DHOST=macos-arm64 \
        -DSTEP=check-version -DBIN="$work/no-$missing"
done

# lld runs once per flavor, so a driver that fails for one is refused.
tools_reporting "$work/flavor" "$version"
printf '#!/bin/sh\n[ "$2" = link ] && exit 1\necho "LLD %s"\n' "$version" \
    > "$work/flavor/lld"
expect_refusal "lld -flavor link" recipe "$root" -DHOST=macos-arm64 \
    -DSTEP=check-version -DBIN="$work/flavor"

# The clang of a macOS host records the pinned ld64 version, and the step
# check-link-version refuses one that records another or none.
link_version=$(sed -n 's/^set(darwin_link_version \([0-9.]*\))$/\1/p' \
    "$root/build-llvm.cmake")
[ "$link_version" = 1267 ] ||
    fail "build-llvm.cmake pins the ld64 version '$link_version', not 1267"
# Write clang into directory $1 as a script whose -### line records the
# linker version $2, or none when $2 is empty.
clang_recording() {
    mkdir -p "$1"
    {
        printf '#!/bin/sh\n'
        if [ -n "$2" ]; then
            printf 'echo \x27 "-cc1" "-target-linker-version" "%s" "-x" "c"\x27 >&2\n' "$2"
        else
            printf 'echo \x27 "-cc1" "-x" "c"\x27 >&2\n'
        fi
    } > "$1/clang"
    chmod +x "$1/clang"
}
clang_recording "$work/pinned" "$link_version"
recipe "$root" -DHOST=macos-arm64 -DSTEP=check-link-version -DBIN="$work/pinned" \
    >/dev/null || fail "a clang that records $link_version was refused"
clang_recording "$work/xcode" 27037.1
expect_refusal "records the ld64 version 27037.1" recipe "$root" -DHOST=macos-arm64 \
    -DSTEP=check-link-version -DBIN="$work/xcode"
clang_recording "$work/unpinned" ""
expect_refusal "records no ld64 version" recipe "$root" -DHOST=macos-arm64 \
    -DSTEP=check-link-version -DBIN="$work/unpinned"

# The tools of another operating system run through RUNNER alone.
expect_refusal "RUNNER" recipe "$root" -DHOST=linux-x86_64 \
    -DSTEP=check-version -DBIN="$work/right"
recipe "$root" -DHOST=linux-x86_64 -DSTEP=check-version -DBIN="$work/right" \
    -DRUNNER=env >/dev/null || fail "a tool run through RUNNER was refused"
finished=yes
