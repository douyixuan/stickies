# iStickies2 — Product Roadmap

> Updated: 2026-10-29. This is a delivery plan, not a claim that any untested feature works.
> Repository: [douyixuan/stickies](https://github.com/douyixuan/stickies)

## 定位

**macOS 原生桌面便签工作台**：快速创建便签、直接在桌面编辑、自由摆放和整理，内容安全可恢复。

主体验是独立的原生便签窗口。**Canvas（集中画布）是按需开启、可以关闭的可选视图**，不是默认入口，也不是独立数据源。云同步也是可选增强，不影响离线可用。

## 核心交互契约

1. **默认桌面模式**：不打开画布，也能通过菜单、Dock 和 ⌘N 新建、编辑、隐藏/恢复、删除/恢复便签。关闭便签窗口只是隐藏，不是删除。
2. **可选画布**：用户通过菜单/快捷键打开或关闭，且可自行决定下次启动是否自动打开（默认不自动打开）。画布与桌面窗口可同时使用，不强制二选一。
3. **单一数据源**：Canvas 与桌面共享同一 NoteStore、同一 note ID。画布搜索、筛选、选择、批量管理都作用于同一数据；任何模式切换不能丢数据。
4. **布局独立**：画布排序、窗口几何不自动改变桌面便签的 frame、可见性、折叠状态和窗口层级。只有用户明确选择「排列桌面便签」才重排桌面；窗口位置等设备状态保存在本机。
5. **离线优先**：本地保存与备份先达标；未来 iCloud 同步必须由用户选择启用，且不能成为基本使用的依赖。

## 交付阶段

| 顺序 | 目标版本 | 必须交付 | Issues | 验收关口 |
| --- | --- | --- | --- | --- |
| M0 | 0.4 稳定核心 | 新建/编辑/隐藏/删除完整闭环、真实 Mac GUI 34 项验证、旧数据安全备份与迁移 | [#37](https://github.com/douyixuan/stickies/issues/37), [#35](https://github.com/douyixuan/stickies/issues/35), [#36](https://github.com/douyixuan/stickies/issues/36) | 真实 Mac 可日常创建编辑，重启不丢，损坏或版本不兼容不会覆盖用户数据 |
| M1 | 0.5 可选画布 | 画布开关与启动偏好、搜索定位、多选、批量删除恢复；独立便签保持可用 | [#38](https://github.com/douyixuan/stickies/issues/38) | 关闭画布后全部桌面窗口仍正常；20+ 张便签管理稳定 |
| M2 | 0.6 布局协作 | Free/Grid/List/Compact、Undo/Restore、多屏恢复；画布与桌面布局状态不串扰 | [#39](https://github.com/douyixuan/stickies/issues/39) | 排列/开关画布/拔插显示器/重启均不丢失可访问窗口 |
| M3 | 1.0 可日用发行 | 可下载安装、清晰版本号、签名与公证（条件具备时）、实机回归、安全升级和回滚 | [#42](https://github.com/douyixuan/stickies/issues/42) | 发布产物经过实机验收；所有 P0 bug 关闭 |
| M4 | 1.1 可选 iCloud | 先验证 Apple entitlement 与双机 CRUD，再落地用户选择启用、离线编辑、冲突保留 | [#40](https://github.com/douyixuan/stickies/issues/40), [#41](https://github.com/douyixuan/stickies/issues/41) | 真正双 Mac 验收；未具备签名和真机条件则标记阻塞，不声称交付 |

**注意**：以上版本是规划目标，不是已有发布版本；M3 可先行打包不含 iCloud 的稳定版。不得为了做云同步拖延本地版本发布。

## 现状与分支整理

- 2026-10-26 合并的 [PR #31](https://github.com/douyixuan/stickies/pull/31) 已收敛为 Core / App / CLI，README 表明当前版本仅本地存储，提供原生窗口及多种布局。
- [PR #32](https://github.com/douyixuan/stickies/pull/32) 为待合并草稿，拟解决只读状态下的离屏窗口，但 GUI 实测尚未完成；[#33](https://github.com/douyixuan/stickies/pull/33) 为待合并草稿，拟解决 CLI 非法输入。按独立代码审查、CI、回归证据分别处理。
- 功能是否存在 ≠ 功能已经验收。**真实鼠标、Spaces、Stage Manager、多显示器行为必须在 Mac 上验证**；[34 项 QA](docs/QA.md) 是 M0 的实机测试入口。
- 旧版本 0.3 到新 schema 10 的转换不可无数据备份直接回退。升级前保留完整、静态 profile；旧版 CLI 无法读取 schema 10。
- 现阶段不恢复同步框架、通用 agent 命令账本、无限画布、复杂工作区或任意云盘桥接。基础 CLI `list/search/get/add` 保持为简单工具，不与 GUI 交付抢优先级。

## Issue / PR 规则

- 一个 Issue 描述一项**可演示的用户能力**与可测试 Done，不按抽象基础设施切碎任务。
- 优先完成 **M0 → M1 → M2 → M3 → M4**；同阶段先解决会导致丢数据、无法新建或窗口不可达的 P0 问题。
- 每个 PR 写明关联 Issue、使用的隔离 profile、自动测试结果、真实 Mac 验证结果或明确阻塞；不能将编译成功写成 GUI 已验收。
- 合并后检查 CI；失败需修复或说明阻塞。不要自动安装到用户本机，也不要读取或修改真实便签数据。

## 暂缓

分组、整组移动、命名工作区、团队协作、多平台客户端、插件生态与通用自动化命令服务。只有当真实使用表明有需求时再单独评估，不作为 1.0 前置条件。
