# 登录节点 SMB 入口网关

## 目标

Windows 资源管理器或 macOS 可以连接任意登录节点 IP，并访问 Storage Server
上的同一份 Samba 共享：

```text
\\192.168.1.122\alice
\\192.168.1.125\alice
\\192.168.1.215\alice
```

节点不运行第二套 Samba 存储服务，也不保存 Samba 用户密码。节点使用
`systemd-socket-proxyd` 把本机 TCP 445 双向转发到 Storage Server TCP 445：

```text
客户端 -> 登录节点:445 -> Storage Server:445 -> /srv/samba/users
```

认证、用户隔离、quota 和文件锁仍全部由 Storage Server 负责。

## 批量安装

在 Storage Server 上执行：

```bash
sudo scripts/deploy_smb_gateways.sh
```

脚本读取 `/etc/ssms/nodes.conf`，依次为 NodeA、NodeB、NodeC 安装网关。
首次测试时可以只部署 NodeC：

```bash
sudo scripts/deploy_smb_gateways.sh --node NodeC
```

新节点通过 `join_node.sh` 接入时会默认安装；需要跳过时使用：

```bash
sudo scripts/join_node.sh NodeC 192.168.1.215 nodec1 --skip-smb-gateway
```

即使使用 `--skip-copy`，接入脚本仍会单独复制 Gateway 安装脚本和 systemd
socket 模板。安装完成后，脚本会确认 `ssms-smb-gateway.socket` 正在运行、
TCP 445 正在监听且转发目标为当前 Storage Server。

## 单节点安装

在登录节点执行：

```bash
sudo scripts/install_smb_gateway.sh --storage-server 192.168.1.187
```

检查：

```bash
systemctl is-active ssms-smb-gateway.socket
sudo ss -ltnp 'sport = :445'
```

如果启用了 UFW，需要允许局域网访问 TCP 445。

## 客户端测试

Windows 资源管理器地址栏：

```text
\\192.168.1.215\alice
```

macOS Finder：

```text
smb://192.168.1.215/alice
```

使用 Storage Server 上 `alice` 的 Samba 用户名和统一密码登录。

## 卸载

在节点执行：

```bash
sudo scripts/install_smb_gateway.sh --uninstall
```

`leave_node.sh` 会自动卸载该节点网关。

## NodeC 离开与重新加入测试

所有命令均在 Storage Server 上执行。先让 NodeC 离开：

```bash
sudo scripts/leave_node.sh NodeC --storage-user a2
```

脚本会先在 NodeC 停止并卸载 Gateway，确认 socket、service 和 systemd unit
均无残留，然后清理 Agent、SSH key、节点清单和后台记录。NodeC 本地用户及
Storage Server 上的共享数据不会被删除。

确认离开结果：

```bash
grep -w NodeC configs/nodes.conf /etc/ssms/nodes.conf || echo "节点清单已清理"
ssh nodec1@192.168.1.215 \
  'systemctl is-active ssms-smb-gateway.socket || true; sudo ss -ltnp "sport = :445"'
```

重新接入 NodeC：

```bash
sudo scripts/join_node.sh NodeC 192.168.1.215 nodec1 \
  --storage-user a2 \
  --storage-host 192.168.1.187 \
  --storage-project /home/a2/ServerStorageManagementSystem
```

确认重新加入结果：

```bash
ssh nodec1@192.168.1.215 \
  'systemctl is-active ssms-smb-gateway.socket; sudo ss -ltnp "sport = :445"'
```

最后从 Windows 资源管理器访问 `\\192.168.1.215\alice`，确认 Gateway
仍使用 Storage Server 的 Samba 账号并能看到原有文件。

## 限制

- 网关只增加访问入口，不复制文件，也不提供 Storage Server 高可用。
- Storage Server 停机后，所有节点入口均无法访问共享。
- 客户端到节点、节点到 Storage Server 会产生两段网络传输。
- 仅代理现代 SMB 使用的 TCP 445，不提供 NetBIOS 137-139 端口。
- 节点本机不能同时运行占用 TCP 445 的 Samba 服务。
- Windows 同一登录会话对同一服务器名称只能使用一套 SMB 凭据。切换测试
  用户前可执行 `net use * /delete /y`，正常使用建议一个 Windows 用户对应
  一个存储用户。

## 实测记录

```text
测试日期：2026-06-27
NodeA：192.168.1.122，Windows 资源管理器访问通过
NodeB：192.168.1.125，Windows 资源管理器访问通过
NodeC：192.168.1.215，Windows 资源管理器访问通过
后端存储：192.168.1.187
```

三个入口均使用 Storage Server 上的 Samba 账号认证，并访问同一份用户数据。
