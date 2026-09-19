#!/bin/sh
# The Linux sanitizer runtimes compile against glibc 2.35 and the kernel
# headers of Ubuntu 22.04. pins/sysroot.toml names three packages of the
# jammy release pocket per processor, and STEP=glibc-sysroot unpacks them
# into one tree. Stand-in packages served from file:// URLs take their
# place in a copy of the repository.
. "$(dirname "$0")/lib.sh"

# The pins name the release pocket of jammy, whose files never change.
for arch in x86_64 aarch64; do
    for package in libc-dev libc headers; do
        url=$(sed -n "/^\[glibc-$arch\]/,/^\[/s/^$package-url = \"\(.*\)\"$/\1/p" \
              "$root/pins/sysroot.toml")
        digest=$(sed -n "/^\[glibc-$arch\]/,/^\[/s/^$package-sha256 = \"\(.*\)\"$/\1/p" \
                 "$root/pins/sysroot.toml")
        case $url in
            https://archive.ubuntu.com/ubuntu/pool/main/*_amd64.deb) [ $arch = x86_64 ] ;;
            https://ports.ubuntu.com/ubuntu-ports/pool/main/*_arm64.deb) [ $arch = aarch64 ] ;;
            *) false ;;
        esac || fail "glibc-$arch names '$url' for $package"
        case $url in
            *2.35-0ubuntu3_*|*linux-libc-dev_5.15.0-25.25_*) ;;
            *) fail "glibc-$arch names '$url', not a package of the jammy release" ;;
        esac
        printf '%s\n' "$digest" | grep -Eqx '[0-9a-f]{64}' ||
            fail "glibc-$arch has the digest '$digest' for $package"
    done
done

bin=$(release_bin)

# Write the stand-in package $1 whose data holds the files named after it.
deb() {
    name=$1
    shift
    stage="$work/stage-$name"
    rm -rf "$stage"
    mkdir -p "$stage/data"
    for path in "$@"; do
        mkdir -p "$(dirname "$stage/data/$path")"
        printf '%s\n' "$path" > "$stage/data/$path"
    done
    printf '2.0\n' > "$stage/debian-binary"
    (cd "$stage/data" && cmake -E tar cf ../data.tar.zst --zstd -- .)
    (cd "$stage/data" && cmake -E tar cf ../control.tar.zst --zstd -- .)
    (cd "$stage" && "$bin/llvm-ar" rc --format=gnu "$work/$name.deb" \
        debian-binary control.tar.zst data.tar.zst)
}
deb libc-dev usr/include/features.h usr/lib/x86_64-linux-gnu/libc.so
deb libc lib/x86_64-linux-gnu/libc.so.6
deb headers usr/include/linux/futex.h

copy=$(checkout_copy)
digest() {
    shasum -a 256 "$work/$1.deb" | cut -d' ' -f1
}
{
    printf '\n[glibc-x86_64]\n'
    for package in libc-dev libc headers; do
        printf '%s-url = "file://%s/%s.deb"\n' $package "$work" $package
        printf '%s-sha256 = "%s"\n' $package "$(digest $package)"
    done
} > "$work/pins"
# The copy keeps every other table and takes the stand-in glibc-x86_64.
awk '/^\[glibc-x86_64\]$/ { skip = 1; next } /^\[/ { skip = 0 } !skip' \
    "$copy/pins/sysroot.toml" > "$work/sysroot.toml"
cat "$work/sysroot.toml" "$work/pins" > "$copy/pins/sysroot.toml"

# The step prints the directory last, after the lines of the download.
tree=$(recipe "$copy" -DSTEP=glibc-sysroot -DARCH=x86_64 | tail -n 1)
for path in usr/include/features.h usr/lib/x86_64-linux-gnu/libc.so \
            lib/x86_64-linux-gnu/libc.so.6 usr/include/linux/futex.h; do
    [ "$(cat "$tree/$path" 2>/dev/null)" = "$path" ] ||
        fail "the glibc sysroot $tree lacks $path"
done
[ ! -e "$tree/debian-binary" ] || fail "the package wrapper landed in the sysroot"

# A package of another digest is refused.
printf 'changed\n' >> "$work/libc.deb"
rm -rf "$copy/build/downloads"
expect_refusal "the pin is" recipe "$copy" -DSTEP=glibc-sysroot -DARCH=x86_64
finished=yes
