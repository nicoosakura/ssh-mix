package api

import (
	"encoding/json"
	"log"
	"net/http"
	"server-manager/config"
	"server-manager/middleware"
	"server-manager/models"
	gossh "server-manager/ssh"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// wsMsg 前端发送的消息体
type wsMsg struct {
	Type string `json:"type"` // "input" 或 "resize"
	Data string `json:"data"` // type=input 时的内容
	Cols uint32 `json:"cols"` // type=resize 时的列数
	Rows uint32 `json:"rows"` // type=resize 时的行数
}

// TerminalWS 处理 SSH WebSocket 终端连接
func TerminalWS(c *gin.Context) {
	// 获取 serverID
	serverID := c.Param("id")
	// 从查询参数中获取 token
	tokenStr := c.Query("token")
	if tokenStr == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Token missing"})
		return
	}

	// 验证 token 并在请求上下文中获取 userID
	claims := &middleware.Claims{}
	_, err := jwt.ParseWithClaims(tokenStr, claims, func(token *jwt.Token) (interface{}, error) {
		return middleware.GetJWTSecret(), nil
	})
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Token invalid"})
		return
	}
	userID := claims.UserID

	var server models.Server
	if err := config.DB.Where("user_id = ?", userID).First(&server, serverID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Server not found or access denied"})
		return
	}

	wsConn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println("WebSocket upgrade error:", err)
		return
	}
	defer wsConn.Close()

	sshClient, err := gossh.NewClient(server)
	if err != nil {
		wsConn.WriteMessage(websocket.TextMessage, []byte("连接失败: "+err.Error()))
		return
	}
	defer sshClient.Close()

	// 用于执行独立短命令的辅助 Client
	helperClient, err := gossh.NewClient(server)
	if err != nil {
		wsConn.WriteMessage(websocket.TextMessage, []byte("辅助连接失败: "+err.Error()))
		return
	}
	defer helperClient.Close()

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

	// WebSocket → SSH stdin（支持 JSON resize/input + 兼容纯文本）
readLoop:
	for {
		_, raw, err := wsConn.ReadMessage()
		if err != nil {
			break
		}

		var msg wsMsg
		if jsonErr := json.Unmarshal(raw, &msg); jsonErr == nil && msg.Type != "" {
			switch msg.Type {
			case "resize":
				if msg.Cols > 0 && msg.Rows > 0 {
					_ = session.WindowChange(int(msg.Rows), int(msg.Cols))
				}
			case "input":
				if _, err := stdin.Write([]byte(msg.Data)); err != nil {
					break readLoop
				}
			case "fetch_files":
				// 前端请求特定目录的文件列表
				go func(targetPath string) {
					if targetPath == "" || targetPath == "." || targetPath == "/" {
						// 为了兼容且不破坏基础，这里如果前端传 . 我们默认转为 /，或者前端会传绝对路径
						if targetPath == "." {
							targetPath = "/"
						}
					}
					script := `ls -la ` + targetPath + ` | tail -n +2 | awk '{print $9, $5, $1}'`
					sess, err := helperClient.NewSession()
					if err == nil {
						out, _ := sess.Output(script)
						lines := strings.Split(string(out), "\n")

						type FileItem struct {
							Name  string `json:"name"`
							Size  int64  `json:"size"`
							IsDir bool   `json:"is_dir"`
						}

						var fileList []FileItem
						for _, line := range lines {
							parts := strings.Fields(line)
							if len(parts) >= 3 {
								name := parts[0]
								if name == "." || name == ".." {
									continue
								}
								size, _ := strconv.ParseInt(parts[1], 10, 64)
								isDir := strings.HasPrefix(parts[2], "d")
								fileList = append(fileList, FileItem{
									Name:  name,
									Size:  size,
									IsDir: isDir,
								})
							}
						}

						resultJSON, _ := json.Marshal(map[string]interface{}{
							"_type": "files",
							"pwd":   targetPath,
							"files": fileList,
						})
						wsConn.WriteMessage(websocket.TextMessage, resultJSON)
						sess.Close()
					}
				}(msg.Data)
			}
		} else {
			// 兼容旧格式：纯文本直接转发
			if _, err := stdin.Write(raw); err != nil {
				break readLoop
			}
		}
	}
}

// testSSHConnection 测试 SSH 连接
func testSSHConnection(server models.Server) error {
	client, err := gossh.NewClient(server)
	if err != nil {
		return err
	}
	client.Close()
	return nil
}
