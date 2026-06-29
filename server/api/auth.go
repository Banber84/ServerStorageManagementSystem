package api

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"

	"server-storage-management-system/server/models"
)

const (
	authCookieName = "ssms_session"
	sessionTTL     = 12 * time.Hour
)

type AuthConfig struct {
	Enabled       bool
	Username      string
	Password      string
	PasswordHash  string
	SessionSecret string
}

func AuthConfigFromEnv() (AuthConfig, error) {
	config := AuthConfig{
		Enabled:       envBool("SSMS_AUTH_ENABLED", false),
		Username:      strings.TrimSpace(os.Getenv("SSMS_ADMIN_USERNAME")),
		Password:      os.Getenv("SSMS_ADMIN_PASSWORD"),
		PasswordHash:  strings.TrimSpace(os.Getenv("SSMS_ADMIN_PASSWORD_HASH")),
		SessionSecret: os.Getenv("SSMS_SESSION_SECRET"),
	}
	if !config.Enabled {
		return config, nil
	}
	if config.Username == "" {
		config.Username = "admin"
	}
	if strings.TrimSpace(config.Password) == "" && config.PasswordHash == "" {
		return config, errors.New("SSMS_AUTH_ENABLED=1 requires SSMS_ADMIN_PASSWORD or SSMS_ADMIN_PASSWORD_HASH")
	}
	if config.SessionSecret == "" {
		secret, err := randomToken(32)
		if err != nil {
			return config, err
		}
		config.SessionSecret = secret
	}
	return config, nil
}

func (h *Handler) loginPage(ctx *gin.Context) {
	if !h.auth.Enabled {
		ctx.Redirect(http.StatusSeeOther, "/")
		return
	}
	if username, ok := h.authenticatedUsername(ctx); ok && username == h.auth.Username {
		ctx.Redirect(http.StatusSeeOther, safeNextPath(ctx.Query("next"), "/"))
		return
	}
	ctx.HTML(http.StatusOK, "login.html", gin.H{
		"Title":       "管理员登录",
		"Next":        safeNextPath(ctx.Query("next"), "/"),
		"AuthEnabled": true,
	})
}

func (h *Handler) login(ctx *gin.Context) {
	if !h.auth.Enabled {
		ctx.Redirect(http.StatusSeeOther, "/")
		return
	}

	username := strings.TrimSpace(ctx.PostForm("username"))
	password := ctx.PostForm("password")
	next := safeNextPath(ctx.PostForm("next"), "/")
	if username != h.auth.Username || !h.verifyPassword(password) {
		_, _ = h.store.CreateLog(models.CreateLogRequest{
			Type:     "system",
			Username: username,
			Message:  "admin login failed",
		})
		ctx.HTML(http.StatusUnauthorized, "login.html", gin.H{
			"Title":       "管理员登录",
			"Next":        next,
			"Error":       "用户名或密码错误",
			"AuthEnabled": true,
		})
		return
	}

	h.setSessionCookie(ctx, username)
	_, _ = h.store.CreateLog(models.CreateLogRequest{
		Type:     "system",
		Username: username,
		Message:  "admin login succeeded",
	})
	ctx.Redirect(http.StatusSeeOther, next)
}

func (h *Handler) logout(ctx *gin.Context) {
	if h.auth.Enabled {
		if username, ok := h.authenticatedUsername(ctx); ok {
			_, _ = h.store.CreateLog(models.CreateLogRequest{
				Type:     "system",
				Username: username,
				Message:  "admin logged out",
			})
		}
	}
	ctx.SetSameSite(http.SameSiteLaxMode)
	ctx.SetCookie(authCookieName, "", -1, "/", "", false, true)
	ctx.Redirect(http.StatusSeeOther, "/login")
}

func (h *Handler) requireAdminPage() gin.HandlerFunc {
	return func(ctx *gin.Context) {
		ctx.Set("auth_enabled", h.auth.Enabled)
		if !h.auth.Enabled {
			ctx.Next()
			return
		}

		username, ok := h.authenticatedUsername(ctx)
		if !ok {
			ctx.Redirect(http.StatusSeeOther, "/login?next="+urlQueryEscape(ctx.Request.URL.RequestURI()))
			ctx.Abort()
			return
		}
		ctx.Set("admin_username", username)
		ctx.Next()
	}
}

func (h *Handler) authenticatedUsername(ctx *gin.Context) (string, bool) {
	cookie, err := ctx.Cookie(authCookieName)
	if err != nil || cookie == "" {
		return "", false
	}

	parts := strings.Split(cookie, ".")
	if len(parts) != 2 {
		return "", false
	}
	payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return "", false
	}
	payload := string(payloadBytes)
	if !h.validSignature(payload, parts[1]) {
		return "", false
	}

	fields := strings.Split(payload, "|")
	if len(fields) != 3 {
		return "", false
	}
	username := fields[0]
	expiresAt, err := strconv.ParseInt(fields[1], 10, 64)
	if err != nil || time.Now().Unix() > expiresAt {
		return "", false
	}
	if username != h.auth.Username {
		return "", false
	}
	return username, true
}

func (h *Handler) setSessionCookie(ctx *gin.Context, username string) {
	nonce, err := randomToken(16)
	if err != nil {
		nonce = strconv.FormatInt(time.Now().UnixNano(), 10)
	}
	payload := fmt.Sprintf("%s|%d|%s", username, time.Now().Add(sessionTTL).Unix(), nonce)
	value := base64.RawURLEncoding.EncodeToString([]byte(payload)) + "." + h.sign(payload)
	ctx.SetSameSite(http.SameSiteLaxMode)
	ctx.SetCookie(authCookieName, value, int(sessionTTL.Seconds()), "/", "", false, true)
}

func (h *Handler) verifyPassword(password string) bool {
	if h.auth.PasswordHash != "" {
		return bcrypt.CompareHashAndPassword([]byte(h.auth.PasswordHash), []byte(password)) == nil
	}
	expected := sha256.Sum256([]byte(h.auth.Password))
	actual := sha256.Sum256([]byte(password))
	return subtle.ConstantTimeCompare(expected[:], actual[:]) == 1
}

func (h *Handler) sign(payload string) string {
	mac := hmac.New(sha256.New, []byte(h.auth.SessionSecret))
	_, _ = mac.Write([]byte(payload))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (h *Handler) validSignature(payload string, signature string) bool {
	expected := h.sign(payload)
	return subtle.ConstantTimeCompare([]byte(expected), []byte(signature)) == 1
}

func envBool(name string, defaultValue bool) bool {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(name)))
	switch value {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return defaultValue
	}
}

func randomToken(size int) (string, error) {
	buf := make([]byte, size)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func safeNextPath(value string, fallback string) string {
	if value == "" || !strings.HasPrefix(value, "/") || strings.HasPrefix(value, "//") || strings.Contains(value, "\\") {
		return fallback
	}
	if strings.HasPrefix(value, "/login") || strings.HasPrefix(value, "/logout") {
		return fallback
	}
	return value
}

func urlQueryEscape(value string) string {
	replacer := strings.NewReplacer(
		"%", "%25",
		" ", "%20",
		"?", "%3F",
		"&", "%26",
		"=", "%3D",
		"#", "%23",
	)
	return replacer.Replace(value)
}
