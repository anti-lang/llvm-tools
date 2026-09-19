#!/bin/sh
# The step check-builtins refuses a tree of compiler-rt runtimes that
# lacks a file. It also refuses a file of another format. Each target has
# its builtins. Linux on glibc, windows-x86_64 and macOS also have ASan
# and UBSan. windows-arm64 has UBSan alone, since compiler-rt 23.1.1 gives
# Windows on arm64 no ASan. The release clang writes a small object of
# each format for the fixtures.
. "$(dirname "$0")/lib.sh"

bin=$(release_bin)
printf 'int f(void) { return 0; }\n' > "$work/f.c"
tree="$work/lib"

# Write an object of target $1 to $2.
object() {
    "$bin/clang" --target="$1" -c -o "$2" "$work/f.c"
}

# Write an archive of target $1 to the path $2 of the tree.
archive() {
    mkdir -p "$(dirname "$tree/$2")"
    object "$1" "$work/member.o"
    rm -f "$tree/$2"
    "$bin/llvm-ar" rc "$tree/$2" "$work/member.o"
}

# Write an object of target $1 to the path $2 of the tree.
plain() {
    mkdir -p "$(dirname "$tree/$2")"
    object "$1" "$tree/$2"
}

# The start files and builtins of both musl targets.
for arch in x86_64 aarch64; do
    archive $arch-unknown-linux-musl $arch-unknown-linux-musl/libclang_rt.builtins.a
    plain $arch-unknown-linux-musl $arch-unknown-linux-musl/clang_rt.crtbegin.o
    plain $arch-unknown-linux-musl $arch-unknown-linux-musl/clang_rt.crtend.o
done

# The static sanitizer runtimes of both glibc targets, and the symbol
# lists that clang passes to the linker beside them.
for arch in x86_64 aarch64; do
    gnu=$arch-unknown-linux-gnu
    for name in asan asan_cxx asan_static asan-preinit ubsan_standalone \
                ubsan_standalone_cxx; do
        archive $gnu $gnu/libclang_rt.$name.a
    done
    for name in asan asan_cxx ubsan_standalone ubsan_standalone_cxx; do
        printf '{\n  f;\n};\n' > "$tree/$gnu/libclang_rt.$name.a.syms"
    done
done

# Windows. The ASan runtime of x86_64 is a DLL with its import library
# and two thunks. llvm-dlltool writes a real import library, whose stubs
# name no machine.
x64=x86_64-pc-windows-msvc
arm=aarch64-pc-windows-msvc
archive $x64 $x64/clang_rt.builtins.lib
archive $arm $arm/clang_rt.builtins.lib
plain $x64 $x64/clang_rt.asan_dynamic.dll
printf 'LIBRARY clang_rt.asan_dynamic.dll\nEXPORTS\n__asan_init\n' > "$work/asan.def"
"$bin/llvm-dlltool" -m i386:x86-64 -d "$work/asan.def" \
    -l "$tree/$x64/clang_rt.asan_dynamic.lib"
for name in asan_dynamic_runtime_thunk asan_static_runtime_thunk \
            ubsan_standalone ubsan_standalone_cxx; do
    archive $x64 $x64/clang_rt.$name.lib
done
for name in ubsan_standalone ubsan_standalone_cxx; do
    archive $arm $arm/clang_rt.$name.lib
done

# macOS: one universal file of arm64 and x86_64 each.
object arm64-apple-macos11 "$work/arm64.o"
object x86_64-apple-macos11 "$work/x86_64.o"
mkdir -p "$tree/darwin"
for name in libclang_rt.osx.a libclang_rt.asan_osx_dynamic.dylib \
            libclang_rt.ubsan_osx_dynamic.dylib; do
    "$bin/llvm-lipo" -create "$work/arm64.o" "$work/x86_64.o" \
        -output "$tree/darwin/$name"
done

check() {
    recipe "$root" -DSTEP=check-builtins -DBUILTINS="$tree"
}

check >/dev/null || fail "a complete tree was refused: $(check 2>&1 | tail -5)"

# A missing runtime, a missing symbol list and a runtime of the other
# processor are refused, each by name.
mv "$tree/aarch64-unknown-linux-gnu/libclang_rt.asan.a" "$work/kept.a"
expect_refusal "aarch64-unknown-linux-gnu/libclang_rt.asan.a" check
mv "$work/kept.a" "$tree/aarch64-unknown-linux-gnu/libclang_rt.asan.a"

mv "$tree/x86_64-unknown-linux-gnu/libclang_rt.ubsan_standalone.a.syms" "$work/kept.syms"
expect_refusal "libclang_rt.ubsan_standalone.a.syms" check
mv "$work/kept.syms" "$tree/x86_64-unknown-linux-gnu/libclang_rt.ubsan_standalone.a.syms"

archive $x64 $arm/clang_rt.ubsan_standalone.lib
expect_refusal "coff-arm64" check
archive $arm $arm/clang_rt.ubsan_standalone.lib

archive aarch64-unknown-linux-gnu x86_64-unknown-linux-gnu/libclang_rt.asan_cxx.a
expect_refusal "elf64-x86-64" check
archive x86_64-unknown-linux-gnu x86_64-unknown-linux-gnu/libclang_rt.asan_cxx.a

check >/dev/null || fail "the restored tree was refused"
finished=yes
