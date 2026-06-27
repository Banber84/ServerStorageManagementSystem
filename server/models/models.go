package models

import "time"

// User 是后台保存的用户管理记录，不直接代表 Linux/Samba 系统账号本身。
type User struct {
	ID         int64     `json:"id"`
	Username   string    `json:"username"`
	FullName   string    `json:"full_name"`
	Email      string    `json:"email"`
	QuotaBytes int64     `json:"quota_bytes"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// StorageUsage 表示某个用户最近一次扫描到的空间使用情况。
type StorageUsage struct {
	ID             int64     `json:"id"`
	UserID         int64     `json:"user_id"`
	Username       string    `json:"username"`
	QuotaBytes     int64     `json:"quota_bytes"`
	UsedBytes      int64     `json:"used_bytes"`
	RemainingBytes int64     `json:"remaining_bytes"`
	Path           string    `json:"path"`
	ScannedAt      time.Time `json:"scanned_at"`
}

// ServerStatus 保存 Agent 上报的节点资源状态和在线状态。
type ServerStatus struct {
	ID          int64     `json:"id"`
	Name        string    `json:"name"`
	Address     string    `json:"address"`
	CPUUsage    float64   `json:"cpu_usage"`
	MemoryUsage float64   `json:"memory_usage"`
	DiskUsage   float64   `json:"disk_usage"`
	Online      bool      `json:"online"`
	LastSeen    time.Time `json:"last_seen"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// LogEntry 统一保存登录、挂载和系统操作日志。
type LogEntry struct {
	ID         int64     `json:"id"`
	Type       string    `json:"type"`
	Username   string    `json:"username"`
	ServerName string    `json:"server_name"`
	Message    string    `json:"message"`
	CreatedAt  time.Time `json:"created_at"`
}

// LogFilter 描述日志页面和日志 API 支持的筛选条件。
type LogFilter struct {
	Level   string `json:"level"`
	Type    string `json:"type"`
	Keyword string `json:"keyword"`
	KeyOnly bool   `json:"key_only"`
	Limit   int    `json:"limit"`
}

// Dashboard 是首页需要的聚合视图数据。
type Dashboard struct {
	UserCount       int64          `json:"user_count"`
	ServerCount     int64          `json:"server_count"`
	OnlineServers   int64          `json:"online_servers"`
	TotalQuotaBytes int64          `json:"total_quota_bytes"`
	TotalUsedBytes  int64          `json:"total_used_bytes"`
	RecentLogs      []LogEntry     `json:"recent_logs"`
	Servers         []ServerStatus `json:"servers"`
}

// CreateUserRequest 同时服务 REST API 和后台页面表单。
type CreateUserRequest struct {
	Username   string `json:"username" form:"username" binding:"required"`
	FullName   string `json:"full_name" form:"full_name"`
	Email      string `json:"email" form:"email"`
	QuotaBytes int64  `json:"quota_bytes" form:"quota_bytes" binding:"required,min=1"`
}

// UpdateQuotaRequest 用于按 ID 或用户名同步用户配额。
type UpdateQuotaRequest struct {
	QuotaBytes int64 `json:"quota_bytes" form:"quota_bytes" binding:"required,min=1"`
}

// UpdateStorageUsageRequest 是按后台用户 ID 写入存储统计的请求。
type UpdateStorageUsageRequest struct {
	UserID    int64  `json:"user_id" binding:"required"`
	UsedBytes int64  `json:"used_bytes" binding:"min=0"`
	Path      string `json:"path"`
}

// UpdateStorageUsageByUsernameRequest 方便 A 侧脚本按 Linux/Samba 用户名同步用量。
type UpdateStorageUsageByUsernameRequest struct {
	Username  string `json:"username" binding:"required"`
	UsedBytes int64  `json:"used_bytes" binding:"min=0"`
	Path      string `json:"path"`
}

// ServerReportRequest 是 Agent 上报节点状态时使用的请求体。
type ServerReportRequest struct {
	Name        string  `json:"name" binding:"required"`
	Address     string  `json:"address"`
	CPUUsage    float64 `json:"cpu_usage"`
	MemoryUsage float64 `json:"memory_usage"`
	DiskUsage   float64 `json:"disk_usage"`
}

// CreateLogRequest 用于脚本、Agent 或页面写入操作日志。
type CreateLogRequest struct {
	Type       string `json:"type" form:"type" binding:"required"`
	Username   string `json:"username" form:"username"`
	ServerName string `json:"server_name" form:"server_name"`
	Message    string `json:"message" form:"message" binding:"required"`
}
