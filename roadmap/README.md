# ROADMAP 细化入口

根 [ROADMAP](../ROADMAP.md) 保留唯一功能树。采用[通用流程](../docs/PRODUCT_WORKFLOW.md)和[功能模板](_template.md)，当前实例为[新建、编辑、保存与恢复](note-lifecycle.md)。执行仍在[原计划](../artifact/010-desktop-first/plan.md)，证据仍在[原验收记录](../artifact/010-desktop-first/acceptance.md)。不建立第二张状态台账。

模板、流程、检查脚本及其回归来源为 Didadi 本地提交 `ff0e7691e3ee2eacef6cd929094318bee1a1df2c`；仅填写本项目元数据，不继承 Didadi 功能、权限、版本或验收结果。测试文件由 tests 移到本仓库既有 Tests 目录。PR28 复审后局部增强检查器：配置历史豁免时必须给出基线；新增合成 Git 基线回归。通用源目录不变，增强应回馈模板维护者。来源仓库未修改。

运行 `python3 -m scripts.check_roadmap --baseline-ref 7f70349ec995225384e201d598be95804ba7889e` 和 `python3 -m unittest discover -s Tests -p test_roadmap_gate.py -v`。准备勾选时使用 `--baseline-ref 7f70349ec995225384e201d598be95804ba7889e --require-checkable note-lifecycle`；当前完整 GUI 闭环未自验，应拒绝勾选。
