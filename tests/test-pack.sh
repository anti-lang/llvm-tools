#!/bin/sh
# scripts/pack.sh packs the tools of one host with the licences and a
# VERSION file, and only from a build of a committed recipe.
. "$(dirname "$0")/lib.sh"

copy=$(checkout_copy)
version=$(cat "$copy/pins/llvm-version")
build=$(cat "$copy/pins/build-number")
commit=$(git -C "$copy" rev-parse HEAD)

# Stand in for a finished build of <host>: five tools and the stamp that the
# recipe writes after its checks, with clean set to $2.
fake_build() {
    host=$1
    bin=$(recipe_path "$copy" "$host" bin)
    stamp=$(recipe_path "$copy" "$host" stamp)
    exe=$(recipe_path "$copy" "$host" exe)
    mkdir -p "$bin" "$(dirname "$stamp")"
    for tool in lld llvm-mc llvm-ar llvm-objdump llvm-readobj; do
        printf '%s of %s\n' "$tool" "$host" > "$bin/$tool$exe"
        chmod +x "$bin/$tool$exe"
    done
    printf 'llvm=%s\ncommit=%s\nclean=%s\n' "$version" "$3" "$2" > "$stamp"
}

dist=$(recipe_path "$copy" linux-x86_64 dist)

fake_build linux-x86_64 yes "$commit"
"$copy/scripts/pack.sh" linux-x86_64 >/dev/null
archive="$dist/llvm-tools-$version-$build-linux-x86_64.tar.xz"
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

# A Windows archive holds .exe files and no musl licence.
fake_build windows-arm64 yes "$commit"
"$copy/scripts/pack.sh" windows-arm64 >/dev/null
listing=$(tar -tJf "$dist/llvm-tools-$version-$build-windows-arm64.tar.xz" |
    sort | tr '\n' ' ')
expected="VERSION bin/ bin/lld.exe bin/llvm-ar.exe bin/llvm-mc.exe bin/llvm-objdump.exe bin/llvm-readobj.exe licenses/ licenses/llvm.txt "
[ "$listing" = "$expected" ] || fail "the Windows archive holds: $listing"

# A build of a recipe with uncommitted changes is refused.
fake_build linux-arm64 no "$commit"
expect_refusal "uncommitted" "$copy/scripts/pack.sh" linux-arm64

# A build from a commit whose recipe differs from HEAD is refused.
fake_build linux-arm64 yes "$commit"
printf '# a change\n' >> "$copy/hosts.toml"
git -C "$copy" -c user.name=test -c user.email=test@example.invalid \
    commit -q -am "Change the recipe"
expect_refusal "hosts.toml" "$copy/scripts/pack.sh" linux-arm64

# A missing tool is refused.
fake_build macos-arm64 yes "$(git -C "$copy" rev-parse HEAD)"
rm "$(recipe_path "$copy" macos-arm64 bin)/llvm-mc"
expect_refusal "llvm-mc" "$copy/scripts/pack.sh" macos-arm64

# An archive already written is never overwritten.
fake_build linux-x86_64 yes "$(git -C "$copy" rev-parse HEAD)"
expect_refusal "exists" "$copy/scripts/pack.sh" linux-x86_64

expect_refusal "no-such-host" "$copy/scripts/pack.sh" no-such-host
finished=yes
