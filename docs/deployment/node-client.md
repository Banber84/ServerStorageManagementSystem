# 登录节点部署文档

本文中的 IP 和用户名均为示例，实际值以 `configs/site.env` 和
`/etc/ssms` 运行配置为准。

以下步骤需要在 NodeA 和 NodeB 上分别执行。

## 1. 环境要求

本项目当前按 `ubuntu-26.04-live-server-amd64` 编写部署步骤。若 Ubuntu 安装在 Windows PC、双系统或虚拟机中，请先参考：

```text
docs/deployment/winpc-ubuntu26.md
```

登录节点建议使用固定 IP：

```text
NodeA: 192.168.56.11
NodeB: 192.168.56.12
```

## 2. 设置 Storage Server 地址

安装前编辑 `configs/system.conf`：

```bash
STORAGE_SERVER="192.168.1.221"
MOUNT_POINT_NAME="storage"
```

## 3. 安装客户端组件和 pam_mount

```bash
sudo scripts/install_node_client.sh
```

安装脚本会写入以下文件：

```text
/etc/ssms/system.conf
/etc/security/pam_mount.conf.xml
```

## 4. 创建本地登录用户

在每台登录节点上创建同名 Linux 用户：

```bash
sudo scripts/create_node_user.sh alice
```

该用户密码必须与 Storage Server 上创建的 Samba 密码一致。这样用户登录节点时，`pam_mount` 才能使用登录密码挂载个人共享目录。

## 5. 自动挂载行为

用户 `alice` 登录 NodeA 或 NodeB 后，系统会自动挂载：

```text
//192.168.1.221/alice -> /home/alice/storage
```

挂载参数配置在：

```text
configs/pam_mount.conf.xml
```

## 6. 手动挂载测试

如果需要在启用登录自动挂载前进行测试，可以执行：

```bash
sudo mkdir -p /mnt/ssms-alice
sudo mount -t cifs //192.168.1.221/alice /mnt/ssms-alice \
  -o username=alice,vers=3.0,sec=ntlmssp,uid=$(id -u alice),gid=$(id -g alice),file_mode=0600,dir_mode=0700
mount | grep /mnt/ssms-alice
sudo -u alice ls -l /mnt/ssms-alice
sudo umount /mnt/ssms-alice
```

如果当前登录用户不是 `alice`，直接执行 `ls -l /mnt/ssms-alice` 可能出现：

```text
Permission denied
```

这是正常现象。手动挂载参数中设置了 `uid=alice`、`gid=alice`、`dir_mode=0700`，表示只有 `alice` 或 `root` 可以查看该挂载目录。可以使用以下命令验证：

```bash
sudo ls -l /mnt/ssms-alice
sudo -u alice ls -l /mnt/ssms-alice
```

如果出现以下错误：

```text
id: 'alice': no such user
```

说明当前登录节点还没有创建本地 `alice` 用户，需要先执行：

```bash
sudo scripts/create_node_user.sh alice
```

## 7. 登录挂载测试

切换到用户 `alice`：

```bash
su - alice
mount | grep /home/alice/storage
touch /home/alice/storage/node-test.txt
```

也可以执行脚本检查：

```bash
scripts/test_mount.sh alice
```
