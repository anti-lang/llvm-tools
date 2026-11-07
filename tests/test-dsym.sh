#!/bin/sh
# The step check-dsym links checks/hello.c with debug information, through
# the release clang and lld. dsymutil of a host must write its dSYM, whose
# DWARF file names the UUID of the program and holds its debug sections,
# which llvm-objdump of the host reads. The dsymutil and llvm-objdump of the
# release stand in for those of a build.
. "$(dirname "$0")/lib.sh"

bin=$(release_bin)

check() {
    recipe "$root" -DHOST="$1" -DSTEP=check-dsym -DBIN="$2" -DOUT="$work/out"
}

# Fill directory $1 with links to dsymutil and llvm-objdump of the release.
from_release() {
    mkdir -p "$1"
    for tool in dsymutil llvm-objdump; do
        ln -s "$bin/$tool" "$1/$tool"
    done
}

# Replace dsymutil in directory $1 with a script that runs the lines of $2
# with out set to the path after -o.
dsymutil_doing() {
    rm "$1/dsymutil"
    cat > "$1/dsymutil" <<STUB
#!/bin/sh
while [ "\$#" -gt 0 ]; do
    [ "\$1" = -o ] && out=\$2
    shift
done
$2
STUB
    chmod +x "$1/dsymutil"
}

from_release "$work/right"
output=$(check macos-arm64 "$work/right" 2>&1) ||
    fail "the tools of the release were refused: $output"
printf '%s\n' "$output" | grep -q "dsymutil writes the dSYM of hello" ||
    fail "no line for the dSYM: $output"
for file in hello hello.o hello.dSYM/Contents/Resources/DWARF/hello; do
    [ -f "$work/out/$file" ] || fail "$work/out/$file is missing"
done

# A dsymutil that fails is refused, and so is a missing one.
from_release "$work/fails"
dsymutil_doing "$work/fails" "exit 3"
expect_refusal "dsymutil failed" check macos-arm64 "$work/fails"
from_release "$work/missing"
rm "$work/missing/dsymutil"
expect_refusal "dsymutil is missing" check macos-arm64 "$work/missing"

# A dsymutil that writes nothing is refused.
from_release "$work/nothing"
dsymutil_doing "$work/nothing" "exit 0"
expect_refusal "writes no DWARF file" check macos-arm64 "$work/nothing"

# A dSYM whose file is the program itself names the right UUID and holds
# no debug section, and is refused.
from_release "$work/program"
dsymutil_doing "$work/program" 'mkdir -p "$out/Contents/Resources/DWARF"
cp "$(dirname "$out")/hello" "$out/Contents/Resources/DWARF/hello"'
expect_refusal "holds no __debug_info" check macos-arm64 "$work/program"

# The dSYM of another program names another UUID, and is refused.
sdk=$(recipe "$root" -DHOST=macos-arm64 -DSTEP=paths | sed -n 's/^sysroot=//p')
printf 'int main(void) { return 0; }\n' > "$work/other.c"
"$bin/clang" -isysroot "$sdk" -g -c -o "$work/other.o" "$work/other.c"
"$bin/clang" -isysroot "$sdk" -fuse-ld=lld -o "$work/other" "$work/other.o"
mkdir -p "$work/elsewhere"
cp "$work/other" "$work/elsewhere/hello"
from_release "$work/other-uuid"
dsymutil_doing "$work/other-uuid" "exec \"$bin/dsymutil\" \"$work/elsewhere/hello\" -o \"\$out\""
expect_refusal "names the UUID" check macos-arm64 "$work/other-uuid"

# dsymutil writes the dSYM of a macOS program, which the release clang
# links on this machine alone.
expect_refusal "linux-x86_64" check linux-x86_64 "$work/right"
finished=yes
