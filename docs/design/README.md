# 设计文档索引

本目录保存后台和整体设计文档。

| 文档 | 用途 |
| --- | --- |
| [architecture.md](architecture.md) | Go 管理后台和 Agent 的职责边界 |
| [api.md](api.md) | REST API 说明 |
| [database.md](database.md) | SQLite 表结构 |
| [runbook.md](runbook.md) | 运行、部署、systemd 和接口测试手册 |

日常部署优先阅读 [runbook.md](runbook.md)。需要核对接口或数据库字段时，再查看 API 和数据库文档。

已执行测试的过程和结论不放在设计文档中，统一查阅
[`../reports/README.md`](../reports/README.md)。
