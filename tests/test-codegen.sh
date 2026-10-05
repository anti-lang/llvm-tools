#!/bin/sh
# The step check-codegen runs checks/hello.ll through opt and llc of a host
# for each of the six triples that antic compiles for. llvm-readobj of the
# same host must read each object in the format of its triple. llvm-profdata
# of the host merges checks/hello.proftext, and opt must apply that profile
# to hello.ll in a module that verifies. The opt, llc, llvm-readobj and
# llvm-profdata of the release stand in for those of a build.
. "$(dirname "$0")/lib.sh"

bin=$(release_bin)
triples="x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu x86_64-apple-macos
arm64-apple-macos x86_64-pc-windows-msvc aarch64-pc-windows-msvc"

check() {
    recipe "$root" -DHOST="$1" -DSTEP=check-codegen -DBIN="$2" -DOUT="$work/out"
}

# Fill directory $1 with links to opt, llc, llvm-readobj and llvm-profdata
# of the release.
from_release() {
    mkdir -p "$1"
    for tool in opt llc llvm-readobj llvm-profdata; do
        ln -s "$bin/$tool" "$1/$tool"
    done
}

from_release "$work/right"
output=$(check macos-arm64 "$work/right" 2>&1) ||
    fail "the tools of the release were refused: $output"
for triple in $triples; do
    printf '%s\n' "$output" | grep -q "hello.o for $triple: " ||
        fail "no object for $triple: $output"
    [ -f "$work/out/$triple/hello.o" ] || fail "$work/out/$triple/hello.o is missing"
done
printf '%s\n' "$output" | grep -q "opt applies the profile of hello.proftext" ||
    fail "no line for the profile: $output"
[ -f "$work/out/hello.profdata" ] || fail "$work/out/hello.profdata is missing"

# An llc that writes an ELF object of x86_64 for every triple is refused at
# the first triple of another format.
"$bin/llc" -filetype=obj -mtriple=x86_64-unknown-linux-gnu -o "$work/elf.o" \
    "$root/checks/hello.ll"
from_release "$work/elf-only"
rm "$work/elf-only/llc"
cat > "$work/elf-only/llc" <<EOF
#!/bin/sh
while [ "\$#" -gt 0 ]; do
    [ "\$1" = -o ] && out=\$2
    shift
done
cp "$work/elf.o" "\$out"
EOF
chmod +x "$work/elf-only/llc"
expect_refusal "elf64-x86-64 for aarch64-unknown-linux-gnu" \
    check macos-arm64 "$work/elf-only"

# An opt that fails is refused, and so is a missing llc.
from_release "$work/bad-opt"
rm "$work/bad-opt/opt"
printf '#!/bin/sh\nexit 3\n' > "$work/bad-opt/opt"
chmod +x "$work/bad-opt/opt"
expect_refusal "opt -passes=default<O2>" check macos-arm64 "$work/bad-opt"
from_release "$work/no-llc"
rm "$work/no-llc/llc"
expect_refusal "llc is missing" check macos-arm64 "$work/no-llc"

# An llvm-profdata that fails is refused, and so is a missing one.
from_release "$work/bad-profdata"
rm "$work/bad-profdata/llvm-profdata"
printf '#!/bin/sh\nexit 3\n' > "$work/bad-profdata/llvm-profdata"
chmod +x "$work/bad-profdata/llvm-profdata"
expect_refusal "llvm-profdata merge" check macos-arm64 "$work/bad-profdata"
from_release "$work/no-profdata"
rm "$work/no-profdata/llvm-profdata"
expect_refusal "llvm-profdata is missing" check macos-arm64 "$work/no-profdata"

# A profile whose hash does not match @main is one that opt drops with a
# warning and status 0. The check refuses it.
sed 's/^784007056844089447$/1/' "$root/checks/hello.proftext" > "$work/stale.proftext"
from_release "$work/stale"
rm "$work/stale/llvm-profdata"
cat > "$work/stale/llvm-profdata" <<EOF
#!/bin/sh
while [ "\$#" -gt 0 ]; do
    [ "\$1" = -o ] && out=\$2
    shift
done
exec "$bin/llvm-profdata" merge -o "\$out" "$work/stale.proftext"
EOF
chmod +x "$work/stale/llvm-profdata"
expect_refusal "does not apply the profile" check macos-arm64 "$work/stale"

# The tools of another operating system do not run on this machine, and the
# check refuses them rather than pass them by.
expect_refusal "linux-x86_64" check linux-x86_64 "$work/right"
finished=yes
