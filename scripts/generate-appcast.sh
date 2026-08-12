#!/bin/zsh

# Stage a notarized DayDrop DMG for the website and generate a Sparkle appcast.
# The EdDSA private key remains in the login Keychain under the DayDrop account.

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "$project_dir"

project_version=$(awk -F ': *' '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)
project_build=$(awk -F ': *' '/CURRENT_PROJECT_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)
dmg=${1:-"$project_dir/dist/DayDrop-$project_version.dmg"}
downloads_dir="$project_dir/Product_Site/downloads"
updates_dir="$project_dir/Product_Site/updates"
appcast="$updates_dir/appcast.xml"
sparkle_account=com.liuyuhang.DayDrop

"$project_dir/scripts/verify-version.sh" \
    --version "$project_version" \
    --build "$project_build"

[[ -f "$dmg" ]] || { print -u2 "错误：找不到更新包：$dmg"; exit 1; }

generate_appcast=${SPARKLE_GENERATE_APPCAST:-}
if [[ -z "$generate_appcast" ]]; then
    candidates=(
        "$project_dir/build/ReleaseDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
        "$project_dir/build/ReleaseTestsDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
    )
    for candidate in $candidates; do
        if [[ -x "$candidate" ]]; then
            generate_appcast="$candidate"
            break
        fi
    done
fi

[[ -x "$generate_appcast" ]] || {
    print -u2 "错误：找不到 Sparkle generate_appcast。请先构建项目，或设置 SPARKLE_GENERATE_APPCAST。"
    exit 1
}
sign_update=${SPARKLE_SIGN_UPDATE:-${generate_appcast:h}/sign_update}
[[ -x "$sign_update" ]] || {
    print -u2 "错误：找不到 Sparkle sign_update。"
    exit 1
}

mkdir -p "$downloads_dir" "$updates_dir"
ditto "$dmg" "$downloads_dir/${dmg:t}"
archive_sha=$(shasum -a 256 "$downloads_dir/${dmg:t}" | awk '{print $1}')
print "$archive_sha  ${dmg:t}" > "$downloads_dir/${dmg:t}.sha256"

"$generate_appcast" \
    --account "$sparkle_account" \
    --download-url-prefix "https://daydrop.liveby.app/downloads/" \
    --release-notes-url-prefix "https://daydrop.liveby.app/downloads/" \
    --full-release-notes-url "https://daydrop.liveby.app/#download" \
    --link "https://daydrop.liveby.app/" \
    --maximum-versions 3 \
    --maximum-deltas 2 \
    -o "$appcast" \
    "$downloads_dir"

# Archives created before DayDrop embedded Sparkle do not advertise a public
# update key, so generate_appcast cannot infer that they should be signed. Sign
# any such historical enclosure explicitly before signing the full feed.
for archive in "$downloads_dir"/DayDrop-*.dmg(N); do
    archive_name=${archive:t}
    if ! grep -F "$archive_name" "$appcast" \
        | grep -F '<enclosure' \
        | grep -F 'sparkle:edSignature=' >/dev/null; then
        signature_attributes=$("$sign_update" --account "$sparkle_account" "$archive")
        ed_signature=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' \
            <<< "$signature_attributes")
        [[ -n "$ed_signature" ]] || {
            print -u2 "错误：无法签署更新包 $archive_name。"
            exit 1
        }
        patched_appcast=$(mktemp /tmp/DayDrop-appcast.XXXXXX)
        awk -v target="$archive_name" -v signature="$ed_signature" '
            index($0, target) && index($0, "<enclosure") && !index($0, "sparkle:edSignature=") {
                sub(/<enclosure /, "<enclosure sparkle:edSignature=\"" signature "\" ")
            }
            { print }
        ' "$appcast" > "$patched_appcast"
        mv "$patched_appcast" "$appcast"
    fi
done

for notes in "$downloads_dir"/DayDrop-*.md(N); do
    notes_name=${notes:t}
    if ! grep -F "$notes_name" "$appcast" | grep -F 'sparkle:edSignature=' >/dev/null; then
        notes_attributes=$("$sign_update" --account "$sparkle_account" \
            --disable-signing-warning "$notes")
        notes_signature=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' \
            <<< "$notes_attributes")
        notes_length=$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' \
            <<< "$notes_attributes")
        [[ -n "$notes_signature" && -n "$notes_length" ]] || {
            print -u2 "错误：无法签署更新说明 $notes_name。"
            exit 1
        }
        patched_appcast=$(mktemp /tmp/DayDrop-appcast.XXXXXX)
        awk -v target="$notes_name" -v signature="$notes_signature" -v length="$notes_length" '
            index($0, target) && index($0, "<sparkle:releaseNotesLink") && !index($0, "sparkle:edSignature=") {
                sub(/<sparkle:releaseNotesLink>/,
                    "<sparkle:releaseNotesLink sparkle:edSignature=\"" signature "\" length=\"" length "\">")
            }
            { print }
        ' "$appcast" > "$patched_appcast"
        mv "$patched_appcast" "$appcast"
    fi
done

"$sign_update" --account "$sparkle_account" --disable-signing-warning "$appcast"
xmllint --noout "$appcast"
grep -F "${dmg:t}" "$appcast" \
    | grep -F '<enclosure' \
    | grep -F "sparkle:edSignature=" >/dev/null || {
    print -u2 "错误：Appcast 中缺少 EdDSA 更新签名。"
    exit 1
}
grep -F "${dmg:t}" "$appcast" >/dev/null || {
    print -u2 "错误：Appcast 中缺少 ${dmg:t}。"
    exit 1
}

print "更新 Feed 已生成：$appcast"
print "更新包已暂存：$downloads_dir/${dmg:t}"

"$project_dir/scripts/prepare-web-release.sh"
