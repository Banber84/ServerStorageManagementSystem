# 命令参考

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
sudo scripts/create_user.sh alice --quota-gb 10
sudo scripts/quota_manager.sh set alice 20
sudo scripts/quota_manager.sh report
sudo scripts/storage_usage_report.sh --format json
sudo scripts/delete_user.sh alice --keep-data
```

## 登录节点

```bash
sudo scripts/install_node_client.sh
sudo scripts/create_node_user.sh alice
su - alice
mount | grep /home/alice/storage
scripts/test_mount.sh alice
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
