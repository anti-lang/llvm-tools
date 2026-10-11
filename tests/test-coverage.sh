#!/bin/sh
# The step check-coverage compiles checks/hello.c with the release clang,
# instrumented for coverage, and runs the program. llvm-profdata of a host
# merges the profile of that run, and llvm-cov report of the host must count
# the lines of hello.c and the two that the run never reaches. The
# llvm-profdata and llvm-cov of the release stand in for those of a build.
. "$(dirname "$0")/lib.sh"

bin=$(release_bin)

check() {
    recipe "$root" -DHOST="$1" -DSTEP=check-coverage -DBIN="$2" -DOUT="$work/out"
}

# Fill directory $1 with links to llvm-profdata and llvm-cov of the release.
from_release() {
    mkdir -p "$1"
    for tool in llvm-profdata llvm-cov; do
        ln -s "$bin/$tool" "$1/$tool"
    done
}

from_release "$work/right"
output=$(check macos-arm64 "$work/right" 2>&1) ||
    fail "the tools of the release were refused: $output"
printf '%s\n' "$output" |
    grep -q "llvm-cov report counts 14 lines of hello.c, 2 of them missed" ||
    fail "no line for the report: $output"
for file in hello hello.profraw hello.profdata; do
    [ -f "$work/out/$file" ] || fail "$work/out/$file is missing"
done

# An llvm-cov that fails is refused, and so is a missing one.
from_release "$work/bad-cov"
rm "$work/bad-cov/llvm-cov"
printf '#!/bin/sh\nexit 3\n' > "$work/bad-cov/llvm-cov"
chmod +x "$work/bad-cov/llvm-cov"
expect_refusal "llvm-cov report failed" check macos-arm64 "$work/bad-cov"
from_release "$work/no-cov"
rm "$work/no-cov/llvm-cov"
expect_refusal "llvm-cov is missing" check macos-arm64 "$work/no-cov"

# An llvm-cov that reports no file is refused.
from_release "$work/silent-cov"
rm "$work/silent-cov/llvm-cov"
printf '#!/bin/sh\nexit 0\n' > "$work/silent-cov/llvm-cov"
chmod +x "$work/silent-cov/llvm-cov"
expect_refusal "llvm-cov report names no hello.c" check macos-arm64 "$work/silent-cov"

# An llvm-profdata that fails is refused, and so is a missing one.
from_release "$work/bad-profdata"
rm "$work/bad-profdata/llvm-profdata"
printf '#!/bin/sh\nexit 3\n' > "$work/bad-profdata/llvm-profdata"
chmod +x "$work/bad-profdata/llvm-profdata"
expect_refusal "llvm-profdata merge" check macos-arm64 "$work/bad-profdata"
from_release "$work/no-profdata"
rm "$work/no-profdata/llvm-profdata"
expect_refusal "llvm-profdata is missing" check macos-arm64 "$work/no-profdata"

# A profile whose hash does not match main is one that llvm-cov drops with
# a warning and status 0. It then reports the seven lines of sum alone,
# none of them reached, and the check refuses it.
printf 'main\n1\n1\n1\n' > "$work/stale.proftext"
from_release "$work/stale"
rm "$work/stale/llvm-profdata"
cat > "$work/stale/llvm-profdata" <<STUB
#!/bin/sh
while [ "\$#" -gt 0 ]; do
    [ "\$1" = -o ] && out=\$2
    shift
done
exec "$bin/llvm-profdata" merge -o "\$out" "$work/stale.proftext"
STUB
chmod +x "$work/stale/llvm-profdata"
expect_refusal "counts 7 lines of hello.c and 7 missed" check macos-arm64 "$work/stale"

# The tools of another operating system do not run on this machine, and the
# check refuses them rather than pass them by.
expect_refusal "linux-x86_64" check linux-x86_64 "$work/right"
finished=yes
