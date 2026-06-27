# 用户同步方案

## 目标

在不使用 Active Directory、LDAP、Kerberos 的前提下，实现 Storage Server、NodeA、NodeB 三台服务器的用户同步。

同步效果：

```text
1. 在 Storage Server 上创建 Linux/Samba 存储用户。
2. 在 NodeA、NodeB 上创建同名 Linux 登录用户。
3. 三方使用同一个密码。
4. 用户登录 NodeA 或 NodeB 后，由 pam_mount 自动挂载个人共享目录。
5. 删除用户时，也可以由 Storage Server 统一同步删除三方用户。
```

## 设计说明

本项目采用最简单稳定的中心化同步方式：

```text
Storage Server
└── scripts/sync_user.sh
    ├── 调用 scripts/create_user.sh 创建 Storage Server 用户
    ├── SSH 到 NodeA 调用 scripts/create_node_user.sh
    └── SSH 到 NodeB 调用 scripts/create_node_user.sh

Storage Server
└── scripts/sync_delete_user.sh
    ├── 调用 scripts/delete_user.sh 删除 Storage Server 用户并归档数据
    ├── SSH 到 NodeA 调用 scripts/delete_node_user.sh
    └── SSH 到 NodeB 调用 scripts/delete_node_user.sh
```

该方案不需要新增常驻服务，不需要消息队列，不需要后台 Web 服务持有 root 权限。用户同步可以由管理员在 Storage Server 上执行，也可以由 NodeA/NodeB 通过 SSH 请求 Storage Server 统一执行。

## 前置条件

### 1. Storage Server 已部署

Storage Server 上已完成：

```bash
sudo scripts/install_storage_server.sh
sudo scripts/quota_manager.sh enable
```

### 2. NodeA/NodeB 已部署客户端

每台登录节点已完成：

```bash
sudo scripts/install_node_client.sh
```

### 3. 配置 SSH

Storage Server 必须能 SSH 登录每台节点。

推荐使用 SSH key，并让节点上的 SSH 用户可以免密执行 sudo：

```bash
sudo visudo
```

示例：

```text
nodea1 ALL=(ALL) NOPASSWD: /home/nodea1/ServerStorageManagementSystem/scripts/create_node_user.sh
nodeb1 ALL=(ALL) NOPASSWD: /home/nodeb1/ServerStorageManagementSystem/scripts/create_node_user.sh
nodea1 ALL=(ALL) NOPASSWD: /home/nodea1/ServerStorageManagementSystem/scripts/delete_node_user.sh
nodeb1 ALL=(ALL) NOPASSWD: /home/nodeb1/ServerStorageManagementSystem/scripts/delete_node_user.sh
```

如果项目目录不同，请改成实际路径。

说明：

```text
sync_user.sh 需要用 sudo 在 Storage Server 上执行。
脚本发起 SSH 时会优先使用执行 sudo 的原用户 SSH 配置。
例如 a2 执行 sudo scripts/sync_user.sh 时，SSH 会优先使用 a2 的 SSH key。
```

如果允许 NodeA/NodeB 作为同步发起端，还需要让节点 SSH 用户可以免密调用 Storage Server 上的同步脚本。

在 Storage Server 上执行：

```bash
sudo visudo
```

示例：

```text
a2 ALL=(ALL) NOPASSWD: /home/a2/ServerStorageManagementSystem/scripts/sync_user.sh
a2 ALL=(ALL) NOPASSWD: /home/a2/ServerStorageManagementSystem/scripts/sync_delete_user.sh
```

## 配置节点清单

编辑：

```bash
vim configs/nodes.conf
```

格式：

```text
节点名 主机地址 SSH用户 项目目录
```

示例：

```text
NodeA 192.168.1.188 nodea1 /home/nodea1/ServerStorageManagementSystem
NodeB 192.168.1.189 nodeb1 /home/nodeb1/ServerStorageManagementSystem
```

## 一键接入新节点

如果要加入一台新的登录节点，推荐在 Storage Server 上执行：

```bash
sudo scripts/join_node.sh nodeC 192.168.1.130 nodec1
```

该脚本会完成：

```text
1. 将 nodeC 写入 configs/nodes.conf。
2. 更新 configs/sync.conf 中的 Storage Server 连接信息。
3. 配置 Storage Server 与新节点的双向 SSH key。
4. 将 configs、scripts、docs 复制到新节点项目目录。
5. 将正确的 Storage Server 地址写入新节点配置并执行 install_node_client.sh。
6. 后续 SSH 和 SCP 均由指定的 Storage Server 管理用户发起。
7. 配置 Storage Server 和新节点两边的 sudoers 免密同步命令。
8. 验证创建和删除同步脚本可以远程调用。
9. 扫描 Storage Server 的现有用户并补建到新节点。
10. 安装 SMB 入口网关，使客户端可以通过节点 IP 访问共享。
11. 安装并启动 storage-agent，使新节点出现在管理后台。
```

节点会同时写入项目内 `configs/nodes.conf` 和运行时
`/etc/ssms/nodes.conf`。如果存在 `configs/site.env`，其中的 `SSMS_NODES`
也会同步更新，后续重新生成统一配置不会丢失该节点。

默认新节点项目目录为：

```text
/home/节点用户/ServerStorageManagementSystem
```

如果项目目录不同：

```bash
sudo scripts/join_node.sh nodeC 192.168.1.130 nodec1 \
  --node-project /home/nodec1/ServerStorageManagementSystem
```

如果 Storage Server 的 SSH 用户或项目目录不同：

```bash
sudo scripts/join_node.sh nodeC 192.168.1.130 nodec1 \
  --storage-user a2 \
  --storage-host 192.168.1.187 \
  --storage-project /home/a2/ServerStorageManagementSystem
```

脚本执行过程中，如果新节点还没有配置 SSH key，第一次连接需要输入新节点用户密码。安装客户端和配置远端 sudoers时，按提示输入新节点用户的 sudo 密码。

Storage Server 创建用户时会让 Linux 与 Samba 使用相同密码。接入新节点时，
脚本由 root 读取 Linux shadow 中不可逆的密码哈希，经 SSH 管道写入新节点，
因此无需保存或重新输入明文统一密码。哈希不会写入项目配置、日志或额外文件。
Storage Server 是密码哈希的权威来源；新节点已有同名用户时也会覆盖为该哈希，
确保节点登录密码与 Samba 密码保持一致。如果只接入基础设施、不补建现有用户，可以使用：

```bash
sudo scripts/join_node.sh nodeC 192.168.1.130 nodec1 --skip-existing-users
```

如果暂时不部署监控 Agent，可以使用 `--skip-agent`。默认管理后台地址读取
`backend.conf`，也可以使用 `--management-url` 显式指定。

如果不需要客户端通过该节点访问 SMB，可以使用 `--skip-smb-gateway`。

统一密码必须通过 `sync_user.sh` 创建或更新，不能只执行 `smbpasswd`，
否则 Storage Server 的 Linux shadow 哈希会与 Samba 密码不一致。

脚本的配置写入均可重复执行；某一步中断后可以使用相同参数重新运行。

接入完成后，可以直接测试从新节点发起创建：

```bash
ssh nodec1@192.168.1.130
cd ~/ServerStorageManagementSystem
scripts/request_user_sync.sh joincheck --quota-gb 1
```

也可以测试从 Storage Server 发起同步到所有节点：

```bash
sudo scripts/sync_user.sh joincheck2 --quota-gb 1
```

## 移除登录节点

在 Storage Server 上执行：

```bash
sudo scripts/leave_node.sh nodeC --storage-user a2
```

该命令会停止并卸载节点 SMB Gateway 和 Agent、删除同步 sudoers、撤销双向 SSH 公钥、
从项目和运行时节点清单删除该节点，并删除后台节点状态记录。
不会删除节点本地用户、用户 home 或 Storage Server 上的共享数据。

节点已离线且无法通过 SSH 清理时，可以使用 `--config-only` 只清理控制面记录。

## 同步创建用户

在 Storage Server 上执行：

```bash
sudo scripts/sync_user.sh alice --quota-gb 1
```

脚本会要求输入两次统一密码。该密码会用于：

```text
1. Storage Server 上的 Linux 用户 alice。
2. Storage Server 上的 Samba 用户 alice。
3. NodeA 上的 Linux 登录用户 alice。
4. NodeB 上的 Linux 登录用户 alice。
```

## 从 NodeA/NodeB 发起同步

先在节点上通过统一部署模板生成 Storage Server 连接配置：

```bash
cp configs/site.env.example configs/site.env
vim configs/site.env
scripts/apply_site_config.sh --config configs/site.env --output-dir configs
```

需要关注的字段：

```text
STORAGE_SYNC_HOST
STORAGE_SYNC_USER
STORAGE_SYNC_PROJECT_DIR
DEFAULT_SYNC_QUOTA_GB
```

在 NodeA 或 NodeB 上执行：

```bash
scripts/request_user_sync.sh alice --quota-gb 1
```

如果没有配置 SSH key，执行过程中会要求输入 Storage Server 上 `a2` 用户的 SSH 密码。功能可以正常完成，但不适合自动化。建议配置 SSH key 后再作为正式测试结果。

执行流程：

```text
1. 当前节点读取 `configs/sync.conf` 或 `/etc/ssms/sync.conf`。
2. 当前节点通过 SSH 登录 Storage Server。
3. Storage Server 执行 sudo scripts/sync_user.sh alice --quota-gb 1 --password-stdin。
4. Storage Server 创建/更新本机 Samba 用户。
5. Storage Server 再同步 NodeA、NodeB 上的同名 Linux 登录用户。
6. 用户登录节点后由 pam_mount 自动挂载个人目录。
```

验证 Storage Server 远程调用：

```bash
ssh a2@192.168.1.187 'sudo /home/a2/ServerStorageManagementSystem/scripts/sync_user.sh --help'
```

如果该命令不需要输入密码，并且直接显示 `sync_user.sh` 用法，说明节点发起同步所需的 SSH 和 sudo 权限已配置完成。

## 删除用户同步

在 Storage Server 上执行：

```bash
sudo scripts/sync_delete_user.sh alice
```

默认行为：

```text
1. Storage Server 删除 Samba 用户和 Linux 用户。
2. Storage Server 将 /srv/samba/users/alice 归档为 _deleted_alice_时间。
3. NodeA 删除本地 Linux 登录用户 alice 和 /home/alice。
4. NodeB 删除本地 Linux 登录用户 alice 和 /home/alice。
```

如果需要保留 Storage Server 上的数据目录：

```bash
sudo scripts/sync_delete_user.sh alice --keep-data
```

如果需要保留节点本地 home：

```bash
sudo scripts/sync_delete_user.sh alice --keep-node-home
```

如果只补删除节点用户：

```bash
sudo scripts/sync_delete_user.sh alice --nodes-only
```

从 NodeA/NodeB 发起删除：

```bash
scripts/request_user_delete.sh alice
```

验证 Storage Server 删除远程调用：

```bash
ssh a2@192.168.1.187 'sudo /home/a2/ServerStorageManagementSystem/scripts/sync_delete_user.sh --help'
```

## 只同步 Storage Server

```bash
sudo scripts/sync_user.sh alice --quota-gb 1 --storage-only
```

## 只同步登录节点

如果 Storage Server 上已经创建用户，只需要补同步节点：

```bash
sudo scripts/sync_user.sh alice --quota-gb 1 --nodes-only
```

## 验证

在 Storage Server 上：

```bash
id alice
pdbedit -L | grep '^alice:'
ls -ld /srv/samba/users/alice
```

在 NodeA/NodeB 上：

```bash
id alice
su - alice
mount | grep /home/alice/storage
ls -l /home/alice/storage
exit
```

删除后验证：

```bash
id alice
pdbedit -L | grep '^alice:'
ls -ld /srv/samba/users/alice
```

在 NodeA/NodeB 上：

```bash
id alice
ls -ld /home/alice
```

## 注意事项

```text
1. sync_user.sh 需要在 Storage Server 上执行。
2. NodeA/NodeB 必须已经安装 pam_mount。
3. 用户登录节点时才会触发自动挂载。
4. 如果节点上用户已存在，脚本会同步更新该用户密码。
5. 如果 SSH 用户不能免密 sudo，远程同步会失败。
6. NodeA/NodeB 发起同步时，本质仍由 Storage Server 执行最终同步，避免多端状态不一致。
7. 删除用户前应确保该用户已经退出 NodeA/NodeB，否则 userdel 可能因为仍有进程运行而失败。
```
