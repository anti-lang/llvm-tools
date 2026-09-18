#!/bin/sh
# scripts/release.sh tags the recipe commit, signs SHA256SUMS and uploads
# the six archives, and never replaces a published one. gh and gpg are
# stand-ins here, and origin is a bare repository on disk.
. "$(dirname "$0")/lib.sh"

copy=$(checkout_copy)
version=$(cat "$copy/pins/llvm-version")
build=$(cat "$copy/pins/build-number")
tag="$version-$build"
commit=$(git -C "$copy" rev-parse HEAD)
dist=$(recipe_path "$copy" linux-x86_64 dist)
git init -q --bare "$work/origin.git"
git -C "$copy" remote add origin "$work/origin.git"
git -C "$copy" push -q origin main

# Write the six archives, each with a VERSION that names commit $1.
fake_archives() {
    rm -rf "$dist"
    mkdir -p "$dist" "$work/stage"
    printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build" "$1" \
        > "$work/stage/VERSION"
    for host in linux-x86_64 linux-arm64 macos-arm64 macos-x86_64 \
                windows-x86_64 windows-arm64; do
        tar -cJf "$dist/llvm-tools-$tag-$host.tar.xz" -C "$work/stage" VERSION
    done
}

# gh records each call. "release view" finds the release named in
# $FAKE_RELEASE, "release download" copies the files of dist.
mkdir -p "$work/fake"
cat > "$work/fake/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$work/gh.log"
case "\$1 \$2" in
    "release view")
        [ -n "\${FAKE_RELEASE:-}" ] || { echo "release not found" >&2; exit 1; }
        echo "\$FAKE_RELEASE"
        ;;
    "release download")
        while [ "\$#" -gt 0 ]; do
            [ "\$1" = --dir ] && cp "$dist"/* "\$2"
            shift
        done
        ;;
esac
EOF
real_gpg=$(command -v gpg)
cat > "$work/fake/gpg" <<EOF
#!/bin/sh
case " \$* " in
    *" --detach-sign "*)
        while [ "\$1" != --output ]; do shift; done
        printf 'signature\n' > "\$2"
        ;;
    *) exec "$real_gpg" "\$@" ;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' > "$work/fake/gpgv"
chmod +x "$work/fake"/*
release() {
    PATH="$work/fake:$PATH" GH_REPO=anti-lang/llvm-tools \
        "$copy/scripts/release.sh" "$@"
}

fake_archives "$commit"
release >/dev/null
sums="$dist/SHA256SUMS"
[ "$(wc -l < "$sums" | tr -d ' ')" = 6 ] || fail "SHA256SUMS: $(cat "$sums")"
(cd "$dist" && shasum -a 256 -c SHA256SUMS >/dev/null) ||
    fail "SHA256SUMS does not match the archives"
[ "$(sort "$sums")" = "$(cat "$sums")" ] || fail "SHA256SUMS is not sorted"
[ -f "$dist/SHA256SUMS.sig" ] || fail "SHA256SUMS.sig was not written"
[ "$(git -C "$work/origin.git" rev-parse "$tag^{commit}")" = "$commit" ] ||
    fail "origin has no tag $tag on $commit"
create=$(grep '^release create' "$work/gh.log") ||
    fail "gh release create was not called"
for file in SHA256SUMS SHA256SUMS.sig llvm-tools-$tag-linux-x86_64.tar.xz \
            llvm-tools-$tag-windows-arm64.tar.xz; do
    case $create in
        *"$dist/$file"*) ;;
        *) fail "gh release create did not upload $file: $create" ;;
    esac
done
if grep -q -e --clobber -e 'release upload' "$work/gh.log"; then
    fail "release.sh replaced an asset: $(cat "$work/gh.log")"
fi

# A published release is never replaced.
: > "$work/gh.log"
expect_refusal "already" env FAKE_RELEASE=published PATH="$work/fake:$PATH" \
    GH_REPO=anti-lang/llvm-tools "$copy/scripts/release.sh"
if grep -q '^release create' "$work/gh.log"; then
    fail "release.sh created a release over a published one"
fi

# A tag on origin that names another commit is refused.
git -C "$copy" tag -d "$tag" >/dev/null
git -C "$copy" -c user.name=test -c user.email=test@example.invalid \
    commit -q --allow-empty -m "Another commit"
fake_archives "$(git -C "$copy" rev-parse HEAD)"
expect_refusal "$tag" release

# Archives from two different commits are refused.
fake_archives "$commit"
printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build" \
    "$(git -C "$copy" rev-parse HEAD)" > "$work/stage/VERSION"
tar -cJf "$dist/llvm-tools-$tag-linux-arm64.tar.xz" -C "$work/stage" VERSION
expect_refusal "commit" release

# A missing archive is refused.
fake_archives "$commit"
rm "$dist/llvm-tools-$tag-macos-x86_64.tar.xz"
expect_refusal "macos-x86_64" release
finished=yes
