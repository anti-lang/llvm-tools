#!/bin/sh
# The step check-profile refuses a profile runtime that cannot serve a
# program that -fprofile-generate instruments. The runtime must define
# __llvm_profile_runtime and __llvm_profile_write_file, which the program
# references, and a Darwin one must define both for arm64 and x86_64. On
# Linux the C library of the sysroot must define every name that the
# runtime leaves undefined, the weak ones aside, and no member may ask the
# linker for a library. No runtime may hold the path of the build tree. The
# release clang writes stand-in C libraries and runtimes.
. "$(dirname "$0")/lib.sh"

bin=$(release_bin)

# Compile the C text $3 for target $2 into the object $1.
object() {
    printf '%s\n' "$3" > "$work/source.c"
    case $2 in
        *-linux-*) pic=-fPIC ;;
        *) pic="" ;;
    esac
    "$bin/clang" --target="$2" $pic -c -o "$1" "$work/source.c"
}

# Write the archive $1 of the objects named after it.
archive() {
    name=$1
    shift
    rm -f "$work/$name"
    "$bin/llvm-ar" rc "$work/$name" "$@"
}

check() {
    recipe "$root" -DSTEP=check-profile -DLIBRARY="$work/$1" -DTARGET="$2" \
        ${3:+-DSYSROOT="$3"}
}

# The two names that an instrumented program references, a call into the C
# library, a weak reference to a section bound that the linker defines, and
# __ehdr_start, the ELF header that the linker defines. The Linux runtime
# reads its build ID through the last.
runtime='int __llvm_profile_runtime;
extern char __start___llvm_prf_cnts __attribute__((weak, visibility("hidden")));
extern const char __ehdr_start __attribute__((visibility("hidden")));
int getpid(void); int atexit(void (*f)(void));
int __llvm_profile_write_file(void) { atexit(0); return getpid() + (&__start___llvm_prf_cnts != 0) + __ehdr_start; }'
no_runtime_var='int __llvm_profile_write_file(void) { return 0; }'

# glibc: the stand-in libc.so.6 exports getpid with a symbol version of
# glibc, and libc_nonshared.a defines atexit.
gnu=x86_64-unknown-linux-gnu
glibc="$work/glibc"
mkdir -p "$glibc/lib/x86_64-linux-gnu" "$glibc/usr/lib/x86_64-linux-gnu"
object "$work/libc.o" $gnu 'int getpid(void) { return 1; }'
printf 'GLIBC_2.2.5 { global: getpid; local: *; };\n' > "$work/libc.map"
"$bin/clang" --target=$gnu -shared -nostdlib -fuse-ld=lld \
    "-Wl,--version-script=$work/libc.map" -o "$glibc/lib/x86_64-linux-gnu/libc.so.6" \
    "$work/libc.o"
object "$work/nonshared.o" $gnu 'int atexit(void (*f)(void)) { return 0; }'
"$bin/llvm-ar" rc "$glibc/usr/lib/x86_64-linux-gnu/libc_nonshared.a" "$work/nonshared.o"

object "$work/gnu.o" $gnu "$runtime"
archive gnu.a "$work/gnu.o"
check gnu.a $gnu "$glibc" >/dev/null ||
    fail "a complete glibc runtime was refused: $(check gnu.a $gnu "$glibc" 2>&1 | tail -5)"

# A runtime without either name is refused by that name.
object "$work/no-var.o" $gnu "$no_runtime_var"
archive no-var.a "$work/no-var.o"
expect_refusal "__llvm_profile_runtime" check no-var.a $gnu "$glibc"
object "$work/no-write.o" $gnu 'int __llvm_profile_runtime;'
archive no-write.a "$work/no-write.o"
expect_refusal "__llvm_profile_write_file" check no-write.a $gnu "$glibc"

# A name that the libc of the sysroot does not define is refused by name.
object "$work/outside.o" $gnu 'int __gcc_outside(void); int helper(void) { return __gcc_outside(); }'
archive outside.a "$work/gnu.o" "$work/outside.o"
expect_refusal "__gcc_outside" check outside.a $gnu "$glibc"

# A member that asks the linker for libdl is refused by the library.
object "$work/deplib.o" $gnu '#pragma comment(lib, "dl")
int helper(void) { return 0; }'
archive deplib.a "$work/gnu.o" "$work/deplib.o"
expect_refusal "the library dl" check deplib.a $gnu "$glibc"

# A member that holds the path of the build tree is refused.
object "$work/path.o" $gnu "const char *where = \"$root/build/builtins/x.c\";"
archive path.a "$work/gnu.o" "$work/path.o"
expect_refusal "holds the path" check path.a $gnu "$glibc"

# A sysroot without the libc of the target is refused, and so is a Linux
# target without a sysroot.
expect_refusal "libc.so.6" check gnu.a aarch64-unknown-linux-gnu "$glibc"
expect_refusal "SYSROOT" check gnu.a $gnu

# musl: libc.a of the sysroot defines getpid and atexit.
musl=x86_64-unknown-linux-musl
musl_root="$work/musl"
mkdir -p "$musl_root/usr/lib"
object "$work/musl-libc.o" $musl 'int getpid(void) { return 1; }
int atexit(void (*f)(void)) { return 0; }'
"$bin/llvm-ar" rc "$musl_root/usr/lib/libc.a" "$work/musl-libc.o"
object "$work/musl.o" $musl "$runtime"
archive musl.a "$work/musl.o"
check musl.a $musl "$musl_root" >/dev/null ||
    fail "a complete musl runtime was refused: $(check musl.a $musl "$musl_root" 2>&1 | tail -5)"
object "$work/musl-outside.o" $musl 'int __gcc_outside(void); int helper(void) { return __gcc_outside(); }'
archive musl-outside.a "$work/musl.o" "$work/musl-outside.o"
expect_refusal "__gcc_outside" check musl-outside.a $musl "$musl_root"
expect_refusal "libc.a" check musl.a $musl "$glibc"

# Windows: the two names, and no C library to check against.
win=aarch64-pc-windows-msvc
object "$work/win.o" $win "$runtime"
archive win.lib "$work/win.o"
check win.lib $win >/dev/null ||
    fail "a complete Windows runtime was refused: $(check win.lib $win 2>&1 | tail -5)"
object "$work/win-no-var.o" $win "$no_runtime_var"
archive win-no-var.lib "$work/win-no-var.o"
expect_refusal "__llvm_profile_runtime" check win-no-var.lib $win

# Darwin: one universal archive, whose names carry an underscore in front.
# Each processor must define both.
object "$work/arm64.o" arm64-apple-macos11 "$runtime"
object "$work/x86_64.o" x86_64-apple-macos11 "$runtime"
object "$work/x86_64-no-write.o" x86_64-apple-macos11 'int __llvm_profile_runtime;'
archive arm64.a "$work/arm64.o"
archive x86_64.a "$work/x86_64.o"
archive x86_64-no-write.a "$work/x86_64-no-write.o"
"$bin/llvm-lipo" -create "$work/arm64.a" "$work/x86_64.a" -output "$work/osx.a"
check osx.a darwin >/dev/null ||
    fail "a complete Darwin runtime was refused: $(check osx.a darwin 2>&1 | tail -5)"
"$bin/llvm-lipo" -create "$work/arm64.a" -output "$work/arm64-only.a"
expect_refusal "x86_64" check arm64-only.a darwin
"$bin/llvm-lipo" -create "$work/arm64.a" "$work/x86_64-no-write.a" \
    -output "$work/osx-no-write.a"
expect_refusal "__llvm_profile_write_file" check osx-no-write.a darwin

# A target that the clang archives carry no profile runtime of is refused.
expect_refusal "riscv64-unknown-linux-gnu" check gnu.a riscv64-unknown-linux-gnu "$glibc"
finished=yes
