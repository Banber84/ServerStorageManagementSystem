# 新 Storage Server 自动部署测试报告

> 本文仅记录历史实测过程与结论。日常操作请查阅 `docs/deployment/`。

## 基本信息

```text
测试日期：2026-06-29
系统：Ubuntu Server 26.04 amd64
Storage Server：192.168.1.221
管理用户：main
项目目录：/home/main/ServerStorageManagementSystem
部署命令：sudo scripts/ssmsctl system bootstrap --host 192.168.1.221
```

本次测试用于验证全新虚拟机自动部署，不包含旧服务器数据、账号或数据库迁移。

## 已验证项目

```text
1. bootstrap 可以自动安装 build-essential、Go、Samba、quota 等依赖。
2. 可以根据 --host 和 sudo 发起用户生成 /etc/ssms 运行配置。
3. Samba 配置通过 testparm，并启动 smbd、nmbd。
4. STORAGE_ROOT 位于根文件系统 /，文件系统类型为 ext4。
5. fstab quota 参数写入并重新挂载后，脚本可以识别 quota 已启用。
6. storage-server 和 storage-agent 可以自动编译。
7. 管理后台用户 API 可用。
8. ssmsctl user list 可以列出后台全部用户。
9. 用户列表支持 table 和 json 格式。
10. 表格会根据内容动态计算列宽，并兼容中文全角字符。
```

## 测试中发现并修复的问题

### 1. 运行配置复制到自身

首次执行在安装完依赖并生成 `/etc/ssms/system.conf` 后停止：

```text
install: '/etc/ssms/system.conf' and '/etc/ssms/system.conf' are the same file
```

原因是 bootstrap 将系统运行配置传给基础安装脚本后，基础脚本仍尝试将该文件
复制到原路径。

修复内容：

- 使用 Bash `-ef` 判断源文件和目标文件是否相同。
- 相同时只校正权限，不重复复制。
- 为后台配置增加 `BACKEND_CONFIG_FILE`，防止生成后的新服务器 API 地址被项目
  默认模板覆盖。

### 2. bootstrap 输出手工部署提示

基础安装完成后曾输出：

```text
下一步：
1. 为 /srv/samba/users 所在文件系统启用 quota 挂载参数。
2. 执行 quota_manager.sh enable
```

这是底层手工安装脚本的通用提示，并不代表需要退出 `ssmsctl`。现增加
`BOOTSTRAP_MODE=1`，自动部署过程中只提示 bootstrap 将继续执行。
手工安装提示也已统一改为 `ssmsctl` 命令。

### 3. 已启用 quota 时重复 quotacheck

重新挂载 ext4 后，用户 quota 已由系统启用，但旧判断没有识别该状态，导致
重复执行：

```text
quotacheck: Quota for users is enabled on mountpoint / so quotacheck might damage the file.
Please turn quotas off or use -f to force checking.
```

`quotacheck` 主动拒绝执行，没有造成文件系统或 quota 数据损坏。

修复内容：

- 同时检查挂载参数中的 `quota` 和 `quotaon -p` 输出。
- quota 已启用时跳过重复 `quotacheck`。
- `quota_manager.sh enable` 本身也改为可重复执行。

### 4. Go 编译缺少进度输出

首次编译 server 和 agent 时终端短时间没有新输出，看起来像停止。实际进程
正在下载依赖并编译，稍后正常完成。该阶段无需中断。

### 5. ssmsctl 缺少用户列表

第一版只有用户创建和删除，没有查看全部用户的命令。现增加：

```bash
ssmsctl user list
ssmsctl user list --format json
```

表格数据来自管理后台 `GET /api/users`，不是扫描 `/etc/passwd`。
JSON 使用 Python 3 标准库解析，Python 不参与后台、Agent、Samba 或 quota
运行。

### 6. 用户列表列宽不齐

初版直接使用 Tab 分隔，长邮箱会使列错位。现根据每列内容计算显示宽度，
使用空格补齐，并使用 Unicode East Asian Width 兼容中文姓名。

## 用户列表实测

新服务器执行：

```bash
ssmsctl user list
```

成功返回 `alice`、`bob`、`tony` 三个后台用户及其配额和更新时间，证明
后台用户 API 与统一命令可以正常联动。

## 当前结论

新 Storage Server 的自动依赖安装、配置生成、Samba、quota 状态识别、
server/agent 编译和后台用户查询已经完成实测。相同命令可在中断后安全重跑。

新根服务器通过 `ssmsctl node join` 接入登录节点的结果尚未记录，需在后续
联调完成后追加。
