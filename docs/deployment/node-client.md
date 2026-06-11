# 登录节点部署文档

以下步骤需要在 Node01 和 Node02 上分别执行。

## 1. 环境要求

本项目当前按 `ubuntu-26.04-live-server-amd64` 编写部署步骤。若 Ubuntu 安装在 Windows PC、双系统或虚拟机中，请先参考：

```text
docs/deployment/winpc-ubuntu26.md
```

登录节点建议使用固定 IP：

```text
Node01: 192.168.56.11
Node02: 192.168.56.12
```

## 2. 设置 Storage Server 地址

安装前编辑 `configs/system.conf`：

```bash
STORAGE_SERVER="192.168.56.10"
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

用户 `alice` 登录 Node01 或 Node02 后，系统会自动挂载：

```text
//192.168.56.10/alice -> /home/alice/storage
```

挂载参数配置在：

```text
configs/pam_mount.conf.xml
```

## 6. 手动挂载测试

如果需要在启用登录自动挂载前进行测试，可以执行：

```bash
sudo mkdir -p /mnt/ssms-alice
sudo mount -t cifs //192.168.56.10/alice /mnt/ssms-alice \
  -o username=alice,vers=3.0,sec=ntlmssp,uid=$(id -u alice),gid=$(id -g alice),file_mode=0600,dir_mode=0700
df -h /mnt/ssms-alice
sudo umount /mnt/ssms-alice
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
