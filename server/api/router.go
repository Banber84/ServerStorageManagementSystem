package api

import (
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"server-storage-management-system/server/models"
	"server-storage-management-system/server/service"
)

type Handler struct {
	store *service.Store
	auth  AuthConfig
}

// NewRouter 注册管理后台页面路由和 REST API 路由。
func NewRouter(store *service.Store) *gin.Engine {
	return NewRouterWithAuth(store, AuthConfig{})
}

func NewRouterWithAuth(store *service.Store, auth AuthConfig) *gin.Engine {
	handler := &Handler{store: store, auth: auth}

	router := gin.Default()
	router.SetFuncMap(map[string]any{
		"formatMB":      formatMB,
		"formatTime":    formatTime,
		"formatTimeISO": formatTimeISO,
		"quotaMB":       quotaMB,
		"quotaUnit":     quotaUnit,
		"quotaValue":    quotaValue,
	})
	router.LoadHTMLGlob("server/templates/*.html")
	router.Static("/static", "server/static")

	router.GET("/login", handler.loginPage)
	router.POST("/login", handler.login)
	router.POST("/logout", handler.logout)

	// 页面路由：提供 Bootstrap 管理后台，适合课程 demo 直接浏览操作。
	pages := router.Group("/")
	pages.Use(handler.requireAdminPage())
	pages.GET("/", handler.dashboardPage)
	pages.GET("/users", handler.usersPage)
	pages.GET("/storage", handler.storagePage)
	pages.GET("/servers", handler.serversPage)
	pages.GET("/logs", handler.logsPage)

	// 表单路由：页面上的创建、删除、修改操作最终也复用 service 层。
	pages.POST("/users", handler.createUserForm)
	pages.POST("/users/:id/delete", handler.deleteUserForm)
	pages.POST("/users/:id/quota", handler.updateQuotaForm)
	pages.POST("/servers/:id/delete", handler.deleteServerForm)
	pages.POST("/logs", handler.createLogForm)

	// REST API：供 Agent、系统脚本和外部测试命令调用。
	group := router.Group("/api")
	group.GET("/health", handler.health)
	group.GET("/dashboard", handler.dashboard)
	group.GET("/users", handler.listUsers)
	group.POST("/users", handler.createUser)
	group.DELETE("/users/:id", handler.deleteUser)
	group.PUT("/users/id/:id/quota", handler.updateQuota)
	group.PUT("/users/username/:username/quota", handler.updateQuotaByUsername)
	group.GET("/storage", handler.listStorageUsage)
	group.POST("/storage", handler.upsertStorageUsage)
	group.POST("/storage/username", handler.upsertStorageUsageByUsername)
	group.GET("/servers", handler.listServers)
	group.DELETE("/servers/:id", handler.deleteServer)
	group.POST("/servers/report", handler.reportServer)
	group.GET("/logs", handler.listLogs)
	group.POST("/logs", handler.createLog)

	return router
}

// 页面处理函数：读取 service 层数据并渲染 HTML 模板。
func (h *Handler) health(ctx *gin.Context) {
	ctx.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func (h *Handler) dashboardPage(ctx *gin.Context) {
	dashboard, err := h.store.Dashboard()
	render(ctx, "dashboard.html", gin.H{"Title": "概览", "Page": "dashboard", "Dashboard": dashboard}, err)
}

func (h *Handler) usersPage(ctx *gin.Context) {
	users, err := h.store.ListUsers()
	render(ctx, "users.html", gin.H{"Title": "用户管理", "Page": "users", "Users": users}, err)
}

func (h *Handler) storagePage(ctx *gin.Context) {
	items, err := h.store.ListStorageUsage()
	render(ctx, "storage.html", gin.H{"Title": "存储统计", "Page": "storage", "Items": items}, err)
}

func (h *Handler) serversPage(ctx *gin.Context) {
	_ = h.store.MarkOfflineAfter(service.ServerOfflineThreshold)
	servers, err := h.store.ListServers()
	render(ctx, "servers.html", gin.H{"Title": "节点监控", "Page": "servers", "Servers": servers}, err)
}

func (h *Handler) logsPage(ctx *gin.Context) {
	filter := logFilterFromQuery(ctx)
	logs, err := h.store.ListLogsFiltered(filter)
	render(ctx, "logs.html", gin.H{"Title": "系统日志", "Page": "logs", "Logs": logs, "Filter": filter}, err)
}

func (h *Handler) dashboard(ctx *gin.Context) {
	dashboard, err := h.store.Dashboard()
	respond(ctx, dashboard, err)
}

// 用户管理 API：创建、删除用户管理记录，以及同步配额。
func (h *Handler) listUsers(ctx *gin.Context) {
	users, err := h.store.ListUsers()
	respond(ctx, users, err)
}

func (h *Handler) createUser(ctx *gin.Context) {
	var req models.CreateUserRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	user, err := h.store.CreateUser(req)
	respondCreated(ctx, user, err)
}

func (h *Handler) createUserForm(ctx *gin.Context) {
	quotaBytes, err := quotaBytesFromForm(ctx)
	if err != nil {
		ctx.String(http.StatusBadRequest, err.Error())
		return
	}
	req := models.CreateUserRequest{
		Username:   ctx.PostForm("username"),
		FullName:   ctx.PostForm("full_name"),
		Email:      ctx.PostForm("email"),
		QuotaBytes: quotaBytes,
	}
	if _, err := h.store.CreateUser(req); err != nil {
		ctx.String(statusCode(err), err.Error())
		return
	}
	ctx.Redirect(http.StatusSeeOther, "/users")
}

func (h *Handler) deleteUser(ctx *gin.Context) {
	id, ok := idParam(ctx)
	if !ok {
		return
	}
	err := h.store.DeleteUser(id)
	respondNoContent(ctx, err)
}

func (h *Handler) deleteUserForm(ctx *gin.Context) {
	id, ok := idParam(ctx)
	if !ok {
		return
	}
	if err := h.store.DeleteUser(id); err != nil {
		ctx.String(statusCode(err), err.Error())
		return
	}
	ctx.Redirect(http.StatusSeeOther, "/users")
}

func (h *Handler) updateQuota(ctx *gin.Context) {
	id, ok := idParam(ctx)
	if !ok {
		return
	}
	var req models.UpdateQuotaRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.store.UpdateQuota(id, req.QuotaBytes)
	respond(ctx, user, err)
}

func (h *Handler) updateQuotaByUsername(ctx *gin.Context) {
	var req models.UpdateQuotaRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.store.UpdateQuotaByUsername(ctx.Param("username"), req.QuotaBytes)
	respond(ctx, user, err)
}

func (h *Handler) updateQuotaForm(ctx *gin.Context) {
	id, ok := idParam(ctx)
	if !ok {
		return
	}
	quotaBytes, err := quotaBytesFromForm(ctx)
	if err != nil {
		ctx.String(http.StatusBadRequest, err.Error())
		return
	}
	if _, err := h.store.UpdateQuota(id, quotaBytes); err != nil {
		ctx.String(statusCode(err), err.Error())
		return
	}
	ctx.Redirect(http.StatusSeeOther, "/users")
}

// 存储统计 API：支持按用户 ID 或用户名写入扫描结果。
func (h *Handler) listStorageUsage(ctx *gin.Context) {
	items, err := h.store.ListStorageUsage()
	respond(ctx, items, err)
}

func (h *Handler) upsertStorageUsage(ctx *gin.Context) {
	var req models.UpdateStorageUsageRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	usage, err := h.store.UpsertStorageUsage(req)
	respond(ctx, usage, err)
}

func (h *Handler) upsertStorageUsageByUsername(ctx *gin.Context) {
	var req models.UpdateStorageUsageByUsernameRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	usage, err := h.store.UpsertStorageUsageByUsername(req)
	respond(ctx, usage, err)
}

// 节点监控 API：接收 Agent 上报，并提供管理员清理节点记录能力。
func (h *Handler) listServers(ctx *gin.Context) {
	_ = h.store.MarkOfflineAfter(service.ServerOfflineThreshold)
	servers, err := h.store.ListServers()
	respond(ctx, servers, err)
}

func (h *Handler) reportServer(ctx *gin.Context) {
	var req models.ServerReportRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	server, err := h.store.UpsertServerReport(req)
	respond(ctx, server, err)
}

func (h *Handler) deleteServer(ctx *gin.Context) {
	id, ok := idParam(ctx)
	if !ok {
		return
	}
	err := h.store.DeleteServer(id)
	respondNoContent(ctx, err)
}

func (h *Handler) deleteServerForm(ctx *gin.Context) {
	id, ok := idParam(ctx)
	if !ok {
		return
	}
	if err := h.store.DeleteServer(id); err != nil {
		ctx.String(statusCode(err), err.Error())
		return
	}
	ctx.Redirect(http.StatusSeeOther, "/servers")
}

// 日志 API：保存系统脚本、登录挂载和后台操作日志。
func (h *Handler) listLogs(ctx *gin.Context) {
	filter := logFilterFromQuery(ctx)
	logs, err := h.store.ListLogsFiltered(filter)
	respond(ctx, logs, err)
}

func (h *Handler) createLog(ctx *gin.Context) {
	var req models.CreateLogRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	log, err := h.store.CreateLog(req)
	respondCreated(ctx, log, err)
}

func (h *Handler) createLogForm(ctx *gin.Context) {
	var req models.CreateLogRequest
	if err := ctx.ShouldBind(&req); err != nil {
		ctx.String(http.StatusBadRequest, err.Error())
		return
	}
	if _, err := h.store.CreateLog(req); err != nil {
		ctx.String(statusCode(err), err.Error())
		return
	}
	ctx.Redirect(http.StatusSeeOther, "/logs")
}

// 响应辅助函数：集中把 service 错误转换为页面文本或 JSON 响应。
func quotaBytesFromForm(ctx *gin.Context) (int64, error) {
	valueText := strings.TrimSpace(ctx.PostForm("quota_value"))
	if valueText == "" {
		return strconv.ParseInt(strings.TrimSpace(ctx.PostForm("quota_bytes")), 10, 64)
	}

	value, err := strconv.ParseFloat(valueText, 64)
	if err != nil || value <= 0 {
		return 0, errors.New("quota_value must be greater than zero")
	}

	unit := strings.ToUpper(strings.TrimSpace(ctx.DefaultPostForm("quota_unit", "MB")))
	var multiplier float64
	switch unit {
	case "MB":
		multiplier = 1024 * 1024
	case "GB":
		multiplier = 1024 * 1024 * 1024
	default:
		return 0, errors.New("quota_unit must be MB or GB")
	}

	bytes := value * multiplier
	if bytes <= 0 || bytes > float64(int64(^uint64(0)>>1)) {
		return 0, errors.New("quota value is out of range")
	}
	return int64(bytes), nil
}

func logFilterFromQuery(ctx *gin.Context) models.LogFilter {
	limit, _ := strconv.Atoi(ctx.DefaultQuery("limit", "100"))
	keyOnly := false
	switch strings.ToLower(strings.TrimSpace(ctx.Query("key_only"))) {
	case "1", "true", "on", "yes":
		keyOnly = true
	}
	return models.LogFilter{
		Level:   strings.ToUpper(strings.TrimSpace(ctx.Query("level"))),
		Type:    strings.ToLower(strings.TrimSpace(ctx.Query("type"))),
		Keyword: strings.TrimSpace(ctx.Query("keyword")),
		KeyOnly: keyOnly,
		Limit:   limit,
	}
}

func formatMB(bytes int64) string {
	return fmt.Sprintf("%.2f MB", float64(bytes)/(1024*1024))
}

func quotaMB(bytes int64) string {
	return fmt.Sprintf("%.2f", float64(bytes)/(1024*1024))
}

func quotaUnit(bytes int64) string {
	if bytes > 0 && bytes%(1024*1024*1024) == 0 {
		return "GB"
	}
	return "MB"
}

func quotaValue(bytes int64) string {
	if quotaUnit(bytes) == "GB" {
		return fmt.Sprintf("%.2f", float64(bytes)/(1024*1024*1024))
	}
	return quotaMB(bytes)
}

func formatTime(value time.Time) string {
	return value.In(chinaLocation()).Format("2006-01-02 15:04:05")
}

func formatTimeISO(value time.Time) string {
	return value.UTC().Format(time.RFC3339)
}

func chinaLocation() *time.Location {
	location, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		return time.FixedZone("Asia/Shanghai", 8*60*60)
	}
	return location
}

func render(ctx *gin.Context, template string, data gin.H, err error) {
	if err != nil {
		ctx.String(statusCode(err), err.Error())
		return
	}
	if _, exists := data["AuthEnabled"]; !exists {
		data["AuthEnabled"] = ctx.GetBool("auth_enabled")
	}
	if _, exists := data["AdminUsername"]; !exists {
		if username, ok := ctx.Get("admin_username"); ok {
			data["AdminUsername"] = username
		}
	}
	ctx.HTML(http.StatusOK, template, data)
}

func respond(ctx *gin.Context, value any, err error) {
	if err != nil {
		ctx.JSON(statusCode(err), gin.H{"error": err.Error()})
		return
	}
	ctx.JSON(http.StatusOK, value)
}

func respondCreated(ctx *gin.Context, value any, err error) {
	if err != nil {
		ctx.JSON(statusCode(err), gin.H{"error": err.Error()})
		return
	}
	ctx.JSON(http.StatusCreated, value)
}

func respondNoContent(ctx *gin.Context, err error) {
	if err != nil {
		ctx.JSON(statusCode(err), gin.H{"error": err.Error()})
		return
	}
	ctx.Status(http.StatusNoContent)
}

func idParam(ctx *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(ctx.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return 0, false
	}
	return id, true
}

func statusCode(err error) int {
	if errors.Is(err, sql.ErrNoRows) {
		return http.StatusNotFound
	}
	return http.StatusBadRequest
}
