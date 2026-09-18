#!/bin/sh
# Facts that stand in two places of the repository agree.
. "$(dirname "$0")/lib.sh"

cmp -s "$root/LICENSE" "$root/licenses/llvm.txt" ||
    fail "LICENSE and licenses/llvm.txt differ"

# The README names the fingerprint of the key that signs SHA256SUMS, the
# SHA-256 digest of its public key in DER form.
fingerprint=$(openssl pkey -pubin -in "$root/keys/release.pem" -outform DER |
    openssl dgst -sha256 | sed 's/^.*= //')
[ -n "$fingerprint" ] || fail "keys/release.pem holds no public key"
grep -q "$fingerprint" "$root/README.md" ||
    fail "README.md does not name the fingerprint $fingerprint"
finished=yes
