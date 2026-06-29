# 测试报告索引

本目录只保存已经执行过的测试过程、终端现象、问题修复和结论。
功能原理、部署步骤和日常命令统一维护在 `docs/design/` 与
`docs/deployment/`，避免历史命令被误当成当前操作手册。

## 报告列表

| 文档 | 测试范围 |
| --- | --- |
| [demo-test-report.md](demo-test-report.md) | 第一版 Web、REST API 与 Agent |
| [storage-server-test-report.md](storage-server-test-report.md) | Storage Server 单机 Samba、quota 与隔离 |
| [full-integration-test-report.md](full-integration-test-report.md) | NodeA、NodeB 三机联调 |
| [nodec-integration-test-report.md](nodec-integration-test-report.md) | NodeC 接入、同步与生命周期 |
| [bootstrap-storage-server-test-report.md](bootstrap-storage-server-test-report.md) | 全新 Storage Server 自动部署 |

## 阅读说明

- 报告中的 IP、用户名、时间和错误输出属于当时环境。
- 报告保留旧脚本命令用于追溯，不代表当前推荐入口。
- 当前推荐命令以
  [ssmsctl 统一管理命令](../deployment/ssmsctl.md)和
  [命令参考](../deployment/commands.md)为准。
- 新的实测结果应追加到对应报告，不写入功能说明文档。
