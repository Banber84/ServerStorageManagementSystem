# 三虚拟机完整联调测试报告

## 基本信息

```text
测试日期：2026-06-21
系统版本：Ubuntu 26.04 Server
安装介质：ubuntu-26.04-live-server-amd64
测试范围：Storage Server、NodeA、NodeB 三虚拟机联调
Storage Server IP：192.168.1.187
NodeA：192.168.1.122，登录用户 nodea1
NodeB：192.168.1.125，登录用户 nodeb1
项目目录：~/ServerStorageManagementSystem
```

本次测试在已经完成 Storage Server 单机测试的基础上，继续验证登录节点自动挂载、跨节点共享访问和用户隔离。

## 测试目标

```text
1. NodeA 和 NodeB 可以访问 Storage Server 的 Samba 共享。
2. alice 在 NodeA 和 NodeB 上可以挂载同一份个人目录。
3. NodeA 创建的文件可以在 NodeB 上看到。
4. NodeB 创建的文件可以在 NodeA 上看到。
5. alice 登录节点后可以自动挂载 /home/alice/storage。
6. bob 登录后不能看到 alice 的文件。
7. Samba 用户隔离、Linux 权限隔离和 pam_mount 自动挂载均正常。
```

## 测试前置条件

Storage Server 已完成：

```text
1. Samba 服务已安装并运行。
2. /srv/samba/users 已创建。
3. alice、bob 已在 Storage Server 上创建为 Linux 用户和 Samba 用户。
4. alice、bob 的用户目录权限为 0700。
5. 用户 quota 已启用。
6. Storage Server 地址为 192.168.1.187。
```

NodeA 和 NodeB 已完成：

```text
1. 项目目录 ~/ServerStorageManagementSystem 已存在。
2. configs/system.conf 中 STORAGE_SERVER="192.168.1.187"。
3. install_node_client.sh 已安装 cifs-utils 和 libpam-mount。
4. /etc/security/pam_mount.conf.xml 已写入 Storage Server 地址。
5. 本地登录用户 alice、bob 已创建。
6. 节点本地 alice、bob 的密码与 Storage Server 上对应 Samba 密码一致。
```

## 测试步骤与结果

### 1. NodeA 手动挂载 alice 共享

在 NodeA 上执行：

```bash
sudo mkdir -p /mnt/ssms-alice
sudo mount -t cifs //192.168.1.187/alice /mnt/ssms-alice \
  -o username=alice,vers=3.0,sec=ntlmssp,uid=$(id -u alice),gid=$(id -g alice),file_mode=0600,dir_mode=0700
sudo -u alice touch /mnt/ssms-alice/manual-node01.txt
sudo -u alice ls -l /mnt/ssms-alice
sudo umount /mnt/ssms-alice
```

实测结果：

```text
NodeA 手动挂载 //192.168.1.187/alice 成功。
NodeA 可以在 alice 共享目录中创建 manual-node01.txt。
```

结论：NodeA 到 Storage Server 的 Samba 访问正常。

### 2. NodeB 手动挂载 alice 共享

在 NodeB 上首次执行手动挂载时，发现本地没有 `alice` 用户：

```text
id: 'alice': no such user
```

处理方式：

```bash
sudo scripts/create_node_user.sh alice
id alice
```

重新挂载：

```bash
sudo mkdir -p /mnt/ssms-alice
sudo mount -t cifs //192.168.1.187/alice /mnt/ssms-alice \
  -o username=alice,vers=3.0,sec=ntlmssp,uid=$(id -u alice),gid=$(id -g alice),file_mode=0600,dir_mode=0700
mount | grep /mnt/ssms-alice
sudo -u alice ls -l /mnt/ssms-alice
sudo -u alice touch /mnt/ssms-alice/manual-nodeb.txt
sudo -u alice ls -l /mnt/ssms-alice
sudo umount /mnt/ssms-alice
```

实测结果：

```text
NodeB 手动挂载 //192.168.1.187/alice 成功。
NodeB 可以看到 NodeA 创建的 manual-node01.txt。
NodeB 可以创建 manual-nodeb.txt。
```

说明：

```text
普通用户 nodeb1 执行 ls -l /mnt/ssms-alice 时出现 Permission denied。
这是预期行为，因为挂载参数将目录权限映射为 uid=alice、gid=alice、dir_mode=0700。
使用 sudo ls 或 sudo -u alice ls 可以正常查看。
```

结论：NodeB 到 Storage Server 的 Samba 访问正常，权限映射符合设计。

### 3. NodeB 登录自动挂载

在 NodeB 上执行：

```bash
su - alice
mount | grep /home/alice/storage
ls -l /home/alice/storage
touch /home/alice/storage/auto-nodeb.txt
exit
```

实测结果：

```text
alice 登录 NodeB 后，/home/alice/storage 自动挂载成功。
自动挂载目录中可以看到 NodeA 和 NodeB 手动挂载测试创建的文件。
NodeB 可以通过自动挂载目录创建 auto-nodeb.txt。
```

结论：NodeB 的 pam_mount 自动挂载生效。

### 4. NodeA 验证 NodeB 写入文件

在 NodeA 上执行：

```bash
su - alice
ls -l /home/alice/storage
exit
```

实测结果：

```text
NodeA 可以看到 NodeB 创建的 manual-nodeb.txt 和 auto-nodeb.txt。
```

结论：alice 在 NodeA 和 NodeB 上访问的是 Storage Server 上的同一份个人数据。

### 5. bob 用户隔离测试

在节点上以 bob 登录：

```bash
su - bob
mount | grep /home/bob/storage
ls -l /home/bob/storage
exit
```

实测结果：

```text
bob 登录后看不到 alice 的文件。
```

结论：用户隔离生效，bob 不能访问 alice 的数据。

### 6. NodeA 发起用户同步测试

测试目标：验证登录节点也可以作为用户创建入口，由节点请求 Storage Server 统一同步三方用户。

在 NodeA 上执行：

```bash
cd ~/ServerStorageManagementSystem
scripts/request_user_sync.sh nodecreate1 --quota-gb 1
```

执行过程中输入两次统一密码。随后脚本通过 SSH 调用 Storage Server：

```text
向 Storage Server 发起用户同步：a2@192.168.1.187
```

实测结果：

```text
Storage Server 成功创建 nodecreate1 的 Linux 用户。
Storage Server 成功创建 nodecreate1 的 Samba 用户。
Storage Server 成功为 nodecreate1 设置 1 GB quota。
Storage Server 继续同步 NodeA、NodeB 上的同名登录用户。
```

结论：NodeA 作为同步发起端的主流程可用。

说明：本次测试中，NodeA 发起请求时仍需要输入 Storage Server 上 `a2` 用户的 SSH 登录密码。该行为不影响功能正确性，但会影响自动化体验。后续已明确通过 SSH key 配置免密登录来优化。

### 7. SSH 免密优化验证项

为实现“节点一键发起同步”，需要配置 NodeA/NodeB 到 Storage Server 的 SSH key。

NodeA 上执行：

```bash
ssh-keygen -t ed25519
ssh-copy-id a2@192.168.1.187
ssh a2@192.168.1.187 'hostname'
```

NodeB 上执行：

```bash
ssh-keygen -t ed25519
ssh-copy-id a2@192.168.1.187
ssh a2@192.168.1.187 'hostname'
```

Storage Server 上确认 sudoers：

```text
a2 ALL=(ALL) NOPASSWD: /home/a2/ServerStorageManagementSystem/scripts/sync_user.sh
```

验证命令：

```bash
ssh a2@192.168.1.187 'sudo /home/a2/ServerStorageManagementSystem/scripts/sync_user.sh --help'
```

预期结果：

```text
直接显示 sync_user.sh 用法，不再要求输入 a2 密码。
```

### 8. 三方删除同步测试

测试目标：验证 Storage Server、NodeA、NodeB 均可作为删除同步发起端，最终删除三方同名用户。

#### 8.1 Storage Server 发起删除

在 Storage Server 上执行：

```bash
cd ~/ServerStorageManagementSystem
sudo scripts/sync_delete_user.sh nodecreate2
```

实测结果：

```text
Storage Server 成功删除 nodecreate2 的 Samba 用户和 Linux 用户。
Storage Server 将 /srv/samba/users/nodecreate2 归档为 _deleted_nodecreate2_时间。
Storage Server 同步删除 NodeA、NodeB 上的 nodecreate2 本地登录用户。
```

结论：Storage Server 作为删除同步发起端测试通过。

#### 8.2 NodeA 发起删除

在 NodeA 上执行：

```bash
cd ~/ServerStorageManagementSystem
scripts/request_user_delete.sh nodecreate3
```

实测结果：

```text
NodeA 成功请求 Storage Server 执行删除同步。
Storage Server 成功删除 nodecreate3 的 Samba 用户和 Linux 用户。
Storage Server 成功同步删除 NodeA、NodeB 上的 nodecreate3 本地登录用户。
```

结论：NodeA 作为删除同步发起端测试通过。

#### 8.3 NodeB 发起删除

在 NodeB 上执行：

```bash
cd ~/ServerStorageManagementSystem
scripts/request_user_delete.sh nodecreate4
```

实测结果：

```text
NodeB 成功请求 Storage Server 执行删除同步。
Storage Server 成功删除 nodecreate4 的 Samba 用户和 Linux 用户。
Storage Server 成功同步删除 NodeA、NodeB 上的 nodecreate4 本地登录用户。
```

结论：NodeB 作为删除同步发起端测试通过。

## 测试结论

三虚拟机完整联调测试通过。

已验证功能：

```text
1. NodeA 手动挂载 //192.168.1.187/alice 成功。
2. NodeB 手动挂载 //192.168.1.187/alice 成功。
3. NodeB 能看到 NodeA 创建的 manual-node01.txt。
4. NodeB 能创建 manual-nodeb.txt。
5. alice 登录 NodeB 后，/home/alice/storage 自动挂载成功。
6. NodeA 能看到 NodeB 创建的文件。
7. alice 在不同节点访问同一份共享数据。
8. bob 登录后看不到 alice 的文件。
9. Samba 用户隔离、Linux 权限隔离、pam_mount 自动挂载、跨节点共享访问均通过。
10. NodeA 可以作为用户同步发起端，请求 Storage Server 创建并同步用户。
11. Storage Server 可以作为删除同步发起端，删除三方用户。
12. NodeA 可以作为删除同步发起端，删除三方用户。
13. NodeB 可以作为删除同步发起端，删除三方用户。
```

## 本次测试发现的问题与处理

### 1. NodeB 缺少本地 alice 用户

现象：

```text
id: 'alice': no such user
```

原因：

```text
NodeB 尚未创建本地 Linux 登录用户 alice。
手动挂载命令中的 uid=$(id -u alice)、gid=$(id -g alice) 无法解析。
```

处理：

```bash
sudo scripts/create_node_user.sh alice
```

结果：问题解决。

### 2. nodeb1 查看 alice 挂载目录被拒绝

现象：

```text
ls: cannot open directory '/mnt/ssms-alice': Permission denied
```

原因：

```text
CIFS 挂载使用 uid=alice、gid=alice、dir_mode=0700。
这表示只有 alice 或 root 可以访问该挂载目录。
nodeb1 不是 alice，因此访问被拒绝是正确的权限隔离表现。
```

验证：

```bash
sudo ls -l /mnt/ssms-alice
sudo -u alice ls -l /mnt/ssms-alice
```

结果：root 和 alice 均可查看，权限设计正确。

### 3. NodeA 发起同步时仍需输入 a2 SSH 密码

现象：

```text
a2@192.168.1.187's password:
```

原因：

```text
NodeA 尚未配置到 Storage Server 的 SSH key 免密登录。
request_user_sync.sh 需要通过 SSH 调用 Storage Server 上的 sync_user.sh，因此会要求输入 a2 的 SSH 密码。
```

处理：

```bash
ssh-keygen -t ed25519
ssh-copy-id a2@192.168.1.187
ssh a2@192.168.1.187 'sudo /home/a2/ServerStorageManagementSystem/scripts/sync_user.sh --help'
```

结果：配置 SSH key 后，节点发起同步时只需要输入新用户统一密码，不需要再输入 `a2` SSH 密码。

### 4. 删除同步时远程 sudo 需要免密权限

现象：

```text
sudo: A terminal is required to authenticate
sudo: interactive authentication is required
```

原因：

```text
删除同步需要跨机器执行 sudo scripts/delete_node_user.sh 或 sudo scripts/sync_delete_user.sh。
如果 sudoers 未配置 NOPASSWD，远程 SSH 命令无法交互输入 sudo 密码。
```

处理：

Storage Server 上允许 a2 被节点远程调用删除同步脚本：

```text
a2 ALL=(ALL) NOPASSWD: /home/a2/ServerStorageManagementSystem/scripts/sync_delete_user.sh
```

NodeA 上允许 nodea1 被 Storage Server 远程调用节点删除脚本：

```text
nodea1 ALL=(ALL) NOPASSWD: /home/nodea1/ServerStorageManagementSystem/scripts/delete_node_user.sh
```

NodeB 上允许 nodeb1 被 Storage Server 远程调用节点删除脚本：

```text
nodeb1 ALL=(ALL) NOPASSWD: /home/nodeb1/ServerStorageManagementSystem/scripts/delete_node_user.sh
```

验证：

```bash
ssh a2@192.168.1.187 'sudo -n /home/a2/ServerStorageManagementSystem/scripts/sync_delete_user.sh --help'
ssh nodea1@192.168.1.122 'sudo -n /home/nodea1/ServerStorageManagementSystem/scripts/delete_node_user.sh --help'
ssh nodeb1@192.168.1.125 'sudo -n /home/nodeb1/ServerStorageManagementSystem/scripts/delete_node_user.sh --help'
```

结果：配置后删除同步测试通过。

## 后续建议

```text
1. 在 docs/deployment/node-client.md 中补充 Permission denied 排错说明。
2. 若需要长期运行节点状态采集 Agent，可继续补充 systemd 服务文件。
3. 后续可以把用户同步脚本和后台 API 对接，实现创建用户后自动写入后台 users 表。
4. 后续可以把删除同步脚本和后台 API 对接，实现删除用户后自动删除后台 users 表记录。
```
