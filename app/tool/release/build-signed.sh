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

[ "$#" = 0 ] || die "build-signed.sh は引数を受け取りません。入力は AMENBO_INPUT から読みます：$*"

store_id=work.amenbo.viewer

worktree=$(input_dir worktree)
name=$(input_required バージョン)
number=$(input_required ビルド番号)
[[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "入力のバージョン名が <major>.<minor>.<patch> の形ではありません：\"$name\""
[[ "$number" =~ ^[0-9]+$ ]] || die "入力のビルド番号が数字ではありません：\"$number\""

app="$worktree/app"
pubspec="$app/pubspec.yaml"
[ -f "$pubspec" ] || die "${worktree} に app/pubspec.yaml がありません"
held=$(grep -E '^version: ' "$pubspec" || true)
[ "$held" = "version: $name+$number" ] ||
    die "${worktree} の app/pubspec.yaml は \"$held\" で、\"version: $name+$number\" ではありません"
[ -f "$app/android/key.properties" ] ||
    die "${worktree} に app/android/key.properties が無いので、AAB がデバッグキーで署名されてしまいます"

flutter=${BUILD_FLUTTER:-flutter}
keytool=${BUILD_KEYTOOL:-keytool}
codesign=${BUILD_CODESIGN:-codesign}
aapt2=${BUILD_AAPT2:-}
if [ -z "$aapt2" ]; then
    sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
    aapt2=$(find "$sdk/build-tools" -mindepth 2 -maxdepth 2 -name aapt2 2>/dev/null | sort -V | tail -n 1)
    [ -n "$aapt2" ] || die "${sdk}/build-tools に aapt2 がありません。AAB のマニフェストは aapt2 で読みます"
fi
for tool in "$flutter" "$keytool" "$codesign" "$aapt2" unzip zip plutil; do
    command -v "$tool" >/dev/null || die "${tool} が入っていません。このステップで使います"
done

tmp=$(mktemp -d) || die "一時フォルダを作れませんでした"
trap 'rm -rf "${tmp:?}"' EXIT
touch "$tmp/started"

build_log=焼いた出力.txt
: > "$out_dir/$build_log" || die "$out_dir/$build_log に書けませんでした"

# Run one flutter command in the app, its output going to the build log, or the step stops.
build() {
    printf '$ flutter %s\n' "$*" >> "$out_dir/$build_log"
    (cd "$app" && "$flutter" "$@") >> "$out_dir/$build_log" 2>&1 ||
        die "${app} で flutter $* が失敗しました。出力は $out_dir/$build_log にあります"
}

build clean
build build appbundle --release --flavor store
build build ipa --flavor store

aab="$app/build/app/outputs/bundle/storeRelease/app-store-release.aab"
[ -f "$aab" ] || die "flutter のビルドで ${aab} に AAB ができていません"
ipas=$(find "$app/build/ios/ipa" -maxdepth 1 -name '*.ipa' 2>/dev/null || true)
[ -n "$ipas" ] || die "flutter のビルドで $app/build/ios/ipa に .ipa ができていません"
[ "$(printf '%s\n' "$ipas" | wc -l | tr -d ' ')" = 1 ] || die "$app/build/ios/ipa に .ipa が2つ以上あります"
ipa=$ipas

failed=()
fail() { failed+=("$*"); }

# Whether what was read matches what is expected, noting a failed check when it does not.
expect() {
    local what="$1" got="$2" want="$3"
    [ "$got" = "$want" ] || fail "${what} は \"$got\" で、\"$want\" ではありません"
}

[ "$aab" -nt "$tmp/started" ] || fail "AAB はこのビルドで書かれたものではありません"
[ "$ipa" -nt "$tmp/started" ] || fail "ipa はこのビルドで書かれたものではありません"

# The AAB: its signer, then its manifest. The base module's manifest is in proto format, which
# aapt2 reads only from an APK laid out the same way, so it is moved into one.
signer=$("$keytool" -J-Duser.language=en -printcert -jarfile "$aab" 2>&1 || true)
if ! grep -q '^Owner: ' <<< "$signer"; then
    fail "AAB が署名されていません"
elif grep -q 'CN=Android Debug' <<< "$signer"; then
    fail "AAB がデバッグキーで署名されています"
fi

mkdir -p "$tmp/aab/proto"
unzip -q -o -d "$tmp/aab" "$aab" base/manifest/AndroidManifest.xml base/resources.pb ||
    die "${aab} から base モジュールのマニフェストを取り出せませんでした"
cp "$tmp/aab/base/manifest/AndroidManifest.xml" "$tmp/aab/base/resources.pb" "$tmp/aab/proto/"
(cd "$tmp/aab/proto" && zip -q ../proto.apk AndroidManifest.xml resources.pb) ||
    die "AAB のマニフェストを aapt2 で読む APK に詰められませんでした"
package=$("$aapt2" dump badging "$tmp/aab/proto.apk" 2>/dev/null | grep -E '^package: ' || true)
[ -n "$package" ] || die "aapt2 で ${aab} のマニフェストを読めませんでした"

# One attribute of the package line, as name='value'.
attr() { sed -nE "s/.* $1='([^']*)'.*/\1/p" <<< "$package"; }
expect "AAB の package" "$(attr name)" "$store_id"
expect "AAB の versionName" "$(attr versionName)" "$name"
expect "AAB の versionCode" "$(attr versionCode)" "$number"

# The ipa: the one app in its Payload, its signer, then its Info.plist.
unzip -q -o -d "$tmp/ipa" "$ipa" 'Payload/*' || die "${ipa} を展開できませんでした"
apps=$(find "$tmp/ipa/Payload" -mindepth 1 -maxdepth 1 -name '*.app')
[ -n "$apps" ] && [ "$(printf '%s\n' "$apps" | wc -l | tr -d ' ')" = 1 ] ||
    die "${ipa} の Payload にある .app が1つではありません"
ios_app=$apps

ios_signer=$("$codesign" -dv --verbose=2 "$ios_app" 2>&1 || true)
grep -q '^Authority=Apple Distribution:' <<< "$ios_signer" ||
    fail "ipa の app が Apple Distribution で署名されていません"

# One key of the app's Info.plist, or nothing.
plist() { plutil -extract "$1" raw -o - "$ios_app/Info.plist" 2>/dev/null || true; }
expect "ipa の CFBundleIdentifier" "$(plist CFBundleIdentifier)" "$store_id"
expect "ipa の CFBundleShortVersionString" "$(plist CFBundleShortVersionString)" "$name"
expect "ipa の CFBundleVersion" "$(plist CFBundleVersion)" "$number"

if [ "${#failed[@]}" -gt 0 ]; then
    results=検査の結果.txt
    printf '%s\n' "${failed[@]}" > "$out_dir/$results" || die "$out_dir/$results に書けませんでした"
    leave 検査で落ちた "$(jq -n --arg f "$results" '{"検査の結果": $f}')" \
        "${worktree} でストア向けの AAB と ipa をビルドしましたが、${#failed[@]} 件の検査が通りませんでした。端末向けのビルドは作っていません。通らなかった検査は $results に、ビルドの出力は $build_log にあります"
fi

build build ios --release --flavor store
build build apk --release --flavor store
rm -f "$out_dir/$build_log"

leave 完了 "$(jq -n --arg a "$aab" --arg i "$ipa" '{AAB: $a, ipa: $i}')" \
    "${worktree} で ${name}+${number} のストア向けの AAB と ipa をビルドしました。AAB はデバッグキー以外の鍵で、ipa の app は Apple Distribution で署名されていて、どちらも ${store_id} ${name}（${number}）です。端末向けのビルド（ios・apk）も作りました"
