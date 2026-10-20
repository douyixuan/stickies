# 验证记录

状态：部分验证，未安装、未交付。

- 12 项 CLI 隔离集成测试通过，包括完整 CRUD/搜索/Unicode/慢速 stdin、锁拒绝、批量 ID 原子验证、legacy/v2扩展保留、失败拒写、并发进程及应用存储集成。
- 真实 NoteStore 的无窗口 probe 持锁时，CLI edit/delete/list 返回75及正常退出提示；数据哈希不变。probe正常释放后读取原正文一致。
- 本机Trash期间由 NoteStore.applySync 注入较新正文，CLI恢复后保留较新正文，不恢复旧文本快照。
- 32项模拟同步断言及临时目录双副本同步测试通过；不是实际云传输。
- Canvas 50条/隐藏便签/新进程恢复与布局快照/失败恢复回归通过。
- 独立 review 发现List未排除Trash，已修复结果、计数、编辑器和选择清理。独立11项CLI测试通过；额外未知数值1e9999保留probe通过。
- Review证据：/tmp/stickies-cli-review.y1kq9768。

明确限制：App运行时CLI不能并用，包括读取；只允许正常关闭App后操作。该切片不宣称满足日常GUI/CLI并用需求。
UI多选作用范围仍待回答。真实GUI、完整产品验收和双机云传输未完成。当前安装保持0.3.58。
本地候选打包及PR CI结果在后续实际完成后记录，不预先记成功。

## Review P2 修复

父流程独立 review 发现文件读取错误被归入解码错误。现已分离读取与解码：读取失败为 io/74，损坏内容仍为 invalid_data/65。
13 项 CLI 隔离测试通过。新增 notes.json 与 trash.json 不可读常规文件测试覆盖 list/edit/delete，恢复权限后文件哈希不变。
该修复独立静态 review 通过。新 head CI 待实际结果，旧 head 通过不替代新 head 验证。
并用后续设计见 coexistence-plan.md；未实现，现有 App 运行时拒绝仍是产品缺口。
