# 编译与运行说明

## 环境要求

- Go 1.24 或更新版本
- SQLite 3 运行环境

## 启动管理后台

在项目根目录执行：

```bash
go mod tidy
go run ./server -addr :8080 -db server-storage.db
```

如果需要从局域网其他电脑访问管理后台，监听地址应改为 `0.0.0.0:8080`：

```bash
go run ./server -addr 0.0.0.0:8080 -db server-storage.db
```

浏览器访问：

```text
http://127.0.0.1:8080
```

局域网访问时，将地址替换为服务器 IP，例如第一版 demo 环境：

```text
http://192.168.1.187:8080
```

后台页面：

- `http://127.0.0.1:8080/`：仪表盘
- `http://127.0.0.1:8080/users`：用户管理
- `http://127.0.0.1:8080/storage`：存储统计
- `http://127.0.0.1:8080/servers`：节点监控
- `http://127.0.0.1:8080/logs`：日志管理

## 启动 Agent

在需要上报状态的节点上执行：

```bash
go run ./agent -server http://127.0.0.1:8080 -name NodeA -disk /
```

如果管理后台运行在局域网服务器上，将 `-server` 改为该服务器地址：

```bash
go run ./agent -server http://192.168.1.187:8080 -name NodeA -disk /
```

参数说明：

- `-server`：管理后台地址。
- `-name`：节点名称，未传时默认使用主机名。
- `-address`：节点地址，未传时自动选择第一个内网 IPv4。
- `-disk`：需要统计的磁盘路径，默认 `/`。
- `-interval`：上报间隔，默认 `30s`。
- `-once`：只上报一次后退出，适合测试。

管理后台会把超过 2 分钟没有上报的节点标记为离线。首页和节点监控页面每 30 秒自动刷新一次，所以 Agent 停止后，页面会在离线阈值到达后自动显示离线状态。

如果需要清理不再使用的节点，可以在 `/servers` 页面点击删除，或调用管理员删除接口：

```bash
curl -X DELETE http://127.0.0.1:8080/api/servers/1
```

删除只会清理后台节点状态记录，不会停止节点上的 Agent。如果 Agent 仍在运行，下一次上报后节点会重新出现。

只上报一次：

```bash
go run ./agent -server http://127.0.0.1:8080 -name NodeA -disk / -once
```

注意：`agent/` 不是独立 Go module，`go.mod` 位于仓库根目录。开发测试时应在项目根目录执行 `go run ./agent`。部署到其他节点时，建议先在根目录编译二进制，再分发 `bin/storage-agent`。

## 编译二进制

```bash
go build -o bin/storage-server ./server
go build -o bin/storage-agent ./agent
```

## 统一部署配置

迁移服务器 IP、端口、节点清单时，优先修改统一模板，不要分别手改多个配置文件。

首次准备：

```bash
cp configs/site.env.example configs/site.env
vim configs/site.env
```

`configs/site.env.example` 中和机器身份相关的字段默认留空。生成配置前必须填写真实值，否则 `apply_site_config.sh` 会报错并停止。

常用字段：

```text
SSMS_MANAGEMENT_HOST      管理后台 IP 或域名
SSMS_MANAGEMENT_PORT      管理后台端口
STORAGE_SERVER            Samba/Storage Server IP
STORAGE_SYNC_HOST         登录节点请求用户同步时连接的 Storage Server
SSMS_AGENT_NAME           当前机器上报到后台的节点名称
SSMS_AGENT_ADDRESS        当前机器上报到后台的节点 IP
SSMS_NODES                Storage Server 批量同步用户时使用的登录节点清单
```

在仓库内生成脚本使用的配置文件：

```bash
scripts/apply_site_config.sh --config configs/site.env --output-dir configs
```

在部署机器上直接生成 systemd 和脚本读取的配置文件：

```bash
sudo scripts/apply_site_config.sh --config configs/site.env --output-dir /etc/ssms
```

该命令会生成：

```text
system.conf
sync.conf
nodes.conf
storage-server.env
storage-agent.env
```

## systemd 部署管理后台

管理后台运行时需要读取 `server/templates/*.html`，建议把项目发布目录放到 `/opt/ssms`：

```bash
sudo scripts/install_management_server.sh
```

如果还没有准备统一部署配置，先执行：

```bash
cp configs/site.env.example configs/site.env
vim configs/site.env
```

生成后的管理后台环境变量示例：

```text
SSMS_SERVER_ADDR=0.0.0.0:8080
SSMS_DB_PATH=/var/lib/ssms/server-storage.db
GIN_MODE=release
```

安装脚本会自动创建 `/opt/ssms` 和 `/etc/ssms`，并复制 Web 模板、文档、配置和脚本。不要只安装 `/usr/local/bin/storage-server`，否则 systemd 启动时会因为 `WorkingDirectory=/opt/ssms` 不存在或缺少 `server/templates` 而失败。

启动服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now storage-server
sudo systemctl status storage-server
```

安装脚本还会启用 `storage-usage-sync.timer`，默认每 5 分钟把实际目录用量
同步到管理后台：

```bash
systemctl list-timers storage-usage-sync.timer
sudo systemctl start storage-usage-sync.service
journalctl -u storage-usage-sync.service
```

查看日志：

```bash
journalctl -u storage-server -f
```

测试后如需删除管理后台并重新部署：

```bash
sudo scripts/uninstall_management_server.sh
```

默认会删除 `storage-server.service`、`/usr/local/bin/storage-server` 和 `/opt/ssms`，但保留 SQLite 数据库、日志和 `/etc/ssms/storage-server.env`。如果要彻底清理测试数据：

```bash
sudo scripts/uninstall_management_server.sh --purge-all
```

分发 Agent 到节点示例：

```bash
scp bin/storage-agent user@192.168.1.188:/tmp/storage-agent
ssh user@192.168.1.188 'sudo install -m 0755 /tmp/storage-agent /usr/local/bin/storage-agent'
```

## systemd 部署 Agent

在每台需要上报状态的节点上执行：

```bash
sudo scripts/install_storage_agent.sh
```

安装脚本会检查 `bin/storage-agent`、`configs/site.env` 和 Agent 必填环境变量。每台节点部署前，在 `configs/site.env` 中把 `SSMS_AGENT_NAME` 和 `SSMS_AGENT_ADDRESS` 改成当前节点值。`SSMS_SERVER_URL`、`SSMS_AGENT_NAME`、`SSMS_AGENT_ADDRESS` 不能为空，否则安装脚本和 systemd 都会拒绝启动 Agent。

当前 Go 后端是 HTTP 服务，`SSMS_SERVER_URL` 应使用 `http://主节点IP:8080`，不要写成 `https://`。

生成后的 Agent 环境变量示例：

```text
SSMS_SERVER_URL=http://192.168.1.187:8080
SSMS_AGENT_NAME=NodeA
SSMS_AGENT_ADDRESS=192.168.1.188
SSMS_AGENT_DISK=/
SSMS_AGENT_INTERVAL=30s
```

启动服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now storage-agent
sudo systemctl status storage-agent
```

查看日志：

```bash
journalctl -u storage-agent -f
```

## API 快速测试

健康检查：

```bash
curl http://127.0.0.1:8080/api/health
```

创建用户：

```bash
curl -X POST http://127.0.0.1:8080/api/users \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","full_name":"Alice","email":"alice@example.com","quota_bytes":1073741824}'
```

写入存储统计：

```bash
curl -X POST http://127.0.0.1:8080/api/storage \
  -H 'Content-Type: application/json' \
  -d '{"user_id":1,"used_bytes":1048576,"path":"/srv/samba/users/alice"}'
```

按用户名写入存储统计：

```bash
curl -X POST http://127.0.0.1:8080/api/storage/username \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","used_bytes":1048576,"path":"/srv/samba/users/alice"}'
```

按用户名修改配额：

```bash
curl -X PUT http://127.0.0.1:8080/api/users/username/alice/quota \
  -H 'Content-Type: application/json' \
  -d '{"quota_bytes":2147483648}'
```

上报节点状态：

```bash
curl -X POST http://127.0.0.1:8080/api/servers/report \
  -H 'Content-Type: application/json' \
  -d '{"name":"NodeA","address":"192.168.1.21","cpu_usage":10.5,"memory_usage":40.2,"disk_usage":55.1}'
```

写入日志：

```bash
curl -X POST http://127.0.0.1:8080/api/logs \
  -H 'Content-Type: application/json' \
  -d '{"type":"login","username":"alice","server_name":"NodeA","message":"user logged in"}'
```

## 测试命令

```bash
go test ./...
```

## 注意事项

管理后台不执行 Linux 用户创建、Samba 账户创建、挂载或 quota 修改等高权限操作。这些操作由成员 A 的脚本完成。脚本执行成功后，可以调用本文档中的 REST API 将结果写入后台数据库。
