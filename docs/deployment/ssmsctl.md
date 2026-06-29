# ssmsctl 统一管理命令

## 目标

`ssmsctl` 是 SSMS 的统一命令入口。它不重复实现用户、配额、节点和 Gateway
逻辑，而是调用项目中已经验证过的脚本，因此原脚本仍然可以独立使用。

Storage Server、管理后台或登录节点执行对应安装脚本后，命令会安装到：

```text
/usr/local/bin/ssmsctl
```

查看总帮助：

```bash
ssmsctl --help
```

查看分组帮助：

```bash
ssmsctl node --help
ssmsctl user --help
ssmsctl quota --help
ssmsctl gateway --help
ssmsctl usage --help
ssmsctl system --help
```

## 节点管理

在 Storage Server 上执行：

```bash
sudo ssmsctl node join NodeC 192.168.1.215 nodec1
sudo ssmsctl node leave NodeC --storage-user a2
ssmsctl node list
```

`node join` 和 `node leave` 的附加参数会原样传递给 `join_node.sh` 和
`leave_node.sh`。

## 用户管理

Storage Server 创建或删除用户并同步全部节点：

```bash
ssmsctl user list
ssmsctl user list --format json
sudo ssmsctl user create alice --quota-gb 10
sudo ssmsctl user delete alice
```

登录节点向 Storage Server 发起请求：

```bash
ssmsctl user request-create alice --quota-gb 10
ssmsctl user request-delete alice
```

## 配额与用量

```bash
sudo ssmsctl quota enable
sudo ssmsctl quota set alice 20
sudo ssmsctl quota report
sudo ssmsctl usage sync
sudo ssmsctl usage report --format json
```

## SMB Gateway

Storage Server 批量部署：

```bash
sudo ssmsctl gateway deploy
sudo ssmsctl gateway deploy --node NodeC
```

在登录节点安装、卸载或检查本机 Gateway：

```bash
sudo ssmsctl gateway install --storage-server 192.168.1.187
sudo ssmsctl gateway uninstall
ssmsctl gateway status
```

在 Storage Server 远程检查指定节点：

```bash
ssmsctl gateway status NodeC
```

## 系统检查

```bash
ssmsctl backend health
sudo ssmsctl backend upsert-user alice 10
sudo ssmsctl backend update-quota alice 20
sudo ssmsctl backend delete-user alice
sudo ssmsctl backend delete-server NodeC
ssmsctl system status
ssmsctl system check
```

在全新的 Ubuntu 虚拟机自动部署 Storage Server：

```bash
sudo scripts/ssmsctl system bootstrap --host 192.168.1.230 --check-only
sudo scripts/ssmsctl system bootstrap --host 192.168.1.230
```

`--check-only` 只做环境和配置预检查，不安装依赖、不启动服务、不修改系统文件。

完整说明见 `docs/deployment/bootstrap-storage-server.md`。

`backend` 分组只同步 Go 管理后台数据库，不创建或删除 Linux/Samba 系统用户。
完整用户生命周期仍优先使用 `ssmsctl user create/delete`。

`system status` 汇总本机管理后台、用量定时器、Agent 和 Gateway 的 systemd
状态。`system check` 执行项目 Shell、配置和 Go 测试。

## 项目目录解析

命令按以下顺序查找项目：

1. 环境变量 `SSMS_PROJECT_ROOT`。
2. `ssmsctl` 自身所在的项目目录。
3. 当前工作目录。
4. `/etc/ssms/sync.conf` 中的 Storage Server 项目目录。
5. 当前管理用户的 `~/SSMS`。
6. 当前管理用户的旧目录 `~/ServerStorageManagementSystem`，仅用于兼容历史部署。
7. `/opt/ssms`。

需要临时指定项目时：

```bash
SSMS_PROJECT_ROOT=/home/a2/SSMS ssmsctl system check
```
