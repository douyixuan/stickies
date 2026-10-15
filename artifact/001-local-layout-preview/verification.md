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
