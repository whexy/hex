#!/bin/bash
# Installs the newest active App Store profile of every bundle in an archive and
# writes export options that sign with them and the Apple Distribution identity.
# Xcode's automatic export signing needs cloud-managed certificates, which an
# App Manager API key cannot use, so the export signs manually.
#
#   store-profiles.sh <archive> <ExportOptions.plist> <team id> <export|upload>
#
# Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH. A bundle without a profile
# fails here, before the export, naming the profile to create.
set -euo pipefail

archive=$1 options=$2 team=$3 destination=$4
token=$(bash "$(dirname "$0")/asc-token.sh")
profiles=$(mktemp)
trap 'rm -f "$profiles"' EXIT

# App Store Connect answers 5xx and 429 for minutes at a time; curl retries those.
curl -gsS --fail-with-body --retry 4 --retry-delay 15 --max-time 60 \
  -H "Authorization: Bearer $token" \
  'https://api.appstoreconnect.apple.com/v1/profiles?filter[profileType]=IOS_APP_STORE&filter[profileState]=ACTIVE&include=bundleId&limit=200' \
  >"$profiles"

entries=""
missing=()
while IFS= read -r bundle; do
  id=$(plutil -extract CFBundleIdentifier raw -o - "$bundle/Info.plist")
  uuid=$(jq -r --arg id "$id" '
    (.included // [] | map(select(.type == "bundleIds")) | map({(.id): .attributes.identifier}) | add // {}) as $ids
    | [.data[] | select($ids[.relationships.bundleId.data.id] == $id)]
    | sort_by(.attributes.expirationDate) | last | .attributes.uuid // empty' "$profiles")
  if [[ -z $uuid ]]; then
    missing+=("$id")
    continue
  fi
  for dir in "Library/MobileDevice/Provisioning Profiles" "Library/Developer/Xcode/UserData/Provisioning Profiles"; do
    mkdir -p "$HOME/$dir"
    jq -r --arg u "$uuid" '.data[] | select(.attributes.uuid == $u) | .attributes.profileContent' "$profiles" |
      base64 --decode >"$HOME/$dir/$uuid.mobileprovision"
  done
  entries+="<key>$id</key><string>$uuid</string>"
  echo "store-profiles: $id -> $uuid"
done < <(find "$archive/Products/Applications" -type d \( -name '*.app' -o -name '*.appex' \))

if ((${#missing[@]} > 0)); then
  echo "store-profiles: no active IOS_APP_STORE profile for ${missing[*]}." >&2
  echo "Create one per bundle ID with the Apple Distribution certificate (see .github/operations.md)." >&2
  exit 1
fi

cat >"$options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>$destination</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Apple Distribution</string>
<key>teamID</key><string>$team</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>stripSwiftSymbols</key><true/>
<key>uploadSymbols</key><true/>
<key>provisioningProfiles</key><dict>$entries</dict>
</dict></plist>
EOF
