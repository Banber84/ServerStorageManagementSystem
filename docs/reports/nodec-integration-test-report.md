# NodeC 一键接入测试报告

> 本文仅记录历史实测过程与结论。日常操作请查阅 `docs/deployment/`。

## 基本信息

```text
测试日期：2026-06-27
Storage Server：192.168.1.187，管理用户 a2
NodeC：192.168.1.215，管理用户 nodec1
NodeC 项目目录：/home/nodec1/ServerStorageManagementSystem
```

## 已通过项目

```text
1. Storage Server 可以通过 SSH 登录 NodeC。
2. NodeC 已安装 cifs-utils 和 libpam-mount。
3. NodeC 的 Storage Server 地址为 192.168.1.187。
4. Storage Server 与 NodeC 双向 SSH 公钥配置成功。
5. Storage Server 与 NodeC 的同步 sudoers 校验通过。
6. NodeC 已加入项目节点清单。
7. alice 在 NodeC 登录后可以自动挂载并访问个人文件。
8. alice、bob、testsync 无需重新输入密码即可同步 shadow 哈希。
9. NodeC Agent 自动安装并在管理后台持续在线。
10. Storage Server 创建 nodeverify 后，NodeA、NodeB、NodeC 均成功创建用户。
11. nodeverify 在 NodeC 写入的文件可以在 NodeA 读取和修改。
12. NodeC 可以发起 nodecfromc 的创建与删除同步。
13. storage-usage-sync.timer 已启用，后台页面用量显示正确。
14. Windows 资源管理器可以通过 NodeA、NodeB、NodeC 的 SMB Gateway 访问共享。
15. join_node.sh 可以在接入 NodeC 时自动安装并检查 SMB Gateway。
16. leave_node.sh 已完成 NodeC 实机退出测试，Gateway、Agent、同步 sudoers、
    双向 SSH key、节点清单和后台记录均成功清理。
17. ssmsctl 已安装到 Storage Server，后台、Agent、用量定时器和健康检查正常。
```

## 测试中发现并修复的问题

### 1. SSH 身份不统一

初版脚本通过 `sudo` 运行后使用 root 发起 SSH，导致重复输入节点密码。
现已统一使用指定的 Storage Server 管理用户发起 SSH 和 SCP。

### 2. 远端 sudo 输入冲突

初版脚本通过 SSH 标准输入同时传输 sudoers 内容和读取 sudo 密码，
导致认证提示混乱。现已编码 sudoers 内容，使终端只负责密码输入。

### 3. Storage Server 地址错误

初次安装沿用了示例地址 `192.168.56.10`。现已在安装节点客户端前，
根据 `--storage-host` 强制生成节点运行配置。

### 4. 临时配置文件不可读

root 创建的临时配置权限为 `0600`，指定的管理用户无法通过 SCP 读取。
现已在传输前设置为 `0644`，传输结束后立即删除。

### 5. 旧用户需要重复输入密码

现改为由 Storage Server root 读取 Linux shadow 中的不可逆密码哈希，
经 SSH 管道写入新节点。无需保存或输入明文统一密码。

### 6. 运行时节点清单可能遗漏 NodeC

现同时更新：

```text
configs/nodes.conf
/etc/ssms/nodes.conf
configs/site.env 中的 SSMS_NODES（文件存在时）
```

### 7. 新节点没有自动部署 Agent

现由 `join_node.sh` 自动安装、配置并启动 `storage-agent`。

### 8. 删除同步只处理第一个节点

`sync_delete_user.sh` 的 SSH 命令读取了节点清单标准输入，删除第一个节点后
吞掉剩余行。现已为 SSH 增加 `-n`；使用 `--nodes-only --no-backend`
补跑后，NodeA、NodeB、NodeC 均完成删除。

### 9. 节点名称大小写不一致

Linux hostname 保持小写 `nodec`，SSMS 显示名称统一为 `NodeC`。
项目配置、运行时配置和 `site.env` 已统一。

### 10. 用户存储用量刷新较慢

通过 Windows 资源管理器向 bob 的共享目录写入约 700 MB 文件后，管理后台
较长时间才显示新用量。原因是 `storage-usage-sync.timer` 原先每 5 分钟
执行一次，另有最多 30 秒随机延迟，且存储统计页面不会自动刷新。

现调整为：

```text
Storage Server 启动后 30 秒执行首次用量同步
之后每 1 分钟执行一次用量同步
存储统计页面每 30 秒自动刷新
```

项目检查已通过；部署后预期最迟约 1 分 30 秒在页面看到变化。

### 11. 运维入口分散

节点、用户、配额、Gateway、用量同步和系统检查原先需要分别记忆多个脚本。
现新增统一命令 `ssmsctl`，保留原脚本作为底层实现，支持：

```text
ssmsctl node ...
ssmsctl user ...
ssmsctl quota ...
ssmsctl gateway ...
ssmsctl usage ...
ssmsctl backend ...
ssmsctl system ...
```

Storage Server、管理后台和节点客户端安装脚本都会将其安装到
`/usr/local/bin/ssmsctl`。

## ssmsctl Storage Server 实测

在 Storage Server 更新项目并重新执行 `install_management_server.sh` 后，
`ssmsctl` 成功安装。实际状态如下：

```text
storage-server.service        loaded  active
storage-usage-sync.timer      loaded  active
storage-agent.service         loaded  active
ssms-smb-gateway.socket       not-found inactive
```

Storage Server 本机不安装节点 Gateway，因此最后一项为 `not-found` 符合预期。
后台健康检查返回：

```json
{"status":"ok"}
```

一分钟用量同步定时器已生效，最近一次同步服务以 `status=0/SUCCESS` 完成：

```text
alice       15015936 bytes
bob         813105152 bytes
nodeverify  20480 bytes
testsync    16384 bytes
```

其中 bob 约 700 MB 测试文件的用量已正确写入管理后台。

## NodeC 生命周期实测

### 重新加入

```bash
sudo scripts/join_node.sh NodeC 192.168.1.215 nodec1 \
  --storage-user a2 \
  --storage-host 192.168.1.187 \
  --storage-project /home/a2/ServerStorageManagementSystem
```

结果：节点客户端、现有用户、Agent、同步权限和 SMB Gateway 均完成配置。
接入过程中仍需要多次输入 SSH 登录密码或远端 sudo 密码，后续可继续优化
认证交互。

### 完整退出

```bash
sudo scripts/leave_node.sh NodeC --storage-user a2
```

实际结果：

```text
SMB 网关已卸载。
NodeC 的 SMB 网关已停止并卸载。
后台节点已删除：NodeC
节点已移除：NodeC (192.168.1.215)
节点本地用户和 Storage Server 共享数据均未删除。
```

退出流程执行完成且未报错，验证了 Gateway 会随节点生命周期自动卸载。

## ssmsctl NodeC 待回归

NodeC 当前处于已退出状态。下一步使用统一命令重新加入：

```bash
sudo ssmsctl node join NodeC 192.168.1.215 nodec1
```

该步骤将验证 `ssmsctl` 对完整接入流程的参数转发，并由 `join_node.sh`
继续完成项目复制、现有用户同步、Agent、sudoers 和 SMB Gateway 安装。
尚未取得本次命令输出，因此暂不标记为通过。

## 后续检查命令

重新加入 NodeC 后检查节点、Agent 和 Gateway：

```bash
ssmsctl node list
ssmsctl gateway status NodeC
ssh nodec1@192.168.1.215 'systemctl is-active storage-agent'
ssh nodec1@192.168.1.215 \
  'systemctl is-active ssms-smb-gateway.socket; sudo ss -ltnp "sport = :445"'
curl http://192.168.1.187:8080/api/servers
```

检查项目：

```bash
scripts/check_project.sh
```
