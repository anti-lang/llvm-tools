#!/bin/sh
# scripts/release.sh tags the recipe commit, signs SHA256SUMS with the
# private release key and uploads the twelve archives, the tools and clang
# of six hosts, or those of the hosts named on the command line. It never
# replaces a published one. gh is a stand-in, origin
# is a bare repository on disk, and a key made here stands in for the
# release key.
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
public=$(common_value "$copy" public_key)
private=$(common_value "$copy" private_key)
openssl pkey -in "$work/test-key.pem" -pubout -out "$public"
mkdir -p "$(dirname "$private")"

# Write the archives of the hosts after $1, or the twelve of the six hosts
# without them, each with a VERSION that names commit $1.
fake_archives() {
    named=$1
    shift
    [ "$#" -gt 0 ] || set -- linux-x86_64 linux-arm64 macos-arm64 macos-x86_64 \
        windows-x86_64 windows-arm64
    rm -rf "$dist"
    mkdir -p "$dist" "$work/stage"
    printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build" "$named" \
        > "$work/stage/VERSION"
    for kind in llvm-tools clang; do
        for host in "$@"; do
            tar -cJf "$dist/$kind-$tag-$host.tar.xz" -C "$work/stage" VERSION
        done
    done
}

# gh records each call. "release view" finds the release named in
# $FAKE_RELEASE. "release download" copies the file of dist that --pattern
# names, and adds a line to the one that $FAKE_CORRUPT names.
mkdir -p "$work/fake"
cat > "$work/fake/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$work/gh.log"
case "\$1 \$2" in
    "release view")
        [ -n "\${FAKE_RELEASE:-}" ] || { echo "release not found" >&2; exit 1; }
        echo "\$FAKE_RELEASE"
        ;;
    "release create"|"release edit")
        echo "https://github.com/anti-lang/llvm-tools/releases/tag/$tag"
        ;;
    "release download")
        pattern=""
        dir=""
        while [ "\$#" -gt 0 ]; do
            case \$1 in
                --pattern) pattern=\$2 ;;
                --dir) dir=\$2 ;;
            esac
            shift
        done
        cp "$dist/\$pattern" "\$dir/"
        [ "\$pattern" != "\${FAKE_CORRUPT:-}" ] || echo corrupt >> "\$dir/\$pattern"
        ;;
esac
EOF
chmod +x "$work/fake"/*
tools=$(cd "$copy" && sh -c '. scripts/common.sh && toml_get hosts.toml "" tools' |
    wc -l | tr -d ' ')
release() {
    PATH="$work/fake:$PATH" GH_REPO=anti-lang/llvm-tools \
        "$copy/scripts/release.sh" "$@"
}

# Without the private key the run stops and names its path. Nothing is
# tagged or uploaded.
fake_archives "$commit"
: > "$work/gh.log"
expect_refusal "$private" release
[ -f "$dist/SHA256SUMS" ] || fail "SHA256SUMS was not written"
if git -C "$work/origin.git" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    fail "the tag was pushed without a signature"
fi
if grep -q '^release create' "$work/gh.log"; then
    fail "a release was created without a signature"
fi

# A private key whose public half is not the public key is refused.
cp "$work/other-key.pem" "$private"
expect_refusal "does not verify" release
if grep -q '^release create' "$work/gh.log"; then
    fail "a release was created with the signature of another key"
fi

# The private release key signs, and the release goes through.
cp "$work/test-key.pem" "$private"
: > "$work/gh.log"
output=$(release 2>&1) || fail "the release failed: $output"
sums="$dist/SHA256SUMS"
[ "$(wc -l < "$sums" | tr -d ' ')" = 12 ] || fail "SHA256SUMS: $(cat "$sums")"
(cd "$dist" && shasum -a 256 -c SHA256SUMS >/dev/null) ||
    fail "SHA256SUMS does not match the archives"
[ "$(sort "$sums")" = "$(cat "$sums")" ] || fail "SHA256SUMS is not sorted"
openssl dgst -sha256 -binary -out "$work/check.sha256" "$sums"
openssl pkeyutl -verify -pubin -inkey "$public" \
    -in "$work/check.sha256" -sigfile "$dist/SHA256SUMS.sig" >/dev/null ||
    fail "SHA256SUMS.sig does not verify against $public"
[ "$(git -C "$work/origin.git" rev-parse "$tag^{commit}")" = "$commit" ] ||
    fail "origin has no tag $tag on $commit"

# gh creates a draft, uploads each file on its own and publishes the draft
# after the last upload. It downloads each file again. The output shows
# every upload, every download and the comparison of each file.
names="SHA256SUMS SHA256SUMS.sig $(cd "$dist" && ls ./*.tar.xz | sed 's#^\./##')"
grep -q '^release create .*--draft' "$work/gh.log" ||
    fail "the release was not created as a draft: $(cat "$work/gh.log")"
[ "$(grep -c '^release upload' "$work/gh.log")" = 14 ] ||
    fail "gh did not upload 14 files: $(cat "$work/gh.log")"
last_upload=$(grep -n '^release upload' "$work/gh.log" | tail -n 1 | cut -d: -f1)
publish=$(grep -n '^release edit .*--draft=false' "$work/gh.log" | cut -d: -f1)
[ -n "$publish" ] && [ "$publish" -gt "$last_upload" ] ||
    fail "the draft was not published after the last upload: $(cat "$work/gh.log")"
[ "$(grep -c '^release download .*--pattern' "$work/gh.log")" = 14 ] ||
    fail "gh did not download 14 files: $(cat "$work/gh.log")"
for name in $names; do
    grep -qF "release upload $tag $dist/$name " "$work/gh.log" ||
        fail "gh did not upload $name: $(cat "$work/gh.log")"
    for status in uploaded downloaded same; do
        printf '%s\n' "$output" | grep -q "$name .*$status" ||
            fail "the output shows no '$status' for $name: $output"
    done
done
printf '%s\n' "$output" | grep -q "All 14 files on GitHub match" ||
    fail "the output does not end in the comparison: $output"
if grep -q -e --clobber "$work/gh.log"; then
    fail "release.sh replaced an asset: $(cat "$work/gh.log")"
fi
# The title names the build, and the notes name the tools and the six hosts.
grep -qF -- "--title LLVM $version, anti build $build --notes The $tools LLVM tools and clang of LLVM $version for linux-x86_64, linux-arm64, macos-arm64, macos-x86_64, windows-x86_64 and windows-arm64, built from the recipe at $commit." \
    "$work/gh.log" || fail "the title or the notes are wrong: $(cat "$work/gh.log")"

# A download that differs from its file fails the run, after every file is
# compared.
bad="clang-$tag-linux-arm64.tar.xz"
expect_refusal "differ" env FAKE_CORRUPT="$bad" PATH="$work/fake:$PATH" \
    GH_REPO=anti-lang/llvm-tools "$copy/scripts/release.sh"
printf '%s\n' "$output" | grep -q "$bad .*DIFFERS" ||
    fail "the output does not show that $bad differs: $output"
[ "$(printf '%s\n' "$output" | grep -c ' same$')" = 13 ] ||
    fail "the other 13 files were not compared: $output"

# A published release is never replaced.
: > "$work/gh.log"
expect_refusal "already" env FAKE_RELEASE=published PATH="$work/fake:$PATH" \
    GH_REPO=anti-lang/llvm-tools "$copy/scripts/release.sh"
if grep -q '^release create' "$work/gh.log"; then
    fail "release.sh created a release over a published one"
fi

# A release of the hosts named on the command line covers those alone, by
# the decision of 2026-11-07 to release the macOS hosts first. An archive
# of another host, from another commit, plays no part.
fake_archives "$commit" macos-arm64 macos-x86_64
printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build" 0000000 \
    > "$work/stage/VERSION"
tar -cJf "$dist/llvm-tools-$tag-linux-arm64.tar.xz" -C "$work/stage" VERSION
: > "$work/gh.log"
output=$(release macos-arm64 macos-x86_64 2>&1) || fail "the release failed: $output"
expected="clang-$tag-macos-arm64.tar.xz
clang-$tag-macos-x86_64.tar.xz
llvm-tools-$tag-macos-arm64.tar.xz
llvm-tools-$tag-macos-x86_64.tar.xz"
[ "$(awk '{ print $2 }' "$sums")" = "$expected" ] || fail "SHA256SUMS: $(cat "$sums")"
(cd "$dist" && shasum -a 256 -c SHA256SUMS >/dev/null) ||
    fail "SHA256SUMS does not match the archives"
openssl dgst -sha256 -binary -out "$work/check.sha256" "$sums"
openssl pkeyutl -verify -pubin -inkey "$public" \
    -in "$work/check.sha256" -sigfile "$dist/SHA256SUMS.sig" >/dev/null ||
    fail "SHA256SUMS.sig does not verify against $public"
[ "$(grep -c '^release upload' "$work/gh.log")" = 6 ] ||
    fail "gh did not upload 6 files: $(cat "$work/gh.log")"
if grep -q "^release upload .*linux-arm64" "$work/gh.log"; then
    fail "gh uploaded an archive of a host that was not named: $(cat "$work/gh.log")"
fi
printf '%s\n' "$output" | grep -q "All 6 files on GitHub match" ||
    fail "the output does not end in the comparison of 6 files: $output"
grep -qF -- "--title LLVM $version, anti build $build for macos-arm64 and macos-x86_64 --notes The $tools LLVM tools and clang of LLVM $version for macos-arm64 and macos-x86_64, built from the recipe at $commit." \
    "$work/gh.log" || fail "the title or the notes are wrong: $(cat "$work/gh.log")"

# A named host whose archive is missing, or names another commit, is
# refused. So are a host that hosts.toml lacks and a host named twice,
# before gh is asked anything.
fake_archives "$commit" macos-arm64 macos-x86_64
rm "$dist/clang-$tag-macos-x86_64.tar.xz"
expect_refusal "clang-$tag-macos-x86_64" release macos-arm64 macos-x86_64
fake_archives "$commit" macos-arm64 macos-x86_64
printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build" 0000000 \
    > "$work/stage/VERSION"
tar -cJf "$dist/clang-$tag-macos-x86_64.tar.xz" -C "$work/stage" VERSION
expect_refusal "commit" release macos-arm64 macos-x86_64
: > "$work/gh.log"
expect_refusal "now is not a host of hosts.toml" release macos-arm64 now
expect_refusal "macos-arm64 is named twice" release macos-arm64 macos-arm64
[ ! -s "$work/gh.log" ] || fail "gh ran for a refused host: $(cat "$work/gh.log")"

# A tag on origin that names another commit is refused, after the
# signature.
git -C "$copy" tag -d "$tag" >/dev/null
git -C "$copy" -c user.name=test -c user.email=test@example.invalid \
    commit -q --allow-empty -m "Another commit"
fake_archives "$(git -C "$copy" rev-parse HEAD)"
expect_refusal "$tag" release
openssl dgst -sha256 -binary -out "$work/check.sha256" "$sums"
openssl pkeyutl -verify -pubin -inkey "$public" \
    -in "$work/check.sha256" -sigfile "$dist/SHA256SUMS.sig" >/dev/null ||
    fail "the signature of the private key does not verify"

# Archives from two different commits are refused.
fake_archives "$commit"
printf 'llvm %s\nbuild %s\nrecipe %s\n' "$version" "$build" \
    "$(git -C "$copy" rev-parse HEAD)" > "$work/stage/VERSION"
tar -cJf "$dist/llvm-tools-$tag-linux-arm64.tar.xz" -C "$work/stage" VERSION
expect_refusal "commit" release

# A missing archive of either kind is refused.
fake_archives "$commit"
rm "$dist/llvm-tools-$tag-macos-x86_64.tar.xz"
expect_refusal "llvm-tools-$tag-macos-x86_64" release
fake_archives "$commit"
rm "$dist/clang-$tag-linux-arm64.tar.xz"
expect_refusal "clang-$tag-linux-arm64" release
finished=yes
