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

	usage, err := store.UpsertStorageUsage(models.UpdateStorageUsageRequest{
		UserID:    user.ID,
		UsedBytes: 512,
		Path:      "/srv/samba/users/alice",
	})
	if err != nil {
		t.Fatalf("upsert storage usage: %v", err)
	}
	if usage.RemainingBytes != 1536 {
		t.Fatalf("remaining = %d, want 1536", usage.RemainingBytes)
	}

	items, err := store.ListStorageUsage()
	if err != nil {
		t.Fatalf("list storage usage: %v", err)
	}
	if len(items) != 1 || items[0].Username != "alice" || items[0].UsedBytes != 512 {
		t.Fatalf("unexpected storage usage: %#v", items)
	}

	server, err := store.UpsertServerReport(models.ServerReportRequest{
		Name:        "node01",
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

	if _, err := store.CreateLog(models.CreateLogRequest{
		Type:       "login",
		Username:   "alice",
		ServerName: "node01",
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
	if dashboard.TotalQuotaBytes != 2048 || dashboard.TotalUsedBytes != 512 {
		t.Fatalf("unexpected dashboard storage totals: %#v", dashboard)
	}
}
