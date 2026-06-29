# 新 Storage Server 自动部署

## 适用范围

本流程用于一台全新的 Ubuntu 虚拟机，不迁移旧服务器的数据、用户或数据库。
虚拟机中只需要先完成：

1. 安装 Ubuntu Server。
2. 创建具备 sudo 权限的管理用户。
3. 配置固定 IP 并启用 SSH。
4. 将本项目放入管理用户的 home 目录。

自动部署默认安装 Samba、quota、Go 编译环境、管理后台、Storage Agent、
用量同步定时器和 `ssmsctl`。

## 一条命令部署

进入项目目录：

```bash
cd ~/SSMS
chmod +x scripts/*.sh scripts/ssmsctl
```

如果你的目录名不是 `SSMS`，进入实际项目目录即可。

使用新服务器的固定 IP 执行：

```bash
sudo scripts/ssmsctl system bootstrap --host 192.168.1.230 --check-only
```

预检查只读取系统状态和配置，不安装依赖，也不会修改 `/etc/ssms`、
`configs/site.env` 或 `/etc/fstab`。通过后执行正式部署：

```bash
sudo scripts/ssmsctl system bootstrap --host 192.168.1.230
```

脚本会使用 sudo 发起用户作为 Storage Server 管理用户，并自动生成
`configs/site.env`。同时会启用 Web 管理页面登录认证，生成：

- `SSMS_ADMIN_USERNAME`：默认 `admin`。
- `SSMS_ADMIN_PASSWORD`：首次部署随机生成。
- `SSMS_SESSION_SECRET`：首次部署随机生成。

初始密码会打印在 bootstrap 输出和 `/var/log/ssms/bootstrap-storage-server.log`
中。部署完成后应保存密码，并在 `configs/site.env` 中改成自己的管理员密码后
重新执行：

```bash
sudo scripts/apply_site_config.sh --config configs/site.env --output-dir /etc/ssms
sudo systemctl restart storage-server
```

初始 `SSMS_NODES` 可以为空，后续通过以下命令添加节点：

```bash
sudo ssmsctl node join NodeA 192.168.1.122 nodea1
```

## 使用已有 site.env

也可以在部署前填写统一配置：

```bash
cp configs/site.env.example configs/site.env
vim configs/site.env
chmod 600 configs/site.env
sudo scripts/ssmsctl system bootstrap --config configs/site.env
```

## quota 安全处理

自动配置只支持 `STORAGE_ROOT` 所在的 ext4 文件系统。脚本会：

1. 查找实际挂载点。
2. 备份 `/etc/fstab`。
3. 只为对应条目追加 `usrquota,grpquota`。
4. 重新挂载并验证参数。
5. 执行 `quota_manager.sh enable`。

如果 `/etc/fstab` 已更新但重新挂载失败，脚本会自动恢复刚才的备份，并提示
检查挂载配置后重试，不会把失败的 fstab 配置留在系统中。

备份文件格式：

```text
/etc/fstab.ssms.YYYYMMDDhhmmss.bak
```

如果使用其他文件系统，可先跳过：

```bash
sudo scripts/ssmsctl system bootstrap \
  --host 192.168.1.230 \
  --skip-quota
```

然后按文件系统要求手工配置。

如果创建用户时出现：

```text
setquota: Cannot open quotafile //aquota.user: No such file or directory
setquota: Not all specified mountpoints are using quota.
```

说明用户创建流程已经走到配额设置阶段，但 `STORAGE_ROOT` 所在文件系统的 quota
尚未启用。先执行：

```bash
source /etc/ssms/system.conf
findmnt -no SOURCE,TARGET,FSTYPE,OPTIONS --target "$STORAGE_ROOT"
```

确认 `TARGET` 后，为该挂载点启用 `usrquota,grpquota`，再执行：

```bash
sudo mount -o remount TARGET
sudo ssmsctl quota enable
sudo ssmsctl quota set alice 10
sudo ssmsctl usage sync
```

其中 `TARGET` 替换为实际挂载点，例如 `/` 或 `/srv`。

## Go 下载配置

默认使用：

```text
GOPROXY=https://goproxy.cn,direct
GOSUMDB=sum.golang.google.cn
```

bootstrap 会将这两个值写入管理用户的 `go env`，后续手工执行 `go build` 也会
默认使用相同镜像。查看当前配置：

```bash
go env GOPROXY GOSUMDB
```

可以覆盖：

```bash
sudo scripts/ssmsctl system bootstrap \
  --host 192.168.1.230 \
  --go-proxy https://proxy.golang.org,direct \
  --go-sumdb sum.golang.org
```

## 自动验证

部署结束前会检查：

- `smbd` 与 `nmbd`
- `storage-server`
- `storage-agent`
- `storage-usage-sync.timer`
- Samba 配置
- 管理后台 `/api/health`
- 首次用户用量同步

查看结果：

```bash
ssmsctl system status
curl http://127.0.0.1:8080/api/health
systemctl list-timers --no-pager storage-usage-sync.timer
```

完整日志：

```bash
sudo less /var/log/ssms/bootstrap-storage-server.log
```
