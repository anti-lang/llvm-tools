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
assets="$files $dist/SHA256SUMS $dist/SHA256SUMS.sig"
total=0
width=0
for file in $assets; do
    name=$(basename "$file")
    total=$((total + 1))
    [ "${#name}" -le "$width" ] || width=${#name}
done

# Print the size of <file>, in bytes below a megabyte.
size() {
    wc -c < "$1" | awk '{
        if ($1 >= 1000000) printf "%.1f MB", $1 / 1000000
        else printf "%d bytes", $1
    }'
}

# Start the line of the output for the file named <name>, which a status
# ends. The size of <file> follows the name when it is given.
row() {
    printf "  %-${width}s  " "$1"
    [ "$#" -lt 2 ] || printf '%10s  ' "$(size "$2")"
}

# The manifest lists the archives, sorted by name, in the format that
# shasum -c and sha256sum -c read.
printf 'Writing SHA256SUMS of the %s archives in %s\n' "$((total - 2))" "$dist"
(cd "$dist" && for file in $files; do basename "$file"; done | sort |
    xargs shasum -a 256 > SHA256SUMS)

# DESIGN: openssl signs and checks, because macOS, every Linux and Git for
# Windows carry it. The signature is ECDSA P-256 over the SHA-256 digest of
# SHA256SUMS, which the LibreSSL of macOS verifies with pkeyutl as well.
public=${public_key#"$root"/}
private=${private_key#"$root"/}
fingerprint=$(openssl pkey -pubin -in "$public_key" -outform DER |
    openssl dgst -sha256 | sed 's/^.*= //')
[ -n "$fingerprint" ] || die "$public holds no public key"
[ -f "$private_key" ] || die "$private_key, the private release key, is missing"
work=$(mktemp -d "${TMPDIR:-/tmp}/llvm-tools-release.XXXXXX")
trap 'rm -rf "$work"' EXIT
openssl dgst -sha256 -binary -out "$work/SHA256SUMS.sha256" "$dist/SHA256SUMS"
printf 'Signing SHA256SUMS with %s, whose passphrase openssl asks for\n' "$private"
openssl pkeyutl -sign -inkey "$private_key" -in "$work/SHA256SUMS.sha256" \
    -out "$work/SHA256SUMS.sig" || die "openssl could not sign with $private_key"
# A signature that fails the check never reaches dist.
openssl pkeyutl -verify -pubin -inkey "$public_key" -in "$work/SHA256SUMS.sha256" \
    -sigfile "$work/SHA256SUMS.sig" >/dev/null 2>&1 ||
    die "the signature of $private_key does not verify against $public"
mv "$work/SHA256SUMS.sig" "$dist/SHA256SUMS.sig"
printf 'The signature verifies against %s, fingerprint %s\n' "$public" "$fingerprint"

# The tag goes on the recipe commit. One that origin already holds must
# name the same commit, which lets a run that failed after the push resume.
remote=$(git -C "$root" ls-remote origin "refs/tags/$tag^{}" | cut -f1)
if [ -n "$remote" ]; then
    [ "$remote" = "$commit" ] ||
        die "origin has the tag $tag on $remote, and the archives name $commit"
    printf 'origin has the tag %s on %s already\n' "$tag" "$commit"
else
    if ! git -C "$root" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        git -C "$root" tag -a "$tag" -m "LLVM $version, anti build $build_number" \
            "$commit"
    fi
    [ "$(git -C "$root" rev-parse "$tag^{commit}")" = "$commit" ] ||
        die "the local tag $tag does not name $commit"
    printf 'Pushing the tag %s on %s to origin\n' "$tag" "$commit"
    git -C "$root" push -q origin "refs/tags/$tag"
fi

# DESIGN: the release stays a draft until its last file is uploaded, so a
# failed upload leaves no published release with missing files. Each file
# goes up on its own, so the output shows each upload, and gh release
# upload without --clobber never replaces a file.
printf '\nUploading %s files to a draft of the release %s of %s\n' "$total" "$tag" "$repo"
gh release create "$tag" --repo "$repo" --verify-tag --draft \
    --title "LLVM $version, anti build $build_number" \
    --notes "The five LLVM tools and clang of LLVM $version for six hosts, built from the recipe at $commit. SHA256SUMS.sig is an ECDSA P-256 signature over the SHA-256 digest of SHA256SUMS, by the key of release@anti-lang.com in $public, whose SHA-256 fingerprint is $fingerprint." \
    >/dev/null
for file in $assets; do
    row "$(basename "$file")" "$file"
    if ! gh release upload "$tag" "$file" --repo "$repo" >"$work/gh.out" 2>&1; then
        printf 'FAILED\n'
        cat "$work/gh.out" >&2
        die "the upload failed, and $tag stays a draft. Delete the draft on GitHub before the next run."
    fi
    printf 'uploaded\n'
done
url=$(gh release edit "$tag" --repo "$repo" --draft=false)
printf 'Published %s\n' "$url"

printf '\nDownloading the %s files from the release %s\n' "$total" "$tag"
mkdir "$work/readback"
for file in $assets; do
    name=$(basename "$file")
    row "$name"
    if ! gh release download "$tag" --repo "$repo" --pattern "$name" \
            --dir "$work/readback" >"$work/gh.out" 2>&1; then
        printf 'FAILED\n'
        cat "$work/gh.out" >&2
        die "the download of $name failed"
    fi
    printf '%10s  downloaded\n' "$(size "$work/readback/$name")"
done

printf '\nComparing each download with its file in %s\n' "$dist"
differ=0
for file in $assets; do
    name=$(basename "$file")
    row "$name"
    if cmp -s "$file" "$work/readback/$name"; then
        printf 'same\n'
    else
        printf 'DIFFERS\n'
        differ=$((differ + 1))
    fi
done
[ "$differ" -eq 0 ] ||
    die "$differ of the $total files on GitHub differ from the files in $dist"
printf '\nAll %s files on GitHub match the files in %s\n' "$total" "$dist"
