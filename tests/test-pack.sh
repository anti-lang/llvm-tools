#!/bin/sh
# scripts/pack.sh packs two archives of one host, the tools and clang. Each
# holds the licences and a VERSION file, and comes only from a build of a
# committed recipe. The clang archive adds the builtins of all six targets,
# which the builtins build of the same commit wrote.
. "$(dirname "$0")/lib.sh"

copy=$(checkout_copy)
version=$(cat "$copy/pins/llvm-version")
major=${version%%.*}
build=$(cat "$copy/pins/build-number")
commit=$(git -C "$copy" rev-parse HEAD)
tag="$version-anti.$build"

# Stand in for a finished build of <host>: five tools, clang and the
# built-in headers. The stamp that the recipe writes after its checks gets
# clean set to $2 and the commit $3.
fake_build() {
    host=$1
    bin=$(recipe_path "$copy" "$host" bin)
    resource=$(recipe_path "$copy" "$host" resource)
    stamp=$(recipe_path "$copy" "$host" stamp)
    exe=$(recipe_path "$copy" "$host" exe)
    mkdir -p "$bin" "$resource/include" "$(dirname "$stamp")"
    for tool in lld llvm-mc llvm-ar llvm-objdump llvm-readobj clang; do
        printf '%s of %s\n' "$tool" "$host" > "$bin/$tool$exe"
        chmod +x "$bin/$tool$exe"
    done
    printf 'typedef int size_t;\n' > "$resource/include/stddef.h"
    printf 'llvm=%s\ncommit=%s\nclean=%s\n' "$version" "$3" "$2" > "$stamp"
}

# Stand in for the builtins build, with clean $1 and the commit $2.
fake_builtins() {
    lib=$(recipe_path "$copy" linux-x86_64 builtins)
    stamp=$(recipe_path "$copy" linux-x86_64 builtins-stamp)
    rm -rf "$lib"
    for triple in x86_64-unknown-linux-musl aarch64-unknown-linux-musl; do
        mkdir -p "$lib/$triple"
        for file in libclang_rt.builtins.a clang_rt.crtbegin.o clang_rt.crtend.o; do
            printf '%s\n' "$file" > "$lib/$triple/$file"
        done
    done
    mkdir -p "$lib/darwin"
    printf 'osx\n' > "$lib/darwin/libclang_rt.osx.a"
    for triple in x86_64-pc-windows-msvc aarch64-pc-windows-msvc; do
        mkdir -p "$lib/$triple"
        printf 'lib\n' > "$lib/$triple/clang_rt.builtins.lib"
    done
    mkdir -p "$(dirname "$stamp")"
    printf 'llvm=%s\ncommit=%s\nclean=%s\n' "$version" "$2" "$1" > "$stamp"
}

dist=$(recipe_path "$copy" linux-x86_64 dist)

fake_builtins yes "$commit"
fake_build linux-x86_64 yes "$commit"
"$copy/scripts/pack.sh" linux-x86_64 >/dev/null
archive="$dist/llvm-tools-$tag-linux-x86_64.tar.xz"
[ -f "$archive" ] || fail "$archive was not written"
listing=$(tar -tJf "$archive" | sort | tr '\n' ' ')
expected="VERSION bin/ bin/lld bin/llvm-ar bin/llvm-mc bin/llvm-objdump bin/llvm-readobj licenses/ licenses/llvm.txt licenses/musl.txt "
[ "$listing" = "$expected" ] || fail "the archive holds: $listing"
tar -xJf "$archive" -C "$work" VERSION bin/lld licenses/llvm.txt
printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build" "$commit" \
    | cmp -s - "$work/VERSION" || fail "VERSION reads: $(cat "$work/VERSION")"
[ -x "$work/bin/lld" ] || fail "bin/lld is not executable in the archive"
cmp -s "$work/licenses/llvm.txt" "$copy/licenses/llvm.txt" ||
    fail "licenses/llvm.txt differs from the committed licence"

# The clang archive holds clang alone in bin/, the built-in headers, the
# builtins of the six targets, the licences and VERSION.
clang_archive="$dist/clang-$tag-linux-x86_64.tar.xz"
[ -f "$clang_archive" ] || fail "$clang_archive was not written"
entries=$(tar -tJf "$clang_archive" | sort)
for entry in VERSION bin/clang "lib/clang/$major/include/stddef.h" \
             "lib/clang/$major/lib/x86_64-unknown-linux-musl/libclang_rt.builtins.a" \
             "lib/clang/$major/lib/x86_64-unknown-linux-musl/clang_rt.crtbegin.o" \
             "lib/clang/$major/lib/aarch64-unknown-linux-musl/libclang_rt.builtins.a" \
             "lib/clang/$major/lib/darwin/libclang_rt.osx.a" \
             "lib/clang/$major/lib/x86_64-pc-windows-msvc/clang_rt.builtins.lib" \
             "lib/clang/$major/lib/aarch64-pc-windows-msvc/clang_rt.builtins.lib" \
             licenses/llvm.txt licenses/musl.txt; do
    printf '%s\n' "$entries" | grep -qx "$entry" ||
        fail "the clang archive lacks $entry: $(printf '%s' "$entries" | tr '\n' ' ')"
done
[ "$(printf '%s\n' "$entries" | grep '^bin/.' | tr '\n' ' ')" = "bin/clang " ] ||
    fail "bin/ of the clang archive holds more than clang"
tar -xJf "$clang_archive" -C "$work" VERSION
printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build" "$commit" \
    | cmp -s - "$work/VERSION" || fail "VERSION of clang reads: $(cat "$work/VERSION")"

# A Windows host has .exe files and no musl licence in either archive.
fake_build windows-arm64 yes "$commit"
"$copy/scripts/pack.sh" windows-arm64 >/dev/null
listing=$(tar -tJf "$dist/llvm-tools-$tag-windows-arm64.tar.xz" |
    sort | tr '\n' ' ')
expected="VERSION bin/ bin/lld.exe bin/llvm-ar.exe bin/llvm-mc.exe bin/llvm-objdump.exe bin/llvm-readobj.exe licenses/ licenses/llvm.txt "
[ "$listing" = "$expected" ] || fail "the Windows archive holds: $listing"
entries=$(tar -tJf "$dist/clang-$tag-windows-arm64.tar.xz" | sort)
printf '%s\n' "$entries" | grep -qx bin/clang.exe ||
    fail "the Windows clang archive lacks bin/clang.exe"
if printf '%s\n' "$entries" | grep -q musl.txt; then
    fail "the Windows clang archive carries the musl licence"
fi

# A build of a recipe with uncommitted changes is refused.
fake_build linux-arm64 no "$commit"
expect_refusal "uncommitted" "$copy/scripts/pack.sh" linux-arm64

# Builtins from another commit than the host are refused, and so are none.
fake_build linux-arm64 yes "$commit"
fake_builtins yes 0000000000000000000000000000000000000000
expect_refusal "builtins" "$copy/scripts/pack.sh" linux-arm64
rm "$(recipe_path "$copy" linux-x86_64 builtins-stamp)"
expect_refusal "builtins" "$copy/scripts/pack.sh" linux-arm64
fake_builtins yes "$commit"

# A build from a commit whose recipe differs from HEAD is refused.
printf '# a change\n' >> "$copy/hosts.toml"
git -C "$copy" -c user.name=test -c user.email=test@example.invalid \
    commit -q -am "Change the recipe"
expect_refusal "hosts.toml" "$copy/scripts/pack.sh" linux-arm64
head=$(git -C "$copy" rev-parse HEAD)
fake_builtins yes "$head"

# A missing tool or a missing clang is refused.
fake_build macos-arm64 yes "$head"
rm "$(recipe_path "$copy" macos-arm64 bin)/llvm-mc"
expect_refusal "llvm-mc" "$copy/scripts/pack.sh" macos-arm64
fake_build macos-arm64 yes "$head"
rm "$(recipe_path "$copy" macos-arm64 bin)/clang"
expect_refusal "clang" "$copy/scripts/pack.sh" macos-arm64

# An archive already written is never overwritten.
fake_build linux-x86_64 yes "$head"
expect_refusal "exists" "$copy/scripts/pack.sh" linux-x86_64

expect_refusal "no-such-host" "$copy/scripts/pack.sh" no-such-host
finished=yes
