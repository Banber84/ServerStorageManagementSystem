# Storage Server 单机测试报告

> 本文仅记录历史实测过程与结论。日常操作请查阅 `docs/deployment/`。

## 测试环境

```text
测试日期：2026-06-16
系统版本：Ubuntu 26.04 Server
安装介质：ubuntu-26.04-live-server-amd64
虚拟机 IP：192.168.1.187
登录用户：a2
项目目录：~/ServerStorageManagementSystem
测试范围：Storage Server 单机测试
```

本次测试只覆盖成员 A 负责的 Storage Server 部署、Samba 共享、Linux 权限、quota 配额和使用量统计。NodeA、NodeB 尚未安装，因此自动挂载和跨节点访问暂未测试。

## 测试步骤与结果

### 1. 检查存储目录所在文件系统

执行命令：

```bash
findmnt --target /srv/samba/users
findmnt -no OPTIONS --target /srv/samba/users
```

实测结果：

```text
/srv/samba/users 位于根分区 /
文件系统为 ext4
启用前挂载参数为 rw,relatime
```

### 2. 启用 quota 挂载参数

修改 `/etc/fstab`，将根分区挂载参数从：

```text
defaults
```

改为：

```text
defaults,usrquota,grpquota
```

执行命令：

```bash
sudo mount -a
sudo mount -o remount /
findmnt -no OPTIONS --target /srv/samba/users
```

实测结果：

```text
rw,relatime,quota,usrquota,grpquota
```

结论：quota 挂载参数已生效。

### 3. 初始化并启用用户 quota

执行命令：

```bash
sudo scripts/quota_manager.sh enable
```

实测结果包含：

```text
/dev/mapper/ubuntu--vg-ubuntu--lv [/]: user quotas turned on
```

结论：用户 quota 已启用。

说明：Ubuntu 26.04 上 quota 命令输出了 `tmpfs` 和 ext4 external quota files 相关警告。该警告不影响本次课程测试，后续脚本已改进为过滤可忽略的 `tmpfs` 警告。

### 4. 创建测试用户

执行命令：

```bash
sudo scripts/create_user.sh alice --quota-gb 1
sudo scripts/create_user.sh bob --quota-gb 1
```

实测结果：

```text
alice 创建成功，Samba 用户启用成功，1 GB quota 设置成功。
bob 创建成功，Samba 用户启用成功，1 GB quota 设置成功。
```

### 5. 检查用户目录权限

执行命令：

```bash
ls -ld /srv/samba/users/alice /srv/samba/users/bob
```

实测结果：

```text
alice 目录属主为 alice，权限为 0700。
bob 目录属主为 bob，权限为 0700。
```

结论：Linux 文件权限隔离生效。

### 6. 测试 Samba 访问

执行命令：

```bash
smbclient //localhost/alice -U alice -c 'ls'
smbclient //localhost/alice -U alice -c 'mkdir testdir; rmdir testdir'
```

实测结果：

```text
alice 可以列出自己的共享目录。
alice 可以在自己的共享目录中创建并删除目录。
```

结论：Samba 认证和个人共享读写正常。

### 7. 测试用户隔离

执行命令：

```bash
smbclient //localhost/bob -U alice -c 'ls'
```

实测结果：

```text
alice 访问 bob 的共享目录失败。
```

结论：Samba 用户隔离生效，用户不能访问其他用户数据。

### 8. 测试使用量统计

执行命令：

```bash
sudo scripts/storage_usage_report.sh --format csv
sudo scripts/storage_usage_report.sh --format json
```

实测结果：

```text
alice 和 bob 均能正常输出。
初始目录使用量约为 16 KB。
```

结论：使用量统计脚本正常。

### 9. 测试 quota 限制

执行命令：

```bash
sudo -u alice dd if=/dev/zero of=/srv/samba/users/alice/quota-test.bin bs=100M count=12 status=progress
```

实测结果：

```text
dd: IO error: Disk quota exceeded
```

结论：alice 超过 1 GB 配额后写入失败，用户 quota 限制生效。

清理命令：

```bash
sudo rm -f /srv/samba/users/alice/quota-test.bin
```

清理结果：测试文件已删除。

## 测试结论

Storage Server 单机测试通过，已验证：

```text
1. Samba 服务和配置可用。
2. Linux 用户目录创建正常。
3. 用户目录权限隔离正常。
4. Samba 用户认证正常。
5. 用户不能访问其他用户共享目录。
6. 使用量统计脚本正常。
7. 用户 quota 限制正常。
```

待后续 NodeA、NodeB 部署后继续测试：

```text
1. 登录节点自动挂载。
2. 用户登录任意节点访问同一份数据。
3. pam_mount 登录触发挂载。
```

## 根据测试完成的项目改进

```text
1. install_storage_server.sh 增加 smbclient 安装，便于在 Storage Server 单机完成 Samba 自测。
2. quota_manager.sh 过滤 Ubuntu 26.04 中可忽略的 tmpfs quota 警告。
3. delete_user.sh 过滤删除用户清理 quota 时的 tmpfs 警告。
4. quota_manager.sh report 改为只报告 STORAGE_ROOT 所在文件系统，减少无关挂载点输出。
5. storage-server.md 增加 Ubuntu 26.04 quota 警告说明和 smbclient 检查步骤。
```
