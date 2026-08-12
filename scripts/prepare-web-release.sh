#!/bin/zsh

# Update the static homepage to the current project version, then verify that
# the complete Product_Site directory is ready for an explicit deployment.

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "$project_dir"

project_version=$(awk -F ': *' '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)
project_build=$(awk -F ': *' '/CURRENT_PROJECT_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)
release_date=${RELEASE_DATE:-$(date +%F)}
homepage="$project_dir/Product_Site/index.html"

for command_name in awk date jq perl; do
    command -v "$command_name" >/dev/null || {
        print -u2 "错误：缺少命令 $command_name。"
        exit 1
    }
done

[[ -n "$project_version" ]] || { print -u2 "错误：无法读取项目版本。"; exit 1; }
"$project_dir/scripts/verify-version.sh" \
    --version "$project_version" \
    --build "$project_build"
[[ -f "$homepage" ]] || { print -u2 "错误：找不到网站首页：$homepage"; exit 1; }

SITE_RELEASE_VERSION="$project_version" SITE_RELEASE_DATE="$release_date" perl -0pi -e '
    s/DayDrop-[0-9]+\.[0-9]+\.[0-9]+\.dmg/DayDrop-$ENV{SITE_RELEASE_VERSION}.dmg/g;
    s/下载 DayDrop [0-9]+\.[0-9]+\.[0-9]+/下载 DayDrop $ENV{SITE_RELEASE_VERSION}/g;
    s/\bv[0-9]+\.[0-9]+\.[0-9]+\b/v$ENV{SITE_RELEASE_VERSION}/g;
    s/(class="foot-mono">v[0-9]+\.[0-9]+\.[0-9]+ · )[0-9]{4}-[0-9]{2}-[0-9]{2}/$1$ENV{SITE_RELEASE_DATE}/g;
' "$homepage"

"$project_dir/scripts/verify-web-release.sh"
print "网站发行内容已准备完成；确认页面后执行：npm run publish:web"
