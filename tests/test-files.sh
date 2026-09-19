#!/bin/sh
# Facts that stand in two places of the repository agree.
. "$(dirname "$0")/lib.sh"

cmp -s "$root/LICENSE" "$root/licenses/llvm.txt" ||
    fail "LICENSE and licenses/llvm.txt differ"

# The README names the fingerprint of the key that signs SHA256SUMS, the
# SHA-256 digest of its public key in DER form.
public=$(common_value "$root" public_key)
fingerprint=$(openssl pkey -pubin -in "$public" -outform DER |
    openssl dgst -sha256 | sed 's/^.*= //')
[ -n "$fingerprint" ] || fail "$public holds no public key"
grep -q "$fingerprint" "$root/README.md" ||
    fail "README.md does not name the fingerprint $fingerprint"

# scripts/common.sh defines the paths of the release key, and no other
# script or command spells them.
for file in "$root"/scripts/*.sh "$root/c" "$root/r"; do
    [ -f "$file" ] || fail "$file is missing"
    [ "$file" = "$root/scripts/common.sh" ] && continue
    if grep -n 'keys/' "$file"; then
        fail "$file spells a path of the release key"
    fi
done
finished=yes
