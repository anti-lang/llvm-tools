#!/bin/sh
# The step check-strip compiles checks/debug.ll with llc of a host for the
# ELF and the Mach-O triples that antic compiles for. llvm-objdump of the
# host must find debug sections in each object, and llvm-strip --strip-debug
# of the host must remove them all and leave every allocated section with
# the bytes it had. The llc, llvm-strip and llvm-objdump of the release
# stand in for those of a build.
. "$(dirname "$0")/lib.sh"

bin=$(release_bin)
triples="x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu x86_64-apple-macos
arm64-apple-macos"

check() {
    recipe "$root" -DHOST="$1" -DSTEP=check-strip -DBIN="$2" -DOUT="$work/out"
}

# Fill directory $1 with links to llc, llvm-strip and llvm-objdump of the
# release.
from_release() {
    mkdir -p "$1"
    for tool in llc llvm-strip llvm-objdump; do
        ln -s "$bin/$tool" "$1/$tool"
    done
}

# Replace tool $2 in directory $1 with a script that writes file $3 to the
# path after -o.
writes() {
    rm "$1/$2"
    cat > "$1/$2" <<STUB
#!/bin/sh
while [ "\$#" -gt 0 ]; do
    [ "\$1" = -o ] && out=\$2
    shift
done
cp "$3" "\$out"
STUB
    chmod +x "$1/$2"
}

from_release "$work/right"
output=$(check macos-arm64 "$work/right" 2>&1) ||
    fail "the tools of the release were refused: $output"
for triple in $triples; do
    printf '%s\n' "$output" | grep -q "debug.o for $triple: llvm-strip --strip-debug removes" ||
        fail "no line for $triple: $output"
    for file in debug.o stripped.o; do
        [ -f "$work/out/$triple/$file" ] || fail "$work/out/$triple/$file is missing"
    done
done
if printf '%s\n' "$output" | grep -q "for x86_64-pc-windows-msvc"; then
    fail "the check strips a COFF object: $output"
fi

# An llvm-strip that copies the object is refused for the debug sections it
# keeps.
from_release "$work/copies"
rm "$work/copies/llvm-strip"
cat > "$work/copies/llvm-strip" <<'STUB'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case $1 in
        -o) out=$2; shift ;;
        -*) ;;
        *) in=$1 ;;
    esac
    shift
done
cp "$in" "$out"
STUB
chmod +x "$work/copies/llvm-strip"
expect_refusal "keeps the debug section .debug_" check macos-arm64 "$work/copies"

# An llvm-strip whose object holds other code is refused for the size of
# .text. The code of -O0 is longer than that of -O2.
"$bin/llc" -O0 -filetype=obj -mtriple=x86_64-unknown-linux-gnu \
    -o "$work/o0.o" "$root/checks/debug.ll"
"$bin/llvm-strip" --strip-debug -o "$work/o0-stripped.o" "$work/o0.o"
from_release "$work/other-code"
writes "$work/other-code" llvm-strip "$work/o0-stripped.o"
expect_refusal "changes the size of .text" check macos-arm64 "$work/other-code"

# An llvm-strip whose .text holds as many zero bytes as the code is refused
# for the bytes of .text.
"$bin/llc" -O2 -filetype=obj -mtriple=x86_64-unknown-linux-gnu \
    -o "$work/o2.o" "$root/checks/debug.ll"
size=$("$bin/llvm-objdump" --section-headers "$work/o2.o" |
    awk '$2 == ".text" { print $3 }')
head -c "$((0x$size))" /dev/zero > "$work/zeros"
"$bin/llvm-objcopy" --strip-debug --update-section=.text="$work/zeros" \
    "$work/o2.o" "$work/zeroed.o"
from_release "$work/zeroed"
writes "$work/zeroed" llvm-strip "$work/zeroed.o"
expect_refusal "changes the bytes of .text" check macos-arm64 "$work/zeroed"

# An llvm-strip that drops an allocated section is refused.
"$bin/llvm-objcopy" --strip-debug --remove-section=.eh_frame \
    --remove-section=.rela.eh_frame "$work/o2.o" "$work/no-eh.o"
from_release "$work/drops"
writes "$work/drops" llvm-strip "$work/no-eh.o"
expect_refusal "drops the section .eh_frame" check macos-arm64 "$work/drops"

# An llc whose object holds no debug section is refused, since nothing
# would show that llvm-strip strips.
"$bin/llc" -O2 -filetype=obj -mtriple=x86_64-unknown-linux-gnu \
    -o "$work/plain.o" "$root/checks/hello.ll"
from_release "$work/no-debug"
writes "$work/no-debug" llc "$work/plain.o"
expect_refusal "llc writes no debug section for x86_64-unknown-linux-gnu" \
    check macos-arm64 "$work/no-debug"

# A missing llvm-strip is refused.
from_release "$work/no-strip"
rm "$work/no-strip/llvm-strip"
expect_refusal "llvm-strip is missing" check macos-arm64 "$work/no-strip"

# The tools of another operating system do not run on this machine, and the
# check refuses them rather than pass them by.
expect_refusal "linux-x86_64" check linux-x86_64 "$work/right"
finished=yes
