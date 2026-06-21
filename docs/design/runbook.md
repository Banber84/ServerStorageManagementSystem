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
go run ./agent -server http://127.0.0.1:8080 -name node01 -disk /
```

如果管理后台运行在局域网服务器上，将 `-server` 改为该服务器地址：

```bash
go run ./agent -server http://192.168.1.187:8080 -name node01 -disk /
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
go run ./agent -server http://127.0.0.1:8080 -name node01 -disk / -once
```

注意：`agent/` 不是独立 Go module，`go.mod` 位于仓库根目录。开发测试时应在项目根目录执行 `go run ./agent`。部署到其他节点时，建议先在根目录编译二进制，再分发 `bin/storage-agent`。

## 编译二进制

```bash
go build -o bin/storage-server ./server
go build -o bin/storage-agent ./agent
```

分发 Agent 到节点示例：

```bash
scp bin/storage-agent user@192.168.1.188:/tmp/storage-agent
ssh user@192.168.1.188 'sudo install -m 0755 /tmp/storage-agent /usr/local/bin/storage-agent'
```

systemd 常驻运行模板见：

```text
agent/storage-agent.service
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
curl -X POST http://127.0.0.1:8080/api/storage/by-username \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","used_bytes":1048576,"path":"/srv/samba/users/alice"}'
```

按用户名修改配额：

```bash
curl -X PUT http://127.0.0.1:8080/api/users/alice/quota \
  -H 'Content-Type: application/json' \
  -d '{"quota_bytes":2147483648}'
```

上报节点状态：

```bash
curl -X POST http://127.0.0.1:8080/api/servers/report \
  -H 'Content-Type: application/json' \
  -d '{"name":"node01","address":"192.168.1.21","cpu_usage":10.5,"memory_usage":40.2,"disk_usage":55.1}'
```

写入日志：

```bash
curl -X POST http://127.0.0.1:8080/api/logs \
  -H 'Content-Type: application/json' \
  -d '{"type":"login","username":"alice","server_name":"node01","message":"user logged in"}'
```

## 测试命令

```bash
go test ./...
```

## 注意事项

管理后台不执行 Linux 用户创建、Samba 账户创建、挂载或 quota 修改等高权限操作。这些操作由成员 A 的脚本完成。脚本执行成功后，可以调用本文档中的 REST API 将结果写入后台数据库。
