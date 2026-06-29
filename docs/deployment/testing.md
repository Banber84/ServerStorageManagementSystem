# 测试方案

本文档作为测试入口索引和最小验收流程。详细实测过程保留在独立测试报告中，避免重复维护。

## 测试环境

项目按 Ubuntu Server 编写部署步骤，支持虚拟机、物理机或双系统环境。

推荐三机结构：

```text
Storage Server: 集中存储、Samba、quota、用户目录
NodeA/NodeB:    登录节点、pam_mount 自动挂载
Management:     Go 管理后台，可与 Storage Server 同机
```

当前实测环境中，Storage Server / Management Server 使用：

```text
192.168.1.187
```

虚拟机安装和静态 IP 配置参考：

```text
docs/deployment/winpc-ubuntu26.md
```

## 测试报告索引

| 文档 | 内容 |
| --- | --- |
| [../reports/demo-test-report.md](../reports/demo-test-report.md) | 第一版 Web 管理后台、REST API、Agent 上报测试 |
| [../reports/storage-server-test-report.md](../reports/storage-server-test-report.md) | Storage Server 单机 Samba、quota、用户隔离测试 |
| [../reports/full-integration-test-report.md](../reports/full-integration-test-report.md) | 三虚拟机完整联调、跨节点访问、用户同步与删除同步测试 |
| [../reports/nodec-integration-test-report.md](../reports/nodec-integration-test-report.md) | NodeC 接入、生命周期与 Gateway 测试 |
| [../reports/bootstrap-storage-server-test-report.md](../reports/bootstrap-storage-server-test-report.md) | 全新 Storage Server 自动部署测试 |

## 最小验收流程

### 1. 管理后台

启动后台：

```bash
go run ./server -addr 0.0.0.0:8080 -db demo.db
```

健康检查：

```bash
curl http://192.168.1.187:8080/api/health
```

预期结果：

```json
{"status":"ok"}
```

页面检查：

```text
http://192.168.1.187:8080
http://192.168.1.187:8080/users
http://192.168.1.187:8080/storage
http://192.168.1.187:8080/servers
http://192.168.1.187:8080/logs
```

### 2. Storage Server

安装并启用基础能力：

```bash
sudo scripts/install_storage_server.sh
sudo ssmsctl quota enable
# 原脚本：sudo scripts/quota_manager.sh enable
sudo ssmsctl user create alice --quota-gb 1
sudo ssmsctl user create bob --quota-gb 1
```

验证用户目录隔离：

```bash
ls -ld /srv/samba/users/alice /srv/samba/users/bob
smbclient //localhost/alice -U alice -c 'ls'
smbclient //localhost/bob -U alice -c 'ls'
```

预期结果：

- `alice` 可以访问自己的共享目录。
- `alice` 不能访问 `bob` 的共享目录。

验证配额：

```bash
sudo ssmsctl quota report
# 原脚本：sudo scripts/quota_manager.sh report
quota -u alice
```

### 3. 登录节点

安装登录节点组件：

```bash
sudo scripts/install_node_client.sh
sudo scripts/create_node_user.sh alice
```

用户登录后验证自动挂载：

```bash
su - alice
mount | grep /home/alice/storage
```

预期结果：可以看到来自 Storage Server 的 CIFS 挂载。

### 4. 跨节点访问

在 NodeA 上写入：

```bash
echo node-a > /home/alice/storage/shared.txt
```

在 NodeB 上读取：

```bash
cat /home/alice/storage/shared.txt
```

预期结果：

```text
node-a
```

### 5. 后台数据同步

同步用户：

```bash
curl -X POST http://192.168.1.187:8080/api/users \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","full_name":"Alice","email":"","quota_bytes":1073741824}'
```

同步配额：

```bash
curl -X PUT http://192.168.1.187:8080/api/users/username/alice/quota \
  -H 'Content-Type: application/json' \
  -d '{"quota_bytes":1073741824}'
```

同步存储用量：

```bash
curl -X POST http://192.168.1.187:8080/api/storage/username \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","used_bytes":1048576,"path":"/srv/samba/users/alice"}'
```

### 6. Agent 节点监控

单次上报：

```bash
go run ./agent \
  -server http://192.168.1.187:8080 \
  -name node-a \
  -address 192.168.1.188 \
  -disk / \
  -once
```

页面验证：

```text
http://192.168.1.187:8080/servers
```

预期结果：节点在线，CPU、内存、磁盘使用率正常显示。

## 通过标准

- 管理后台页面和 API 可访问。
- Storage Server 用户目录、Samba 访问和 quota 生效。
- 登录节点用户登录后自动挂载个人目录。
- 同一用户在不同节点访问同一份数据。
- 用户之间不能互相访问数据。
- Agent 可以上报节点状态。
- 后台可以展示用户、配额、存储用量、节点状态和日志。
