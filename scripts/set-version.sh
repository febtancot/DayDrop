#!/bin/zsh

# Update all source-controlled DayDrop version declarations, regenerate the
# Xcode project, and verify the result before keeping any mutation.

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "$project_dir"

usage() {
    print "用法：npm run version:set -- <x.y.z> <positive-integer>"
}

(( $# == 2 )) || { usage >&2; exit 2; }
release_version=$1
release_build=$2

grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' <<< "$release_version" || {
    print -u2 "错误：版本号必须是 x.y.z 格式：$release_version"
    exit 1
}
grep -Eq '^[1-9][0-9]*$' <<< "$release_build" || {
    print -u2 "错误：构建号必须是正整数：$release_build"
    exit 1
}

for command_name in cp grep jq mktemp mv perl rm xcodegen; do
    command -v "$command_name" >/dev/null || {
        print -u2 "错误：缺少命令 $command_name。"
        exit 1
    }
done

project_file="$project_dir/project.yml"
package_file="$project_dir/package.json"
package_lock_file="$project_dir/package-lock.json"
backup_dir=$(mktemp -d /tmp/DayDrop-version-backup.XXXXXX)
mutation_complete=false
package_temp=""
lock_temp=""

cp "$project_file" "$backup_dir/project.yml"
cp "$package_file" "$backup_dir/package.json"
cp "$package_lock_file" "$backup_dir/package-lock.json"

cleanup() {
    if [[ "$mutation_complete" != true ]]; then
        print -u2 "版本更新未完成，正在恢复原版本文件。"
        cp "$backup_dir/project.yml" "$project_file"
        cp "$backup_dir/package.json" "$package_file"
        cp "$backup_dir/package-lock.json" "$package_lock_file"
        xcodegen generate >/dev/null 2>&1 || true
    fi
    if [[ -d "$backup_dir" && "$backup_dir" == /tmp/DayDrop-version-backup.* ]]; then
        rm -rf "$backup_dir"
    fi
    if [[ -n "$package_temp" && -f "$package_temp" && "$package_temp" == /tmp/DayDrop-package.* ]]; then
        rm -f "$package_temp"
    fi
    if [[ -n "$lock_temp" && -f "$lock_temp" && "$lock_temp" == /tmp/DayDrop-package-lock.* ]]; then
        rm -f "$lock_temp"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

VERSION_VALUE="$release_version" BUILD_VALUE="$release_build" perl -0pi -e '
    s/(CURRENT_PROJECT_VERSION:\s*)[^\n]+/$1$ENV{BUILD_VALUE}/;
    s/(MARKETING_VERSION:\s*)[^\n]+/$1$ENV{VERSION_VALUE}/;
' "$project_file"

package_temp=$(mktemp /tmp/DayDrop-package.XXXXXX)
lock_temp=$(mktemp /tmp/DayDrop-package-lock.XXXXXX)
jq --arg version "$release_version" '.version = $version' \
    "$package_file" > "$package_temp"
jq --arg version "$release_version" \
    '.version = $version | .packages[""].version = $version' \
    "$package_lock_file" > "$lock_temp"
cp "$package_temp" "$package_file"
cp "$lock_temp" "$package_lock_file"
rm -f "$package_temp" "$lock_temp"
package_temp=""
lock_temp=""

xcodegen generate
"$project_dir/scripts/verify-version.sh" \
    --version "$release_version" \
    --build "$release_build"

mutation_complete=true
print "已设置 DayDrop $release_version（构建 $release_build）。"
