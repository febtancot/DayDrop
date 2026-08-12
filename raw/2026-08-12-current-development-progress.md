---
title: DayDrop current development progress source notes
created: 2026-08-12
source_type: conversation-and-code
content_type: raw-input
status: archived
tags:
  - source/user-conversation
  - source/current-workspace
  - content/raw-input
  - domain/daydrop
  - workflow/documentation-maintenance
  - artifact/source-notes
  - status/archived
---

# Original request

> 结合当前的开发进度，帮我整理并更新相关的知识文档

# Development inputs from the current conversation

- “圈出的选项左对齐，另外增加设置按钮，进入设置项”
- “可以使用npm run mac 来进行测试吗？”
- “请帮我将构建的版本放到/Applications，同时终止之前的版本进行替换”
- “将这个过程集成到 npm run mac 的命令中”
- “增加打开今日 folder，另外首次进入软件的页面如何再次的打开？”
- “如果今日文件夹没有创建出来的话……正确的逻辑应该是创建今日的文件夹，并进入。”
- “欢迎页面滚动后会出现文字的重叠”
- “今日文件夹打开的能力应该集成到今日下载的模块……而不用单独的菜单”
- “现在自启动和完成通知的 toggle 按钮有点突兀……选中的色彩稍微的调浅一点”

# Current verification inputs

- The current generated Xcode project passes 70 XCTest cases on arm64 macOS.
- `npm run mac` currently builds a Debug arm64 app, stops the running DayDrop process, moves the existing `/Applications/DayDrop.app` into a recoverable Trash backup, installs the new Debug app, verifies its ad-hoc signature, and launches it.
- The installed development build is not the Developer ID universal distribution artifact.
- `dist/DayDrop-1.0.0.dmg` predates the 2026-08-12 UI and workflow changes and has not been notarized.

# Documentation target

Update the project knowledge set without presenting automated checks as proof of signed permissions, real-browser download behavior, visual quality, performance, notarization, or release readiness.
