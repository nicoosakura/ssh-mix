package api

import (
	"net/http"
	"server-manager/config"
	"server-manager/models"

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

	c.JSON(http.StatusOK, gin.H{"message": "用户已删除"})
}
