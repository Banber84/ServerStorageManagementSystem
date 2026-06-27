# NodeC 一键接入测试报告

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

## 待实机回归

```text
1. 无需输入 alice、bob、testsync 密码即可同步其密码哈希。
2. /etc/ssms/nodes.conf 中包含 nodeC。
3. Storage Server 创建的新用户同时到达 NodeA、NodeB、NodeC。
4. NodeC 可以发起创建和删除同步。
5. NodeC 出现在管理后台并持续上报 CPU、内存、磁盘和在线状态。
6. storage-usage-sync.timer 每 5 分钟更新一次后台用量。
7. leave_node.sh 可以移除测试节点且不删除共享数据。
```

## 回归命令

在 Storage Server 重新运行接入：

```bash
sudo scripts/join_node.sh nodeC 192.168.1.215 nodec1 \
  --storage-user a2 \
  --storage-host 192.168.1.187 \
  --storage-project /home/a2/ServerStorageManagementSystem \
  --skip-install
```

检查节点与 Agent：

```bash
grep nodeC /etc/ssms/nodes.conf
ssh nodec1@192.168.1.215 'systemctl is-active storage-agent'
curl http://192.168.1.187:8080/api/servers
```

检查项目：

```bash
scripts/check_project.sh
```
