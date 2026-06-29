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
cd ~/ServerStorageManagementSystem
chmod +x scripts/*.sh scripts/ssmsctl
```

使用新服务器的固定 IP 执行：

```bash
sudo scripts/ssmsctl system bootstrap --host 192.168.1.230
```

脚本会使用 sudo 发起用户作为 Storage Server 管理用户，并自动生成
`configs/site.env`。初始 `SSMS_NODES` 可以为空，后续通过以下命令添加节点：

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
