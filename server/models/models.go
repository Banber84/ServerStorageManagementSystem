package models

import "time"

type User struct {
	ID         int64     `json:"id"`
	Username   string    `json:"username"`
	FullName   string    `json:"full_name"`
	Email      string    `json:"email"`
	QuotaBytes int64     `json:"quota_bytes"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

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

type LogEntry struct {
	ID         int64     `json:"id"`
	Type       string    `json:"type"`
	Username   string    `json:"username"`
	ServerName string    `json:"server_name"`
	Message    string    `json:"message"`
	CreatedAt  time.Time `json:"created_at"`
}

type Dashboard struct {
	UserCount       int64          `json:"user_count"`
	ServerCount     int64          `json:"server_count"`
	OnlineServers   int64          `json:"online_servers"`
	TotalQuotaBytes int64          `json:"total_quota_bytes"`
	TotalUsedBytes  int64          `json:"total_used_bytes"`
	RecentLogs      []LogEntry     `json:"recent_logs"`
	Servers         []ServerStatus `json:"servers"`
}

type CreateUserRequest struct {
	Username   string `json:"username" form:"username" binding:"required"`
	FullName   string `json:"full_name" form:"full_name"`
	Email      string `json:"email" form:"email"`
	QuotaBytes int64  `json:"quota_bytes" form:"quota_bytes" binding:"required,min=1"`
}

type UpdateQuotaRequest struct {
	QuotaBytes int64 `json:"quota_bytes" form:"quota_bytes" binding:"required,min=1"`
}

type UpdateStorageUsageRequest struct {
	UserID    int64  `json:"user_id" binding:"required"`
	UsedBytes int64  `json:"used_bytes" binding:"min=0"`
	Path      string `json:"path"`
}

type ServerReportRequest struct {
	Name        string  `json:"name" binding:"required"`
	Address     string  `json:"address"`
	CPUUsage    float64 `json:"cpu_usage"`
	MemoryUsage float64 `json:"memory_usage"`
	DiskUsage   float64 `json:"disk_usage"`
}

type CreateLogRequest struct {
	Type       string `json:"type" form:"type" binding:"required"`
	Username   string `json:"username" form:"username"`
	ServerName string `json:"server_name" form:"server_name"`
	Message    string `json:"message" form:"message" binding:"required"`
}
