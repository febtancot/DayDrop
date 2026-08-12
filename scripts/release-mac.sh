#!/bin/zsh

# Build, Developer ID-sign, notarize, staple, and verify the DayDrop DMG.
#
# Default authentication intentionally matches the proven LiveBy release flow:
# App Store Connect API key (.p8), Key ID, and Issuer ID are passed directly to
# every notarytool command. This script never falls back to an Apple ID password.
#
# Usage:
#   npm run release:mac
#
# Resume a successfully uploaded submission without rebuilding or re-uploading:
#   SUBMISSION_ID=<UUID> npm run release:mac
#
# Supported overrides:
#   NOTARY_KEY=/absolute/path/AuthKey_XXXXXXXXXX.p8
#   NOTARY_KEY_ID=XXXXXXXXXX
#   NOTARY_ISSUER=<issuer-uuid>
#   SIGN_IDENTITY=<Developer-ID-certificate-name-or-SHA1>
#   SKIP_TESTS=1

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "$project_dir"

project_file="$project_dir/project.yml"
package_file="$project_dir/package.json"
entitlements_file="$project_dir/DayDrop/Resources/DayDrop.entitlements"
dist_dir="$project_dir/dist"
test_derived_data="$project_dir/build/ReleaseTestsDerivedData"
analysis_derived_data="$project_dir/build/ReleaseAnalyzeDerivedData"
release_derived_data="$project_dir/build/ReleaseDerivedData"

version=$(awk -F ': *' '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' "$project_file")
package_version=$(jq -r '.version // empty' "$package_file")

[[ -n "$version" ]] || { print -u2 "错误：无法从 project.yml 读取 MARKETING_VERSION。"; exit 1; }
[[ "$package_version" == "$version" ]] || {
    print -u2 "错误：package.json 版本（$package_version）与 project.yml（$version）不一致。"
    exit 1
}

dmg="$dist_dir/DayDrop-$version.dmg"
app="$release_derived_data/Build/Products/Release/DayDrop.app"
submit_result="$dist_dir/DayDrop-$version-notary-submit.json"
info_result="$dist_dir/DayDrop-$version-notary-info.json"
notary_log="$dist_dir/DayDrop-$version-notary-log.json"
checksum_file="$dmg.sha256"
submitted_checksum_file="$dist_dir/DayDrop-$version-submitted.sha256"

sign_identity=${SIGN_IDENTITY:-7ECCD3054C47B78210E275F51C1FF0E83A9AA51E}
expected_team_id=8NF4K823FV
notary_key=${NOTARY_KEY:-$HOME/private_keys/AuthKey_YWL2Z99ZG9.p8}
notary_key_id=${NOTARY_KEY_ID:-YWL2Z99ZG9}
notary_issuer=${NOTARY_ISSUER:-83cbc057-c415-4c90-85fd-26be41761bd1}

required_commands=(
    awk caffeinate codesign ditto grep hdiutil jq lipo npm plutil security
    shasum spctl stat tee xcodebuild xcodegen xcrun xmllint
)
for command_name in $required_commands; do
    command -v "$command_name" >/dev/null || {
        print -u2 "错误：缺少命令 $command_name。"
        exit 1
    }
done

[[ -f "$notary_key" ]] || {
    print -u2 "错误：找不到 App Store Connect API 私钥：$notary_key"
    exit 1
}

key_permissions=$(stat -f '%Lp' "$notary_key")
[[ "$key_permissions" == "600" ]] || {
    print -u2 "错误：$notary_key 的权限是 $key_permissions；请先执行 chmod 600。"
    exit 1
}

security find-identity -v -p codesigning | grep -F "$sign_identity" >/dev/null || {
    print -u2 "错误：钥匙串中找不到指定的 Developer ID Application 身份：$sign_identity"
    exit 1
}

notary_args=(
    --key "$notary_key"
    --key-id "$notary_key_id"
    --issuer "$notary_issuer"
)

print "正在验证 .p8 公证凭据…"
xcrun notarytool history "${notary_args[@]}" --output-format json \
    | jq -e 'has("history")' >/dev/null || {
        print -u2 "错误：.p8、Key ID 或 Issuer ID 无法通过 Apple 公证服务验证。"
        exit 1
    }

stage_dir=""
mount_dir=""
wait_log=""
entitlements_dump=""
expanded_entitlements_file=""
cleanup() {
    if [[ -n "$mount_dir" && -d "$mount_dir" ]]; then
        hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
        rmdir "$mount_dir" >/dev/null 2>&1 || true
    fi
    if [[ -n "$stage_dir" && -d "$stage_dir" && "$stage_dir" == /tmp/DayDrop-release-stage.* ]]; then
        rm -rf "$stage_dir"
    fi
    if [[ -n "$wait_log" && -f "$wait_log" && "$wait_log" == /tmp/DayDrop-notary-wait.* ]]; then
        rm -f "$wait_log"
    fi
    if [[ -n "$entitlements_dump" && -f "$entitlements_dump" && "$entitlements_dump" == /tmp/DayDrop-entitlements.* ]]; then
        rm -f "$entitlements_dump"
    fi
    if [[ -n "$expanded_entitlements_file" && -f "$expanded_entitlements_file" && "$expanded_entitlements_file" == /tmp/DayDrop-expanded-entitlements.* ]]; then
        rm -f "$expanded_entitlements_file"
    fi
}
trap cleanup EXIT INT TERM

submission_id=${SUBMISSION_ID:-}

if [[ -z "$submission_id" ]]; then
    print "正在生成 Xcode 工程…"
    xcodegen generate

    if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
        [[ "$test_derived_data" == "$project_dir/build/ReleaseTestsDerivedData" ]] || exit 1
        rm -rf "$test_derived_data"
        print "正在运行发布前测试…"
        xcodebuild -quiet \
            -project DayDrop.xcodeproj \
            -scheme DayDrop \
            -configuration Debug \
            -destination 'platform=macOS,arch=arm64' \
            -derivedDataPath "$test_derived_data" \
            SWIFT_STRICT_CONCURRENCY=complete \
            SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
            GCC_TREAT_WARNINGS_AS_ERRORS=YES \
            CODE_SIGNING_ALLOWED=NO \
            test

        [[ "$analysis_derived_data" == "$project_dir/build/ReleaseAnalyzeDerivedData" ]] || exit 1
        rm -rf "$analysis_derived_data"
        print "正在运行发布前静态分析…"
        xcodebuild -quiet \
            -project DayDrop.xcodeproj \
            -scheme DayDrop \
            -configuration Release \
            -destination 'generic/platform=macOS' \
            -derivedDataPath "$analysis_derived_data" \
            SWIFT_STRICT_CONCURRENCY=complete \
            SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
            GCC_TREAT_WARNINGS_AS_ERRORS=YES \
            CODE_SIGNING_ALLOWED=NO \
            analyze
    else
        print "警告：已通过 SKIP_TESTS=1 跳过发布前测试。"
    fi

    [[ "$release_derived_data" == "$project_dir/build/ReleaseDerivedData" ]] || exit 1
    rm -rf "$release_derived_data"
    mkdir -p "$dist_dir"

    print "正在构建 arm64 + x86_64 Release 应用…"
    xcodebuild -quiet \
        -project DayDrop.xcodeproj \
        -scheme DayDrop \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$release_derived_data" \
        ARCHS='arm64 x86_64' \
        ONLY_ACTIVE_ARCH=NO \
        SWIFT_STRICT_CONCURRENCY=complete \
        SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
        GCC_TREAT_WARNINGS_AS_ERRORS=YES \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        build

    [[ -d "$app" ]] || { print -u2 "错误：找不到 Release 应用：$app"; exit 1; }

    built_bundle_id_for_signing=$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")
    [[ "$built_bundle_id_for_signing" == "com.liuyuhang.DayDrop" ]] || {
        print -u2 "错误：签名前的 Bundle ID 不符合预期：$built_bundle_id_for_signing"
        exit 1
    }
    expanded_entitlements_file=$(mktemp /tmp/DayDrop-expanded-entitlements.XXXXXX)
    sed \
        's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.liuyuhang.DayDrop/g' \
        "$entitlements_file" > "$expanded_entitlements_file"
    plutil -lint "$expanded_entitlements_file" >/dev/null
    if grep -Fq '$(PRODUCT_BUNDLE_IDENTIFIER)' "$expanded_entitlements_file"; then
        print -u2 "错误：签名权限中仍包含未展开的 PRODUCT_BUNDLE_IDENTIFIER。"
        exit 1
    fi

    sparkle_framework="$app/Contents/Frameworks/Sparkle.framework"
    sparkle_root="$sparkle_framework/Versions/B"
    [[ -d "$sparkle_root/XPCServices/Installer.xpc" ]] || {
        print -u2 "错误：Release 应用缺少 Sparkle Installer.xpc。"
        exit 1
    }

    print "正在使用 Developer ID 签名 Sparkle 更新组件与应用…"
    codesign --force --options runtime --timestamp \
        --sign "$sign_identity" "$sparkle_root/XPCServices/Installer.xpc"
    codesign --force --options runtime --timestamp \
        --preserve-metadata=entitlements \
        --sign "$sign_identity" "$sparkle_root/XPCServices/Downloader.xpc"
    codesign --force --options runtime --timestamp \
        --sign "$sign_identity" "$sparkle_root/Autoupdate"
    codesign --force --options runtime --timestamp \
        --sign "$sign_identity" "$sparkle_root/Updater.app"
    codesign --force --options runtime --timestamp \
        --sign "$sign_identity" "$sparkle_framework"
    codesign --force \
        --options runtime \
        --timestamp \
        --generate-entitlement-der \
        --entitlements "$expanded_entitlements_file" \
        --sign "$sign_identity" \
        "$app"

    codesign --verify --deep --strict --verbose=2 "$app"

    signature_details=$(codesign -d --verbose=4 "$app" 2>&1)
    grep -q 'Authority=Developer ID Application:' <<< "$signature_details" || {
        print -u2 "错误：应用没有使用 Developer ID Application 证书签名。"
        exit 1
    }
    grep -q "TeamIdentifier=$expected_team_id" <<< "$signature_details" || {
        print -u2 "错误：应用签名 TeamIdentifier 不是 $expected_team_id。"
        exit 1
    }
    grep -q 'flags=.*runtime' <<< "$signature_details" || {
        print -u2 "错误：应用没有启用 Hardened Runtime。"
        exit 1
    }
    grep -q 'Timestamp=' <<< "$signature_details" || {
        print -u2 "错误：应用签名没有安全时间戳。"
        exit 1
    }

    entitlements_dump=$(mktemp /tmp/DayDrop-entitlements.XXXXXX)
    codesign -d --entitlements - --xml "$app" > "$entitlements_dump"
    entitlements_json=$(plutil -convert json -o - "$entitlements_dump")
    expected_entitlements_json=$(plutil -convert json -o - "$expanded_entitlements_file")
    [[ "$(jq -S . <<< "$entitlements_json")" == "$(jq -S . <<< "$expected_entitlements_json")" ]] || {
        print -u2 "错误：构建产物权限与 DayDrop.entitlements 不完全一致。"
        print -u2 "实际权限："
        jq . <<< "$entitlements_json" >&2
        rm -f "$entitlements_dump"
        exit 1
    }
    for entitlement_key in \
        com.apple.security.app-sandbox \
        com.apple.security.files.bookmarks.app-scope \
        com.apple.security.files.user-selected.read-write \
        com.apple.security.network.client; do
        jq -e --arg key "$entitlement_key" '.[$key] == true' \
            <<< "$entitlements_json" >/dev/null || {
            print -u2 "错误：缺少或禁用了必要权限 $entitlement_key。"
            rm -f "$entitlements_dump"
            exit 1
        }
    done
    for mach_service in \
        com.liuyuhang.DayDrop-spks \
        com.liuyuhang.DayDrop-spki; do
        jq -e --arg service "$mach_service" \
            '.["com.apple.security.temporary-exception.mach-lookup.global-name"] | index($service) != null' \
            <<< "$entitlements_json" >/dev/null || {
            print -u2 "错误：缺少 Sparkle 沙盒通信权限 $mach_service。"
            rm -f "$entitlements_dump"
            exit 1
        }
    done
    if jq -e '.["com.apple.security.get-task-allow"] == true' \
        <<< "$entitlements_json" >/dev/null; then
        print -u2 "错误：Release 应用包含 get-task-allow，Apple 公证会拒绝。"
        rm -f "$entitlements_dump"
        exit 1
    fi
    rm -f "$entitlements_dump"
    entitlements_dump=""

    architectures=$(lipo -archs "$app/Contents/MacOS/DayDrop")
    lipo "$app/Contents/MacOS/DayDrop" -verify_arch arm64 x86_64 || {
        print -u2 "错误：Release 应用不是 arm64 + x86_64 通用构建：$architectures"
        exit 1
    }

    built_version=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")
    [[ "$built_version" == "$version" ]] || {
        print -u2 "错误：构建版本 $built_version 与项目版本 $version 不一致。"
        exit 1
    }
    built_bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")
    [[ "$built_bundle_id" == "com.liuyuhang.DayDrop" ]] || {
        print -u2 "错误：Bundle ID 不符合预期：$built_bundle_id"
        exit 1
    }
    minimum_system_version=$(plutil -extract LSMinimumSystemVersion raw -o - "$app/Contents/Info.plist")
    [[ "$minimum_system_version" == "13.0" ]] || {
        print -u2 "错误：最低系统版本不符合预期：$minimum_system_version"
        exit 1
    }
    [[ -f "$app/Contents/Resources/AppIcon.icns" ]] || {
        print -u2 "错误：Release 应用缺少 AppIcon.icns。"
        exit 1
    }
    [[ "$(plutil -extract SUFeedURL raw -o - "$app/Contents/Info.plist")" \
        == "https://daydrop.liveby.app/updates/appcast.xml" ]] || {
        print -u2 "错误：Sparkle 更新 Feed 地址不符合预期。"
        exit 1
    }
    [[ "$(plutil -extract SUEnableInstallerLauncherService raw -o - "$app/Contents/Info.plist")" \
        == "true" ]] || {
        print -u2 "错误：沙盒应用未启用 Sparkle Installer Launcher Service。"
        exit 1
    }
    [[ "$(plutil -extract SUVerifyUpdateBeforeExtraction raw -o - "$app/Contents/Info.plist")" \
        == "true" ]] || {
        print -u2 "错误：签名 Feed 未启用下载包解压前验证。"
        exit 1
    }
    [[ -n "$(plutil -extract SUPublicEDKey raw -o - "$app/Contents/Info.plist")" ]] || {
        print -u2 "错误：缺少 Sparkle EdDSA 公钥。"
        exit 1
    }

    stage_dir=$(mktemp -d /tmp/DayDrop-release-stage.XXXXXX)
    ditto "$app" "$stage_dir/DayDrop.app"
    ln -s /Applications "$stage_dir/Applications"

    print "正在生成并签名 DMG…"
    hdiutil create \
        -volname DayDrop \
        -srcfolder "$stage_dir" \
        -ov \
        -format UDZO \
        -imagekey zlib-level=9 \
        "$dmg" >/dev/null
    codesign --force --timestamp --sign "$sign_identity" "$dmg"
    codesign --verify --strict --verbose=2 "$dmg"
    hdiutil verify "$dmg" >/dev/null

    submitted_sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
    print "$submitted_sha  ${dmg:t}" > "$submitted_checksum_file"

    print "正在上传 Apple 公证服务…"
    xcrun notarytool submit "$dmg" \
        "${notary_args[@]}" \
        --output-format json \
        --no-progress > "$submit_result"

    submission_id=$(jq -r '.id // empty' "$submit_result")
    [[ -n "$submission_id" ]] || {
        print -u2 "错误：上传完成但没有取得 Submission ID。"
        exit 1
    }
else
    [[ -f "$dmg" ]] || {
        print -u2 "错误：续跑要求现有 DMG：$dmg"
        exit 1
    }
    [[ -f "$submitted_checksum_file" ]] || {
        print -u2 "错误：续跑缺少提交时校验文件：$submitted_checksum_file"
        exit 1
    }
    expected_submitted_sha=$(awk '{print $1}' "$submitted_checksum_file")
    current_submitted_sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
    [[ "$current_submitted_sha" == "$expected_submitted_sha" ]] || {
        print -u2 "错误：当前 DMG 与提交公证时的文件不一致，拒绝续跑。"
        exit 1
    }
    grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' \
        <<< "$submission_id" || {
        print -u2 "错误：SUBMISSION_ID 格式无效。"
        exit 1
    }
    print "正在续跑已有公证任务，不重新构建或上传。"
fi

print "Submission ID: $submission_id"
print "正在等待 Apple 公证结果…"

wait_completed=false
for attempt in 1 2 3 4 5; do
    wait_log=$(mktemp /tmp/DayDrop-notary-wait.XXXXXX)
    if caffeinate -i xcrun notarytool wait "$submission_id" \
        "${notary_args[@]}" --timeout 30m 2>&1 | tee "$wait_log"; then
        wait_completed=true
        break
    fi

    wait_error=$(<"$wait_log")
    print -u2 "$wait_error"
    if grep -qiE 'credential|authentication|unauthorized|forbidden|key.*not found|issuer' \
        <<< "$wait_error"; then
        print -u2 "错误：公证凭据无效，重试无意义。"
        exit 1
    fi
    if [[ $attempt == 5 ]]; then
        print -u2 "错误：公证等待连续中断。稍后可执行："
        print -u2 "SUBMISSION_ID=$submission_id npm run release:mac"
        exit 1
    fi
    rm -f "$wait_log"
    wait_log=""
    print "第 $attempt 次等待中断，正在重新连接…"
done

[[ "$wait_completed" == true ]] || exit 1

xcrun notarytool info "$submission_id" \
    "${notary_args[@]}" \
    --output-format json > "$info_result"

# Apple recommends inspecting the log even for Accepted submissions.
xcrun notarytool log "$submission_id" "$notary_log" "${notary_args[@]}"

notary_status=$(jq -r '.status // empty' "$info_result")
if [[ "$notary_status" != "Accepted" ]]; then
    print -u2 "错误：Apple 公证状态为 $notary_status。详情：$notary_log"
    jq . "$notary_log" >&2
    exit 1
fi

print "公证已通过，正在附加票据…"
xcrun stapler staple -v "$dmg"
xcrun stapler validate -v "$dmg"

codesign --verify --strict --verbose=2 "$dmg"
hdiutil verify "$dmg" >/dev/null
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"

mount_dir=$(mktemp -d /tmp/DayDrop-release-mount.XXXXXX)
hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$mount_dir" >/dev/null
[[ -d "$mount_dir/DayDrop.app" ]] || { print -u2 "错误：DMG 内缺少 DayDrop.app。"; exit 1; }
[[ "$(readlink "$mount_dir/Applications")" == "/Applications" ]] || {
    print -u2 "错误：DMG 内缺少有效的 Applications 快捷方式。"
    exit 1
}
codesign --verify --deep --strict --verbose=2 "$mount_dir/DayDrop.app"
spctl --assess --type execute --verbose=4 "$mount_dir/DayDrop.app"

final_sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
print "$final_sha  ${dmg:t}" > "$checksum_file"

print "发布完成：$dmg"
print "SHA-256：$final_sha"
print "公证日志：$notary_log"

print "正在生成网站更新 Feed…"
SPARKLE_GENERATE_APPCAST="$release_derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$project_dir/scripts/generate-appcast.sh" "$dmg"
