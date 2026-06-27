package service_test

import (
	"path/filepath"
	"testing"

	"server-storage-management-system/server/database"
	"server-storage-management-system/server/models"
	"server-storage-management-system/server/service"
)

func TestStoreManagementFlow(t *testing.T) {
	db, err := database.Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	defer db.Close()

	store := service.NewStore(db)

	user, err := store.CreateUser(models.CreateUserRequest{
		Username:   "alice",
		FullName:   "Alice",
		Email:      "alice@example.com",
		QuotaBytes: 1024,
	})
	if err != nil {
		t.Fatalf("create user: %v", err)
	}

	user, err = store.UpdateQuota(user.ID, 2048)
	if err != nil {
		t.Fatalf("update quota: %v", err)
	}
	if user.QuotaBytes != 2048 {
		t.Fatalf("quota = %d, want 2048", user.QuotaBytes)
	}

	user, err = store.UpdateQuotaByUsername("alice", 4096)
	if err != nil {
		t.Fatalf("update quota by username: %v", err)
	}
	if user.QuotaBytes != 4096 {
		t.Fatalf("quota = %d, want 4096", user.QuotaBytes)
	}

	usage, err := store.UpsertStorageUsage(models.UpdateStorageUsageRequest{
		UserID:    user.ID,
		UsedBytes: 512,
		Path:      "/srv/samba/users/alice",
	})
	if err != nil {
		t.Fatalf("upsert storage usage: %v", err)
	}
	if usage.RemainingBytes != 3584 {
		t.Fatalf("remaining = %d, want 3584", usage.RemainingBytes)
	}

	usage, err = store.UpsertStorageUsageByUsername(models.UpdateStorageUsageByUsernameRequest{
		Username:  "alice",
		UsedBytes: 1024,
		Path:      "/srv/samba/users/alice",
	})
	if err != nil {
		t.Fatalf("upsert storage usage by username: %v", err)
	}
	if usage.UserID != user.ID || usage.UsedBytes != 1024 || usage.RemainingBytes != 3072 {
		t.Fatalf("unexpected username storage usage: %#v", usage)
	}

	items, err := store.ListStorageUsage()
	if err != nil {
		t.Fatalf("list storage usage: %v", err)
	}
	if len(items) != 1 || items[0].Username != "alice" || items[0].UsedBytes != 1024 {
		t.Fatalf("unexpected storage usage: %#v", items)
	}

	server, err := store.UpsertServerReport(models.ServerReportRequest{
		Name:        "NodeA",
		Address:     "192.168.1.21",
		CPUUsage:    11.5,
		MemoryUsage: 45,
		DiskUsage:   60,
	})
	if err != nil {
		t.Fatalf("upsert server report: %v", err)
	}
	if !server.Online {
		t.Fatal("server should be online")
	}

	if _, err := store.UpsertServerReport(models.ServerReportRequest{
		Name:        "NodeA",
		Address:     "192.168.1.21",
		CPUUsage:    12,
		MemoryUsage: 46,
		DiskUsage:   61,
	}); err != nil {
		t.Fatalf("repeat server report: %v", err)
	}
	logs, err := store.ListLogs(100)
	if err != nil {
		t.Fatalf("list logs: %v", err)
	}
	nodeRegistrationLogs := 0
	for _, entry := range logs {
		if entry.ServerName == "NodeA" && entry.Message == "node registered" {
			nodeRegistrationLogs++
		}
	}
	if nodeRegistrationLogs != 1 {
		t.Fatalf("repeated report should not create another system log: %#v", logs)
	}

	if _, err := store.CreateLog(models.CreateLogRequest{
		Type:       "login",
		Username:   "alice",
		ServerName: "NodeA",
		Message:    "user logged in",
	}); err != nil {
		t.Fatalf("create log: %v", err)
	}

	dashboard, err := store.Dashboard()
	if err != nil {
		t.Fatalf("dashboard: %v", err)
	}
	if dashboard.UserCount != 1 || dashboard.ServerCount != 1 || dashboard.OnlineServers != 1 {
		t.Fatalf("unexpected dashboard counts: %#v", dashboard)
	}
	if dashboard.TotalQuotaBytes != 4096 || dashboard.TotalUsedBytes != 1024 {
		t.Fatalf("unexpected dashboard storage totals: %#v", dashboard)
	}
}

func TestDashboardMarksStaleServersOffline(t *testing.T) {
	db, err := database.Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	defer db.Close()

	store := service.NewStore(db)
	if _, err := store.UpsertServerReport(models.ServerReportRequest{
		Name:        "NodeA",
		Address:     "192.168.1.21",
		CPUUsage:    10,
		MemoryUsage: 20,
		DiskUsage:   30,
	}); err != nil {
		t.Fatalf("upsert server report: %v", err)
	}

	if _, err := db.Exec(`UPDATE servers SET online = 1, last_seen = datetime('now', '-3 minutes') WHERE name = 'NodeA'`); err != nil {
		t.Fatalf("age server report: %v", err)
	}

	dashboard, err := store.Dashboard()
	if err != nil {
		t.Fatalf("dashboard: %v", err)
	}
	if dashboard.ServerCount != 1 {
		t.Fatalf("server count = %d, want 1", dashboard.ServerCount)
	}
	if dashboard.OnlineServers != 0 {
		t.Fatalf("online servers = %d, want 0", dashboard.OnlineServers)
	}
	if len(dashboard.Servers) != 1 || dashboard.Servers[0].Online {
		t.Fatalf("stale server should be offline: %#v", dashboard.Servers)
	}
}

func TestDeleteServer(t *testing.T) {
	db, err := database.Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	defer db.Close()

	store := service.NewStore(db)
	server, err := store.UpsertServerReport(models.ServerReportRequest{
		Name:        "NodeA",
		Address:     "192.168.1.21",
		CPUUsage:    10,
		MemoryUsage: 20,
		DiskUsage:   30,
	})
	if err != nil {
		t.Fatalf("upsert server report: %v", err)
	}

	if err := store.DeleteServer(server.ID); err != nil {
		t.Fatalf("delete server: %v", err)
	}
	servers, err := store.ListServers()
	if err != nil {
		t.Fatalf("list servers: %v", err)
	}
	if len(servers) != 0 {
		t.Fatalf("servers after delete = %#v, want empty", servers)
	}

	logs, err := store.ListLogs(10)
	if err != nil {
		t.Fatalf("list logs: %v", err)
	}
	found := false
	for _, log := range logs {
		if log.ServerName == "NodeA" && log.Message == "deleted server status record" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("delete log not found: %#v", logs)
	}
}
