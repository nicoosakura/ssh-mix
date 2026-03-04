package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"server-manager/config"
	"server-manager/models"
	smanager "server-manager/ssh"
	"strings"

	"github.com/gin-gonic/gin"
)

// GetDockerContainers 获取容器列表
func GetDockerContainers(c *gin.Context) {
	serverID := c.Param("id")
	var server models.Server
	if err := config.DB.First(&server, serverID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器未找到"})
		return
	}

	client, err := smanager.NewClient(server)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "无法连接到服务器", "details": err.Error()})
		return
	}
	defer client.Close()

	cmd := `docker ps -a --format '{"id":"{{.ID}}","names":"{{.Names}}","image":"{{.Image}}","state":"{{.State}}","status":"{{.Status}}","ports":"{{.Ports}}"}'`
	out, err := smanager.RunClientCommand(client, cmd)
	if err != nil {
		// Possibly docker is not installed
		c.JSON(http.StatusInternalServerError, gin.H{"error": "无法获取 Docker 状态", "details": err.Error()})
		return
	}

	// Parse JSON output
	var containers []map[string]interface{}
	for _, line := range strings.Split(out, "\n") {
		if line == "" {
			continue
		}
		var con map[string]interface{}
		if err := json.Unmarshal([]byte(line), &con); err == nil {
			containers = append(containers, con)
		}
	}

	c.JSON(http.StatusOK, containers)
}

// ContainerAction 启停容器
func ContainerAction(c *gin.Context) {
	serverID := c.Param("id")
	containerID := c.Param("cid")
	action := c.Param("action") // start, stop, restart, rm

	validActions := map[string]bool{"start": true, "stop": true, "restart": true, "rm": true}
	if !validActions[action] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的动作"})
		return
	}

	var server models.Server
	if err := config.DB.First(&server, serverID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器未找到"})
		return
	}

	client, err := smanager.NewClient(server)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "无法连接到服务器"})
		return
	}
	defer client.Close()

	cmd := fmt.Sprintf("docker %s %s", action, containerID)
	// For 'rm', we might want to force it
	if action == "rm" {
		cmd = fmt.Sprintf("docker rm -f %s", containerID)
	}

	out, err := smanager.RunClientCommand(client, cmd)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "操作执行失败", "output": out, "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "success", "output": out})
}

// GetContainerLogs 查看容器日志
func GetContainerLogs(c *gin.Context) {
	serverID := c.Param("id")
	containerID := c.Param("cid")

	var server models.Server
	if err := config.DB.First(&server, serverID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器未找到"})
		return
	}

	client, err := smanager.NewClient(server)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "无法连接到服务器"})
		return
	}
	defer client.Close()

	cmd := fmt.Sprintf("docker logs --tail 200 %s 2>&1", containerID)
	out, err := smanager.RunClientCommand(client, cmd)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "操作执行失败", "output": out, "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"logs": out})
}
