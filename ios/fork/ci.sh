#!/bin/bash
# The fork's iOS build, one step per command, shared by self-hosted-ios.yml's
# jobs and runnable on any Mac with Xcode:
#
#   ios/fork/ci.sh prepare            rewrite the identity, fetch the model, generate, resolve
#   ios/fork/ci.sh test               unit tests on the newest available iPhone simulator
#   ios/fork/ci.sh archive-unsigned   Release archive, no signing (needs no Apple account)
#   ios/fork/ci.sh archive            signed Release archive (automatic development signing)
#   ios/fork/ci.sh export <export|upload>
#                                     re-sign with App Store profiles; `upload` sends it to TestFlight
#
# Environment: BUILD_NUMBER (CFBundleVersion, default 1), OUT (default
# $RUNNER_TEMP/wehex in CI, else ios/build/fork). archive and export also read ASC_KEY_ID, ASC_ISSUER_ID and
# ASC_KEY_PATH (the .p8 file), and need the signing identities in a keychain.
set -euo pipefail

ios=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fork=$ios/fork
out=${OUT:-${RUNNER_TEMP:+$RUNNER_TEMP/wehex}}
out=${out:-$ios/build/fork}
build=${BUILD_NUMBER:-1}
archive=$out/WeHex.xcarchive
project=$ios/HEXMobile.xcodeproj
xcodegen_min=2.46.0

say() { echo "ci: $*"; }
die() {
  echo "ci: $*" >&2
  exit 1
}

need_key() {
  [[ -n ${ASC_KEY_ID:-} && -n ${ASC_ISSUER_ID:-} && -f ${ASC_KEY_PATH:-} ]] ||
    die "$1 needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH"
  auth=(-allowProvisioningUpdates
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID")
}

team() { sed -nE 's/^    DEVELOPMENT_TEAM: ([A-Z0-9]+)$/\1/p' "$ios/project.yml"; }

# xcodebuild's own log is long; keep it in a file and show its errors.
run_logged() {
  local log=$out/$1.log
  shift
  mkdir -p "$out"
  if ! "$@" >"$log" 2>&1; then
    grep -E "error:|\*\* .* FAILED|Failing tests:|^\s+-\[|Test Case .* failed" "$log" | head -80 >&2 || true
    die "$(basename "$log" .log) failed; full log: $log"
  fi
}

prepare() {
  bash "$fork/identity.sh"
  local have
  have=$(xcodegen --version 2>/dev/null | sed -nE 's/^Version: //p' || true)
  if [[ -z $have || $(printf '%s\n%s\n' "$xcodegen_min" "$have" | sort -V | head -1) != "$xcodegen_min" ]]; then
    say "installing XcodeGen (have '${have:-none}', need $xcodegen_min+)"
    if brew list xcodegen >/dev/null 2>&1; then brew upgrade xcodegen; else brew install xcodegen; fi
    have=$(xcodegen --version | sed -nE 's/^Version: //p')
    [[ $(printf '%s\n%s\n' "$xcodegen_min" "$have" | sort -V | head -1) == "$xcodegen_min" ]] ||
      die "XcodeGen $have is older than $xcodegen_min"
  fi
  sh "$ios/scripts/fetch-cleanup-model.sh"
  (cd "$ios" && xcodegen generate --quiet)
  # The full dependency graph is checked in; resolve exactly it.
  local pins=$project/project.xcworkspace/xcshareddata/swiftpm
  mkdir -p "$pins"
  cp "$ios/Package.resolved" "$pins/Package.resolved"
  run_logged resolve xcodebuild -resolvePackageDependencies -project "$project" -scheme HEXMobile \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
  xcodebuild -version | sed -n 1p
  say "prepared $(team) build $build"
}

simulator() {
  xcrun simctl list devices available --json | jq -r '
    [.devices | to_entries[] | select(.key | test("iOS"))
      | (.key | capture("iOS-(?<maj>[0-9]+)-(?<min>[0-9]+)")) as $v
      | .value[] | select(.name | startswith("iPhone"))
      | {udid, name, v: (($v.maj | tonumber) * 100 + ($v.min | tonumber))}]
    | sort_by(.v) | last | "\(.udid) \(.name)"'
}

test_() {
  local sim
  sim=$(simulator)
  [[ -n $sim && $sim != null* ]] || die "no iPhone simulator available"
  say "testing on ${sim#* }"
  run_logged test xcodebuild test -project "$project" -scheme HEXMobile \
    -destination "id=${sim%% *}" -resultBundlePath "$out/test.xcresult" \
    CURRENT_PROJECT_VERSION="$build"
  say "tests passed"
}

archive_unsigned() {
  rm -rf "$archive"
  run_logged archive xcodebuild archive -project "$project" -scheme HEXMobile \
    -configuration Release -destination generic/platform=iOS -archivePath "$archive" \
    CURRENT_PROJECT_VERSION="$build" CODE_SIGNING_ALLOWED=NO
  say "unsigned archive $archive"
}

archive_signed() {
  need_key archive
  rm -rf "$archive"
  run_logged archive xcodebuild archive -project "$project" -scheme HEXMobile \
    -configuration Release -destination generic/platform=iOS -archivePath "$archive" \
    DEVELOPMENT_TEAM="$(team)" CURRENT_PROJECT_VERSION="$build" "${auth[@]}"
  say "signed archive $archive"
}

export_() {
  local destination=${1:-}
  [[ $destination == export || $destination == upload ]] || die "export needs 'export' or 'upload'"
  need_key export
  [[ -d $archive ]] || die "no archive at $archive"
  bash "$fork/store-profiles.sh" "$archive" "$out/ExportOptions.plist" "$(team)" "$destination"
  rm -rf "$out/export"
  run_logged export xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist "$out/ExportOptions.plist" -exportPath "$out/export" "${auth[@]}"
  if [[ $destination == upload ]]; then
    grep -qE "Upload succeeded|EXPORT SUCCEEDED" "$out/export.log" || die "no upload confirmation in $out/export.log"
    say "uploaded build $build to App Store Connect"
  else
    local ipa
    ipa=$(find "$out/export" -name '*.ipa' | sed -n 1p)
    [[ -n $ipa ]] || die "export produced no .ipa"
    say "exported $ipa"
  fi
}

case ${1:-} in
  prepare) prepare ;;
  test) test_ ;;
  archive-unsigned) archive_unsigned ;;
  archive) archive_signed ;;
  export) export_ "${2:-}" ;;
  *) die "usage: $0 prepare|test|archive-unsigned|archive|export <export|upload>" ;;
esac
