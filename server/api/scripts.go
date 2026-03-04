package api

import (
	"fmt"
	"net/http"
	"server-manager/config"
	"server-manager/models"
	smanager "server-manager/ssh"

	"github.com/gin-gonic/gin"
)

// GetScripts 获取所有脚本列表
func GetScripts(c *gin.Context) {
	var scripts []models.Script
	if err := config.DB.Find(&scripts).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取脚本失败"})
		return
	}
	c.JSON(http.StatusOK, scripts)
}

// CreateScript 创建脚本
func CreateScript(c *gin.Context) {
	var req models.Script
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误", "details": err.Error()})
		return
	}
	if req.Name == "" || req.Content == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "脚本名称和内容不能为空"})
		return
	}

	if err := config.DB.Create(&req).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败", "details": err.Error()})
		return
	}
	c.JSON(http.StatusOK, req)
}

// UpdateScript 更新脚本
func UpdateScript(c *gin.Context) {
	id := c.Param("id")
	var script models.Script
	if err := config.DB.First(&script, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "未找到脚本"})
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

	config.DB.First(&script, id)
	c.JSON(http.StatusOK, script)
}

// DeleteScript 删除脚本
func DeleteScript(c *gin.Context) {
	id := c.Param("id")
	if err := config.DB.Delete(&models.Script{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败", "details": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// RunScriptOnServer 在指定服务器上运行此脚本
func RunScriptOnServer(c *gin.Context) {
	serverID := c.Param("id")
	scriptID := c.Param("script_id")

	var server models.Server
	if err := config.DB.First(&server, serverID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器未找到"})
		return
	}

	var script models.Script
	if err := config.DB.First(&script, scriptID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "脚本未找到"})
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
