#!/bin/sh
# Pack the tools of one host with the licences and a VERSION file.
#
#   scripts/pack.sh <host>
#
# Writes llvm-tools-<version>-<build>-<host>.tar.xz into the dist directory
# of the build tree. The build must come from a committed recipe, the one
# that HEAD holds, since VERSION names that commit.
. "$(dirname "$0")/common.sh"

[ "$#" -eq 1 ] || die "usage: scripts/pack.sh <host>"
host=$1
require_host "$host"

bin=$(recipe_path "$host" bin)
stamp=$(recipe_path "$host" stamp)
exe=$(recipe_path "$host" exe)
dist=$(recipe_path "$host" dist)
archive="$dist/$(archive_name "$host")"

[ -f "$stamp" ] || die "$stamp is missing, so no finished build of $host exists"
field() {
    sed -n "s/^$1=//p" "$stamp"
}
[ "$(field llvm)" = "$version" ] ||
    die "$host was built for LLVM $(field llvm), and the pin is $version"
[ "$(field clean)" = yes ] ||
    die "$host was built from a recipe with uncommitted changes"
commit=$(field commit)
# DESIGN: the files that decide the build must be the ones of HEAD. A
# rebuild with a changed recipe then cannot hide under an old build number.
changed=$(git -C "$root" diff --name-only "$commit" HEAD -- \
    build-llvm.cmake hosts.toml pins) ||
    die "the recipe commit $commit of $host is not in this repository"
[ -z "$changed" ] ||
    die "$host was built from $commit, and HEAD changes $changed since"

# DESIGN: an archive already written may already be published, and a
# published archive is never replaced. A new build takes a new number.
[ ! -e "$archive" ] || die "$archive exists"

stage=$(mktemp -d "${TMPDIR:-/tmp}/llvm-tools-pack.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/bin" "$stage/licenses"
for tool in $(toml_get "$root/hosts.toml" "" tools); do
    [ -f "$bin/$tool$exe" ] || die "$bin/$tool$exe is missing"
    cp "$bin/$tool$exe" "$stage/bin/"
    chmod 755 "$stage/bin/$tool$exe"
done
cp "$root/licenses/llvm.txt" "$stage/licenses/"
# musl is linked into the tools of a Linux host, and its licence asks for
# the notice in every copy.
if [ "$(toml_get "$root/hosts.toml" "$host" sysroot)" = musl ]; then
    cp "$root/licenses/musl.txt" "$stage/licenses/"
fi
printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build_number" "$commit" \
    > "$stage/VERSION"

mkdir -p "$dist"
# The archive names no user of the machine that packed it.
owner="--owner=0 --group=0"
case $(tar --version) in
    bsdtar*) owner="--uid 0 --gid 0 --uname root --gname root" ;;
esac
(cd "$stage" && tar $owner -cJf "$archive.part" VERSION bin licenses)
mv "$archive.part" "$archive"
printf '%s %s bytes\n' "$archive" "$(wc -c < "$archive" | tr -d ' ')"
