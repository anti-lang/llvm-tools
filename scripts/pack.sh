#!/bin/sh
# Pack the tools and clang of one host, each with the licences and a
# VERSION file.
#
#   scripts/pack.sh <host>
#
# Writes llvm-tools-<tag>-<host>.tar.xz and clang-<tag>-<host>.tar.xz into
# the dist directory of the build tree. The clang archive holds clang, its
# built-in headers and the compiler-rt builtins of all six targets, which
# the builtins build of the same commit wrote. Every build must come from a
# committed recipe, the one that HEAD holds, since VERSION names that commit.
. "$(dirname "$0")/common.sh"

[ "$#" -eq 1 ] || die "usage: scripts/pack.sh <host>"
host=$1
require_host "$host"

bin=$(recipe_path "$host" bin)
resource=$(recipe_path "$host" resource)
builtins=$(recipe_path "$host" builtins)
builtins_stamp=$(recipe_path "$host" builtins-stamp)
stamp=$(recipe_path "$host" stamp)
exe=$(recipe_path "$host" exe)
dist=$(recipe_path "$host" dist)
major=${version%%.*}

# Print field <name> of the stamp file <file>.
field() {
    sed -n "s/^$2=//p" "$1"
}
[ -f "$stamp" ] || die "$stamp is missing, so no finished build of $host exists"
[ "$(field "$stamp" llvm)" = "$version" ] ||
    die "$host was built for LLVM $(field "$stamp" llvm), and the pin is $version"
[ "$(field "$stamp" clean)" = yes ] ||
    die "$host was built from a recipe with uncommitted changes"
commit=$(field "$stamp" commit)
# DESIGN: the files that decide the build must be the ones of HEAD. A
# rebuild with a changed recipe then cannot hide under an old build number.
changed=$(git -C "$root" diff --name-only "$commit" HEAD -- \
    build-llvm.cmake hosts.toml pins) ||
    die "the recipe commit $commit of $host is not in this repository"
[ -z "$changed" ] ||
    die "$host was built from $commit, and HEAD changes $changed since"
# Every archive under one tag comes from one commit, the builtins as well.
[ -f "$builtins_stamp" ] ||
    die "$builtins_stamp is missing, so no finished build of the builtins exists"
[ "$(field "$builtins_stamp" commit)" = "$commit" ] &&
    [ "$(field "$builtins_stamp" clean)" = yes ] ||
    die "the builtins were built from $(field "$builtins_stamp" commit), and $host from $commit"

# DESIGN: an archive already written may already be published, and a
# published archive is never replaced. A new build takes a new number.
for kind in $archive_kinds; do
    archive="$dist/$(archive_name "$kind" "$host")"
    [ ! -e "$archive" ] || die "$archive exists"
done

stage=$(mktemp -d "${TMPDIR:-/tmp}/llvm-tools-pack.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/llvm-tools/bin" "$stage/clang/bin" "$stage/clang/lib/clang/$major"
for tool in $(toml_get "$root/hosts.toml" "" tools); do
    [ -f "$bin/$tool$exe" ] || die "$bin/$tool$exe is missing"
    cp "$bin/$tool$exe" "$stage/llvm-tools/bin/"
done
for tool in $(toml_get "$root/hosts.toml" "" compiler); do
    [ -f "$bin/$tool$exe" ] || die "$bin/$tool$exe is missing"
    cp "$bin/$tool$exe" "$stage/clang/bin/"
done
[ -d "$resource/include" ] || die "$resource/include, the built-in headers, is missing"
cp -R "$resource/include" "$stage/clang/lib/clang/$major/"
cp -R "$builtins" "$stage/clang/lib/clang/$major/"
chmod 755 "$stage"/*/bin/*

mkdir -p "$dist"
# The archive names no user of the machine that packed it.
owner="--owner=0 --group=0"
case $(tar --version) in
    bsdtar*) owner="--uid 0 --gid 0 --uname root --gname root" ;;
esac
for kind in $archive_kinds; do
    mkdir -p "$stage/$kind/licenses"
    cp "$root/licenses/llvm.txt" "$stage/$kind/licenses/"
    # musl is linked into the binaries of a Linux host, and its licence asks
    # for the notice in every copy.
    if [ "$(toml_get "$root/hosts.toml" "$host" sysroot)" = musl ]; then
        cp "$root/licenses/musl.txt" "$stage/$kind/licenses/"
    fi
    printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build_number" \
        "$commit" > "$stage/$kind/VERSION"
    archive="$dist/$(archive_name "$kind" "$host")"
    (cd "$stage/$kind" && tar $owner -cJf "$archive.part" VERSION bin \
        $(ls -d lib 2>/dev/null) licenses)
    mv "$archive.part" "$archive"
    printf '%s %s bytes\n' "$archive" "$(wc -c < "$archive" | tr -d ' ')"
done
