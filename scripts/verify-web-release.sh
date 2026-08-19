#!/bin/zsh

# Verify that the project version, homepage, DMG, checksum, and Sparkle feed
# describe the same DayDrop release. Pass a base URL to verify a deployment too.

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "$project_dir"

project_version=$(awk -F ': *' '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)
project_build=$(awk -F ': *' '/CURRENT_PROJECT_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)
site_dir="$project_dir/Product_Site"
homepage="$site_dir/index.html"
downloads_dir="$site_dir/downloads"
appcast="$site_dir/updates/appcast.xml"
dmg_name="DayDrop-$project_version.dmg"
dmg="$downloads_dir/$dmg_name"
checksum_file="$dmg.sha256"
base_url=${1:-}
remote_dir=""
cleanup() {
    if [[ -n "$remote_dir" && -d "$remote_dir" && "$remote_dir" == /tmp/DayDrop-web-verification.* ]]; then
        rm -rf "$remote_dir"
    fi
}
trap cleanup EXIT INT TERM

for command_name in awk curl date grep jq mktemp shasum sort xmllint; do
    command -v "$command_name" >/dev/null || {
        print -u2 "错误：缺少命令 $command_name。"
        exit 1
    }
done

[[ -n "$project_version" ]] || { print -u2 "错误：无法读取项目版本。"; exit 1; }
"$project_dir/scripts/verify-version.sh" \
    --version "$project_version" \
    --build "$project_build"
[[ -f "$homepage" ]] || { print -u2 "错误：找不到网站首页。"; exit 1; }
[[ -f "$dmg" ]] || { print -u2 "错误：网站目录缺少 $dmg_name。"; exit 1; }
[[ -f "$checksum_file" ]] || { print -u2 "错误：网站目录缺少 ${dmg_name}.sha256。"; exit 1; }
[[ -f "$appcast" ]] || { print -u2 "错误：网站目录缺少 appcast.xml。"; exit 1; }

homepage_dmg_versions=$(grep -Eo 'DayDrop-[0-9]+\.[0-9]+\.[0-9]+\.dmg' "$homepage" | sort -u)
[[ "$homepage_dmg_versions" == "$dmg_name" ]] || {
    print -u2 "错误：首页 DMG 引用不唯一或不是 $dmg_name："
    print -u2 "$homepage_dmg_versions"
    exit 1
}
grep -F "v$project_version" "$homepage" >/dev/null || {
    print -u2 "错误：首页没有展示 v$project_version。"
    exit 1
}
grep -F "下载 DayDrop $project_version" "$homepage" >/dev/null || {
    print -u2 "错误：首页主下载按钮没有展示 $project_version。"
    exit 1
}
grep -F 'id="connected-apps"' "$homepage" >/dev/null || {
    print -u2 "错误：首页缺少关联应用介绍区。"
    exit 1
}
grep -F 'href="https://fornow.liveby.app"' "$homepage" >/dev/null || {
    print -u2 "错误：首页缺少搁这儿-ForNow 官网入口。"
    exit 1
}

expected_sha=$(awk 'NR == 1 { print $1 }' "$checksum_file")
actual_sha=$(shasum -a 256 "$dmg" | awk '{ print $1 }')
[[ "$actual_sha" == "$expected_sha" ]] || {
    print -u2 "错误：$dmg_name 的 SHA-256 与校验文件不一致。"
    exit 1
}

xmllint --noout "$appcast"
feed_version=$(xmllint --xpath \
    'string((//*[local-name()="item"])[1]/*[local-name()="shortVersionString"])' \
    "$appcast")
feed_build=$(xmllint --xpath \
    'string((//*[local-name()="item"])[1]/*[local-name()="version"])' \
    "$appcast")
feed_url=$(xmllint --xpath \
    'string((//*[local-name()="item"])[1]/*[local-name()="enclosure"]/@url)' \
    "$appcast")
[[ "$feed_version" == "$project_version" ]] || {
    print -u2 "错误：Appcast 最新版本是 $feed_version，不是 $project_version。"
    exit 1
}
[[ "$feed_build" == "$project_build" ]] || {
    print -u2 "错误：Appcast 最新构建号是 $feed_build，不是 $project_build。"
    exit 1
}
[[ "$feed_url" == "https://daydrop.liveby.app/downloads/$dmg_name" ]] || {
    print -u2 "错误：Appcast 最新下载地址不正确：$feed_url"
    exit 1
}
grep -F "$dmg_name" "$appcast" | grep -F 'sparkle:edSignature=' >/dev/null || {
    print -u2 "错误：Appcast 中的 $dmg_name 缺少 EdDSA 签名。"
    exit 1
}

print "本地网站发行内容一致：DayDrop $project_version"

if [[ -n "$base_url" ]]; then
    [[ "$base_url" == https://* ]] || {
        print -u2 "错误：线上验证地址必须使用 HTTPS：$base_url"
        exit 1
    }
    base_url=${base_url%/}
    verify_nonce=$(date +%s)
    remote_dir=$(mktemp -d /tmp/DayDrop-web-verification.XXXXXX)
    remote_homepage="$remote_dir/index.html"
    remote_appcast="$remote_dir/appcast.xml"
    remote_dmg="$remote_dir/$dmg_name"

    curl -fsSL "$base_url/?release=$project_version&verify=$verify_nonce" -o "$remote_homepage"
    curl -fsSL "$base_url/updates/appcast.xml?release=$project_version&verify=$verify_nonce" -o "$remote_appcast"
    curl -fsSL "$base_url/downloads/$dmg_name?verify=$verify_nonce" -o "$remote_dmg"

    grep -F "v$project_version" "$remote_homepage" >/dev/null || {
        print -u2 "错误：$base_url 首页没有展示 v$project_version。"
        exit 1
    }
    grep -F "/downloads/$dmg_name" "$remote_homepage" >/dev/null || {
        print -u2 "错误：$base_url 首页没有链接 $dmg_name。"
        exit 1
    }
    grep -F 'id="connected-apps"' "$remote_homepage" >/dev/null || {
        print -u2 "错误：$base_url 首页缺少关联应用介绍区。"
        exit 1
    }
    grep -F 'href="https://fornow.liveby.app"' "$remote_homepage" >/dev/null || {
        print -u2 "错误：$base_url 首页缺少搁这儿-ForNow 官网入口。"
        exit 1
    }
    remote_feed_version=$(xmllint --xpath \
        'string((//*[local-name()="item"])[1]/*[local-name()="shortVersionString"])' \
        "$remote_appcast")
    remote_feed_build=$(xmllint --xpath \
        'string((//*[local-name()="item"])[1]/*[local-name()="version"])' \
        "$remote_appcast")
    [[ "$remote_feed_version" == "$project_version" ]] || {
        print -u2 "错误：$base_url 的 Appcast 最新版本是 $remote_feed_version。"
        exit 1
    }
    [[ "$remote_feed_build" == "$project_build" ]] || {
        print -u2 "错误：$base_url 的 Appcast 最新构建号是 $remote_feed_build。"
        exit 1
    }
    remote_sha=$(shasum -a 256 "$remote_dmg" | awk '{ print $1 }')
    [[ "$remote_sha" == "$expected_sha" ]] || {
        print -u2 "错误：$base_url 上的 $dmg_name 与本地发行包不一致。"
        exit 1
    }

    print "线上网站发行内容一致：$base_url · DayDrop $project_version"
fi
