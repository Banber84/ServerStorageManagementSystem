# 数据库设计

数据库引擎：SQLite

默认数据库文件：

```text
server-storage.db
```

表结构由 `server/database/database.go` 在服务启动时自动迁移创建。

## `users`

保存后台管理的用户记录。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PRIMARY KEY | 用户 ID |
| `username` | TEXT UNIQUE NOT NULL | Linux/Samba 用户名 |
| `full_name` | TEXT NOT NULL | 用户姓名 |
| `email` | TEXT NOT NULL | 用户邮箱 |
| `quota_bytes` | INTEGER NOT NULL | 用户最大可用空间，单位字节 |
| `created_at` | DATETIME NOT NULL | 创建时间 |
| `updated_at` | DATETIME NOT NULL | 更新时间 |

约束：

- `username` 唯一。
- `quota_bytes` 必须大于 0。

## `storage_usage`

保存每个用户最近一次扫描到的存储使用量。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PRIMARY KEY | 记录 ID |
| `user_id` | INTEGER UNIQUE NOT NULL | 关联 `users.id` |
| `used_bytes` | INTEGER NOT NULL | 已使用空间，单位字节 |
| `path` | TEXT NOT NULL | 被扫描的用户目录 |
| `scanned_at` | DATETIME NOT NULL | 扫描时间 |

外键：

- `user_id` 引用 `users.id`。
- 删除用户时，自动删除对应的存储统计记录。

## `servers`

保存各节点最近一次上报的运行状态。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PRIMARY KEY | 节点 ID |
| `name` | TEXT UNIQUE NOT NULL | 节点名称 |
| `address` | TEXT NOT NULL | 节点 IP 或主机地址 |
| `cpu_usage` | REAL NOT NULL | CPU 使用率百分比 |
| `memory_usage` | REAL NOT NULL | 内存使用率百分比 |
| `disk_usage` | REAL NOT NULL | 磁盘使用率百分比 |
| `online` | INTEGER NOT NULL | `1` 表示在线，`0` 表示离线 |
| `last_seen` | DATETIME NOT NULL | 最后上报时间 |
| `created_at` | DATETIME NOT NULL | 创建时间 |
| `updated_at` | DATETIME NOT NULL | 更新时间 |

说明：

- Agent 每次上报时按 `name` 更新同一条节点记录。
- 后台查询节点时，会把超过 2 分钟未上报的节点标记为离线。

## `logs`

保存登录、挂载和系统日志。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PRIMARY KEY | 日志 ID |
| `type` | TEXT NOT NULL | 日志类型 |
| `username` | TEXT NOT NULL | 相关用户名 |
| `server_name` | TEXT NOT NULL | 相关节点名 |
| `message` | TEXT NOT NULL | 日志内容 |
| `created_at` | DATETIME NOT NULL | 创建时间 |

常用日志类型：

- `login`
- `mount`
- `system`

## 索引

- `idx_logs_created_at`：用于按时间倒序查询最近日志。
- `idx_servers_last_seen`：用于节点在线状态判断。
