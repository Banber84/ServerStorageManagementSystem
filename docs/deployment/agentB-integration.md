# AgentB 对接说明

agentA 负责 Linux、Samba、权限、挂载和配额这些系统层能力。agentB 的 Go 管理后台可以把以下脚本作为稳定对接点。

## 用户操作

在 Storage Server 上创建存储用户：

```bash
sudo scripts/create_user.sh alice --quota-gb 10
```

修改用户配额：

```bash
sudo scripts/quota_manager.sh set alice 20
```

同步到管理后台：

```bash
curl -X PUT http://192.168.1.187:8080/api/users/alice/quota \
  -H 'Content-Type: application/json' \
  -d '{"quota_bytes":21474836480}'
```

删除用户并保留数据：

```bash
sudo scripts/delete_user.sh alice --keep-data
```

## 使用量采集

输出 CSV：

```bash
sudo scripts/storage_usage_report.sh --format csv
```

输出 JSON：

```bash
sudo scripts/storage_usage_report.sh --format json
```

JSON 示例：

```json
[
  {"username":"alice","path":"/srv/samba/users/alice","used_kb":1024}
]
```

管理后台可以在 SQLite 中保存用户配额配置，再结合该脚本输出的 `used_kb` 计算剩余空间。脚本对接时需要把 `used_kb` 转换为字节后上报：

```bash
curl -X POST http://192.168.1.187:8080/api/storage/by-username \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","used_bytes":1048576,"path":"/srv/samba/users/alice"}'
```

其中：

```text
used_bytes = used_kb * 1024
```

## 节点约定

每台登录节点都需要创建与 Samba 用户同名的本地 Linux 用户，并保持登录密码与 Samba 密码一致。用户登录后的 CIFS 挂载由 `pam_mount` 完成，agentB 不需要直接处理挂载逻辑。

如果需要同时在 Storage Server、NodeA、NodeB 创建同名用户，推荐在 Storage Server 上执行：

```bash
sudo scripts/sync_user.sh alice --quota-gb 1
```

该脚本会调用 A 部分的系统脚本完成三方用户同步。同步完成后，agentB 仍然只需要通过 REST API 写入用户记录、配额记录和存储统计，不需要直接执行 Linux/Samba 命令。

如果创建入口在 NodeA 或 NodeB，可以执行：

```bash
scripts/request_user_sync.sh alice --quota-gb 1
```

该脚本会通过 SSH 请求 Storage Server 执行 `sync_user.sh`，最终仍由 Storage Server 统一同步三方用户状态。

如果需要同步删除三方用户，可以在 Storage Server 上执行：

```bash
sudo scripts/sync_delete_user.sh alice
```

也可以从 NodeA 或 NodeB 发起删除请求：

```bash
scripts/request_user_delete.sh alice
```

删除同步只处理 Linux/Samba 系统用户和目录归档。agentB 后台数据库中的用户记录仍建议通过 Web 页面或 REST API 删除，避免系统删除和后台审计记录混在一起。
