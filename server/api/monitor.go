package api

import (
	"log"
	"net"
	"server-manager/config"
	"server-manager/models"
	"strconv"
	"time"
)

// StartBackgroundMonitor 启动后台服务器健康检查器
func StartBackgroundMonitor() {
	log.Println("Background Monitor started: Checking server health every 15s")

	ticker := time.NewTicker(15 * time.Second)
	go func() {
		for range ticker.C {
			checkAllServersStatus()
		}
	}()
}

func checkAllServersStatus() {
	var servers []models.Server
	if err := config.DB.Find(&servers).Error; err != nil {
		log.Println("Monitor Error: Failed to fetch servers:", err)
		return
	}

	for _, s := range servers {
		go func(srv models.Server) {
			status := "offline"

			// 简单的 TCP 端口探测，如果不通则标记为 offline
			// 这样比尝试完整的 SSH 连接更轻量，且能快速反映网络连通性
			addr := net.JoinHostPort(srv.Host, strconv.Itoa(srv.Port))
			conn, err := net.DialTimeout("tcp", addr, 3*time.Second)

			if err == nil {
				status = "online"
				conn.Close()
			}

			// 更新数据库状态
			now := time.Now()
			config.DB.Model(&srv).Updates(map[string]interface{}{
				"status":       status,
				"last_checked": &now,
			})
		}(s)
	}
}
