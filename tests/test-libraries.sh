#!/bin/sh
# The recipe refuses a tool that names a shared library outside the system
# set of its host. The set is empty on Linux. It holds libSystem and libc++
# on macOS, with CoreFoundation for dsymutil alone, and the system DLLs on
# Windows. Each case links a small program with the release clang.
. "$(dirname "$0")/lib.sh"

bin=$(release_bin)
clang="$bin/clang"
tools="$(recipe "$root" -DSTEP=tools) $(recipe "$root" -DSTEP=compiler)"

# Fill directory $1 with the tools of hosts.toml and clang, each a copy of
# file $2 with the suffix $3.
binaries() {
    mkdir -p "$1"
    for tool in $tools; do
        cp "$2" "$1/$tool$3"
    done
}

check() {
    recipe "$root" -DHOST="$1" -DSTEP=check-libraries -DBIN="$2"
}

printf 'int dep_value(void) { return 1; }\n' > "$work/dep.c"
printf 'int dep_value(void);\nint main(void) { return dep_value(); }\n' \
    > "$work/uses-dep.c"
printf 'int main(void) { return 0; }\n' > "$work/alone.c"

# Linux: a static executable passes, one that needs libdep.so does not.
elf="--target=x86_64-unknown-linux-musl -nostdlib -fuse-ld=lld -Wl,-e,main"
"$clang" $elf -shared -o "$work/libdep.so" "$work/dep.c"
"$clang" $elf -o "$work/elf-dynamic" "$work/uses-dep.c" -L"$work" -ldep
"$clang" $elf -static -o "$work/elf-static" "$work/alone.c"
binaries "$work/linux-static" "$work/elf-static" ""
binaries "$work/linux-dynamic" "$work/elf-dynamic" ""
check linux-x86_64 "$work/linux-static" >/dev/null ||
    fail "a static Linux tool was refused"
expect_refusal "libdep.so" check linux-x86_64 "$work/linux-dynamic"
# The same binary is an x86_64 one, which the arm64 host refuses.
expect_refusal "elf64-x86-64" check linux-arm64 "$work/linux-static"

# macOS: libSystem alone passes, a library of our own does not.
sdk=$(recipe "$root" -DHOST=macos-arm64 -DSTEP=paths | sed -n 's/^sysroot=//p')
macho="-arch arm64 -isysroot $sdk -fuse-ld=lld -mmacos-version-min=11.0"
"$clang" $macho -dynamiclib -install_name /opt/dep/libdep.dylib \
    -o "$work/libdep.dylib" "$work/dep.c"
"$clang" $macho -o "$work/macho-dynamic" "$work/uses-dep.c" -L"$work" -ldep
"$clang" $macho -o "$work/macho-system" "$work/alone.c"
binaries "$work/macos-system" "$work/macho-system" ""
binaries "$work/macos-dynamic" "$work/macho-dynamic" ""
check macos-arm64 "$work/macos-system" >/dev/null ||
    fail "a macOS tool that needs libSystem alone was refused"
expect_refusal "/opt/dep/libdep.dylib" check macos-arm64 "$work/macos-dynamic"

# macOS: dsymutil may name CoreFoundation, and any other tool that names it
# is refused.
printf '#include <CoreFoundation/CoreFoundation.h>\nint main(void) { return CFAbsoluteTimeGetCurrent() < 0; }\n' \
    > "$work/uses-cf.c"
"$clang" $macho -framework CoreFoundation -o "$work/macho-cf" "$work/uses-cf.c"
binaries "$work/macos-cf-dsymutil" "$work/macho-system" ""
cp "$work/macho-cf" "$work/macos-cf-dsymutil/dsymutil"
check macos-arm64 "$work/macos-cf-dsymutil" >/dev/null ||
    fail "a dsymutil that names CoreFoundation was refused"
binaries "$work/macos-cf-objcopy" "$work/macho-system" ""
cp "$work/macho-cf" "$work/macos-cf-objcopy/llvm-objcopy"
# CMake wraps the line of the refusal before the path of the library.
expect_refusal "llvm-objcopy of macos-arm64 needs" check macos-arm64 "$work/macos-cf-objcopy"

# macOS: a tool built for a newer macOS than the deployment target refuses
# to start on an older one, so its minos is refused.
"$clang" -arch arm64 -isysroot "$sdk" -fuse-ld=lld -mmacos-version-min=13.0 \
    -o "$work/macho-newer" "$work/alone.c"
binaries "$work/macos-newer" "$work/macho-newer" ""
expect_refusal "minos 13.0" check macos-arm64 "$work/macos-newer"

# Windows: an import of KERNEL32.dll passes, one of dep.dll does not.
printf 'LIBRARY dep.dll\nEXPORTS\n  dep_value\n' > "$work/dep.def"
printf 'LIBRARY KERNEL32.dll\nEXPORTS\n  ExitProcess\n' > "$work/kernel32.def"
"$bin/llvm-dlltool" -m i386:x86-64 -d "$work/dep.def" -l "$work/dep.lib"
"$bin/llvm-dlltool" -m i386:x86-64 -d "$work/kernel32.def" \
    -l "$work/kernel32.lib"
printf '__declspec(dllimport) void ExitProcess(unsigned);\nint main(void) { ExitProcess(0); return 0; }\n' \
    > "$work/win-alone.c"
printf '__declspec(dllimport) int dep_value(void);\n__declspec(dllimport) void ExitProcess(unsigned);\nint main(void) { ExitProcess(dep_value()); return 0; }\n' \
    > "$work/win-dep.c"
pe="--target=x86_64-pc-windows-msvc -nostdlib -fuse-ld=lld -Wl,-entry:main -Wl,-subsystem:console"
"$clang" $pe -o "$work/pe-system.exe" "$work/win-alone.c" "$work/kernel32.lib"
"$clang" $pe -o "$work/pe-dynamic.exe" "$work/win-dep.c" "$work/dep.lib" \
    "$work/kernel32.lib"
binaries "$work/windows-system" "$work/pe-system.exe" ".exe"
binaries "$work/windows-dynamic" "$work/pe-dynamic.exe" ".exe"
check windows-x86_64 "$work/windows-system" >/dev/null ||
    fail "a Windows tool that imports KERNEL32.dll alone was refused"
expect_refusal "dep.dll" check windows-x86_64 "$work/windows-dynamic"

# A missing tool is refused before any library is read.
rm "$work/linux-static/llvm-ar"
expect_refusal "llvm-ar" check linux-x86_64 "$work/linux-static"
finished=yes
