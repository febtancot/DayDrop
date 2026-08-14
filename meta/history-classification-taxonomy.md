---
title: DayDrop 整理历史分类字典
created: 2026-08-12
source_type: product-design
content_type: taxonomy
status: draft
tags:
  - source/code-inspection
  - source/user-request
  - content/taxonomy
  - domain/operation-history
  - workflow/history-query
  - component/history-store
  - artifact/taxonomy
  - status/draft
related_raw_inputs:
  - ../raw/2026-08-12-history-classification-query-request.md
---

# DayDrop 整理历史分类字典

本字典用于约束数据字段、筛选器和界面文案。不同维度必须分开存储，不能把所有值压进一个 `category` 字段。

## 固定系统维度

| 维度 | 建议值 | 说明 |
| --- | --- | --- |
| `operation_kind` | `file_move`、`managed_folder_migration` | 文件整理与 DayDrop 管理目录迁移是两种不同操作。 |
| `trigger` | `automatic_download`、`manual_top_level`、`manual_deep`、`startup_recovery`、`scheduled_migration` | 表示为什么执行，而不是执行结果。 |
| `outcome` | `pending`、`succeeded`、`failed`、`cancelled`、`interrupted`、`unknown` | `unknown` 只用于启动恢复仍无法证明结果的情况，不能当作失败或成功。 |
| `file_category` | `document`、`image`、`audio`、`video`、`archive`、`disk_image`、`application`、`code`、`font`、`data`、`other`、`unknown` | 依据文件扩展名和 `UTType` 做本地、确定性分类；不读取文件内容。 |
| `source_scope` | `root`、`immediate_subfolder`、`managed_folder` | 表示原文件所处范围，避免从绝对路径反向猜测。 |
| `error_code` | 稳定机器码，例如 `metadata_missing`、`target_unmanaged`、`move_failed`、`persistence_failed` | UI 展示本地化消息，查询和统计使用稳定机器码。 |

## 可变维度

- `classifier_version`：系统文件分类规则版本。规则升级后可以显式重分类，并保留原版本信息。
- 用户标签：第一版不实现。后续如加入，应使用独立多对多表，例如“工作”“报销”“稍后处理”；标签不改变系统分类，也不影响整理路由。
- 收藏查询：保存筛选条件和排序规则，而不是复制结果集。

## 不应自动生成的分类

- “来自 Safari/Chrome/某网站”：仅凭普通文件系统元数据不能可靠证明；不要根据文件名猜测。
- 文件主题、机密程度或内容语义：除非未来获得单独、明确的用户授权，否则不读取内容或调用云端模型。
- “重复文件”“可安全删除”：整理历史无法单独证明这两个结论。

## 兼容与显示规则

- 数据库存英文稳定枚举，界面按当前语言本地化。
- 未知新枚举必须显示为“其他/未知”，旧版不能因此无法打开数据库。
- 历史路径优先保存为授权根目录下的相对路径；只有无法安全转换的旧记录保留绝对路径并标记 `legacy_absolute_path`。
- 文件分类是历史快照。文件以后改名、移动或删除，不应改写当时的整理记录。
