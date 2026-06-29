# 部署文档索引

本目录只保存功能说明、部署步骤、命令参考和验收方案。
历史实测过程与结论统一存放在 [`docs/reports/`](../reports/README.md)。

## 推荐阅读顺序

1. [../design/runbook.md](../design/runbook.md)：后端、Agent、systemd 和接口验证总入口。
2. [bootstrap-storage-server.md](bootstrap-storage-server.md)：全新 Storage Server 自动部署。
3. [ssmsctl.md](ssmsctl.md)：统一管理命令。
4. [storage-server.md](storage-server.md)：Storage Server 手工部署。
5. [node-client.md](node-client.md)：登录节点客户端部署。
6. [smb-gateway.md](smb-gateway.md)：SMB Gateway 部署和验证。
7. [testing.md](testing.md)：第一版 demo 测试流程。

## 操作文档

| 文档 | 用途 |
| --- | --- |
| [commands.md](commands.md) | 常用命令速查 |
| [ssmsctl.md](ssmsctl.md) | 统一命令入口 |
| [bootstrap-storage-server.md](bootstrap-storage-server.md) | 全新 Storage Server 自动部署 |
| [storage-server.md](storage-server.md) | 存储服务安装和配置 |
| [node-client.md](node-client.md) | 登录节点安装和自动挂载 |
| [smb-gateway.md](smb-gateway.md) | 节点 SMB Gateway |
| [user-sync.md](user-sync.md) | 用户同步、删除和跨节点分发 |
| [winpc-ubuntu26.md](winpc-ubuntu26.md) | Windows PC 上 Ubuntu 虚拟机环境准备 |
| [agentB-integration.md](agentB-integration.md) | A/B 脚本与后台接口对接说明 |
| [architecture.md](architecture.md) | 部署侧架构简述 |

## 测试与报告

- [testing.md](testing.md)：当前最小验收流程和通过标准。
- [../reports/README.md](../reports/README.md)：已执行测试的报告索引。

## 维护原则

- 功能原理和部署步骤写入本目录，不混入具体测试日期和终端输出。
- 测试报告保留实测命令、现象和结论，统一写入 `docs/reports/`。
- IP 地址、节点名和用户名如属于示例，应明确写成示例；真实环境以 `configs/site.env.example` 和实际配置为准。
