# 命令参考

## ssmsctl 统一入口

```bash
ssmsctl --help
ssmsctl node --help
ssmsctl user --help
ssmsctl system status
```

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
sudo scripts/quota_manager.sh enable
sudo scripts/join_node.sh NodeC 192.168.1.215 nodec1
sudo scripts/leave_node.sh NodeC --storage-user a2
sudo scripts/deploy_smb_gateways.sh
sudo scripts/create_user.sh alice --quota-gb 10
sudo scripts/sync_user.sh alice --quota-gb 10
sudo scripts/sync_delete_user.sh alice
sudo scripts/quota_manager.sh set alice 20
sudo scripts/quota_manager.sh set alice 20 --no-backend
sudo scripts/quota_manager.sh report
sudo scripts/storage_usage_report.sh --format json
sudo scripts/backend_sync.sh sync-usage --format-summary
sudo scripts/delete_user.sh alice --keep-data
```

对应的统一命令：

```bash
sudo ssmsctl node join NodeC 192.168.1.215 nodec1
sudo ssmsctl node leave NodeC --storage-user a2
sudo ssmsctl user create alice --quota-gb 10
sudo ssmsctl user delete alice
sudo ssmsctl quota set alice 20
sudo ssmsctl usage sync
```

## 登录节点

```bash
sudo scripts/install_node_client.sh
sudo scripts/install_node_agent.sh --help
sudo scripts/install_smb_gateway.sh --storage-server 192.168.1.187
sudo scripts/create_node_user.sh alice
su - alice
mount | grep /home/alice/storage
scripts/test_mount.sh alice
scripts/request_user_sync.sh alice --quota-gb 10
scripts/request_user_delete.sh alice
```

对应的统一命令：

```bash
ssmsctl user request-create alice --quota-gb 10
ssmsctl user request-delete alice
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
sudo scripts/storage_usage_report.sh --format csv
sudo scripts/storage_usage_report.sh --format json
```
