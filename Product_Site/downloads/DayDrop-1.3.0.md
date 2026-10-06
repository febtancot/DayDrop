<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# DayDrop 1.3.0

2026-09-28 · 构建 11

- 新增「延迟整理」：在「设置 → 通用 → 自动化」开启后，当天下载留在原处，次日自动整理昨日及更早的顶层文件。此选项默认关闭。
- 支持启动、唤醒及恢复自动整理时补处理待整理文件，并按原下载日期归档；手动「立即整理」仍可随时使用。
- 修复文件索引出现重复路径记录时导致应用崩溃、自动整理停止的问题。已有重复记录可安全恢复，历史记录继续保留。
- 文件查询新增「最新修改」和「最早修改」排序，分页结果保持稳定。

被占用、未通过下载完成检查或隐藏的文件会继续留在原处。最低支持 macOS 13，提供 Apple Silicon 与 Intel 通用安装包。
