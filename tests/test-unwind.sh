#!/bin/sh
# The step check-unwind refuses a libunwind.a that the AddressSanitizer
# runtime of Linux cannot take as its unwinder. The archive must define
# _Unwind_Backtrace and _Unwind_GetIP, which ASan calls. Every other name it
# leaves undefined must be one that the libc of the glibc sysroot defines,
# in libc.so.6 or libc_nonshared.a, and it must ask the linker for no
# library. The release clang writes a stand-in libc and archives.
. "$(dirname "$0")/lib.sh"

bin=$(release_bin)
target=x86_64-unknown-linux-gnu
sysroot="$work/sysroot"
mkdir -p "$sysroot/lib/x86_64-linux-gnu" "$sysroot/usr/lib/x86_64-linux-gnu"

# Compile the C text $2 for the target into the object $1.
object() {
    printf '%s\n' "$2" > "$work/source.c"
    "$bin/clang" --target=$target -fPIC -c -o "$1" "$work/source.c"
}

# The stand-in libc.so.6 exports abort and dl_iterate_phdr with the symbol
# versions of glibc, and libc_nonshared.a defines atexit.
object "$work/libc.o" 'void abort(void) { for (;;) {} } int dl_iterate_phdr(void *f, void *d) { return 0; }'
printf 'GLIBC_2.2.5 { global: abort; dl_iterate_phdr; local: *; };\n' > "$work/libc.map"
"$bin/clang" --target=$target -shared -nostdlib -fuse-ld=lld \
    "-Wl,--version-script=$work/libc.map" -o "$sysroot/lib/x86_64-linux-gnu/libc.so.6" \
    "$work/libc.o"
object "$work/nonshared.o" 'int atexit(void (*f)(void)) { return 0; }'
"$bin/llvm-ar" rc "$sysroot/usr/lib/x86_64-linux-gnu/libc_nonshared.a" "$work/nonshared.o"

# Two members: one calls libc and a helper that the other defines.
object "$work/unwind.o" 'void abort(void); int atexit(void (*f)(void)); int helper(void);
int _Unwind_Backtrace(void *f, void *a) { atexit(0); return helper(); }
unsigned long _Unwind_GetIP(void *c) { abort(); return 0; }'
object "$work/helper.o" 'int dl_iterate_phdr(void *f, void *d);
int helper(void) { return dl_iterate_phdr(0, 0); }'

# Write the archive $1 of the objects named after it.
archive() {
    name=$1
    shift
    rm -f "$work/$name"
    "$bin/llvm-ar" rc "$work/$name" "$@"
}

check() {
    recipe "$root" -DSTEP=check-unwind -DLIBRARY="$work/$1" -DSYSROOT="$sysroot" \
        -DARCH=x86_64
}

archive good.a "$work/unwind.o" "$work/helper.o"
check good.a >/dev/null || fail "a complete libunwind.a was refused: $(check good.a 2>&1 | tail -5)"

# An archive without _Unwind_GetIP is refused by that name.
object "$work/backtrace.o" 'int helper(void); int _Unwind_Backtrace(void *f, void *a) { return helper(); }'
archive no-getip.a "$work/backtrace.o" "$work/helper.o"
expect_refusal "_Unwind_GetIP" check no-getip.a

# A name that the libc of the sysroot does not define is refused by name.
object "$work/outside.o" 'int __gcc_outside(void); int helper2(void) { return __gcc_outside(); }'
archive outside.a "$work/unwind.o" "$work/helper.o" "$work/outside.o"
expect_refusal "__gcc_outside" check outside.a

# A member that asks the linker for libdl is refused by the library.
object "$work/deplib.o" '#pragma comment(lib, "dl")
int helper3(void) { return 0; }'
archive deplib.a "$work/unwind.o" "$work/helper.o" "$work/deplib.o"
expect_refusal "the library dl" check deplib.a

# A sysroot without the libc of ARCH is refused.
expect_refusal "libc.so.6" recipe "$root" -DSTEP=check-unwind \
    -DLIBRARY="$work/good.a" -DSYSROOT="$sysroot" -DARCH=aarch64
finished=yes
