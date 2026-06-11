package service

import (
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"server-storage-management-system/server/models"
)

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

func (s *Store) Dashboard() (models.Dashboard, error) {
	var dashboard models.Dashboard
	if err := s.db.QueryRow(`SELECT COUNT(*), COALESCE(SUM(quota_bytes), 0) FROM users`).Scan(&dashboard.UserCount, &dashboard.TotalQuotaBytes); err != nil {
		return dashboard, err
	}
	if err := s.db.QueryRow(`SELECT COUNT(*), COALESCE(SUM(CASE WHEN online = 1 THEN 1 ELSE 0 END), 0) FROM servers`).Scan(&dashboard.ServerCount, &dashboard.OnlineServers); err != nil {
		return dashboard, err
	}
	if err := s.db.QueryRow(`SELECT COALESCE(SUM(used_bytes), 0) FROM storage_usage`).Scan(&dashboard.TotalUsedBytes); err != nil {
		return dashboard, err
	}
	var err error
	dashboard.RecentLogs, err = s.ListLogs(8)
	if err != nil {
		return dashboard, err
	}
	dashboard.Servers, err = s.ListServers()
	return dashboard, err
}

func (s *Store) CreateUser(req models.CreateUserRequest) (models.User, error) {
	username := strings.TrimSpace(req.Username)
	if username == "" {
		return models.User{}, errors.New("username is required")
	}
	if req.QuotaBytes <= 0 {
		return models.User{}, errors.New("quota_bytes must be greater than zero")
	}

	result, err := s.db.Exec(
		`INSERT INTO users (username, full_name, email, quota_bytes, created_at, updated_at)
		 VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
		username,
		strings.TrimSpace(req.FullName),
		strings.TrimSpace(req.Email),
		req.QuotaBytes,
	)
	if err != nil {
		return models.User{}, fmt.Errorf("create user: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return models.User{}, err
	}
	_, _ = s.db.Exec(
		`INSERT INTO logs (type, username, message, created_at) VALUES ('system', ?, ?, CURRENT_TIMESTAMP)`,
		username,
		"created user",
	)
	return s.GetUser(id)
}

func (s *Store) GetUser(id int64) (models.User, error) {
	var user models.User
	err := s.db.QueryRow(
		`SELECT id, username, full_name, email, quota_bytes, created_at, updated_at FROM users WHERE id = ?`,
		id,
	).Scan(&user.ID, &user.Username, &user.FullName, &user.Email, &user.QuotaBytes, &user.CreatedAt, &user.UpdatedAt)
	return user, err
}

func (s *Store) ListUsers() ([]models.User, error) {
	rows, err := s.db.Query(`SELECT id, username, full_name, email, quota_bytes, created_at, updated_at FROM users ORDER BY username`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	users := make([]models.User, 0)
	for rows.Next() {
		var user models.User
		if err := rows.Scan(&user.ID, &user.Username, &user.FullName, &user.Email, &user.QuotaBytes, &user.CreatedAt, &user.UpdatedAt); err != nil {
			return nil, err
		}
		users = append(users, user)
	}
	return users, rows.Err()
}

func (s *Store) DeleteUser(id int64) error {
	user, err := s.GetUser(id)
	if err != nil {
		return err
	}
	result, err := s.db.Exec(`DELETE FROM users WHERE id = ?`, id)
	if err != nil {
		return err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return sql.ErrNoRows
	}
	_, _ = s.db.Exec(
		`INSERT INTO logs (type, username, message, created_at) VALUES ('system', ?, ?, CURRENT_TIMESTAMP)`,
		user.Username,
		"deleted user",
	)
	return nil
}

func (s *Store) UpdateQuota(id int64, quotaBytes int64) (models.User, error) {
	if quotaBytes <= 0 {
		return models.User{}, errors.New("quota_bytes must be greater than zero")
	}
	result, err := s.db.Exec(`UPDATE users SET quota_bytes = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`, quotaBytes, id)
	if err != nil {
		return models.User{}, err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return models.User{}, err
	}
	if affected == 0 {
		return models.User{}, sql.ErrNoRows
	}
	user, err := s.GetUser(id)
	if err == nil {
		_, _ = s.db.Exec(
			`INSERT INTO logs (type, username, message, created_at) VALUES ('system', ?, ?, CURRENT_TIMESTAMP)`,
			user.Username,
			"updated quota",
		)
	}
	return user, err
}

func (s *Store) UpsertStorageUsage(req models.UpdateStorageUsageRequest) (models.StorageUsage, error) {
	if req.UserID <= 0 {
		return models.StorageUsage{}, errors.New("user_id is required")
	}
	if req.UsedBytes < 0 {
		return models.StorageUsage{}, errors.New("used_bytes must be greater than or equal to zero")
	}
	if _, err := s.GetUser(req.UserID); err != nil {
		return models.StorageUsage{}, err
	}
	_, err := s.db.Exec(
		`INSERT INTO storage_usage (user_id, used_bytes, path, scanned_at)
		 VALUES (?, ?, ?, CURRENT_TIMESTAMP)
		 ON CONFLICT(user_id) DO UPDATE SET
			used_bytes = excluded.used_bytes,
			path = excluded.path,
			scanned_at = CURRENT_TIMESTAMP`,
		req.UserID,
		req.UsedBytes,
		strings.TrimSpace(req.Path),
	)
	if err != nil {
		return models.StorageUsage{}, err
	}
	return s.GetStorageUsage(req.UserID)
}

func (s *Store) GetStorageUsage(userID int64) (models.StorageUsage, error) {
	var usage models.StorageUsage
	err := s.db.QueryRow(
		`SELECT su.id, u.id, u.username, u.quota_bytes, su.used_bytes,
		        CASE WHEN u.quota_bytes - su.used_bytes > 0 THEN u.quota_bytes - su.used_bytes ELSE 0 END,
		        su.path, su.scanned_at
		   FROM storage_usage su
		   JOIN users u ON u.id = su.user_id
		  WHERE su.user_id = ?`,
		userID,
	).Scan(&usage.ID, &usage.UserID, &usage.Username, &usage.QuotaBytes, &usage.UsedBytes, &usage.RemainingBytes, &usage.Path, &usage.ScannedAt)
	return usage, err
}

func (s *Store) ListStorageUsage() ([]models.StorageUsage, error) {
	rows, err := s.db.Query(
		`SELECT COALESCE(su.id, 0), u.id, u.username, u.quota_bytes, COALESCE(su.used_bytes, 0),
		        CASE WHEN u.quota_bytes - COALESCE(su.used_bytes, 0) > 0 THEN u.quota_bytes - COALESCE(su.used_bytes, 0) ELSE 0 END,
		        COALESCE(su.path, ''), su.scanned_at, u.updated_at
		   FROM users u
		   LEFT JOIN storage_usage su ON su.user_id = u.id
		  ORDER BY u.username`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]models.StorageUsage, 0)
	for rows.Next() {
		var usage models.StorageUsage
		var scannedAt sql.NullTime
		var userUpdatedAt time.Time
		if err := rows.Scan(&usage.ID, &usage.UserID, &usage.Username, &usage.QuotaBytes, &usage.UsedBytes, &usage.RemainingBytes, &usage.Path, &scannedAt, &userUpdatedAt); err != nil {
			return nil, err
		}
		usage.ScannedAt = userUpdatedAt
		if scannedAt.Valid {
			usage.ScannedAt = scannedAt.Time
		}
		items = append(items, usage)
	}
	return items, rows.Err()
}

func (s *Store) UpsertServerReport(req models.ServerReportRequest) (models.ServerStatus, error) {
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return models.ServerStatus{}, errors.New("name is required")
	}
	_, err := s.db.Exec(
		`INSERT INTO servers (name, address, cpu_usage, memory_usage, disk_usage, online, last_seen, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		 ON CONFLICT(name) DO UPDATE SET
			address = excluded.address,
			cpu_usage = excluded.cpu_usage,
			memory_usage = excluded.memory_usage,
			disk_usage = excluded.disk_usage,
			online = 1,
			last_seen = CURRENT_TIMESTAMP,
			updated_at = CURRENT_TIMESTAMP`,
		name,
		strings.TrimSpace(req.Address),
		clampPercent(req.CPUUsage),
		clampPercent(req.MemoryUsage),
		clampPercent(req.DiskUsage),
	)
	if err != nil {
		return models.ServerStatus{}, err
	}
	_, _ = s.db.Exec(
		`INSERT INTO logs (type, server_name, message, created_at) VALUES ('system', ?, ?, CURRENT_TIMESTAMP)`,
		name,
		"received server status report",
	)
	return s.GetServerByName(name)
}

func (s *Store) MarkOfflineAfter(maxAge time.Duration) error {
	_, err := s.db.Exec(
		`UPDATE servers SET online = 0, updated_at = CURRENT_TIMESTAMP
		  WHERE last_seen < datetime('now', ?)`,
		fmt.Sprintf("-%d seconds", int(maxAge.Seconds())),
	)
	return err
}

func (s *Store) GetServerByName(name string) (models.ServerStatus, error) {
	var server models.ServerStatus
	var online int
	err := s.db.QueryRow(
		`SELECT id, name, address, cpu_usage, memory_usage, disk_usage, online, last_seen, created_at, updated_at
		   FROM servers WHERE name = ?`,
		name,
	).Scan(&server.ID, &server.Name, &server.Address, &server.CPUUsage, &server.MemoryUsage, &server.DiskUsage, &online, &server.LastSeen, &server.CreatedAt, &server.UpdatedAt)
	server.Online = online == 1
	return server, err
}

func (s *Store) ListServers() ([]models.ServerStatus, error) {
	rows, err := s.db.Query(
		`SELECT id, name, address, cpu_usage, memory_usage, disk_usage, online, last_seen, created_at, updated_at
		   FROM servers ORDER BY online DESC, name`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	servers := make([]models.ServerStatus, 0)
	for rows.Next() {
		var server models.ServerStatus
		var online int
		if err := rows.Scan(&server.ID, &server.Name, &server.Address, &server.CPUUsage, &server.MemoryUsage, &server.DiskUsage, &online, &server.LastSeen, &server.CreatedAt, &server.UpdatedAt); err != nil {
			return nil, err
		}
		server.Online = online == 1
		servers = append(servers, server)
	}
	return servers, rows.Err()
}

func (s *Store) CreateLog(req models.CreateLogRequest) (models.LogEntry, error) {
	logType := strings.TrimSpace(req.Type)
	if logType == "" {
		return models.LogEntry{}, errors.New("type is required")
	}
	message := strings.TrimSpace(req.Message)
	if message == "" {
		return models.LogEntry{}, errors.New("message is required")
	}
	result, err := s.db.Exec(
		`INSERT INTO logs (type, username, server_name, message, created_at)
		 VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)`,
		logType,
		strings.TrimSpace(req.Username),
		strings.TrimSpace(req.ServerName),
		message,
	)
	if err != nil {
		return models.LogEntry{}, err
	}
	id, err := result.LastInsertId()
	if err != nil {
		return models.LogEntry{}, err
	}
	return s.GetLog(id)
}

func (s *Store) GetLog(id int64) (models.LogEntry, error) {
	var log models.LogEntry
	err := s.db.QueryRow(
		`SELECT id, type, username, server_name, message, created_at FROM logs WHERE id = ?`,
		id,
	).Scan(&log.ID, &log.Type, &log.Username, &log.ServerName, &log.Message, &log.CreatedAt)
	return log, err
}

func (s *Store) ListLogs(limit int) ([]models.LogEntry, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	rows, err := s.db.Query(
		`SELECT id, type, username, server_name, message, created_at FROM logs ORDER BY created_at DESC, id DESC LIMIT ?`,
		limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	logs := make([]models.LogEntry, 0)
	for rows.Next() {
		var log models.LogEntry
		if err := rows.Scan(&log.ID, &log.Type, &log.Username, &log.ServerName, &log.Message, &log.CreatedAt); err != nil {
			return nil, err
		}
		logs = append(logs, log)
	}
	return logs, rows.Err()
}

func clampPercent(value float64) float64 {
	switch {
	case value < 0:
		return 0
	case value > 100:
		return 100
	default:
		return value
	}
}
