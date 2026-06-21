# 第一版 Demo 测试报告

## 基本信息

| 项目 | 内容 |
| --- | --- |
| 测试日期 | 2026-06-16 |
| 测试版本 | 第一版 demo |
| 测试范围 | Go 管理后台、REST API、节点状态上报、存储统计、日志展示 |
| 测试环境 | 局域网 Ubuntu 虚拟机 |
| 服务器 IP | `192.168.1.187` |
| 后台地址 | `http://192.168.1.187:8080` |

## 测试目标

验证第一版 demo 是否具备基本演示能力：

- 管理后台页面可以通过局域网访问。
- 用户管理页面可以创建和展示用户。
- 存储统计页面可以展示用户已用空间和剩余空间。
- 节点状态页面可以展示节点在线状态和资源使用率。
- 日志页面可以展示登录日志和系统日志。
- 首页可以汇总显示用户、节点、存储和日志数据。

## 测试环境说明

管理后台运行在局域网内的虚拟机上：

```text
Management Server: 192.168.1.187
Web Port:          8080
```

后台服务需要监听局域网地址：

```bash
go run ./server -addr 0.0.0.0:8080 -db demo.db
```

浏览器访问地址：

```text
http://192.168.1.187:8080
```

## 测试用例与结果

| 编号 | 测试项 | 测试方法 | 预期结果 | 实际结果 | 结论 |
| --- | --- | --- | --- | --- | --- |
| TC-01 | 首页访问 | 浏览器访问 `/` | 首页正常打开，显示统计区域 | 页面可正常访问 | 通过 |
| TC-02 | 用户管理 | 在 `/users` 创建 `alice` | 用户表格显示 `alice` 和配额 | 用户信息正常显示 | 通过 |
| TC-03 | 存储统计 | 调用 `POST /api/storage` 写入用量 | `/storage` 显示已用和剩余空间 | 存储统计正常显示 | 通过 |
| TC-04 | 节点状态 | 调用 `POST /api/servers/report` 上报节点 | `/servers` 显示 `node01` 在线 | 节点状态正常显示 | 通过 |
| TC-05 | 日志管理 | 调用 `POST /api/logs` 写入登录日志 | `/logs` 显示日志记录 | 日志正常显示 | 通过 |
| TC-06 | 首页汇总 | 写入用户、存储、节点、日志后刷新首页 | 首页汇总数据更新 | 首页汇总正常 | 通过 |

## 新增接口测试记录

### 测试信息

| 项目 | 内容 |
| --- | --- |
| 测试日期 | 2026-06-21 |
| 测试地点 | 服务机 |
| 测试范围 | A/B 联调用新增 REST API |
| 测试结论 | 新增接口无问题 |

### 测试用例与结果

| 编号 | 测试项 | 测试方法 | 预期结果 | 实际结果 | 结论 |
| --- | --- | --- | --- | --- | --- |
| TC-07 | 按用户名修改配额 | 调用 `PUT /api/users/{username}/quota` | 返回目标用户，配额更新为请求值 | 接口返回正常，页面和查询结果同步更新 | 通过 |
| TC-08 | 按用户名写入存储统计 | 调用 `POST /api/storage/by-username` | 返回目标用户存储统计，已用和剩余空间正确 | 接口返回正常，存储页面和汇总数据同步更新 | 通过 |
| TC-09 | 原按 ID 修改配额兼容性 | 调用 `PUT /api/users/{id}/quota` | 原接口仍可按 ID 修改配额 | 原接口正常可用 | 通过 |

### 新增接口测试命令

按用户名修改配额：

```bash
curl -X PUT http://192.168.1.187:8080/api/users/alice/quota \
  -H 'Content-Type: application/json' \
  -d '{"quota_bytes":2147483648}'
```

预期响应包含：

```json
{
  "username": "alice",
  "quota_bytes": 2147483648
}
```

按用户名写入存储统计：

```bash
curl -X POST http://192.168.1.187:8080/api/storage/by-username \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","used_bytes":1048576,"path":"/srv/samba/users/alice"}'
```

预期响应包含：

```json
{
  "username": "alice",
  "used_bytes": 1048576,
  "remaining_bytes": 2146435072
}
```

原按 ID 修改配额兼容性测试：

```bash
curl -X PUT http://192.168.1.187:8080/api/users/1/quota \
  -H 'Content-Type: application/json' \
  -d '{"quota_bytes":3221225472}'
```

### 新增接口测试结论

服务机测试确认：

- `PUT /api/users/{username}/quota` 可以直接按 Linux/Samba 用户名同步后台配额。
- `POST /api/storage/by-username` 可以直接按用户名同步存储使用量。
- 原有 `PUT /api/users/{id}/quota` 仍然兼容。
- 新接口满足 A 的脚本侧对接需求，脚本不再需要查询后台数据库用户 ID。

## 关键测试命令

健康检查：

```bash
curl http://192.168.1.187:8080/api/health
```

创建用户：

```bash
curl -X POST http://192.168.1.187:8080/api/users \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","full_name":"Alice","email":"alice@example.com","quota_bytes":1073741824}'
```

写入存储统计：

```bash
curl -X POST http://192.168.1.187:8080/api/storage \
  -H 'Content-Type: application/json' \
  -d '{"user_id":1,"used_bytes":1048576,"path":"/srv/samba/users/alice"}'
```

上报节点状态：

```bash
curl -X POST http://192.168.1.187:8080/api/servers/report \
  -H 'Content-Type: application/json' \
  -d '{"name":"node01","address":"192.168.1.187","cpu_usage":12.5,"memory_usage":40.2,"disk_usage":55.1}'
```

写入日志：

```bash
curl -X POST http://192.168.1.187:8080/api/logs \
  -H 'Content-Type: application/json' \
  -d '{"type":"login","username":"alice","server_name":"node01","message":"user logged in"}'
```

## 测试结论

第一版 demo 的管理后台功能测试通过。当前版本已经可以完成基本演示：

- 通过局域网访问 Web 管理后台。
- 创建用户管理记录。
- 写入并展示存储使用量。
- 上报并展示节点状态。
- 写入并展示日志。
- 首页展示核心汇总数据。

## 遗留问题与后续计划

第一版 demo 主要验证后台页面和 API，系统层能力仍需要继续联调：

- Samba 用户创建脚本与后台用户 API 自动对接。
- 存储使用量脚本 `storage_usage_report.sh` 后续可通过 `POST /api/storage/by-username` 自动同步到后台。
- 登录节点 Agent 长期运行方式需要加入 systemd 管理。
- 用户删除和配额修改需要与 Linux/Samba 实际系统状态保持一致。
- 后续可以增加登录认证，避免管理后台裸露在局域网内。
