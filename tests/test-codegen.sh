#!/bin/sh
# The step check-codegen runs checks/hello.ll through opt and llc of a host
# for each of the six triples that antic compiles for. llvm-readobj of the
# same host must read each object in the format of its triple. The opt, llc
# and llvm-readobj of the release stand in for those of a build.
. "$(dirname "$0")/lib.sh"

bin=$(release_bin)
triples="x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu x86_64-apple-macos
arm64-apple-macos x86_64-pc-windows-msvc aarch64-pc-windows-msvc"

check() {
    recipe "$root" -DHOST="$1" -DSTEP=check-codegen -DBIN="$2" -DOUT="$work/out"
}

# Fill directory $1 with links to opt, llc and llvm-readobj of the release.
from_release() {
    mkdir -p "$1"
    for tool in opt llc llvm-readobj; do
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

# The tools of another operating system do not run on this machine, and the
# check refuses them rather than pass them by.
expect_refusal "linux-x86_64" check linux-x86_64 "$work/right"
finished=yes
