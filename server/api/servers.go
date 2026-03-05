package api

import (
	"net/http"
	"server-manager/config"
	"server-manager/models"
	"strconv"

	"github.com/gin-gonic/gin"
)

// sanitizeServer 清除敏感字段
func sanitizeServer(s *models.Server) {
	s.Password = ""
	s.PrivateKey = ""
}

// GetServers 获取服务器列表
func GetServers(c *gin.Context) {
	var servers []models.Server
	userID := c.MustGet("user_id").(uint)
	query := config.DB.Preload("Group").Where("user_id = ?", userID)

	if groupID := c.Query("group_id"); groupID != "" {
		query = query.Where("group_id = ?", groupID)
	}
	if tag := c.Query("tag"); tag != "" {
		query = query.Where("tags LIKE ?", "%"+tag+"%")
	}
	if search := c.Query("search"); search != "" {
		query = query.Where("name LIKE ? OR host LIKE ? OR description LIKE ?",
			"%"+search+"%", "%"+search+"%", "%"+search+"%")
	}

	if err := query.Find(&servers).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	for i := range servers {
		sanitizeServer(&servers[i])
	}
	c.JSON(http.StatusOK, servers)
}

// GetServer 获取单个服务器
func GetServer(c *gin.Context) {
	var server models.Server
	userID := c.MustGet("user_id").(uint)
	if err := config.DB.Preload("Group").Where("user_id = ?", userID).First(&server, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器不存在或无权限"})
		return
	}
	sanitizeServer(&server)
	c.JSON(http.StatusOK, server)
}

// CreateServer 添加服务器
func CreateServer(c *gin.Context) {
	var server models.Server
	if err := c.ShouldBindJSON(&server); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误: " + err.Error()})
		return
	}
	server.UserID = c.MustGet("user_id").(uint)
	if server.Port == 0 {
		server.Port = 22
	}
	if err := config.DB.Create(&server).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}
	sanitizeServer(&server)
	c.JSON(http.StatusCreated, server)
}

// UpdateServer 更新服务器
func UpdateServer(c *gin.Context) {
	var server models.Server
	userID := c.MustGet("user_id").(uint)
	if err := config.DB.Where("user_id = ?", userID).First(&server, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器不存在或无权限"})
		return
	}
	if err := c.ShouldBindJSON(&server); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}
	config.DB.Save(&server)
	sanitizeServer(&server)
	c.JSON(http.StatusOK, server)
}

// DeleteServer 删除服务器
func DeleteServer(c *gin.Context) {
	userID := c.MustGet("user_id").(uint)
	if err := config.DB.Where("user_id = ?", userID).Delete(&models.Server{}, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// TestConnection 测试服务器连接
func TestConnection(c *gin.Context) {
	var server models.Server
	userID := c.MustGet("user_id").(uint)
	if err := config.DB.Where("user_id = ?", userID).First(&server, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器不存在或无权限"})
		return
	}

	err := testSSHConnection(server)
	if err != nil {
		// 更新状态为离线
		config.DB.Model(&server).Update("status", "offline")
		c.JSON(http.StatusOK, gin.H{"status": "offline", "error": err.Error()})
		return
	}

	config.DB.Model(&server).Update("status", "online")
	c.JSON(http.StatusOK, gin.H{"status": "online"})
}

// GetGroups 获取所有分组
func GetGroups(c *gin.Context) {
	var groups []models.ServerGroup
	userID := c.MustGet("user_id").(uint)
	config.DB.Preload("Servers").Where("user_id = ?", userID).Find(&groups)
	// 清除分组内服务器的敏感字段
	for i := range groups {
		for j := range groups[i].Servers {
			sanitizeServer(&groups[i].Servers[j])
		}
	}
	c.JSON(http.StatusOK, groups)
}

// CreateGroup 创建分组
func CreateGroup(c *gin.Context) {
	var group models.ServerGroup
	if err := c.ShouldBindJSON(&group); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	group.UserID = c.MustGet("user_id").(uint)
	config.DB.Create(&group)
	c.JSON(http.StatusCreated, group)
}

// UpdateGroup 更新分组
func UpdateGroup(c *gin.Context) {
	var group models.ServerGroup
	userID := c.MustGet("user_id").(uint)
	if err := config.DB.Where("user_id = ?", userID).First(&group, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "分组不存在或无权限"})
		return
	}
	var input struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	group.Name = input.Name
	config.DB.Save(&group)
	c.JSON(http.StatusOK, group)
}

// DeleteGroup 删除分组
func DeleteGroup(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	userID := c.MustGet("user_id").(uint)
	// 将该分组下的服务器解除绑定
	config.DB.Model(&models.Server{}).Where("group_id = ? AND user_id = ?", id, userID).Update("group_id", nil)
	config.DB.Where("user_id = ?", userID).Delete(&models.ServerGroup{}, id)
	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}
