# 测试方案

## 测试环境

本项目当前按 `ubuntu-26.04-live-server-amd64` 编写部署步骤。Ubuntu 可以安装在 Windows PC 的虚拟机、双系统或物理机环境中。

第一版 demo 已验证的局域网测试环境：

```text
Management Server: 192.168.1.187
访问地址:          http://192.168.1.187:8080
```

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

## 第一版 demo 测试流程

第一版 demo 重点验证 Go 管理后台页面和 REST API 是否可用。管理后台运行在局域网服务器 `192.168.1.187`，页面访问地址为：

```text
http://192.168.1.187:8080
```

### 测试 1：页面访问

在浏览器打开：

```text
http://192.168.1.187:8080
```

预期结果：

- 管理后台首页可以正常打开。
- 页面显示用户数、节点数、存储统计和最近日志区域。

### 测试 2：用户管理

打开：

```text
http://192.168.1.187:8080/users
```

创建测试用户：

```text
用户名: alice
姓名: Alice
邮箱: alice@example.com
配额: 1073741824
```

预期结果：

- 用户表格出现 `alice`。
- 配额字段正常显示。
- 页面提供配额修改和删除入口。

### 测试 3：存储统计

通过 API 写入测试数据：

```bash
curl -X POST http://192.168.1.187:8080/api/storage \
  -H 'Content-Type: application/json' \
  -d '{"user_id":1,"used_bytes":1048576,"path":"/srv/samba/users/alice"}'
```

打开：

```text
http://192.168.1.187:8080/storage
```

预期结果：

- 页面显示用户 `alice`。
- 已用空间显示为 `1048576`。
- 剩余空间可以按配额自动计算。
- 路径显示为 `/srv/samba/users/alice`。

### 测试 4：节点状态

通过 API 模拟节点上报：

```bash
curl -X POST http://192.168.1.187:8080/api/servers/report \
  -H 'Content-Type: application/json' \
  -d '{"name":"node01","address":"192.168.1.187","cpu_usage":12.5,"memory_usage":40.2,"disk_usage":55.1}'
```

打开：

```text
http://192.168.1.187:8080/servers
```

预期结果：

- 页面显示 `node01`。
- 节点状态显示在线。
- CPU、内存、磁盘使用率正常显示。

### 测试 5：日志查看

写入测试日志：

```bash
curl -X POST http://192.168.1.187:8080/api/logs \
  -H 'Content-Type: application/json' \
  -d '{"type":"login","username":"alice","server_name":"node01","message":"user logged in"}'
```

打开：

```text
http://192.168.1.187:8080/logs
```

预期结果：

- 日志页面显示 `login` 类型日志。
- 用户显示为 `alice`。
- 节点显示为 `node01`。
- 日志内容显示为 `user logged in`。

### 测试 6：首页汇总

回到首页：

```text
http://192.168.1.187:8080
```

预期结果：

- 用户数量更新。
- 节点在线状态更新。
- 存储用量汇总更新。
- 最近日志显示刚写入的日志。

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

## Storage Server 单机实测记录

测试环境：

```text
系统：Ubuntu 26.04 Server
虚拟机 IP：192.168.1.187
登录用户：a2
测试范围：仅 Storage Server，Node01/Node02 尚未部署
```

实测结果：

```text
1. /srv/samba/users 位于根分区 /，文件系统为 ext4。
2. /etc/fstab 已为根分区增加 defaults,usrquota,grpquota。
3. findmnt 输出包含 rw,relatime,quota,usrquota,grpquota。
4. quota_manager.sh enable 成功启用用户 quota。
5. create_user.sh 成功创建 alice 和 bob。
6. /srv/samba/users/alice 与 /srv/samba/users/bob 权限均为 0700，属主分别为 alice 和 bob。
7. smbclient //localhost/alice -U alice 可以列目录、创建目录、删除目录。
8. smbclient //localhost/bob -U alice 访问失败，用户隔离生效。
9. storage_usage_report.sh 可输出 alice、bob 的 CSV 和 JSON 使用量，初始目录均约 16 KB。
10. alice 写入超过 1 GB 测试文件时出现 Disk quota exceeded，配额限制生效。
11. quota 测试文件已清理。
```

本次未覆盖：

```text
1. Node01/Node02 登录自动挂载。
2. 用户登录任意节点访问同一份数据。
3. pam_mount 登录触发挂载。
```

本次测试发现并已改进：

```text
1. install_storage_server.sh 增加 smbclient 安装，便于直接在 Storage Server 上完成 Samba 自测。
2. quota_manager.sh 与 delete_user.sh 过滤 Ubuntu 26.04 中可忽略的 tmpfs quota 警告。
3. quota_manager.sh report 改为只报告 STORAGE_ROOT 所在文件系统，减少无关挂载点噪声。
```

完整测试报告见：

```text
docs/deployment/storage-server-test-report.md
```
