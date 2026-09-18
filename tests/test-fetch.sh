#!/bin/sh
# The recipe keeps a download only when its SHA-256 digest is the pinned one.
. "$(dirname "$0")/lib.sh"

printf 'the pinned file\n' > "$work/source"
good=$(shasum -a 256 "$work/source" | cut -d' ' -f1)
bad=0000000000000000000000000000000000000000000000000000000000000000

expect_refusal "the pin is $bad" recipe "$root" -DSTEP=fetch-file \
    -DURL="file://$work/source" -DFILE="$work/fetched" -DSHA256="$bad"
[ ! -e "$work/fetched" ] || fail "a download with the wrong digest stayed"
[ ! -e "$work/fetched.part" ] || fail "the partial download stayed"

recipe "$root" -DSTEP=fetch-file -DURL="file://$work/source" \
    -DFILE="$work/fetched" -DSHA256="$good" >/dev/null
cmp -s "$work/source" "$work/fetched" || fail "the fetched file differs"

# A file already in place is checked, and a wrong one is refused rather
# than downloaded again.
printf 'changed\n' > "$work/fetched"
expect_refusal "$work/fetched" recipe "$root" -DSTEP=fetch-file \
    -DURL="file://$work/source" -DFILE="$work/fetched" -DSHA256="$good"
finished=yes
