#!/bin/zsh

# Publish a previously prepared Product_Site directory to the production
# Cloudflare Pages project, then verify both the deployment URL and custom URL.

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "$project_dir"

pages_project=daydrop
production_url=https://daydrop.liveby.app
deploy_log=$(mktemp /tmp/DayDrop-pages-deploy.XXXXXX)
cleanup() {
    if [[ -f "$deploy_log" && "$deploy_log" == /tmp/DayDrop-pages-deploy.* ]]; then
        rm -f "$deploy_log"
    fi
}
trap cleanup EXIT INT TERM

for command_name in grep npx sleep tail tee; do
    command -v "$command_name" >/dev/null || {
        print -u2 "错误：缺少命令 $command_name。"
        exit 1
    }
done
"$project_dir/scripts/verify-web-release.sh"

print "正在发布 Product_Site 到 Cloudflare Pages 项目 $pages_project…"
npx wrangler pages deploy Product_Site \
    --project-name "$pages_project" \
    --branch main \
    --commit-dirty=true | tee "$deploy_log"

deployment_url=$(grep -Eo 'https://[a-zA-Z0-9.-]+\.pages\.dev' "$deploy_log" | tail -1)
[[ -n "$deployment_url" ]] || {
    print -u2 "错误：无法从 Wrangler 输出读取本次部署地址。"
    exit 1
}

"$project_dir/scripts/verify-web-release.sh" "$deployment_url"

production_verified=false
for attempt in 1 2 3 4 5; do
    if "$project_dir/scripts/verify-web-release.sh" "$production_url"; then
        production_verified=true
        break
    fi
    [[ $attempt == 5 ]] || sleep 3
done
[[ "$production_verified" == true ]] || {
    print -u2 "错误：生产域名在重试后仍未通过发行一致性校验。"
    exit 1
}

print "网站发布完成：$production_url"
