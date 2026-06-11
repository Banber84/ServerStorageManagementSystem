# 测试方案

## 测试环境

本项目当前按 `ubuntu-26.04-live-server-amd64` 编写部署步骤。Ubuntu 可以安装在 Windows PC 的虚拟机、双系统或物理机环境中。

建议准备三台 Ubuntu Server 虚拟机或物理机：

```text
Storage Server: 192.168.56.10
Node01:         192.168.56.11
Node02:         192.168.56.12
```

安装准备和静态 IP 配置参考：

```text
docs/deployment/winpc-ubuntu26.md
```

## 测试 1：用户隔离

在 Storage Server 上创建两个用户：

```bash
sudo scripts/create_user.sh alice --quota-gb 1
sudo scripts/create_user.sh bob --quota-gb 1
```

检查目录权限：

```bash
ls -ld /srv/samba/users/alice /srv/samba/users/bob
```

预期结果：

```text
drwx------ alice storageusers /srv/samba/users/alice
drwx------ bob   storageusers /srv/samba/users/bob
```

尝试跨用户访问：

```bash
smbclient //localhost/bob -U alice -c 'ls'
```

预期结果：访问被拒绝。

## 测试 2：跨节点访问同一份数据

在 Node01 上以 `alice` 用户执行：

```bash
echo node01 > /home/alice/storage/shared.txt
```

在 Node02 上以 `alice` 用户执行：

```bash
cat /home/alice/storage/shared.txt
```

预期结果：

```text
node01
```

## 测试 3：登录自动挂载

在 Node01 上执行：

```bash
su - alice
mount | grep /home/alice/storage
```

预期结果：可以看到来自 Storage Server 的 CIFS 挂载。

## 测试 4：配额限制

创建 1 GB 配额用户：

```bash
sudo scripts/create_user.sh quotauser --quota-gb 1
```

在登录节点上以 `quotauser` 用户写入大文件：

```bash
dd if=/dev/zero of=/home/quotauser/storage/quota-test.bin bs=100M count=12 status=progress
```

预期结果：超过配额后写入失败。

在 Storage Server 上查看配额：

```bash
sudo scripts/quota_manager.sh report
quota -u quotauser
```

## 测试 5：Samba 服务重启

在 Storage Server 上执行：

```bash
sudo testparm -s
sudo systemctl restart smbd nmbd
sudo systemctl is-active smbd nmbd
```

预期结果：

```text
active
active
```

## 测试 6：使用量统计输出

在 Storage Server 上执行：

```bash
sudo scripts/storage_usage_report.sh --format csv
sudo scripts/storage_usage_report.sh --format json
```

预期结果：每个有效用户目录都会输出 `username`、`path` 和 `used_kb`。
