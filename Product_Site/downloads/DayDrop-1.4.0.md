<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# DayDrop 1.4.0

2026-10-06 · 构建 12

- 新增「整理解压文件夹」，支持 ZIP、RAR/RAR5 和 7z。该选项默认开启，可在「设置 → 通用 → 自动化」关闭。
- 对照原压缩包清单核对文件夹的完整路径、类型和大小，检测到连续 10 秒稳定后整体归档，保留内部层级。
- 原压缩包已被 DayDrop 收入日期文件夹后仍可用于识别；文件夹整理沿用暂停和延迟整理设置。
- 「立即整理」和深度整理可整体移动已识别的解压目录；疑似仍在解压的目录会保留，避免拆散内容。
- 今日下载列表增加文件夹条目和对应图标。

对应压缩包须仍在授权的「下载」目录内。缺少来源、匹配不明确、加密、分卷、包含链接或超过自动检查上限时，目录会保持原位。

支持 macOS 13 或更高版本，提供 Apple Silicon 与 Intel 通用安装包。
