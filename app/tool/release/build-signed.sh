#!/usr/bin/env bash
# build-signed.sh — a script step: build the store AAB and ipa signed, and check what was built by
# reading the built files themselves: where they are, who signed them, and which version they carry.
#
# The checkout is cleaned (`flutter clean`) and built with the store flavor:
#
#   flutter build appbundle --release --flavor store
#   flutter build ipa --flavor store
#
# Then each product is read, not trusted:
#
#   AAB   app/build/app/outputs/bundle/storeRelease/app-store-release.aab, built by this run; signed,
#         and not with the debug key (`keytool -printcert -jarfile`); its manifest's package,
#         versionName and versionCode (`aapt2 dump badging` on the base module's manifest)
#   ipa   the one .ipa in app/build/ios/ipa/, built by this run; its app signed by Apple Distribution
#         (`codesign -dv`); its Info.plist's CFBundleIdentifier, CFBundleShortVersionString and
#         CFBundleVersion
#
# Both must name the store app's identifier, the version name and the build number in the input.
# When every check holds, the device builds are made too, so `flutter install` puts the same release
# on a phone (`flutter build ios --release --flavor store`, `flutter build apk --release --flavor
# store`). Nothing is committed, and nothing is uploaded.
#
# The release build falls back to the debug key when app/android/key.properties is absent, so the
# step stops before building when the checkout has none. The file is never read here, and neither it
# nor the key it points at is named in the output.
#
# Takes no arguments. The step names its ways out and ports in Japanese, so the names below are the
# ones written in the code. Inputs, from AMENBO_INPUT's `ins`:
#
#   worktree     the checkout to build (required)
#   バージョン    the version name, as <major>.<minor>.<patch> (required)
#   ビルド番号    the build number (required)
#
# The version name and the build number must be the ones app/pubspec.yaml's `version:` already holds;
# the step stops when they are not.
#
# Ways out:
#
#   完了          both products were built and every check held, and the device builds were made;
#                 hands on AAB and ipa (the absolute path of each)
#   検査で落ちた  both products were built, but a check did not hold, and the device builds were not
#                 made; hands on 検査の結果, the file beside output.json naming each failed check on a
#                 line of its own
#
# The way out is decided by output.json, never by this script's exit code. Anything it cannot read or
# do — an input missing or malformed, a version that is not the checkout's, a checkout without
# key.properties, a build that failed (its output is left beside output.json), a product that is not
# where it is expected, a tool that is not installed — ends it with exit code 1, which the step leaves
# through its error way out.
#
# To check the ways out without building or signing, BUILD_FLUTTER, BUILD_AAPT2, BUILD_KEYTOOL and
# BUILD_CODESIGN may each name a command that is run in place of flutter, aapt2, keytool and codesign.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../step-lib.sh source-path=SCRIPTDIR
. "$here/../step-lib.sh"

[ "$#" = 0 ] || die "build-signed.sh takes no arguments; its inputs come from AMENBO_INPUT"

store_id=work.amenbo.viewer

worktree=$(input_dir worktree)
name=$(input_required バージョン)
number=$(input_required ビルド番号)
[[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the version name in the input is not <major>.<minor>.<patch>: \"$name\""
[[ "$number" =~ ^[0-9]+$ ]] || die "the build number in the input is not a number: \"$number\""

app="$worktree/app"
pubspec="$app/pubspec.yaml"
[ -f "$pubspec" ] || die "no app/pubspec.yaml in $worktree"
held=$(grep -E '^version: ' "$pubspec" || true)
[ "$held" = "version: $name+$number" ] ||
    die "app/pubspec.yaml in $worktree reads \"$held\", not \"version: $name+$number\""
[ -f "$app/android/key.properties" ] ||
    die "no app/android/key.properties in $worktree, so the AAB would be signed with the debug key"

flutter=${BUILD_FLUTTER:-flutter}
keytool=${BUILD_KEYTOOL:-keytool}
codesign=${BUILD_CODESIGN:-codesign}
aapt2=${BUILD_AAPT2:-}
if [ -z "$aapt2" ]; then
    sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
    aapt2=$(find "$sdk/build-tools" -mindepth 2 -maxdepth 2 -name aapt2 2>/dev/null | sort -V | tail -n 1)
    [ -n "$aapt2" ] || die "no aapt2 under $sdk/build-tools, and the AAB's manifest is read with it"
fi
for tool in "$flutter" "$keytool" "$codesign" "$aapt2" unzip zip plutil; do
    command -v "$tool" >/dev/null || die "$tool is not installed, and the step needs it"
done

tmp=$(mktemp -d) || die "could not make a temporary folder"
trap 'rm -rf "${tmp:?}"' EXIT
touch "$tmp/started"

build_log=焼いた出力.txt
: > "$out_dir/$build_log" || die "could not write $out_dir/$build_log"

# Run one flutter command in the app, its output going to the build log, or the step stops.
build() {
    printf '$ flutter %s\n' "$*" >> "$out_dir/$build_log"
    (cd "$app" && "$flutter" "$@") >> "$out_dir/$build_log" 2>&1 ||
        die "flutter $* failed in $app; its output is in $out_dir/$build_log"
}

build clean
build build appbundle --release --flavor store
build build ipa --flavor store

aab="$app/build/app/outputs/bundle/storeRelease/app-store-release.aab"
[ -f "$aab" ] || die "flutter built no AAB at $aab"
ipas=$(find "$app/build/ios/ipa" -maxdepth 1 -name '*.ipa' 2>/dev/null || true)
[ -n "$ipas" ] || die "flutter built no .ipa in $app/build/ios/ipa"
[ "$(printf '%s\n' "$ipas" | wc -l | tr -d ' ')" = 1 ] || die "more than one .ipa in $app/build/ios/ipa"
ipa=$ipas

failed=()
fail() { failed+=("$*"); }

# Whether what was read matches what is expected, noting a failed check when it does not.
expect() {
    local what="$1" got="$2" want="$3"
    [ "$got" = "$want" ] || fail "$what is \"$got\", not \"$want\""
}

[ "$aab" -nt "$tmp/started" ] || fail "the AAB was not written by this build"
[ "$ipa" -nt "$tmp/started" ] || fail "the ipa was not written by this build"

# The AAB: its signer, then its manifest. The base module's manifest is in proto format, which
# aapt2 reads only from an APK laid out the same way, so it is moved into one.
signer=$("$keytool" -J-Duser.language=en -printcert -jarfile "$aab" 2>&1 || true)
if ! grep -q '^Owner: ' <<< "$signer"; then
    fail "the AAB is not signed"
elif grep -q 'CN=Android Debug' <<< "$signer"; then
    fail "the AAB is signed with the debug key"
fi

mkdir -p "$tmp/aab/proto"
unzip -q -o -d "$tmp/aab" "$aab" base/manifest/AndroidManifest.xml base/resources.pb ||
    die "could not take the base module's manifest out of $aab"
cp "$tmp/aab/base/manifest/AndroidManifest.xml" "$tmp/aab/base/resources.pb" "$tmp/aab/proto/"
(cd "$tmp/aab/proto" && zip -q ../proto.apk AndroidManifest.xml resources.pb) ||
    die "could not pack the AAB's manifest for aapt2"
package=$("$aapt2" dump badging "$tmp/aab/proto.apk" 2>/dev/null | grep -E '^package: ' || true)
[ -n "$package" ] || die "aapt2 could not read the manifest of $aab"

# One attribute of the package line, as name='value'.
attr() { sed -nE "s/.* $1='([^']*)'.*/\1/p" <<< "$package"; }
expect "the AAB's package" "$(attr name)" "$store_id"
expect "the AAB's versionName" "$(attr versionName)" "$name"
expect "the AAB's versionCode" "$(attr versionCode)" "$number"

# The ipa: the one app in its Payload, its signer, then its Info.plist.
unzip -q -o -d "$tmp/ipa" "$ipa" 'Payload/*' || die "could not unpack $ipa"
apps=$(find "$tmp/ipa/Payload" -mindepth 1 -maxdepth 1 -name '*.app')
[ -n "$apps" ] && [ "$(printf '%s\n' "$apps" | wc -l | tr -d ' ')" = 1 ] ||
    die "expected one .app in the Payload of $ipa"
ios_app=$apps

ios_signer=$("$codesign" -dv --verbose=2 "$ios_app" 2>&1 || true)
grep -q '^Authority=Apple Distribution:' <<< "$ios_signer" ||
    fail "the ipa's app is not signed by Apple Distribution"

# One key of the app's Info.plist, or nothing.
plist() { plutil -extract "$1" raw -o - "$ios_app/Info.plist" 2>/dev/null || true; }
expect "the ipa's CFBundleIdentifier" "$(plist CFBundleIdentifier)" "$store_id"
expect "the ipa's CFBundleShortVersionString" "$(plist CFBundleShortVersionString)" "$name"
expect "the ipa's CFBundleVersion" "$(plist CFBundleVersion)" "$number"

if [ "${#failed[@]}" -gt 0 ]; then
    results=検査の結果.txt
    printf '%s\n' "${failed[@]}" > "$out_dir/$results" || die "could not write $out_dir/$results"
    leave 検査で落ちた "$(jq -n --arg f "$results" '{"検査の結果": $f}')" \
        "built the store AAB and ipa in $worktree, but ${#failed[@]} check(s) did not hold, and the device builds were not made; each is in $results (the build output is in $build_log)"
fi

build build ios --release --flavor store
build build apk --release --flavor store
rm -f "$out_dir/$build_log"

leave 完了 "$(jq -n --arg a "$aab" --arg i "$ipa" '{AAB: $a, ipa: $i}')" \
    "built the store AAB and ipa for $name+$number in $worktree: the AAB is signed with a key other than the debug key, the ipa's app by Apple Distribution, and both read $store_id $name ($number); the device builds (ios, apk) were made too"
