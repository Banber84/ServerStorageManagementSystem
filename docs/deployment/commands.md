# 命令参考

## ssmsctl 统一入口

```bash
ssmsctl --help
ssmsctl node --help
ssmsctl user --help
ssmsctl system status
```

## 全新 Storage Server 自动部署

```bash
sudo scripts/ssmsctl system bootstrap --host 192.168.1.230 --check-only
sudo scripts/ssmsctl system bootstrap --host 192.168.1.230
```

该命令用于空白 Ubuntu 虚拟机，不执行旧服务器数据迁移。`--check-only`
只执行环境和配置预检查。

## WinPC 上的 Ubuntu 26.04 基础检查

```bash
lsb_release -a
uname -m
ip addr
sudo systemctl status ssh
```

## Storage Server

```bash
sudo scripts/install_storage_server.sh
sudo ssmsctl quota enable
# 原脚本：sudo scripts/quota_manager.sh enable
sudo ssmsctl node join NodeC 192.168.1.215 nodec1
# 原脚本：sudo scripts/join_node.sh NodeC 192.168.1.215 nodec1
sudo ssmsctl node leave NodeC --storage-user a2
# 原脚本：sudo scripts/leave_node.sh NodeC --storage-user a2
sudo ssmsctl gateway deploy
# 原脚本：sudo scripts/deploy_smb_gateways.sh
ssmsctl user list
sudo ssmsctl user create alice --quota-gb 10
# 原脚本：sudo scripts/sync_user.sh alice --quota-gb 10
sudo ssmsctl user delete alice
# 原脚本：sudo scripts/sync_delete_user.sh alice
sudo ssmsctl quota set alice 20
# 原脚本：sudo scripts/quota_manager.sh set alice 20
sudo ssmsctl quota set alice 20 --no-backend
# 原脚本：sudo scripts/quota_manager.sh set alice 20 --no-backend
sudo ssmsctl quota report
# 原脚本：sudo scripts/quota_manager.sh report
sudo ssmsctl usage sync
# 原脚本：sudo scripts/backend_sync.sh sync-usage --format-summary
sudo ssmsctl usage report --format json
# 原脚本：sudo scripts/storage_usage_report.sh --format json
sudo ssmsctl backend upsert-user alice 10
# 原脚本：sudo scripts/backend_sync.sh upsert-user alice 10
sudo ssmsctl backend delete-user alice
# 原脚本：sudo scripts/backend_sync.sh delete-user alice
```

底层脚本仍可用于排障，例如 `scripts/sync_user.sh`、`scripts/quota_manager.sh`、
`scripts/backend_sync.sh`。

## 登录节点

```bash
sudo scripts/install_node_client.sh
sudo scripts/install_node_agent.sh --help
sudo ssmsctl gateway install --storage-server 192.168.1.187
# 原脚本：sudo scripts/install_smb_gateway.sh --storage-server 192.168.1.187
sudo scripts/create_node_user.sh alice
su - alice
mount | grep /home/alice/storage
scripts/test_mount.sh alice
ssmsctl user request-create alice --quota-gb 10
# 原脚本：scripts/request_user_sync.sh alice --quota-gb 10
ssmsctl user request-delete alice
# 原脚本：scripts/request_user_delete.sh alice
ssmsctl gateway status
```

## Samba 诊断

```bash
testparm -s
sudo systemctl status smbd nmbd
smbclient -L localhost -U alice
smbclient //localhost/alice -U alice -c 'ls'
```

## 配额诊断

```bash
findmnt --target /srv/samba/users
findmnt -no OPTIONS --target /srv/samba/users
sudo quotaon -p /
sudo repquota -a
quota -u alice
```

## 提供给管理后台的使用量报告

```bash
sudo ssmsctl usage report --format csv
# 原脚本：sudo scripts/storage_usage_report.sh --format csv
sudo ssmsctl usage report --format json
# 原脚本：sudo scripts/storage_usage_report.sh --format json
```
