package api

import (
	"net/http"
	"server-manager/config"
	"server-manager/models"
	"server-manager/ssh"

	"github.com/gin-gonic/gin"
)

// GetStats 获取服务器实时状态
func GetStats(c *gin.Context) {
	var server models.Server
	if err := config.DB.First(&server, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器不存在"})
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
		c.JSON(http.StatusBadRequest, gin.H{"error": "至少需要提供一个服务器 ID"})
		return
	}

	var servers []models.Server
	if err := config.DB.Where("id IN ?", ids).Find(&servers).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询服务器失败"})
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
