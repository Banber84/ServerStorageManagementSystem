# WinPC 安装 Ubuntu 26.04 Server 说明

本项目实际部署环境为 Windows PC 上安装 `ubuntu-26.04-live-server-amd64`。可以采用物理机直接安装、双系统安装，或在 Windows 上使用虚拟机安装。为了让 Storage Server、Node01、Node02 能互相访问，重点是网络地址固定、磁盘分区明确、SSH 可用。

## 1. 安装介质

建议使用文件：

```text
ubuntu-26.04-live-server-amd64.iso
```

如果文件名写作 `ubuntu26.04-live-server-amd64`，实际使用时请确认它是 `.iso` 镜像文件。

## 2. 机器规划

最小测试环境可以使用三台机器或三台虚拟机：

```text
Storage Server: 192.168.56.10
Node01:         192.168.56.11
Node02:         192.168.56.12
```

如果只有一台 WinPC，可以在虚拟机中创建三台 Ubuntu Server。虚拟机网络建议使用同一个 Host-only 或桥接网络，确保三台 Ubuntu 可以互相 `ping` 通。

## 3. Ubuntu 安装选项

安装 Ubuntu Server 时建议选择：

```text
语言：English 或中文均可
键盘：按实际键盘选择
网络：配置静态 IP
存储：Storage Server 建议预留独立数据盘或独立分区
OpenSSH Server：安装
其他 snaps：不需要
```

Storage Server 如果有独立数据盘，建议挂载到：

```text
/srv/samba
```

如果只是课程测试，也可以直接使用根分区 `/`，但启用 quota 时需要给根分区增加 `usrquota,grpquota`。

## 4. 静态 IP 示例

Ubuntu Server 26.04 使用 netplan 管理网络。网卡名请用 `ip addr` 查看，常见名称如 `ens33`、`enp0s3`、`eth0`。

示例文件：

```text
/etc/netplan/01-ssms.yaml
```

示例内容：

```yaml
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: false
      addresses:
        - 192.168.56.10/24
      routes:
        - to: default
          via: 192.168.56.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
```

应用配置：

```bash
sudo netplan apply
ip addr
ping -c 3 192.168.56.11
```

Node01 和 Node02 只需要把 `addresses` 分别改成 `192.168.56.11/24`、`192.168.56.12/24`。

## 5. 基础检查

每台 Ubuntu 安装完成后执行：

```bash
lsb_release -a
uname -m
ip addr
sudo systemctl status ssh
```

预期结果：

```text
Ubuntu 26.04
x86_64
SSH 服务 active
Storage Server、Node01、Node02 可以互相 ping 通
```

## 6. 从 WinPC 连接 Ubuntu

Windows 上可以使用 PowerShell 连接：

```powershell
ssh 用户名@192.168.56.10
ssh 用户名@192.168.56.11
ssh 用户名@192.168.56.12
```

如果无法连接，优先检查：

```bash
sudo systemctl status ssh
sudo ufw status
ip route
```

课程测试环境中可以先关闭防火墙排除干扰：

```bash
sudo ufw disable
```

正式环境不建议长期关闭防火墙，应按需放行 SSH 和 Samba 端口。

## 7. 后续部署顺序

建议按以下顺序继续：

```text
1. 在 Storage Server 上部署 Samba、用户目录和 quota。
2. 在 Node01、Node02 上部署 cifs-utils 和 pam_mount。
3. 创建测试用户 alice、bob。
4. 测试用户隔离、跨节点访问、自动挂载和配额限制。
```
