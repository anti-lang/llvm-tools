#!/bin/sh
# scripts/release.sh tags the recipe commit, signs SHA256SUMS with openssl
# and uploads the twelve archives, the tools and clang of six hosts. It
# never replaces a published one. gh is a stand-in, origin is a bare
# repository on disk, and a key made here stands in for the release key.
. "$(dirname "$0")/lib.sh"

copy=$(checkout_copy)
version=$(cat "$copy/pins/llvm-version")
build=$(cat "$copy/pins/build-number")
tag="$version-anti.$build"
commit=$(git -C "$copy" rev-parse HEAD)
dist=$(recipe_path "$copy" linux-x86_64 dist)
git init -q --bare "$work/origin.git"
git -C "$copy" remote add origin "$work/origin.git"
git -C "$copy" push -q origin main

# The release key of the test, and another key that must not pass.
for name in test other; do
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 \
        -pkeyopt ec_param_enc:named_curve -out "$work/$name-key.pem" 2>/dev/null
done
openssl pkey -in "$work/test-key.pem" -pubout -out "$copy/keys/release.pem"

# Sign SHA256SUMS of dist with the private key in $1, as on another machine.
sign_elsewhere() {
    openssl dgst -sha256 -binary -out "$work/sums.sha256" "$dist/SHA256SUMS"
    openssl pkeyutl -sign -inkey "$1" -in "$work/sums.sha256" \
        -out "$dist/SHA256SUMS.sig"
}

# Write the twelve archives, each with a VERSION that names commit $1.
fake_archives() {
    rm -rf "$dist"
    mkdir -p "$dist" "$work/stage"
    printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build" "$1" \
        > "$work/stage/VERSION"
    for kind in llvm-tools clang; do
        for host in linux-x86_64 linux-arm64 macos-arm64 macos-x86_64 \
                    windows-x86_64 windows-arm64; do
            tar -cJf "$dist/$kind-$tag-$host.tar.xz" -C "$work/stage" VERSION
        done
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
chmod +x "$work/fake"/*
release() {
    PATH="$work/fake:$PATH" GH_REPO=anti-lang/llvm-tools \
        "$copy/scripts/release.sh" "$@"
}
signed_release() {
    RELEASE_KEY="$work/test-key.pem" release "$@"
}

# Without the key and without a signature, the run stops and names the
# command that signs SHA256SUMS. Nothing is tagged or uploaded.
fake_archives "$commit"
: > "$work/gh.log"
expect_refusal "pkeyutl -sign" release
[ -f "$dist/SHA256SUMS" ] || fail "SHA256SUMS was not written"
if git -C "$work/origin.git" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    fail "the tag was pushed without a signature"
fi
if grep -q '^release create' "$work/gh.log"; then
    fail "a release was created without a signature"
fi

# A signature of another key is refused.
sign_elsewhere "$work/other-key.pem"
expect_refusal "does not verify" release

# A signature made on another machine with the release key goes through.
sign_elsewhere "$work/test-key.pem"
release >/dev/null
sums="$dist/SHA256SUMS"
[ "$(wc -l < "$sums" | tr -d ' ')" = 12 ] || fail "SHA256SUMS: $(cat "$sums")"
(cd "$dist" && shasum -a 256 -c SHA256SUMS >/dev/null) ||
    fail "SHA256SUMS does not match the archives"
[ "$(sort "$sums")" = "$(cat "$sums")" ] || fail "SHA256SUMS is not sorted"
openssl dgst -sha256 -binary -out "$work/check.sha256" "$sums"
openssl pkeyutl -verify -pubin -inkey "$copy/keys/release.pem" \
    -in "$work/check.sha256" -sigfile "$dist/SHA256SUMS.sig" >/dev/null ||
    fail "SHA256SUMS.sig does not verify against keys/release.pem"
[ "$(git -C "$work/origin.git" rev-parse "$tag^{commit}")" = "$commit" ] ||
    fail "origin has no tag $tag on $commit"
create=$(grep '^release create' "$work/gh.log") ||
    fail "gh release create was not called"
for file in SHA256SUMS SHA256SUMS.sig llvm-tools-$tag-linux-x86_64.tar.xz \
            llvm-tools-$tag-windows-arm64.tar.xz clang-$tag-macos-x86_64.tar.xz \
            clang-$tag-windows-arm64.tar.xz; do
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
    GH_REPO=anti-lang/llvm-tools RELEASE_KEY="$work/test-key.pem" \
    "$copy/scripts/release.sh"
if grep -q '^release create' "$work/gh.log"; then
    fail "release.sh created a release over a published one"
fi

# With RELEASE_KEY the script signs, and a tag on origin that names
# another commit is refused.
git -C "$copy" tag -d "$tag" >/dev/null
git -C "$copy" -c user.name=test -c user.email=test@example.invalid \
    commit -q --allow-empty -m "Another commit"
fake_archives "$(git -C "$copy" rev-parse HEAD)"
expect_refusal "$tag" signed_release
openssl dgst -sha256 -binary -out "$work/check.sha256" "$sums"
openssl pkeyutl -verify -pubin -inkey "$copy/keys/release.pem" \
    -in "$work/check.sha256" -sigfile "$dist/SHA256SUMS.sig" >/dev/null ||
    fail "the signature that RELEASE_KEY made does not verify"

# Archives from two different commits are refused.
fake_archives "$commit"
printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build" \
    "$(git -C "$copy" rev-parse HEAD)" > "$work/stage/VERSION"
tar -cJf "$dist/llvm-tools-$tag-linux-arm64.tar.xz" -C "$work/stage" VERSION
expect_refusal "commit" signed_release

# A missing archive of either kind is refused.
fake_archives "$commit"
rm "$dist/llvm-tools-$tag-macos-x86_64.tar.xz"
expect_refusal "llvm-tools-$tag-macos-x86_64" signed_release
fake_archives "$commit"
rm "$dist/clang-$tag-linux-arm64.tar.xz"
expect_refusal "clang-$tag-linux-arm64" signed_release
finished=yes
