# Storage Server 部署文档

全新 Ubuntu 虚拟机建议直接使用自动部署：

```bash
sudo scripts/ssmsctl system bootstrap --host 192.168.1.230
```

完整说明见 `docs/deployment/bootstrap-storage-server.md`。以下章节保留手工部署和
故障排查步骤。

## 1. 环境要求

本项目当前按 `ubuntu-26.04-live-server-amd64` 编写部署步骤。若 Ubuntu 安装在 Windows PC、双系统或虚拟机中，请先参考：

```text
docs/deployment/winpc-ubuntu26.md
```

Storage Server 建议使用固定 IP。本文示例：

```text
192.168.1.221
```

## 2. 安装 Ubuntu 软件包

```bash
sudo apt-get update
sudo apt-get install -y samba smbclient quota acl
```

也可以直接执行项目安装脚本：

```bash
sudo scripts/install_storage_server.sh
```

## 3. 配置文件

项目中的配置文件路径：

```text
configs/system.conf
configs/smb.conf
```

安装后的系统配置文件路径：

```text
/etc/ssms/system.conf
/etc/samba/smb.conf
```

默认用户存储根目录：

```text
/srv/samba/users
```

Samba 使用 `[homes]` 配置。用户 `alice` 的访问地址为：

```text
//<storage-server>/alice
```

## 4. 启用存储配额

查看 `/srv/samba/users` 所在文件系统：

```bash
findmnt --target /srv/samba/users
```

编辑 `/etc/fstab`，给对应文件系统增加 `usrquota,grpquota` 挂载参数。

如果使用独立数据盘，可以参考：

```text
UUID=xxxx-xxxx /srv/samba ext4 defaults,usrquota,grpquota 0 2
```

如果 `/srv/samba/users` 位于根分区 `/`，可以参考：

```text
UUID=xxxx-xxxx / ext4 errors=remount-ro,usrquota,grpquota 0 1
```

重新挂载并启用配额：

```bash
sudo mount -o remount /
sudo ssmsctl quota enable
# 原脚本：sudo scripts/quota_manager.sh enable
```

Ubuntu 26.04 的 ext4 quota 命令可能提示 external quota files 已废弃。这是兼容性警告，不影响课程测试中的用户配额功能。只要看到类似以下输出，即表示用户 quota 已启用：

```text
/dev/mapper/ubuntu--vg-ubuntu--lv [/]: user quotas turned on
```

如果 `/srv/samba/users` 位于独立挂载点，则重新挂载对应目录：

```bash
sudo mount -o remount /srv/samba
sudo ssmsctl quota enable
# 原脚本：sudo scripts/quota_manager.sh enable
```

## 5. 创建存储用户

```bash
sudo ssmsctl user create alice --quota-gb 10
# 仅排障时直接调用：sudo scripts/create_user.sh alice --quota-gb 10
```

脚本会完成以下工作：

```text
Linux 用户：alice
Samba 用户：alice
用户目录：/srv/samba/users/alice
目录权限：0700
存储配额：10 GB 硬限制，95% 软限制
```

## 6. 修改配额

```bash
sudo ssmsctl quota set alice 20
# 原脚本：sudo scripts/quota_manager.sh set alice 20
sudo ssmsctl quota report
# 原脚本：sudo scripts/quota_manager.sh report
```

`set` 命令默认同时更新 Linux quota 和 Go 管理后台记录。仅在后台维护或故障排查时使用：

```bash
sudo ssmsctl quota set alice 20 --no-backend
# 原脚本：sudo scripts/quota_manager.sh set alice 20 --no-backend
```

## 7. 删除用户

删除账号并归档用户数据：

```bash
sudo ssmsctl user delete alice
# 仅排障时直接调用：sudo scripts/delete_user.sh alice
```

删除账号但保留用户数据目录：

```bash
sudo ssmsctl user delete alice --keep-data
# 仅排障时直接调用：sudo scripts/delete_user.sh alice --keep-data
```

## 8. 验证 Samba

```bash
testparm -s
sudo systemctl status smbd nmbd
which smbclient
smbclient -L localhost -U alice
smbclient //localhost/alice -U alice -c 'mkdir testdir; rmdir testdir'
```

预期结果：

```text
testparm 无配置错误
smbd 和 nmbd 状态为 active
alice 可以访问自己的共享目录
alice 不能访问其他用户的共享目录
```
