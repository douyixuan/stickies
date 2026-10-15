# Stickies 0.2.0 交付候选

这是 macOS 14+ 的本地优先候选包，包含 Apple Silicon / Intel 两个架构。构建仅使用 ad-hoc 签名，没有 Developer ID 或公证；未更改系统安全设置。签名校验不等于 Gatekeeper 信任，也不等于 GUI 验收。

## 安装和启动

1. 用随包的 `.zip.sha256` 校验 ZIP：在文件所在目录运行 `shasum -a 256 -c <文件名>.zip.sha256`。
2. 解压。可把 `Stickies Delivery.app` 复制到自己的 `~/Applications`；升级前退出旧实例并保留旧包。也可从解压目录运行，移动位置不会改变默认数据目录。
3. 原 QA 的应用控制权限获批后，才执行真实 GUI 验收。普通用户启动时打开应用，通过菜单栏便签图标操作；它是菜单栏应用，不要求出现 Dock 图标。若 macOS 阻止该未公证候选包，保留错误交给打包流程，不删除 quarantine、不关闭 Gatekeeper、不改变签名权限。
4. App 内 `Contents/Info.plist` 和 `Contents/Resources/BuildInfo.json` 包含版本、完整 commit、构建时间及架构。ZIP 内 `SHA256SUMS.txt` 可再次检查二进制、元数据和说明。

## 数据隔离与备份

默认数据固定在 `~/Library/Application Support/Stickies Delivery`，与已有 `Stickies` 和开发预览的 `preview-data` 分开。安装/解压过程不创建、迁移或读取真实便签。不要自动把真实 notes 导入验收包。

显式 `STICKIES_DATA_DIR` 优先于默认路径。获准 GUI QA 后可用新建临时目录并通过 LaunchServices 的 `open -n --env "STICKIES_DATA_DIR=<隔离目录>" "<包路径>/Stickies Delivery.app"` 启动。不能用此方式绕过应用控制或系统安全审批。

数据包含 `notes.json`、`layout.json`、`canvas-layout.json`、`preferences.json` 和进程锁。升级或回退前退出所有使用同一目录的实例，并复制**整个目录**到新的、未占用的备份位置。不要在实例运行时删除 `notes.lock`；那会破坏并发写保护。

## 退出、恢复和回退

每次编辑自动原子写入。临时写失败后正常退出会重试；仍失败时默认“Keep Editing”取消退出，只有明确选择“Quit Without Saving”才丢弃内存编辑。强制结束进程不能保存从未成功落盘的编辑；已成功写入的数据在本轮隔离 SIGKILL/重启测试中恢复。没有宣称物理断电持久性测试。

文件损坏/未来版本会被保留，不自动覆盖。保留损坏文件用于诊断；不要用空文件替换。排列快照只恢复 frame/折叠状态，Canvas 有独立快照，均不回滚正文。

回退应用时先保存新编辑并退出，再换回保留的旧 Delivery.app。只有确认数据格式兼容时才直接用当前数据。跨格式回退（例如后续 PR #4 的 schema v2）应保留当前完整数据目录，再由原同步流程按备份说明恢复**整份**升级前副本；不要直接让旧程序覆盖新格式，也不要只替换 notes.json 而混用其他时点的布局。

## 验收边界与操作

Command-N 新建；Shift-Command-0 打开 Canvas；Canvas 中 Command-F 搜索。Command-Option-0/1/2/3 是窗口 Free/Grid/List/Compact，Command-Option-R 恢复上次窗口排列。Board 自己的 Arrange Board 只改卡片位置。关闭便签只隐藏；Show All Notes 恢复。双击标题/菜单折叠展开。All Note Windows 切换 Ordinary/Desktop/Floating；Canvas 始终普通窗口。

源码/隔离测试已验证数据路径、写失败重试、并发拒写、强制退出后锁释放、布局和内容分离。实际快捷键、拖动/折叠/点击、Desktop 遮挡/Spaces、安装首启与退出确认面板仍需原 QA 执行。CloudKit 未实现；本包不代表同步验收通过。
