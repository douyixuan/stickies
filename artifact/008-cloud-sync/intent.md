# 云同步交付
状态：实施中。权威系统：本仓库与对应 PR。
用户于 2026-10-19 授权实现、审查、合入和安全交付，截止北京时间 2026-10-20 06:00；不重复询问已授权的工程决策。
目标：用户显式选择便签后通过 iCloud 同步内容和颜色；布局、可见性和置顶属于设备本地。首次导入、离线、冲突、删除、重启和停用均不得静默丢数据。
禁止：擅自上传原有便签、创建凭据、付费注册、代点权限、多个桌面测试副本。沿用已安装唯一入口，继续保留备份。
真实门槛：本机 security find-identity 成功返回 0 valid identities，0 provisioning profiles，无 Xcode；安装包无Team/CloudKit entitlement，仓库无container。无法据此宣称账户全球没有开发者资格。真实传输和双设备验收受此阻塞；代码与隔离验证继续。
最小外部依赖：已有开发者Team可签名的App ID与CloudKit container/profile，两个登录同一iCloud账户的测试Mac。只使用明确创建的测试便签做真实联调。
