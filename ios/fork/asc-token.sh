#!/bin/bash
# Prints a 20-minute App Store Connect API token (ES256 JWT) for the key in
# ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH. Capture it; never log it.
set -euo pipefail

: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}"
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now=$(date +%s)
header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID" | b64url)
payload=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' \
  "$ASC_ISSUER_ID" "$now" "$((now + 1200))" | b64url)
der=$(mktemp)
trap 'rm -f "$der"' EXIT
printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$ASC_KEY_PATH" >"$der"
# openssl signs in DER; a JWT carries r and s as two raw 32-byte integers.
raw=""
for int in $(openssl asn1parse -inform DER -in "$der" | awk -F: '/INTEGER/ {print $NF}'); do
  int=$(printf '%064s' "$int" | tr ' ' 0)
  raw+=${int: -64}
done
[[ ${#raw} == 128 ]] || { echo "asc-token: unexpected signature" >&2; exit 1; }
printf '%s.%s.%s' "$header" "$payload" "$(printf '%s' "$raw" | xxd -r -p | b64url)"
