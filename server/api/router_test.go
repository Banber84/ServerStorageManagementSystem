package api

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"server-storage-management-system/server/database"
	"server-storage-management-system/server/service"
)

func TestFormatTimeUsesBeijingTime(t *testing.T) {
	value := time.Date(2026, 6, 27, 14, 35, 53, 0, time.UTC)

	if got := formatTime(value); got != "2026-06-27 22:35:53" {
		t.Fatalf("formatTime() = %q, want Beijing time", got)
	}
	if got := formatTimeISO(value); got != "2026-06-27T14:35:53Z" {
		t.Fatalf("formatTimeISO() = %q, want UTC RFC3339", got)
	}
}

func TestAdminAuthProtectsPages(t *testing.T) {
	router := newTestRouter(t, AuthConfig{
		Enabled:       true,
		Username:      "admin",
		Password:      "secret",
		SessionSecret: "test-session-secret",
	})

	pageReq := httptest.NewRequest(http.MethodGet, "/users", nil)
	pageResp := httptest.NewRecorder()
	router.ServeHTTP(pageResp, pageReq)
	if pageResp.Code != http.StatusSeeOther {
		t.Fatalf("GET /users status = %d, want %d", pageResp.Code, http.StatusSeeOther)
	}
	if location := pageResp.Header().Get("Location"); !strings.HasPrefix(location, "/login?next=") {
		t.Fatalf("GET /users Location = %q, want login redirect", location)
	}

	healthReq := httptest.NewRequest(http.MethodGet, "/api/health", nil)
	healthResp := httptest.NewRecorder()
	router.ServeHTTP(healthResp, healthReq)
	if healthResp.Code != http.StatusOK {
		t.Fatalf("GET /api/health status = %d, want %d", healthResp.Code, http.StatusOK)
	}
}

func TestAdminLoginAllowsPageAccess(t *testing.T) {
	router := newTestRouter(t, AuthConfig{
		Enabled:       true,
		Username:      "admin",
		Password:      "secret",
		SessionSecret: "test-session-secret",
	})

	form := url.Values{}
	form.Set("username", "admin")
	form.Set("password", "secret")
	form.Set("next", "/users")
	loginReq := httptest.NewRequest(http.MethodPost, "/login", strings.NewReader(form.Encode()))
	loginReq.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	loginResp := httptest.NewRecorder()
	router.ServeHTTP(loginResp, loginReq)
	if loginResp.Code != http.StatusSeeOther {
		t.Fatalf("POST /login status = %d, want %d", loginResp.Code, http.StatusSeeOther)
	}
	if location := loginResp.Header().Get("Location"); location != "/users" {
		t.Fatalf("POST /login Location = %q, want /users", location)
	}
	cookies := loginResp.Result().Cookies()
	if len(cookies) == 0 {
		t.Fatal("POST /login did not set session cookie")
	}

	pageReq := httptest.NewRequest(http.MethodGet, "/users", nil)
	for _, cookie := range cookies {
		pageReq.AddCookie(cookie)
	}
	pageResp := httptest.NewRecorder()
	router.ServeHTTP(pageResp, pageReq)
	if pageResp.Code != http.StatusOK {
		t.Fatalf("GET /users with session status = %d, want %d", pageResp.Code, http.StatusOK)
	}
}

func newTestRouter(t *testing.T, auth AuthConfig) http.Handler {
	t.Helper()
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat("server/templates"); err != nil {
		if chdirErr := os.Chdir("../.."); chdirErr != nil {
			t.Fatal(chdirErr)
		}
		t.Cleanup(func() {
			_ = os.Chdir(workingDir)
		})
	}

	db, err := database.Open(":memory:")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = db.Close()
	})
	return NewRouterWithAuth(service.NewStore(db), auth)
}
