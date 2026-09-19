#!/bin/sh
# Pack the tools and clang of every host that ./c built, and publish them
# as the release of pins/build-number.
#
#   ./r
#
# A host whose two archives already come from its build is not packed
# again, which lets a run that failed go on. scripts/release.sh then writes
# SHA256SUMS, signs it with the private release key, whose passphrase
# openssl asks for, tags the recipe commit and uploads the release.
. "$(dirname "$0")/scripts/common.sh"

[ "$#" -eq 0 ] || die "usage: ./r"
dist=$(recipe_path linux-x86_64 dist)
for host in $(toml_sections "$root/hosts.toml"); do
    built=$(sed -n 's/^commit=//p' "$(recipe_path "$host" stamp)" 2>/dev/null) ||
        built=""
    packed=yes
    for kind in $archive_kinds; do
        archive="$dist/$(archive_name "$kind" "$host")"
        if [ ! -f "$archive" ] || [ -z "$built" ] ||
            [ "$(tar -xOJf "$archive" VERSION | sed -n 's/^recipe //p')" != "$built" ]; then
            packed=no
        fi
    done
    if [ "$packed" = yes ]; then
        printf 'r: %s is packed from its build %s\n' "$host" "$built"
    else
        "$root/scripts/pack.sh" "$host"
    fi
done
exec "$root/scripts/release.sh"
