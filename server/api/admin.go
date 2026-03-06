package api

import (
	"net/http"
	"os"
	"runtime"
	"server-manager/config"
	"server-manager/models"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

// AdminCheckMiddleware 检查当前用户是否具有 admin 权限
func AdminCheckMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.MustGet("user_id").(uint)
		var user models.User
		if err := config.DB.First(&user, userID).Error; err != nil || user.Role != "admin" {
			c.JSON(http.StatusForbidden, gin.H{"error": "需要管理员权限"})
			c.Abort()
			return
		}
		c.Next()
	}
}

// LogActivity 记录审计日志
func LogActivity(c *gin.Context, action string, detail string) {
	userID, _ := c.Get("user_id")
	var username string
	if userID != nil {
		var user models.User
		config.DB.First(&user, userID)
		username = user.Username
	}

	logEntry := models.AuditLog{
		UserID:   userID.(uint),
		Username: username,
		Action:   action,
		Detail:   detail,
		IP:       c.ClientIP(),
	}
	config.DB.Create(&logEntry)
}

// AdminGetAuditLogs 获取审计日志列表
func AdminGetAuditLogs(c *gin.Context) {
	var logs []models.AuditLog
	if err := config.DB.Order("created_at desc").Limit(50).Find(&logs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询日志失败"})
		return
	}
	c.JSON(http.StatusOK, logs)
}

// AdminGetUsers 获取所有用户列表
func AdminGetUsers(c *gin.Context) {
	var users []models.User
	if err := config.DB.Select("id", "username", "role", "created_at").Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询用户失败"})
		return
	}
	// gorm 不会返回 password 因为在 model 里用了 json:"-" 且没有 select
	c.JSON(http.StatusOK, users)
}

// AdminGetUserServers 获取某个用户下的所有服务器
func AdminGetUserServers(c *gin.Context) {
	uid := c.Param("uid")
	var servers []models.Server
	if err := config.DB.Preload("Group").Where("user_id = ?", uid).Find(&servers).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询服务器失败"})
		return
	}
	for i := range servers {
		sanitizeServer(&servers[i])
	}
	c.JSON(http.StatusOK, servers)
}

// AdminCreateUser 管理员创建新用户
func AdminCreateUser(c *gin.Context) {
	var req struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
		Role     string `json:"role"` // 可选 admin
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数验证失败"})
		return
	}

	var existing models.User
	if err := config.DB.Where("username = ?", req.Username).First(&existing).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "用户名已存在"})
		return
	}

	hash, _ := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	role := "user"
	if req.Role == "admin" {
		role = "admin"
	}

	newUser := models.User{
		Username: req.Username,
		Password: string(hash),
		Role:     role,
	}

	if err := config.DB.Create(&newUser).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建用户失败"})
		return
	}

	LogActivity(c, "CREATE_USER", "创建用户: "+newUser.Username+" (Role: "+newUser.Role+")")

	// 返回脱敏信息
	c.JSON(http.StatusOK, gin.H{
		"id":         newUser.ID,
		"username":   newUser.Username,
		"role":       newUser.Role,
		"created_at": newUser.CreatedAt,
	})
}

// AdminDeleteUser 管理员删除用户
func AdminDeleteUser(c *gin.Context) {
	uid := c.Param("uid")

	// 不能删除自己
	currentUserID := c.MustGet("user_id").(uint)
	var target models.User
	if err := config.DB.First(&target, uid).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}

	if target.ID == currentUserID {
		c.JSON(http.StatusForbidden, gin.H{"error": "不可删除当前账号"})
		return
	}

	// 这里可以考虑级联删除与之关联的服务器/脚本等，或让 gorm constraint 处理。
	// 为了数据干净，最好在此用事务。但简单起见直接删除
	if err := config.DB.Delete(&target).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	LogActivity(c, "DELETE_USER", "删除用户: "+target.Username+" (UID: "+uid+")")

	c.JSON(http.StatusOK, gin.H{"message": "用户已删除"})
}

// AdminUpdateUser 管理员更新用户信息 (角色或密码)
func AdminUpdateUser(c *gin.Context) {
	uid := c.Param("uid")
	var req struct {
		Role     string `json:"role"`
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数验证失败"})
		return
	}

	var user models.User
	if err := config.DB.First(&user, uid).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}

	updates := make(map[string]interface{})
	if req.Role == "admin" || req.Role == "user" {
		updates["role"] = req.Role
	}
	if req.Password != "" {
		if len(req.Password) < 6 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "密码长度至少 6 位"})
			return
		}
		hash, _ := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
		updates["password"] = string(hash)
	}

	if len(updates) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无有效更新字段"})
		return
	}

	if err := config.DB.Model(&user).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}

	LogActivity(c, "UPDATE_USER", "更新用户: "+user.Username)

	c.JSON(http.StatusOK, gin.H{"message": "更新成功"})
}

var startTime = time.Now()

// AdminGetSystemInfo 获取系统监控信息
func AdminGetSystemInfo(c *gin.Context) {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	hostname, _ := os.Hostname()

	c.JSON(http.StatusOK, gin.H{
		"os":          runtime.GOOS,
		"arch":        runtime.GOARCH,
		"cpus":        runtime.NumCPU(),
		"goroutines":  runtime.NumGoroutine(),
		"mem_alloc":   m.Alloc / 1024 / 1024, // MB
		"mem_total":   m.Sys / 1024 / 1024,   // MB
		"hostname":    hostname,
		"up_time_min": int(time.Since(startTime).Minutes()),
		"go_version":  runtime.Version(),
	})
}

// AdminGetAllServers 获取全平台所有服务器
func AdminGetAllServers(c *gin.Context) {
	var servers []models.Server
	if err := config.DB.Preload("Group").Find(&servers).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询全局服务器失败"})
		return
	}

	var users []models.User
	config.DB.Find(&users)
	userMap := make(map[uint]string)
	for _, u := range users {
		userMap[u.ID] = u.Username
	}

	type ServerResp struct {
		models.Server
		OwnerName string `json:"owner_name"`
	}

	resp := make([]ServerResp, len(servers))
	for i, s := range servers {
		srv := servers[i]
		sanitizeServer(&srv)
		resp[i] = ServerResp{
			Server:    srv,
			OwnerName: userMap[s.UserID],
		}
	}

	c.JSON(http.StatusOK, resp)
}

// AdminGetAllScripts 获取全平台所有脚本
func AdminGetAllScripts(c *gin.Context) {
	var scripts []models.Script
	if err := config.DB.Find(&scripts).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询全局脚本失败"})
		return
	}

	var users []models.User
	config.DB.Find(&users)
	userMap := make(map[uint]string)
	for _, u := range users {
		userMap[u.ID] = u.Username
	}

	type ScriptResp struct {
		models.Script
		OwnerName string `json:"owner_name"`
	}

	resp := make([]ScriptResp, len(scripts))
	for i, s := range scripts {
		resp[i] = ScriptResp{
			Script:    s,
			OwnerName: userMap[s.UserID],
		}
	}

	c.JSON(http.StatusOK, resp)
}

// AdminDeleteServer 管理员全局删除服务器
func AdminDeleteServer(c *gin.Context) {
	sid := c.Param("id")
	var server models.Server
	if err := config.DB.First(&server, sid).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器不存在"})
		return
	}

	if err := config.DB.Delete(&server).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	LogActivity(c, "DELETE_SERVER_GLOBAL", "全局删除服务器: "+server.Name+" (ID: "+sid+")")
	c.JSON(http.StatusOK, gin.H{"message": "资产已成功从全平台移除"})
}

// AdminDeleteScript 管理员全局删除脚本
func AdminDeleteScript(c *gin.Context) {
	sid := c.Param("id")
	var script models.Script
	if err := config.DB.First(&script, sid).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "脚本不存在"})
		return
	}

	if err := config.DB.Delete(&script).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	LogActivity(c, "DELETE_SCRIPT_GLOBAL", "全局删除脚本: "+script.Name+" (ID: "+sid+")")
	c.JSON(http.StatusOK, gin.H{"message": "脚本已从全平台清理"})
}
