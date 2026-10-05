# Gotchas of the build

## Probes of the runtimes pass for any library

The runtimes toolchain sets `CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY`, so a
try-compile links nothing. Every `check_library_exists` then passes. libunwind's probes
for `dl` and `pthread` pass, and its objects get a `.deplibs` section that makes lld
add `-ldl -lpthread`. Preset the cache variable to skip a probe, as
`-DLIBUNWIND_HAS_DL_LIB=OFF` in `build_unwind` does. Read any new runtime's
`check_library_exists` calls with this in mind.

The musl libunwind that links the tools still carries `.deplibs` for `dl` and
`pthread`. musl's `libdl.a` and `libpthread.a` are empty, so the links work. It is not
shipped, and nobody has decided to change it.

## Names that the linker defines

The Linux profile runtime takes `__ehdr_start` from the linker, a strong hidden
reference. `check-profile` accepts the names in `profile_linker_names` and skips weak
undefined names, such as `__start___llvm_prf_cnts`. A new runtime check that compares
undefined names with libc needs the same two exceptions.

## The glibc sysroot of x86_64 lacks its dynamic loader path

`usr/lib/x86_64-linux-gnu/libc.so` in `build/sysroot/glibc-x86_64` names
`/lib64/ld-linux-x86-64.so.2`, which the unpacked tree lacks. A test link with `-lc`
fails in lld. Link `lib/x86_64-linux-gnu/libc.so.6` and
`usr/lib/x86_64-linux-gnu/libc_nonshared.a` by path instead. aarch64 links with `-lc`.

## Harmless output of the macOS configure

The LLVM configure of both macOS hosts prints an `xcrun: error` about `ld-classic`.
`HOST_LINK_VERSION` pins 1267, and `check-link-version` refuses any other version.

## Checking that a rebuild changed only what it should

Unpack the archives of the last release and the new ones from `build/dist`, then
`diff -r` each pair. Every file but `VERSION` and the intended additions must match.
anti.4 and anti.5 both passed that check.
