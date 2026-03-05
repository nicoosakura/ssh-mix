package api

import (
	"fmt"
	"net/http"
	"server-manager/config"
	"server-manager/models"
	smanager "server-manager/ssh"

	"github.com/gin-gonic/gin"
)

// GetScripts 获取快捷脚本列表
func GetScripts(c *gin.Context) {
	var scripts []models.Script
	userID := c.MustGet("user_id").(uint)
	if err := config.DB.Where("user_id = ?", userID).Find(&scripts).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取脚本列表失败"})
		return
	}
	c.JSON(http.StatusOK, scripts)
}

// CreateScript 新增快捷脚本
func CreateScript(c *gin.Context) {
	var script models.Script
	if err := c.ShouldBindJSON(&script); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}
	if script.Name == "" || script.Content == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "脚本名称和内容不能为空"})
		return
	}
	script.UserID = c.MustGet("user_id").(uint)
	if err := config.DB.Create(&script).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败", "details": err.Error()})
		return
	}
	c.JSON(http.StatusOK, script)
}

// UpdateScript 更新快捷脚本
func UpdateScript(c *gin.Context) {
	var script models.Script
	userID := c.MustGet("user_id").(uint)
	if err := config.DB.Where("user_id = ?", userID).First(&script, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "脚本不存在或无权限"})
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}

	if err := config.DB.Model(&script).Updates(req).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败", "details": err.Error()})
		return
	}

	config.DB.First(&script, c.Param("id"))
	c.JSON(http.StatusOK, script)
}

// DeleteScript 删除脚本
func DeleteScript(c *gin.Context) {
	userID := c.MustGet("user_id").(uint)
	if err := config.DB.Where("user_id = ?", userID).Delete(&models.Script{}, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败", "details": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// RunScriptOnServer 在指定服务器运行脚本
func RunScriptOnServer(c *gin.Context) {
	serverID := c.Param("serverId")
	scriptID := c.Param("scriptId")
	userID := c.MustGet("user_id").(uint)

	// 1. 获取服务器信息
	var server models.Server
	if err := config.DB.Where("user_id = ?", userID).First(&server, serverID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器不存在或无权限"})
		return
	}

	// 2. 获取脚本信息
	var script models.Script
	if err := config.DB.Where("user_id = ?", userID).First(&script, scriptID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "脚本不存在或无权限"})
		return
	}

	client, err := smanager.NewClient(server)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "无法连接到服务器", "details": err.Error()})
		return
	}
	defer client.Close()

	// 运行多行脚本内容。通过组合输出返回结果。
	cmd := fmt.Sprintf("bash -c %q", script.Content)
	out, err := smanager.RunClientCommand(client, cmd)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "脚本执行失败", "output": out, "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"output": out})
}
