# CLI 契约

命令名 istk。交付包包含 Contents/MacOS/istk；不自动写 PATH 或安装 shell 配置。
所有数据命令使用应用同一 notes.lock 排他锁。忙时返回 75，不停应用、不删锁、不修改 notes.json。
使用 CompatibleNoteFile 读写 legacy/v2，保留正文以外的字段和未知扩展。

成功 stdout、失败 stderr，均为一个 schemaVersion=1 JSON 对象。help/version 不访问 profile。
stdin 为 UTF-8，最大 8 MiB，读取到 EOF。完整 UUID，不接受缩写或重复批量 ID。

CLI delete 为本机废纸篓：仅原子更新 trash.json 成员，保留 notes.json。应用活动列表、独立窗口和排列排除废纸篓记录。
restore 删除本机废纸篓成员，不回滚正文。跨进程持久；失败批量无部分成功。
同步身份保留，既有同步仍可更新被本机归档的便签；不删除云端记录。若远端实际删除，使用既有同步恢复流程。
这不是永久删除或云端删除。UI 多选范围未决定，不以此契约替代其决策。
