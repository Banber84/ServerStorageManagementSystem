# REST API 设计

默认服务地址：

```text
http://127.0.0.1:8080
```

除页面表单接口外，REST API 请求和响应均使用 JSON。

## 健康检查

### `GET /api/health`

用于检查后台服务是否正常运行。

响应示例：

```json
{
  "status": "ok"
}
```

## 仪表盘

### `GET /api/dashboard`

返回后台首页需要的汇总数据：

- 用户总数
- 节点总数
- 在线节点数
- 总配额
- 总已用空间
- 最近日志
- 节点状态

## 用户管理

### `GET /api/users`

查询全部用户。

### `POST /api/users`

创建用户管理记录。

请求示例：

```json
{
  "username": "alice",
  "full_name": "Alice",
  "email": "alice@example.com",
  "quota_bytes": 1073741824
}
```

说明：

- `username` 对应 Linux/Samba 用户名。
- `quota_bytes` 为用户配额，单位是字节。
- 该接口只写入后台数据库，不直接创建 Linux 用户。

### `PUT /api/users/{id或username}/quota`

修改用户配额。路径参数既可以传后台数据库用户 ID，也可以直接传 Linux/Samba 用户名。

按 ID 修改：

```text
PUT /api/users/1/quota
```

按用户名修改：

```text
PUT /api/users/alice/quota
```

请求示例：

```json
{
  "quota_bytes": 2147483648
}
```

响应为更新后的用户记录。

说明：

- 如果路径参数是正整数，后台按用户 ID 查询。
- 如果路径参数不是正整数，后台按 `username` 查询。
- 该接口方便 A 的配额脚本在执行成功后直接用用户名同步后台状态。

### `DELETE /api/users/{id}`

删除用户管理记录。对应的存储统计记录会通过外键级联删除。

成功响应：

```text
204 No Content
```

## 存储统计

### `GET /api/storage`

查询所有用户的存储使用情况。没有扫描记录的用户会显示 `used_bytes = 0`。

### `POST /api/storage`

写入或更新用户存储使用量。该接口可以由 A 的存储扫描脚本调用。

请求示例：

```json
{
  "user_id": 1,
  "used_bytes": 123456,
  "path": "/srv/samba/users/alice"
}
```

响应为更新后的存储统计记录。

### `POST /api/storage/by-username`

按用户名写入或更新用户存储使用量。该接口更适合和 A 的 `storage_usage_report.sh` 脚本对接，因为脚本输出通常包含用户名而不是后台数据库 ID。

请求示例：

```json
{
  "username": "alice",
  "used_bytes": 123456,
  "path": "/srv/samba/users/alice"
}
```

响应为更新后的存储统计记录。

说明：

- `username` 必须已经存在于后台 `users` 表。
- `used_bytes` 单位为字节。如果脚本输出 `used_kb`，调用该接口前需要转换为字节：`used_bytes = used_kb * 1024`。

## 节点状态

### `GET /api/servers`

查询全部节点状态。后台会把超过 2 分钟没有上报的节点标记为离线。

### `DELETE /api/servers/{id}`

管理员删除节点状态记录。

说明：

- 该接口只删除后台 `servers` 表中的节点状态记录。
- 不会停止节点上的 Agent 进程。
- 如果节点 Agent 继续运行，下一次上报后该节点会重新出现在后台。
- 适合清理测试节点、改名后的旧节点或已废弃节点。

成功响应：

```text
204 No Content
```

### `POST /api/servers/report`

节点 Agent 上报接口。

请求示例：

```json
{
  "name": "node01",
  "address": "192.168.1.21",
  "cpu_usage": 12.5,
  "memory_usage": 45.2,
  "disk_usage": 61.8
}
```

响应为更新后的节点状态记录。

## 日志管理

### `GET /api/logs?limit=100`

查询最近日志。

后台页面使用的日志类型包括：

- `login`：用户登录日志
- `mount`：挂载日志
- `system`：系统日志

### `POST /api/logs`

写入日志。

请求示例：

```json
{
  "type": "login",
  "username": "alice",
  "server_name": "node01",
  "message": "user logged in"
}
```

响应为创建后的日志记录。

## HTML 页面

后台同时提供以下页面：

- `GET /`
- `GET /users`
- `GET /storage`
- `GET /servers`
- `GET /logs`
