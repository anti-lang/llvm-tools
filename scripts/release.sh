#!/bin/sh
# Publish the six archives of pins/build-number as a GitHub release.
#
#   scripts/release.sh
#
# Tags the recipe commit that the archives name as <version>-<build> and
# pushes the tag to origin. Writes SHA256SUMS, signs it with the key of
# keys/release.asc into SHA256SUMS.sig, checks the signature, and uploads
# the archives and both files. It then downloads the release again and
# compares every file. GH_REPO names the repository on GitHub. Without it
# the path of the origin remote does.
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
for host in $(toml_sections "$root/hosts.toml"); do
    archive="$dist/$(archive_name "$host")"
    [ -f "$archive" ] || die "$archive is missing. Run scripts/pack.sh $host."
    named=$(tar -xOJf "$archive" VERSION | sed -n 's/^recipe //p')
    [ -n "$commit" ] || commit=$named
    [ "$named" = "$commit" ] ||
        die "$archive names the recipe commit $named, and another archive $commit"
    files="$files $archive"
done

# The manifest lists the six archives, sorted by name, in the format that
# shasum -c and sha256sum -c read.
(cd "$dist" && for file in $files; do basename "$file"; done | sort |
    xargs shasum -a 256 > SHA256SUMS)

fingerprint=$(gpg --show-keys --with-colons "$root/keys/release.asc" |
    awk -F: '$1 == "fpr" { print $10; exit }')
[ -n "$fingerprint" ] || die "keys/release.asc holds no key"
rm -f "$dist/SHA256SUMS.sig"
gpg --local-user "$fingerprint" --detach-sign \
    --output "$dist/SHA256SUMS.sig" "$dist/SHA256SUMS"
keyring=$(mktemp "${TMPDIR:-/tmp}/llvm-tools-key.XXXXXX")
readback=$(mktemp -d "${TMPDIR:-/tmp}/llvm-tools-release.XXXXXX")
trap 'rm -rf "$keyring" "$readback"' EXIT
gpg --dearmor < "$root/keys/release.asc" > "$keyring"
gpgv --keyring "$keyring" "$dist/SHA256SUMS.sig" "$dist/SHA256SUMS" ||
    die "SHA256SUMS.sig does not verify against keys/release.asc"

# The tag goes on the recipe commit. One that origin already holds must
# name the same commit, which lets a run that failed after the push resume.
remote=$(git -C "$root" ls-remote origin "refs/tags/$tag^{}" | cut -f1)
if [ -n "$remote" ]; then
    [ "$remote" = "$commit" ] ||
        die "origin has the tag $tag on $remote, and the archives name $commit"
else
    if ! git -C "$root" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        git -C "$root" tag -a "$tag" -m "LLVM $version, build $build_number" \
            "$commit"
    fi
    [ "$(git -C "$root" rev-parse "$tag^{commit}")" = "$commit" ] ||
        die "the local tag $tag does not name $commit"
    git -C "$root" push origin "refs/tags/$tag"
fi

# gh uploads the assets to a draft and publishes it after the last one. A
# failed upload leaves no published release with missing files.
gh release create "$tag" --repo "$repo" --verify-tag \
    --title "LLVM $version, build $build_number" \
    --notes "The five LLVM tools of LLVM $version for the six hosts of antic, built from the recipe at $commit. SHA256SUMS.sig is signed by the key $fingerprint." \
    $files "$dist/SHA256SUMS" "$dist/SHA256SUMS.sig"

gh release download "$tag" --repo "$repo" --dir "$readback"
for file in $files "$dist/SHA256SUMS" "$dist/SHA256SUMS.sig"; do
    cmp -s "$file" "$readback/$(basename "$file")" ||
        die "$(basename "$file") on GitHub differs from $file"
done
printf '%s holds the release %s, and every file matches\n' "$repo" "$tag"
