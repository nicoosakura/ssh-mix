package api

import (
	"log"
	"net/http"
	"server-manager/config"
	"server-manager/models"
	gossh "server-manager/ssh"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// TerminalWS 处理 SSH WebSocket 终端连接
func TerminalWS(c *gin.Context) {
	var server models.Server
	if err := config.DB.First(&server, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "服务器不存在"})
		return
	}

	// 升级 HTTP 连接为 WebSocket
	wsConn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println("WebSocket upgrade error:", err)
		return
	}
	defer wsConn.Close()

	// 建立 SSH 连接
	sshClient, err := gossh.NewClient(server)
	if err != nil {
		wsConn.WriteMessage(websocket.TextMessage, []byte("连接失败: "+err.Error()))
		return
	}
	defer sshClient.Close()

	// 开启交互式会话
	session, stdout, stdin, err := gossh.OpenInteractiveSession(sshClient)
	if err != nil {
		wsConn.WriteMessage(websocket.TextMessage, []byte("会话失败: "+err.Error()))
		return
	}
	defer session.Close()

	// SSH stdout → WebSocket
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := stdout.Read(buf)
			if n > 0 {
				if err2 := wsConn.WriteMessage(websocket.BinaryMessage, buf[:n]); err2 != nil {
					break
				}
			}
			if err != nil {
				break
			}
		}
		wsConn.WriteMessage(websocket.TextMessage, []byte("\r\n[连接已断开]"))
		wsConn.Close()
	}()

	// WebSocket → SSH stdin
	for {
		_, msg, err := wsConn.ReadMessage()
		if err != nil {
			break
		}
		if _, err := stdin.Write(msg); err != nil {
			break
		}
	}
}

// testSSHConnection 测试 SSH 连接（供 servers.go 使用）
func testSSHConnection(server models.Server) error {
	client, err := gossh.NewClient(server)
	if err != nil {
		return err
	}
	client.Close()
	return nil
}
