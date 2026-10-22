# 完整验收门槛

这是对恢复的 PRD V0.2、后续同步目标及最新用户反馈的验收汇总。
当前完整产品状态为**部分验证**。历史自动测试只证明对应代码路径；代码合入主线不等于安装、发布或完整产品验收。完整产品验收与可靠新版日用更新分开记录；2026-10-21 用户允许可靠新版更新，但保存退出、备份及安装前检查仍必需。

本轮集成范围是 [#16](https://github.com/douyixuan/stickies/pull/16) 的桌面优先入口、CLI 与本机 Trash，[#17](https://github.com/douyixuan/stickies/pull/17) 的隔离 GUI 测试门禁，[#18](https://github.com/douyixuan/stickies/pull/18) 的串行事务与幂等恢复，[#19](https://github.com/douyixuan/stickies/pull/19) 的本地命令通道，[#20](https://github.com/douyixuan/stickies/pull/20) 的单张置顶覆盖与可恢复操作，以及 [#21](https://github.com/douyixuan/stickies/pull/21) 的显式离线账本分段迁移。各 PR 的合入状态以 GitHub 为准；当前主线构建结果见 [main CI](https://github.com/douyixuan/stickies/actions/workflows/build.yml?query=branch%3Amain)。

这些实现覆盖原 PRD 的部分功能，不把 CLI 或隔离演示替代完整产品。多选范围仍待用户确认，GUI 批准仍待答；本轮不自行扩大 P1/P2，也不合入 PR4。

| 范围 | 通过条件 | 当前证据与缺口 |
| --- | --- | --- |
| 默认体验 | 启动、重复打开和 Dock 操作均以独立便签为主，不强制弹 Canvas；关闭管理窗口不删除或迁移便签 | 上版用户截图证明默认体验不符。实现已取消自动 Canvas；原生编译与隔离测试通过，真实交互待验证 |
| 可选管理 | 用户明确打开 Canvas 才显示管理窗口；List/Board、搜索、编辑与独立窗口共享正文；管理窗口关闭后便签仍可用 | 既有 50 条便签与隐藏便签隔离测试通过；实际切换和关闭待验证 |
| 设置入口 | 可见便签的齿轮与菜单都能打开设置/同步；窗口可见且可操作，不依赖状态栏图标是否被遮挡 | PR15 当时对应的 main CI通过；用户看到 Canvas 不能等于设置入口真实验收 |
| 工具条 | 最小 620 点宽度和常用宽度下无逐字竖排、裁切、控件遮挡；键盘焦点及无障碍名称有效 | 已查看用户截图，确认 Browse 竖排；两行工具条实现已编译通过，未渲染验证 |
| 多选 | 用户确认的作用范围内支持明确选中状态、Cmd/Shift 连选或适用交互、数量显示；搜索/视图切换不误删不可见选择 | 范围仍待父流程确认；单张右键/标题菜单本机删除与逐张恢复已实现，不代表多选完成 |
| 批量删除 | 操作对象和设备范围明确；可撤销或恢复；取消无变化；恢复正文、颜色和关联状态；失败不部分丢失 | UI批量未实现；CLI批量本机Trash已有隔离事务/重启测试，不能代替UI多选验收 |
| 便签编辑 | 点击正文编辑和选字；标题拖动、边缘缩放；双击标题折叠/展开；关闭仅隐藏；新建与搜索快捷键可用 | 单张颜色/置顶/本机Trash右键与标题入口已接入；实际正文右键路由、原生文本菜单、手势与快捷键待安全GUI验证 |
| 布局 | Free/Grid/List/Compact/Restore；排列前持久快照；20–50 条可操作；恢复不改正文 | 既有隔离测试和 CI通过；真实显示、拖动及恢复待验证 |
| 窗口模式 | Desktop 不压普通应用，Floating 可单张覆盖；全局默认可恢复；多显示器/Spaces/Stage Manager不丢窗 | 单张本地覆盖、旧偏好迁移、失败回滚、重启与跨设备隔离已有测试；实际遮挡、Spaces、Stage Manager、显示器插拔与全屏待验证 |
| 本地持久性 | 编辑、保存、重启保持数据；锁排除第二写入者；写失败提示且正常退出不丢未保存内容；损坏数据保留 | 既有隔离测试通过；当前完整版本 GUI 错误路径未验收 |
| CLI 与账本 | 独占锁或应用串行通道处理命令；相同请求不重复执行；维护不能清除历史 | 20 项隔离迁移测试、14 项事务测试、14 项 CLI 测试及 11 项通道测试通过；4096→4102 保留全部指纹/结果。schema3 必须显式离线迁移，旧客户端拒读写；16 MiB 单段与 64 MiB 完整事务限制仍在，历史校验成本增长，无清理压缩或断电保证。未迁移真实 profile |
| 同步隐私 | 默认关闭；用户选择目录及便签后才同步；不自动上传旧便签；每次启动需明确启用目录同步 | 隔离状态机通过；本任务不配置真实目录，不上传真实便签 |
| 两台 Mac 同步 | 同一云盘目录中双向新增/编辑、离线并发冲突、选择版本、删除/恢复、重新启动均通过 | 临时本地双副本通过；真实云盘与两台 Mac 尚未验收，不能用 CI替代 |
| 设备分离 | 同步正文/颜色，不同步设备 frame、可见性和窗口模式；无意外覆盖新编辑 | 隔离兼容与状态机测试通过；真实双机待验证 |
| CloudKit 边界 | 如要求 CloudKit，须有签名/container/实际双设备证据；目录模式不要求开发者账号 | 当前实现提供目录模式；CloudKit 仅适配器，真实 CloudKit 未验收 |
| 安装 | 完整范围全部验证后，正常保存退出、验证备份、原位升级，保持唯一应用与原数据目录 | 当前安装仍为 c199a7a/0.3.58；2026-10-21 用户授权可靠新版日用更新；0.3.81 候选已验证，实际安装等待保存退出确认 |
| 最终审查 | 完整最终差异独立 review；PR CI及最终 main CI通过；未解决阻断为零 | 组合代码 0a26b3346525b3b93377c1edb6bb0011b5928c29 独立复审、完整本机回归、[push CI](https://github.com/douyixuan/stickies/actions/runs/39411434021) 与 [PR CI](https://github.com/douyixuan/stickies/actions/runs/39411439679) 通过；两次 CI 暴露的旧恢复回归已修复。主线准确提交 CI 必须另行核对，不能沿用候选结果。CodeRabbit跳过draft不算审查通过；GUI与真实双机仍未验收 |

# 真实验收阻点

目前没有已批准且安全的交互式 GUI 验收路径。不得使用已停止的不安全 GUI/剪贴板流程，不得代点权限。
真实双机和云盘传输尚无证据。用户提供截图可证明已出现的问题，不能证明修正后的画面。
这些缺口由开发/QA流程解决，不能把逐项手工测试转交用户并称为交付。


# Roadmap 原始来源映射

原 PRD V0.2：[恢复来源](https://chatgpt.com/c/6acf79ac-9cb0-83e8-9282-14f16f87aec9?messageId=cd6c7e99-802e-4078-8a98-555d420f0ce0)。以下依据父流程恢复的原文要点，不声称本任务已读取完整对话。

| Roadmap 模块 | 恢复的原始范围与边界 |
| --- | --- |
| 便签窗口 | Desktop / Floating / Canvas；Spaces、Mission Control、全屏、Stage Manager、多屏恢复 |
| 便签操作 | 直接编辑、拖动、缩放、折叠、颜色、置顶、删除、隐藏；新建/搜索/排列快捷键。多选和批量删除作用范围仍待决定 |
| 布局整理 | P0 Free/Grid/List/Compact/Restore；P1 Snap/Undo/Workspace；P2 Group 分组移动和统一折叠。P1/P2 是原路线图范围；会话布局撤销已获后续明确授权并实现，见下节。其余不因列出而授权立即开发 |
| 数据可靠性 | 原模型 Note/Workspace/Placement/DeviceState，要求内容与布局分离。当前本地侧文件和兼容层不等于完整 Workspace 模型已经实现；工作区能力仍在 P1 |
| 可选同步 | 可选 iCloud、离线编辑、冲突副本、双机同步、窗口布局本机优先。原设计 CloudKit 与当前目录同步实现路线有差异：目录方案已有实现及隔离证据，不能据此声称原 CloudKit 路线完成；也不强加 CloudKit 为目录方案验收前置条件。当前有效产品决定允许云目录路线，CloudKit 不另列必做功能；早期技术设计差异仅在此保留 |
| 命令行操作 | 已授权的后续 CLI 切片 #16/#18/#19/#21；不倒填为原 PRD P0，最初用户原话完整来源仍待补证 |
| 日用更新 | 用户 2026-10-21 原话“你每天有新版就给我安装使用”；不是强退、自动迁移或绕过权限授权。未约定每日自动安装调度 |

原富 UI 验收清单全文仍待证。MVP 明确排除 Markdown 富文本、附件、跨平台、协作、AI、复杂任务和 Keep 双向同步，不列入必做功能树。

Roadmap 的“待验收”不证明已安装或完成；按功能范围选择验收环境，CLI 可用真实候选包执行隔离样本验收，不要求破坏性操作用户真实数据。GUI、双机和安装仍须各自验收。0.3.81 对应 main `aa30d0516ae5cde9fc5512641ff3151f23e97bcb`，[准确 main CI](https://github.com/douyixuan/stickies/actions/runs/39414876063) 通过；当前日用仍为 0.3.58。候选包、兼容性及合成数据回滚证据位于本任务工作区 `daily-update-081/verification.json` 和 `rollback-verification.json`，不代表真实备份或 GUI/双机验收。


## Roadmap 勾选依据

- **命令行操作 → 本机删除恢复：已勾选。** 已验证的 0.3.81 包内 `istk` 在独立合成 profile 执行 `delete`、`restore`，随后以新进程 `get` 验证更新后的正文恢复；对应本任务 `daily-update-081/test-candidate.py` 与 `verification.json`。候选源码为 `aa30d0516ae5cde9fc5512641ff3151f23e97bcb`，ZIP SHA-256 为 `85dfd2f653aa07cf38ba7c95fb321348b9e680a7a320ae8887b00c2d75510301`。本项仅指 CLI 本机操作，不覆盖 UI 多选、同步删除或日用安装。
- **命令增改查找：暂不勾选。** 包内已有 add/edit/get 实测，但该完整叶子包含 search，现有包内实测记录未覆盖搜索结果断言；不拿模型测试或部分命令通过替代全部范围。
- **其余项：未勾选。** GUI、真实双机、安装仍有验收缺口；应用命令共存等不可只凭单位模型通过勾选。50 条便签是布局验收规模，保留在本验收表，不另作功能项。


## P1 最近布局撤销（部分验证）

本轮用户明确授权补“撤销最近一次布局操作”。已有 Restore 仅保存一键排列前持久快照，后续手动拖动/缩放不更新它；因此不能替代最近手动几何操作的撤销。本轮不开发边缘吸附、多选或工作区。

实现约定：独立窗口菜单/Canvas 的 Window Layout 增加 `Undo Last Layout`（Command-Option-Z）；Board 的 Arrange Board 增加独立 `Undo Last Board Layout`。无历史时入口禁用。窗口一次拖动/缩放的连续 frame 更新合并为一个操作；排列与 Restore 同样生成一条会话历史。Board 的卡片移动、排列与恢复各生成一条历史。只恢复位置/大小，不回退正文、颜色、当前折叠、可见性、Trash 或后来新增的便签。

复用 `NoteLayoutState.Snapshot` 与 `CanvasBoardState.Snapshot` 结构，仅增加会话内的一步历史，不新增持久化文件或第二份长期快照。保留旧 `layout.json` / `canvas-layout.json` 的 Restore 行为。重启后会话撤销清空且禁用；原有持久 Restore 仍可用。窗口撤销保存失败时保留待保存内容和撤销记录供重试；Board 提交失败时保持当前几何和历史不变。第二写入实例仍由原文件锁阻止。

代码路径：`NoteStore.swift`（会话快照、手势合并与撤销）、`NoteDragHint.swift`（原生输入边界）、`NoteView.swift`（窗口入口）、`CanvasBoard.swift`（画布入口及原子提交）。本任务源码/测试及 PR 为权威证据；原 QA 负责真实窗口/手势验收，当前不启动 GUI、不操作日用版或真实便签。

验证计划：新增 `Tests/LayoutUndoTests.swift` / `scripts/test-layout-undo.sh` 验证无历史、一次手势、几何恢复、正文/颜色/新增便签/折叠/隐藏保留、窗口和画布写失败、并发锁、重启历史清空及持久 Restore 不变；回归现有 50 条布局恢复与 Board 测试，完整编译和准确提交 CI。真实标题拖动、边缘缩放、菜单焦点及快捷键路由仍待安全 GUI 验收，Roadmap 保持未勾选。


本机验证结果：新增会话撤销测试通过（连续手势合并、无历史、重复排列/Restore 不吞历史、保留内容/颜色/新增便签/当前折叠与隐藏、窗口及 Board 写失败/重试、Board 默认位置 before-image、并发实例拒写、重启清会话历史且保留持久 Restore）。独立 reviewer 修正了无变化操作覆盖历史及 Board 条件视图销毁历史两项问题，复审无剩余静态阻断。Board 状态现由稳定 CanvasView 持有；真实视图切换仍须 GUI 验收。首轮测试中的 Swift throwing-autoclosure 编译错误及全隐藏 fixture 未触发排列写入的断言问题已修正；未放宽功能断言。

最终本机回归：现有 7 阶段布局/恢复、4 阶段 Canvas Board 测试及完整本地编译均通过；未启动应用。准确候选提交的 CI 结果以该 PR 为准，不能用旧 main CI 替代。


## P1 拖拽边缘吸附（部分验证）

用户在撤销候选之后明确授权 Snap。已有拖动路径直接保存 frame，未提供吸附算法或用户开关。本轮最小可逆范围是独立便签的显示器可用区域边缘吸附：现有排列菜单增加 `Snap to Screen Edges`，默认关闭；设备本地 preferences 保存开关，缺失字段按关闭读取。用户拖动释放后，距离所处显示器可用边缘不超过 12 点时修正位置，不改尺寸。屏幕选择按交集面积，平局以坐标稳定排序；无有效屏幕、完全离屏、便签大于可用区域时不瞬移。缩放与程序排列不吸附，远离边缘自由移动。未定义的网格参数/便签间吸附不扩大为新设置体系，Canvas 卡片也不受屏幕吸附开关影响。

与 Undo 兼容：吸附属于同一拖动操作，撤销返回拖动前位置；沿用原会话历史及持久 Restore，不增加历史文件。折叠按实际标题窗口计算边缘，保留展开尺寸。偏好写失败保留旧开关；正文文件写失败保留内存数据、未保存标记和撤销机会，成功重试后持久化。原文件锁和 schema 验证继续生效。

实现路径：`LayoutEngine.swift` 几何计算、`NoteStore.swift` 手势结束/偏好保存、`NoteView.swift` 入口、`NoteDragHint.swift` 原生 tracking-loop 结束边界。新增 `Tests/WindowSnapTests.swift` / `scripts/test-window-snap.sh` 验证负坐标、多屏边界和稳定性、12 点阈值、重复拖动、尺寸保留、折叠、开关默认/保存失败/损坏、锁拒写、Undo/排列、正文写失败恢复及跨进程重启。真实拖放和显示器交互仍需安全 GUI 验收，Roadmap 不勾选。

Snap 候选基于独立撤销候选 PR #23；不将 #23 或文档 PR #22 的状态当作 Snap 主线合入、真实验收或安装证据。原 QA/同步职责与 PR4 保持不变。

本机结果：Snap 隔离测试、会话 Undo 回归、窗口模式与单张便签回归、完整本地编译均通过。补充正文文件写失败后内存正文/几何/Undo 保留及 flush 重试成功断言。独立静态复审无阻断；原生标题拖动与 performDrag 的 tracking-loop 事件顺序仍待真实 GUI 验收，直接调用手势方法的测试不替代该验收。


## P1 工作区布局保存与切换（部分验证）

原 P1 Workspace 与 Note/Placement/DeviceState 要求保留内容与布局分离。本轮明确授权创建、重命名、保存与切换，最小完整用户流程为设备本地命名窗口布局；开放 PR #4 是同步模型、#23/#24 是本任务 Undo/Snap 候选，未发现其他工作区认领。候选堆叠在 #24，不改变其他分支或同步 schema。

现有排列菜单的 Layout Workspaces 入口打开独立管理窗口：输入唯一的 1–80 字名称创建当前布局，选中后重命名、用当前布局覆盖保存，或切换至保存布局。创建/重命名/保存均明确持久化，拖动不会自动覆盖已保存布局。workspaces.json 仅存版本、工作区 ID/名称与便签 ID/frame；不存正文、颜色、隐藏、折叠、置顶或云状态，不改变 Canvas Board 排列。工作区不承担便签分组/成员归属语义。

切换只更新仍存在且未进 Trash 的便签位置与大小，后来新增的便签保持不变；旧 ID 不重新创建。沿用屏幕恢复逻辑，适配负坐标、移除显示器、可用区域及折叠标题高度；无有效屏幕时保留保存几何。当前隐藏/折叠/颜色/正文保持。切换形成单步 Undo，重复无变化切换不吞历史；持久 Restore 快照及 Snap 偏好不变，切换不触发拖动吸附。

命名布局与当前几何分别沿用原子目录文件写入和现有 lossless notes writer；没有跨文件的“当前工作区 ID”或启动时自动套用布局，避免切换失败产生错误的持久选中状态。重启加载命名布局和最后成功保存的当前几何，选择列表重新选择即可。目录写失败不发布内存目录；损坏/未知版本保留原件并禁用操作。切换前先保存未保存编辑，失败拒绝切换；切换后的 notes 写失败保留内存编辑、几何、Undo 和明确错误，重试保存或 Undo 可恢复。正常退出仍受原未保存内容门禁保护；不宣称进程强杀后未成功写盘的几何可恢复。

实现位置：WorkspaceLayouts.swift（数据验证和管理窗口）、NoteStore.swift（加载/保存/切换及 Undo）、NoteView.swift（共享入口）。Tests/WorkspaceTests.swift 与 scripts/test-workspaces.sh 覆盖创建/重命名/覆盖/切换、名称验证、正文/颜色/新便签/隐藏/折叠保留、重启、目录写失败/重试、notes 写失败/重试/Undo、第二实例拒写、损坏及未来版本保留、失效/Trash ID、移除屏幕和无屏幕，以及 Restore/Snap 兼容。独立静态复审无阻断；管理窗口的真实选择/输入/按钮流程与多屏 GUI 仍待原 QA，ROADMAP 不勾选。未启动 GUI、未读取真实便签、未退出或安装日用版。

本机最终验证：工作区全阶段隔离测试通过，包含修复存储后 create/save/rename 重试成功、切换失败后保留内容及 Undo；Undo 和 Snap 全套隔离回归、完整本地编译均通过。最终独立静态复审无阻断。准确提交的 CI 结果记录于候选 PR，不以旧提交的 CI 替代。


## 运行中显示器变化恢复（部分验证）

对照原“多屏恢复/不丢窗”需求发现实际缺口：现有边界恢复只发生在 show、Restore、Undo 或工作区切换；没有运行中显示器配置变化入口。此次按本机 AppKit SDK 的 NSApplicationDelegate.applicationDidChangeScreenParameters 接入现有恢复逻辑，不创造新功能范围，也不接管原 GUI QA。

通知到达后只调整不再完整位于有效屏幕可用区域的可见、未进 Trash 便签；已可达窗口保持位置。空/无效屏幕列表暂不移动，负坐标与可用区域缩小复用已有边界约束；折叠按标题可见 frame 恢复，保留展开高度。隐藏/Trash、正文、颜色、Snap 偏好、命名工作区、排列 Restore 文件不变，不覆盖会话 Undo。自动恢复不运行 Snap，也不展示隐藏窗口。保存失败保留内存和退出保护，下一次通知可重试持久化。

Tests/DisplayRecoveryTests.swift 与 scripts/test-display-recovery.sh 已实测屏幕移除、可用区域变小、空屏幕延迟、重复无变化、折叠尺寸、正文及四类侧文件保持、Undo、跨进程重启、写失败重试及第二写入实例拒写。本机完整编译通过。实际 AppKit 通知时机、系统自动搬窗与此恢复的交互、多屏插拔和 GUI 仍待安全 QA，ROADMAP 的多屏位置恢复不勾选。分组成员、UI 多选删除、安装与双机同步仍保留原阻塞，不因此扩大范围。

独立静态复审无阻断，指出跨屏窗口虽仍可操作也可能被收回单屏；本实现沿用已有“整个渲染窗口位于某一屏幕可用区域”的恢复策略，不仅处理完全离屏窗口。已补跨两屏窗口用例并明确此边界，实际体验仍待 GUI 验收。

最终本机结果：新增显示器恢复全部阶段（含跨屏用例）、Undo、Snap、Workspace 隔离回归和完整编译通过。准确提交 CI 记录于候选 PR；未执行 GUI 插拔验收。

### 2026-10-22: New Note blocked by a hard-linked profile

The installed 0.3.91 profile had a regular `notes.json` with link count 2 (metadata only). With no pending command journal, startup recovery rejected the file before loading notes. The store stayed empty and blocked creation. Canvas showed the secondary CLI warning but omitted the storage error.

A synthetic hard-linked profile reproduces the failure on f8fd28f. The fix permits a read-only load of regular hard-linked notes only when there is no pending journal. GUI saves already replace the file atomically. CLI transactions and pending-journal recovery retain their single-link requirement. Canvas now displays the storage error.

The isolated app-store path covers load, the same create operation used by the New Note button, edit, save, and a new-process reload. It checks that the other link stays byte-identical and the strict CLI gate remains active. Existing lock/crash/retry tests also pass. This is not a rendered GUI click/editor acceptance. No live data or running app was changed. A replacement still requires a safe normal exit; the full GUI new-note flow remains pending.

Validation: legacy and v2 hard-link fixtures pass creation/edit/save/restart; v2 extension fields survive. The other link stays unchanged. All delivery recovery phases and 14 command-core tests pass. Independent static review found no data-safety blocker. Schema3 hard-linked profiles retain the strict startup gate and cannot accept unsaved edits. A valid isolated migrated profile verifies this boundary after automated review identified the need for an explicit startup check.

## 2026-10-22 今晚流程接入结果

对应同一功能项：[新建、编辑、保存与恢复](../../roadmap/note-lifecycle.md)。这是今晚既有计划的调整，不新增平行计划或状态台账。

本轮实际完成：新增该闭环的需求来源、根叶子映射、用户流程、完成定义、分层验收标准和项目运行/锁/备份门槛；根 ROADMAP 的八个相关叶子链接到细化文件，层级和勾选保持不变。复核 0.3.91 用户失败、PR #27 修复主线、0.3.94 未安装及 Store/GUI 证据边界。已有回归与准确主线 CI 只作为既有证据引用，不计作今晚新增测试。

今晚可独立完成范围为文件映射、链接检查、通用格式接入及文档提交审查。通用模板与检查入口待 Didadi 原任务/父任务提供后适配；不另造一套标准。真实 GUI 操作及安全替换不在当前许可内，本轮未执行，也不转交用户代测。对应根叶子仍未勾选。未来获准后由执行者按细化文件完成真实闭环并留证。

文档发布与准确 CI 链接以本轮后续 PR 为准；此记录不把文件落地视为功能验收完成。

今晚计划已按用户反馈调整为[五个具体用户目标](plan.md#2026-10-22-今晚功能执行调整)。核对结果：PR23–27均已合入，0.3.94包可复用；开放PR仅其他流程的PR4。未把既有实现/测试重新计入今晚新增成果。四项GUI闭环与分组产品决定的门槛分别列明；未以文档接入替代功能交付。


### 2026-10-22 管理窗口状态设计与先行自验

对应[同一闭环的设计门槛](../../roadmap/note-lifecycle.md#界面设计与交付自验门槛)。本轮实际查看用户 Library 图片 libfile_2a67550ab8948191805c377e6586e2aa，确认旧版 CLI 提示占据中央且存储故障表现成双空态。CanvasView 增加空库新建、无结果清空搜索、禁写故障态，存储错误直接展示，CLI 详情按需展开；不修改存储或锁。

本机 `SDKROOT=.../MacOSX26.5.sdk bash scripts/build-local.sh` 编译通过，未运行 GUI。用户最新许可覆盖两个 App 的独立合成测试点击/输入/拖动/正常重启/测试窗口截图；当前工具清单没有原生 macOS GUI 控制工具，capture_screen_context 仅限活跃语音，不能替代。此处是能力阻塞，不再写成未获授权。真实视觉、焦点、窗口缩放和按钮闭环由我们在具备安全工具后先验，用户不是首轮测试员。日用退出状态未重新确认，本轮不安装。ROADMAP 不新增勾选。

独立静态复审发现 Canvas 的 ⌘N 请求未与禁用按钮保持一致；已在同一 Canvas 请求入口补 localStateWritable 检查。全局其他窗口行为未改。复审不是 GUI 验收。
