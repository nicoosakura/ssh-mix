package api

import (
	"net/http"
	"server-manager/config"
	"server-manager/models"
	"server-manager/ssh"

	"github.com/gin-gonic/gin"
)

// GetServerStats 获取服务器的实时状态
func GetServerStats(c *gin.Context) {
	serverID := c.Param("id")
	userID := c.MustGet("user_id").(uint)

	var server models.Server
	if err := config.DB.Where("user_id = ?", userID).First(&server, serverID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器未找到或无权限"})
		return
	}

	stats, err := ssh.GetStats(server)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "无法获取服务器状态: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, stats)
}

// GetBatchStats 并发获取多个服务器实时状态
func GetBatchStats(c *gin.Context) {
	ids := c.QueryArray("id")
	if len(ids) == 0 {
		c.JSON(http.StatusOK, []interface{}{})
		return
	}
	userID := c.MustGet("user_id").(uint)

	var servers []models.Server
	if err := config.DB.Where("user_id = ? AND id IN ?", userID, ids).Find(&servers).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取服务器失败"})
		return
	}

	// 并发获取状态
	type result struct {
		ID    uint                `json:"id"`
		Stats *models.ServerStats `json:"stats,omitempty"`
		Error string              `json:"error,omitempty"`
	}

	results := make([]result, len(servers))
	resultChan := make(chan result, len(servers))

	for _, s := range servers {
		go func(server models.Server) {
			stats, err := ssh.GetStats(server)
			if err != nil {
				resultChan <- result{ID: server.ID, Error: err.Error()}
				return
			}
			resultChan <- result{ID: server.ID, Stats: stats}
		}(s)
	}

	for i := 0; i < len(servers); i++ {
		res := <-resultChan
		// Find index
		for j, s := range servers {
			if s.ID == res.ID {
				results[j] = res
				break
			}
		}
	}

	c.JSON(http.StatusOK, results)
}
