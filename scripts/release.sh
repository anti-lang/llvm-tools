#!/bin/sh
# Publish the twelve archives of pins/build-number as a GitHub release, the
# tools and clang of each of the six hosts.
#
#   scripts/release.sh
#
# Tags the recipe commit that the archives name as <version>-anti.<build>
# and pushes the tag to origin. Writes SHA256SUMS and signs it into
# SHA256SUMS.sig with the private release key, whose passphrase openssl
# asks for. It checks the signature against the public key and uploads the
# archives and both files. It then downloads the release again and compares
# every file. GH_REPO names the repository on GitHub. Without it the path
# of the origin remote does. scripts/common.sh names both halves of the key.
. "$(dirname "$0")/common.sh"

[ "$#" -eq 0 ] || die "usage: scripts/release.sh"
dist=$(recipe_path linux-x86_64 dist)
repo=${GH_REPO:-$(git -C "$root" remote get-url origin |
    sed -E 's#^.*[:/]([^/]+/[^/]+)$#\1#; s#\.git$##')}

# DESIGN: an archive under a published tag is never replaced. A release
# that exists, draft or not, stops the run, and no call here overwrites
# an asset. A new recipe is a new build number.
if state=$(gh release view "$tag" --repo "$repo" --json isDraft \
        --jq 'if .isDraft then "a draft" else "published" end' 2>/dev/null); then
    die "$repo already has the release $tag, $state"
fi

commit=""
files=""
for kind in $archive_kinds; do
    for host in $(toml_sections "$root/hosts.toml"); do
        archive="$dist/$(archive_name "$kind" "$host")"
        [ -f "$archive" ] || die "$archive is missing. Run scripts/pack.sh $host."
        named=$(tar -xOJf "$archive" VERSION | sed -n 's/^recipe //p')
        [ -n "$commit" ] || commit=$named
        [ "$named" = "$commit" ] ||
            die "$archive names the recipe commit $named, and another archive $commit"
        files="$files $archive"
    done
done

# The manifest lists the archives, sorted by name, in the format that
# shasum -c and sha256sum -c read.
(cd "$dist" && for file in $files; do basename "$file"; done | sort |
    xargs shasum -a 256 > SHA256SUMS)

# DESIGN: openssl signs and checks, because macOS, every Linux and Git for
# Windows carry it. The signature is ECDSA P-256 over the SHA-256 digest of
# SHA256SUMS, which the LibreSSL of macOS verifies with pkeyutl as well.
public=${public_key#"$root"/}
fingerprint=$(openssl pkey -pubin -in "$public_key" -outform DER |
    openssl dgst -sha256 | sed 's/^.*= //')
[ -n "$fingerprint" ] || die "$public holds no public key"
[ -f "$private_key" ] || die "$private_key, the private release key, is missing"
work=$(mktemp -d "${TMPDIR:-/tmp}/llvm-tools-release.XXXXXX")
trap 'rm -rf "$work"' EXIT
openssl dgst -sha256 -binary -out "$work/SHA256SUMS.sha256" "$dist/SHA256SUMS"
openssl pkeyutl -sign -inkey "$private_key" -in "$work/SHA256SUMS.sha256" \
    -out "$work/SHA256SUMS.sig" || die "openssl could not sign with $private_key"
# A signature that fails the check never reaches dist.
openssl pkeyutl -verify -pubin -inkey "$public_key" -in "$work/SHA256SUMS.sha256" \
    -sigfile "$work/SHA256SUMS.sig" >/dev/null 2>&1 ||
    die "the signature of $private_key does not verify against $public"
mv "$work/SHA256SUMS.sig" "$dist/SHA256SUMS.sig"

# The tag goes on the recipe commit. One that origin already holds must
# name the same commit, which lets a run that failed after the push resume.
remote=$(git -C "$root" ls-remote origin "refs/tags/$tag^{}" | cut -f1)
if [ -n "$remote" ]; then
    [ "$remote" = "$commit" ] ||
        die "origin has the tag $tag on $remote, and the archives name $commit"
else
    if ! git -C "$root" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        git -C "$root" tag -a "$tag" -m "LLVM $version, anti build $build_number" \
            "$commit"
    fi
    [ "$(git -C "$root" rev-parse "$tag^{commit}")" = "$commit" ] ||
        die "the local tag $tag does not name $commit"
    git -C "$root" push origin "refs/tags/$tag"
fi

# gh uploads the assets to a draft and publishes it after the last one. A
# failed upload leaves no published release with missing files.
gh release create "$tag" --repo "$repo" --verify-tag \
    --title "LLVM $version, anti build $build_number" \
    --notes "The five LLVM tools and clang of LLVM $version for six hosts, built from the recipe at $commit. SHA256SUMS.sig is an ECDSA P-256 signature over the SHA-256 digest of SHA256SUMS, by the key of release@anti-lang.com in $public, whose SHA-256 fingerprint is $fingerprint." \
    $files "$dist/SHA256SUMS" "$dist/SHA256SUMS.sig"

mkdir "$work/readback"
gh release download "$tag" --repo "$repo" --dir "$work/readback"
for file in $files "$dist/SHA256SUMS" "$dist/SHA256SUMS.sig"; do
    cmp -s "$file" "$work/readback/$(basename "$file")" ||
        die "$(basename "$file") on GitHub differs from $file"
done
printf '%s holds the release %s, and every file matches\n' "$repo" "$tag"
