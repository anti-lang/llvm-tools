#!/bin/sh
# Facts that stand in two places of the repository agree.
. "$(dirname "$0")/lib.sh"

cmp -s "$root/LICENSE" "$root/licenses/llvm.txt" ||
    fail "LICENSE and licenses/llvm.txt differ"

# The README names the fingerprint of the key that signs SHA256SUMS.
fingerprint=$(gpg --show-keys --with-colons "$root/keys/release.asc" |
    awk -F: '$1 == "fpr" { print $10; exit }')
[ -n "$fingerprint" ] || fail "keys/release.asc holds no key"
spaced=$(printf '%s\n' "$fingerprint" |
    sed 's/\(....\)/\1 /g; s/ $//; s/\(.\{24\}\) /\1  /')
grep -q "$spaced" "$root/README.md" ||
    fail "README.md does not name the fingerprint $spaced"
finished=yes
