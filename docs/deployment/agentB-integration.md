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

管理后台可以在 SQLite 中保存用户配额配置，再结合该脚本输出的 `used_kb` 计算剩余空间。

## 节点约定

每台登录节点都需要创建与 Samba 用户同名的本地 Linux 用户，并保持登录密码与 Samba 密码一致。用户登录后的 CIFS 挂载由 `pam_mount` 完成，agentB 不需要直接处理挂载逻辑。
