# 平台与后台架构设计

## 负责范围

本文档说明成员 B 负责的后台平台部分：

- Go 管理后台服务
- SQLite 数据库设计
- REST API
- 用户管理、配额管理、存储统计、节点监控、日志管理
- 节点状态采集 Agent
- Bootstrap 管理页面

Linux 部署、Samba 配置、自动挂载脚本、系统配额脚本由成员 A 负责。后台不直接执行高权限系统命令，只保存管理数据并提供接口。

## 运行架构

```text
登录节点 / 存储节点
        |
        | agent/main.go 上报 CPU、内存、磁盘状态
        v
server/main.go
        |
        | Gin 路由
        v
server/service
        |
        | database/sql
        v
SQLite 数据库
```

管理后台是一个单进程服务，同时提供 HTML 页面和 JSON API。数据库使用 SQLite，方便课程项目部署和演示，不额外引入 Redis、MQ、Docker 或微服务。

## 目录结构

```text
server/
├── api/
│   └── router.go
├── database/
│   └── database.go
├── models/
│   └── models.go
├── service/
│   ├── service.go
│   └── service_test.go
├── templates/
│   ├── dashboard.html
│   ├── logs.html
│   ├── servers.html
│   ├── storage.html
│   └── users.html
└── main.go

agent/
└── main.go

docs/design/
├── api.md
├── architecture.md
├── database.md
└── runbook.md
```

## 模块说明

### 管理后台

`server/main.go` 负责启动 Gin 服务，加载 SQLite 数据库并注册路由。

主要页面：

- `/`：管理后台首页
- `/users`：用户管理和配额修改
- `/storage`：存储用量统计
- `/servers`：节点状态监控
- `/logs`：日志查看和手动写入

### 数据访问

`server/database/database.go` 负责打开 SQLite 数据库和执行表结构迁移。

`server/service/service.go` 负责业务逻辑：

- 创建、删除用户
- 修改用户配额
- 写入和查询存储使用量
- 接收节点状态上报
- 写入和查询日志
- 生成仪表盘聚合数据

### Agent

`agent/main.go` 运行在节点服务器上，使用 `gopsutil` 采集：

- CPU 使用率
- 内存使用率
- 磁盘使用率

Agent 定时调用管理后台的 `POST /api/servers/report` 接口，后台根据最后上报时间判断节点在线状态。

## 与 A 部分的边界

后台不直接创建 Linux 用户、Samba 用户、用户目录或系统 quota。推荐流程如下：

1. A 的脚本完成 Linux/Samba 用户创建。
2. 脚本调用后台 API 写入用户记录和配额记录。
3. 后台页面显示用户、配额、存储用量和日志。

这样可以避免 Web 进程持有 root 权限，降低课程项目实现复杂度。
