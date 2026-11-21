#!/bin/bash
# Rewrites upstream's Apple identity (team, bundle IDs, App Group, home-screen
# name) to the fork's, in this checkout, before `xcodegen generate`. The fork
# never commits the result, so no upstream file carries a fork edit and a
# rebase never conflicts here.
#
# Each rewrite names the exact line it expects and how often. A line that has
# moved, changed or multiplied fails the run, and so does any upstream
# identity left behind afterwards (a new target, entitlements file or Swift
# constant): a half-rewritten app would sign against the wrong team or read
# another App Group. Running it again on a rewritten checkout changes nothing.
#
#   ios/fork/identity.sh            rewrite (from anywhere in the checkout)
#   ios/fork/identity.sh --check    only report whether the checkout is rewritten
set -euo pipefail

team=26DMRHRW6Z
bundle=dev.whexy.hex
group=group.dev.whexy.hex
name=WeHex

ios=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
check=false
[[ ${1:-} == --check ]] && check=true

failures=0
fail() {
  echo "identity: $*" >&2
  failures=$((failures + 1))
}

# rewrite <file under ios/> <expected count> <upstream line> <fork line>
rewrite() {
  local file=$ios/$1 count=$2 old=$3 new=$4 have_old have_new
  [[ -f $file ]] || { fail "$1 is missing"; return; }
  have_old=$(grep -cxF -- "$old" "$file" || true)
  have_new=$(grep -cxF -- "$new" "$file" || true)
  if [[ $have_old == 0 && $have_new == "$count" ]]; then
    return
  fi
  if [[ $have_old != "$count" || $have_new != 0 ]]; then
    fail "$1: expected ${count} of '$old' and none of '$new', found $have_old and $have_new"
    return
  fi
  if $check; then
    fail "$1: not rewritten ('$old')"
    return
  fi
  OLD=$old NEW=$new perl -i -pe 'chomp(my $l = $_); $_ = "$ENV{NEW}\n" if $l eq $ENV{OLD}' "$file"
}

rewrite project.yml 1 '  bundleIdPrefix: anomaly.hex' "  bundleIdPrefix: $bundle"
rewrite project.yml 1 '    DEVELOPMENT_TEAM: 5NZ4Q7NXJ4' "    DEVELOPMENT_TEAM: $team"
rewrite project.yml 1 '        PRODUCT_BUNDLE_IDENTIFIER: anomaly.hex.mobile' "        PRODUCT_BUNDLE_IDENTIFIER: $bundle"
rewrite project.yml 1 '        PRODUCT_BUNDLE_IDENTIFIER: anomaly.hex.mobile.keyboard' "        PRODUCT_BUNDLE_IDENTIFIER: $bundle.keyboard"
rewrite project.yml 1 '        PRODUCT_BUNDLE_IDENTIFIER: anomaly.hex.mobile.widgets' "        PRODUCT_BUNDLE_IDENTIFIER: $bundle.widgets"
rewrite project.yml 1 '        PRODUCT_BUNDLE_IDENTIFIER: anomaly.hex.mobile.tests' "        PRODUCT_BUNDLE_IDENTIFIER: $bundle.tests"
# The app's and the widgets' home-screen name; the keyboard's is its name in
# Settings › Keyboards.
rewrite project.yml 2 '        CFBundleDisplayName: Hex' "        CFBundleDisplayName: $name"
rewrite project.yml 1 '        CFBundleDisplayName: Hex Keyboard' "        CFBundleDisplayName: $name Keyboard"
rewrite HEXMobile/HEXMobile.entitlements 1 $'\t\t<string>group.anomaly.hex.mobile</string>' $'\t\t<string>'"$group"'</string>'
rewrite HEXKeyboard/HEXKeyboard.entitlements 1 $'\t\t<string>group.anomaly.hex.mobile</string>' $'\t\t<string>'"$group"'</string>'
rewrite HEXShared/KeyboardBridge.swift 1 '    nonisolated static let appGroup = "group.anomaly.hex.mobile"' "    nonisolated static let appGroup = \"$group\""
rewrite HEXMobile/KeyboardSetup.swift 1 '    static let keyboardBundleID = "anomaly.hex.mobile.keyboard"' "    static let keyboardBundleID = \"$bundle.keyboard\""

# Upstream identity anywhere the build reads it. Docs, appstoreconnect.json,
# ExportOptions.plist and Xcode Cloud's ci_scripts are upstream's tooling and
# never reach a fork build; a log subsystem is only a label.
leftovers=$(cd "$ios" && grep -rnE \
  -e '5NZ4Q7NXJ4' \
  -e 'group\.anomaly\.hex' \
  -e '(PRODUCT_BUNDLE_IDENTIFIER|bundleIdPrefix): *anomaly\.' \
  -e '"anomaly\.hex\.mobile(\.(keyboard|widgets|tests))?"' \
  --include='*.yml' --include='*.swift' --include='*.entitlements' --include='*.plist' --include='*.xcconfig' \
  --exclude=ExportOptions.plist --exclude-dir=ci_scripts --exclude-dir=fork --exclude-dir=build \
  --exclude-dir='*.xcodeproj' . | grep -v 'subsystem: "anomaly\.' || true)
if [[ -n $leftovers ]]; then
  fail "upstream identity left after the rewrite; add a rewrite for each:"
  echo "$leftovers" >&2
fi

if ((failures > 0)); then
  echo "identity: FAILED ($failures problem(s)); nothing is safe to build" >&2
  exit 1
fi
if $check; then
  echo "identity: checkout uses $team / $bundle / $group / $name"
else
  echo "identity: rewritten to $team / $bundle / $group / $name"
fi
