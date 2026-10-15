# 验证记录

状态：部分验证。实现与本地测试已完成，PR / CI 见后续交付链接。

- 独立 clone，基于 PR #1 的 53a64dd9076772648f7d6b7b7628b9b9ae4815ab；main 只有 README，未覆盖其他 checkout。
- 初始 PR #1 为 draft，GitHub macOS Build SUCCESS；未合并。
- 本机 Xcode 26.2；无需 XcodeGen 的 swiftc app bundle 编译通过。
- 几何断言通过：负坐标、屏幕边界、超量列表/网格、确定性、小屏、显示器移除恢复。
- AppKit 跨进程集成测试通过：首次创建、真实 setFrame 回调保存、文本/颜色、隐藏/显示、精确外框恢复。
- CUA 实际打开便签；真实键盘输入后的文本已在 Application Support/Stickies/notes.json 看到。截图显示原生便签编辑器与颜色菜单。
- CUA drag 报 noWindowsAvailable，未完成鼠标拖拽和视觉重启验证；不能把几何测试等同于交互测试。
- 初次沙箱内 GUI 启动退出 134；获工具执行权限后运行成功。无系统安全设置修改、无 iCloud/凭据配置、无公网部署。
- 完整 PRD 未在仓库或 GitHub issues 中找到；display:both / layout:both 具体含义未核实。桌面层级/Spaces 与 CloudKit 未实施。

预览：`bash scripts/preview.sh`，数据在 build/preview-data；直接打开 build/Stickies.app 使用正常 Application Support 目录。不要让多个实例同时写同一目录。

## 第二轮真实交互与交付

- 新增本地普通/置顶切换、便签内菜单、原生 Notes 菜单、首行窗口标题、重开 app 显示隐藏便签、存档目录互斥锁。
- 本机编译、布局断言及 AppKit 跨进程测试通过；置顶偏好与浮动窗口层级恢复通过；同时运行第二实例的写入保护测试通过。
- CUA 实际输入 18 行长文本并看到原生滚动条；新建第二便签、输入文本、点关闭隐藏，再用 Show All Notes 重开，文本保留。
- CUA 实际点击 Window → Zoom，截图看到窗口扩大与长文本完整展示。退出 app 后重新打开同一 interaction-data，界面恢复 Today，存档与退出前快照逐项完全相同（文字、颜色、可见性、外框）。
- 某次标题拖拽前后坐标从 (120,220) 变为 (315,460)，但后续重复标题拖拽返回成功却没有坐标变化；因此无法可靠归因或声称已完整验证拖拽。边角拖拽仍报 noWindowsAvailable。改独立进程名、LaunchServices 与刷新绑定后普通点击可用，但未证明错误根因已解决。
- CUA 打开 app / TextEdit 有两次调用耗时约 32 分钟后才返回，非代码构建阻塞；未继续无限调试。
- Personal Context 返回 unavailable，完整 PRD 的 both 含义依然没有权威证据。
- 最终截图保存为 build/stickies-preview.jpg，JPEG 520×440，40558 bytes，SHA256 0df35170ac6489c59c276a561491101a96524c5c135e29b6662811c1f62ead99；截图只有隔离测试便签。已保存 Library，file_id=file_0000000074ec81f998207bdb1501bb0c。
- 浏览器 data: 截图保存页被 URL 策略拒绝，未重试或绕过浏览器限制；使用不联网的 TextEdit 导出原始截图字节。TextEdit 最初把绝对路径当文件名保存在其默认目录，随后仅从该已知文件读取并解码到 build。
