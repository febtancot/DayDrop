#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
source_app="$project_dir/build/DerivedData/Build/Products/Debug/DayDrop.app"
target_app="/Applications/DayDrop.app"
current_user="$(id -un)"
trash_root="/Users/${current_user}/.Trash"
backup_stamp="$(date '+%Y%m%d-%H%M%S')"

if [[ ! -d "$source_app" ]]; then
    print -u2 "错误：找不到构建产物：$source_app"
    exit 1
fi

if [[ ! -d "$trash_root" || "${trash_root:A}" != /Users/*/.Trash ]]; then
    print -u2 "错误：无法确认当前用户的废纸篓目录。"
    exit 1
fi

backup_dir="$(mktemp -d "${trash_root}/DayDrop-replaced-${backup_stamp}-XXXXXX")"
backup_app="$backup_dir/DayDrop.app"
failed_app="$backup_dir/Failed-DayDrop.app"
had_previous_app=false

print "正在终止已运行的 DayDrop…"
pkill -TERM -x DayDrop 2>/dev/null || true

for attempt in {1..25}; do
    if ! pgrep -x DayDrop >/dev/null; then
        break
    fi
    sleep 0.2
done

if pgrep -x DayDrop >/dev/null; then
    rmdir "$backup_dir"
    print -u2 "错误：DayDrop 未能安全终止，未替换应用。"
    exit 1
fi

if [[ -d "$target_app" ]]; then
    had_previous_app=true
    print "正在备份现有版本到废纸篓…"
    mv "$target_app" "$backup_app"
fi

restore_previous_version() {
    if [[ -d "$target_app" ]]; then
        mv "$target_app" "$failed_app" 2>/dev/null || true
    fi

    if [[ -d "$backup_app" ]]; then
        mv "$backup_app" "$target_app"
        open "$target_app" 2>/dev/null || true
        print -u2 "已恢复并重新启动之前的版本。"
    fi
}

print "正在安装测试版到 /Applications…"
if ! ditto "$source_app" "$target_app"; then
    restore_previous_version
    print -u2 "错误：复制测试版失败。"
    exit 1
fi

if ! codesign --verify --deep --strict --verbose=2 "$target_app"; then
    restore_previous_version
    print -u2 "错误：安装后的签名校验失败。"
    exit 1
fi

print "正在启动安装后的 DayDrop…"
if ! open "$target_app"; then
    print -u2 "测试版已安装，但启动失败：$target_app"
    exit 1
fi

if [[ "$had_previous_app" == false ]]; then
    rmdir "$backup_dir"
    print "安装完成：$target_app"
else
    print "安装完成：$target_app"
    print "上一版本备份：$backup_app"
fi
