# 同步切片验证记录

本机使用 SDK MacOSX26.5。编译通过，不启动应用，不创建测试 app bundle。
默认 SDK27 的宏插件不适用于当前命令行环境，因此明确选择已安装的兼容 SDK。

## 已通过
- 31 条可注入 transport 状态机断言：选择性上传、离线、重启、三路合并、冲突、in-flight 编辑、未知保存结果、部分拉取失败、pending 恢复、删除、账户变化、停用标记、无锁拒写、启动显式启用。
- 两个临时文件夹模拟设备副本：并发离线多头、显式 join、删除、缺父节点恢复、摘要损坏拒绝、过期写入拒绝。
- NoteStore 集成：v2 本地 frame/visible/扩展保留，远端新建默认隐藏，磁盘失败保留内存，删除持久化。
- 兼容、Canvas、布局快照/恢复、窗口模式、Canvas board、锁/崩溃/未保存重试的既有测试。

文件协调测试在工具默认沙箱内因 NSFileCoordinator IPC 限制失败。
同一隔离测试在自动审批允许的沙箱外执行通过，只访问临时测试目录。
此结果不证明真实 iCloud 或系统权限已通过。

## 独立 review 修复
- failed local delete 后的新编辑保留，Keep Local 清旧墓碑。
- ledger 写失败时独立 off marker 保证重启停用。
- 文件夹选择互斥、实例与停用状态复核、旧 generation 失效。
- 无 notes 存储锁实例不写 off marker。
- 文件夹路线明确为目录授权，启动要求显式重新启用，不冒称账户绑定。
- scope 切换清空勾选，删除明确历史保留，冲突全文可读。

## 未验证
真实 CloudKit：无本机可用签名 identity/profile/container，路径 fail closed。
真实 iCloud Drive：未代用户选择目录，未上传原有便签。
真实双机、GUI、安装权限验收继续交原 QA 流程。

第二轮独立 review 未发现新增阻塞。三次重建实例 probe 均保持停用、零请求、磁盘文件不变，显式启用后才传输。证据目录 /tmp/stickies-consent-review._1067cj6。

通用云盘目录与删除恢复追加验证：32 条状态断言通过，双副本删除/恢复收敛通过。修复失败删除后恢复覆盖新编辑的问题：恢复要求本地不存在且无 pending。CI 标准 runner 从长时间未分配的 macos-15 改为官方 GA macos-26，测试步骤保持不变。

最终补查：ad-hoc 非 launcher 测试包为自身空目录创建并恢复 security-scoped bookmark 成功，不代表真实 picker 或云盘验收。Xcode 沙箱配置补 app-scoped bookmark entitlement，独立 review 确认无全盘/网络权限。最终本地 Canvas/布局/窗口/故障恢复回归再次通过。
