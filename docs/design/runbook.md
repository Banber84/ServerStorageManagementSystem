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

浏览器访问：

```text
http://127.0.0.1:8080
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

参数说明：

- `-server`：管理后台地址。
- `-name`：节点名称，未传时默认使用主机名。
- `-address`：节点地址，未传时自动选择第一个内网 IPv4。
- `-disk`：需要统计的磁盘路径，默认 `/`。
- `-interval`：上报间隔，默认 `30s`。
- `-once`：只上报一次后退出，适合测试。

只上报一次：

```bash
go run ./agent -server http://127.0.0.1:8080 -name node01 -disk / -once
```

## 编译二进制

```bash
go build -o bin/storage-server ./server
go build -o bin/storage-agent ./agent
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
