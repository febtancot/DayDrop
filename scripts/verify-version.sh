#!/bin/zsh

# Verify every source-controlled version declaration used by DayDrop builds.
# With no arguments, project.yml supplies the expected version and build.
# Release automation passes explicit values so an accidental but internally
# consistent configuration cannot publish a different release than intended.

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "$project_dir"

expected_version=""
expected_build=""

usage() {
    print "用法："
    print "  npm run version:check"
    print "  npm run version:check -- --version <x.y.z> --build <positive-integer>"
}

while (( $# > 0 )); do
    case "$1" in
        --version)
            (( $# >= 2 )) || { print -u2 "错误：--version 缺少值。"; usage >&2; exit 2; }
            expected_version=$2
            shift 2
            ;;
        --build)
            (( $# >= 2 )) || { print -u2 "错误：--build 缺少值。"; usage >&2; exit 2; }
            expected_build=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print -u2 "错误：未知参数 $1。"
            usage >&2
            exit 2
            ;;
    esac
done

for command_name in awk grep jq sort; do
    command -v "$command_name" >/dev/null || {
        print -u2 "错误：缺少命令 $command_name。"
        exit 1
    }
done

project_file="$project_dir/project.yml"
package_file="$project_dir/package.json"
package_lock_file="$project_dir/package-lock.json"
xcode_project_file="$project_dir/DayDrop.xcodeproj/project.pbxproj"

for required_file in "$project_file" "$package_file" "$package_lock_file"; do
    [[ -f "$required_file" ]] || {
        print -u2 "错误：缺少版本来源文件 $required_file。"
        exit 1
    }
done

project_version=$(awk -F ': *' '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' "$project_file")
project_build=$(awk -F ': *' '/CURRENT_PROJECT_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' "$project_file")

if [[ -z "$expected_version" && -z "$expected_build" ]]; then
    expected_version=$project_version
    expected_build=$project_build
elif [[ -z "$expected_version" || -z "$expected_build" ]]; then
    print -u2 "错误：--version 与 --build 必须一起提供。"
    usage >&2
    exit 2
fi

grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' <<< "$expected_version" || {
    print -u2 "错误：版本号必须是 x.y.z 格式：$expected_version"
    exit 1
}
grep -Eq '^[1-9][0-9]*$' <<< "$expected_build" || {
    print -u2 "错误：构建号必须是正整数：$expected_build"
    exit 1
}

[[ "$project_version" == "$expected_version" ]] || {
    print -u2 "错误：project.yml MARKETING_VERSION 是 $project_version，预期 $expected_version。"
    exit 1
}
[[ "$project_build" == "$expected_build" ]] || {
    print -u2 "错误：project.yml CURRENT_PROJECT_VERSION 是 $project_build，预期 $expected_build。"
    exit 1
}

package_version=$(jq -r '.version // empty' "$package_file")
lock_version=$(jq -r '.version // empty' "$package_lock_file")
lock_root_version=$(jq -r '.packages[""].version // empty' "$package_lock_file")

[[ "$package_version" == "$expected_version" ]] || {
    print -u2 "错误：package.json 版本是 $package_version，预期 $expected_version。"
    exit 1
}
[[ "$lock_version" == "$expected_version" ]] || {
    print -u2 "错误：package-lock.json 顶层版本是 $lock_version，预期 $expected_version。"
    exit 1
}
[[ "$lock_root_version" == "$expected_version" ]] || {
    print -u2 "错误：package-lock.json 根包版本是 $lock_root_version，预期 $expected_version。"
    exit 1
}

if [[ -f "$xcode_project_file" ]]; then
    generated_versions=$(awk -F '= *' '/MARKETING_VERSION = / {
        gsub(/[;[:space:]]/, "", $2); print $2
    }' "$xcode_project_file" | sort -u)
    generated_builds=$(awk -F '= *' '/CURRENT_PROJECT_VERSION = / {
        gsub(/[;[:space:]]/, "", $2); print $2
    }' "$xcode_project_file" | sort -u)

    [[ "$generated_versions" == "$expected_version" ]] || {
        print -u2 "错误：Xcode 工程版本不是唯一的 $expected_version：$generated_versions"
        exit 1
    }
    [[ "$generated_builds" == "$expected_build" ]] || {
        print -u2 "错误：Xcode 工程构建号不是唯一的 $expected_build：$generated_builds"
        exit 1
    }
fi

print "版本一致：DayDrop $expected_version（构建 $expected_build）"
