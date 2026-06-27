package database

import (
	"database/sql"
	"fmt"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

// Open 初始化 SQLite 连接，并在服务启动时自动完成表结构迁移。
func Open(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite3", path+"?_foreign_keys=on&_busy_timeout=5000&_loc=UTC")
	if err != nil {
		return nil, fmt.Errorf("open sqlite database: %w", err)
	}
	// SQLite 是单文件数据库，限制打开连接数可以减少写锁竞争，适合当前课程项目规模。
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	db.SetConnMaxLifetime(time.Hour)

	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("ping sqlite database: %w", err)
	}
	if err := Migrate(db); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

// Migrate 创建后台所需的核心表：用户、存储统计、节点状态和日志。
func Migrate(db *sql.DB) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			username TEXT NOT NULL UNIQUE,
			full_name TEXT NOT NULL DEFAULT '',
			email TEXT NOT NULL DEFAULT '',
			quota_bytes INTEGER NOT NULL CHECK (quota_bytes > 0),
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS storage_usage (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id INTEGER NOT NULL UNIQUE,
			used_bytes INTEGER NOT NULL DEFAULT 0 CHECK (used_bytes >= 0),
			path TEXT NOT NULL DEFAULT '',
			scanned_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
		);`,
		`CREATE TABLE IF NOT EXISTS servers (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL UNIQUE,
			address TEXT NOT NULL DEFAULT '',
			cpu_usage REAL NOT NULL DEFAULT 0,
			memory_usage REAL NOT NULL DEFAULT 0,
			disk_usage REAL NOT NULL DEFAULT 0,
			online INTEGER NOT NULL DEFAULT 0,
			last_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS logs (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			type TEXT NOT NULL,
			username TEXT NOT NULL DEFAULT '',
			server_name TEXT NOT NULL DEFAULT '',
			message TEXT NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE INDEX IF NOT EXISTS idx_logs_created_at ON logs(created_at DESC);`,
		`CREATE INDEX IF NOT EXISTS idx_servers_last_seen ON servers(last_seen DESC);`,
	}

	for _, statement := range statements {
		if _, err := db.Exec(statement); err != nil {
			return fmt.Errorf("run migration: %w", err)
		}
	}
	return nil
}
