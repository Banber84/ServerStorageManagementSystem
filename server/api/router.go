package api

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"server-storage-management-system/server/models"
	"server-storage-management-system/server/service"
)

type Handler struct {
	store *service.Store
}

func NewRouter(store *service.Store) *gin.Engine {
	handler := &Handler{store: store}

	router := gin.Default()
	router.LoadHTMLGlob("server/templates/*.html")

	router.GET("/", handler.dashboardPage)
	router.GET("/users", handler.usersPage)
	router.GET("/storage", handler.storagePage)
	router.GET("/servers", handler.serversPage)
	router.GET("/logs", handler.logsPage)

	router.POST("/users", handler.createUserForm)
	router.POST("/users/:id/delete", handler.deleteUserForm)
	router.POST("/users/:id/quota", handler.updateQuotaForm)
	router.POST("/logs", handler.createLogForm)

	group := router.Group("/api")
	group.GET("/health", handler.health)
	group.GET("/dashboard", handler.dashboard)
	group.GET("/users", handler.listUsers)
	group.POST("/users", handler.createUser)
	group.DELETE("/users/:id", handler.deleteUser)
	group.PUT("/users/:id/quota", handler.updateQuota)
	group.GET("/storage", handler.listStorageUsage)
	group.POST("/storage", handler.upsertStorageUsage)
	group.GET("/servers", handler.listServers)
	group.POST("/servers/report", handler.reportServer)
	group.GET("/logs", handler.listLogs)
	group.POST("/logs", handler.createLog)

	return router
}

func (h *Handler) health(ctx *gin.Context) {
	ctx.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func (h *Handler) dashboardPage(ctx *gin.Context) {
	dashboard, err := h.store.Dashboard()
	render(ctx, "dashboard.html", gin.H{"Title": "Dashboard", "Dashboard": dashboard}, err)
}

func (h *Handler) usersPage(ctx *gin.Context) {
	users, err := h.store.ListUsers()
	render(ctx, "users.html", gin.H{"Title": "Users", "Users": users}, err)
}

func (h *Handler) storagePage(ctx *gin.Context) {
	items, err := h.store.ListStorageUsage()
	render(ctx, "storage.html", gin.H{"Title": "Storage", "Items": items}, err)
}

func (h *Handler) serversPage(ctx *gin.Context) {
	_ = h.store.MarkOfflineAfter(2 * time.Minute)
	servers, err := h.store.ListServers()
	render(ctx, "servers.html", gin.H{"Title": "Servers", "Servers": servers}, err)
}

func (h *Handler) logsPage(ctx *gin.Context) {
	logs, err := h.store.ListLogs(100)
	render(ctx, "logs.html", gin.H{"Title": "Logs", "Logs": logs}, err)
}

func (h *Handler) dashboard(ctx *gin.Context) {
	dashboard, err := h.store.Dashboard()
	respond(ctx, dashboard, err)
}

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
	var req models.CreateUserRequest
	if err := ctx.ShouldBind(&req); err != nil {
		ctx.String(http.StatusBadRequest, err.Error())
		return
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

func (h *Handler) updateQuotaForm(ctx *gin.Context) {
	id, ok := idParam(ctx)
	if !ok {
		return
	}
	quotaBytes, err := strconv.ParseInt(ctx.PostForm("quota_bytes"), 10, 64)
	if err != nil {
		ctx.String(http.StatusBadRequest, "quota_bytes must be an integer")
		return
	}
	if _, err := h.store.UpdateQuota(id, quotaBytes); err != nil {
		ctx.String(statusCode(err), err.Error())
		return
	}
	ctx.Redirect(http.StatusSeeOther, "/users")
}

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

func (h *Handler) listServers(ctx *gin.Context) {
	_ = h.store.MarkOfflineAfter(2 * time.Minute)
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

func (h *Handler) listLogs(ctx *gin.Context) {
	limit, _ := strconv.Atoi(ctx.DefaultQuery("limit", "100"))
	logs, err := h.store.ListLogs(limit)
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

func render(ctx *gin.Context, template string, data gin.H, err error) {
	if err != nil {
		ctx.String(statusCode(err), err.Error())
		return
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
