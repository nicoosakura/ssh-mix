package main

import (
	"fmt"
	"log"
	"net/http"
	"server-manager/api"
	"server-manager/config"
	"server-manager/middleware"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// ─── ANSI 色彩常量 ─────────────────────────────────────────
const (
	reset   = "\033[0m"
	bold    = "\033[1m"
	dim     = "\033[2m"
	red     = "\033[31m"
	green   = "\033[32m"
	yellow  = "\033[33m"
	blue    = "\033[34m"
	magenta = "\033[35m"
	cyan    = "\033[36m"
	white   = "\033[37m"
	bgBlue  = "\033[44m"
	bgGreen = "\033[42m"
)

// printBanner 打印启动 Banner
func printBanner() {
	banner := `
` + cyan + bold + `   ╔═══════════════════════════════════════════════════╗
   ║` + reset + magenta + bold + `   ____                             __  __         ` + cyan + bold + `║
   ║` + reset + magenta + bold + `  / __/___  ______ ___  ____       /  |/  /__ ____  ` + cyan + bold + `║
   ║` + reset + magenta + bold + ` _\ \/ -_) / __/ // / / -_) __/   / /|_/ / _ '/ _ \ ` + cyan + bold + `║
   ║` + reset + magenta + bold + `/___/\__/ /_/  \_,_/  \__/_/     /_/  /_/\_,_/_//_/ ` + cyan + bold + `║
   ║` + reset + dim + `               Server Manager API v1.0              ` + cyan + bold + `║
   ╚═══════════════════════════════════════════════════╝` + reset + `
`
	fmt.Print(banner)
}

// printRouteTable 打印路由表
func printRouteTable() {
	fmt.Println()
	fmt.Println(dim + "   ┌──────────────────────────────────────────────┐" + reset)
	fmt.Println(dim + "   │" + reset + bold + "  📡  API Routes                               " + dim + "│" + reset)
	fmt.Println(dim + "   ├──────────────────────────────────────────────┤" + reset)

	routes := []struct {
		method string
		path   string
		desc   string
	}{
		{"POST", "/api/auth/login", "用户登录"},
		{"POST", "/api/auth/logout", "退出登录"},
		{"PUT", "/api/auth/password", "修改密码"},
		{"GET", "/api/servers", "服务器列表"},
		{"POST", "/api/servers", "添加服务器"},
		{"GET", "/api/servers/stats/batch", "批量状态"},
		{"GET", "/api/servers/:id", "服务器详情"},
		{"PUT", "/api/servers/:id", "更新服务器"},
		{"DEL", "/api/servers/:id", "删除服务器"},
		{"POST", "/api/servers/:id/test", "测试连接"},
		{"GET", "/api/servers/:id/stats", "实时状态"},
		{"GET", "/api/groups", "分组列表"},
		{"POST", "/api/groups", "创建分组"},
		{"PUT", "/api/groups/:id", "更新分组"},
		{"DEL", "/api/groups/:id", "删除分组"},
		{"WS", "/ws/servers/:id/terminal", "SSH 终端"},
		{"GET", "/health", "健康检查"},
	}

	for _, r := range routes {
		var methodColor string
		switch r.method {
		case "GET":
			methodColor = green
		case "POST":
			methodColor = cyan
		case "PUT":
			methodColor = yellow
		case "DEL":
			methodColor = red
		case "WS":
			methodColor = magenta
		}
		fmt.Printf(dim+"   │"+reset+"  %s%-4s"+reset+" "+dim+"%-26s"+reset+" %s"+dim+reset+"  "+dim+"\n"+reset,
			methodColor+bold, r.method, r.path, r.desc)
	}

	fmt.Println(dim + "   └──────────────────────────────────────────────┘" + reset)
	fmt.Println()
}

// coloredLogger 自定义彩色请求日志中间件
func coloredLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path

		c.Next()

		latency := time.Since(start)
		status := c.Writer.Status()
		method := c.Request.Method

		// 方法颜色
		var methodColor string
		switch method {
		case "GET":
			methodColor = green
		case "POST":
			methodColor = cyan
		case "PUT":
			methodColor = yellow
		case "DELETE":
			methodColor = red
		default:
			methodColor = white
		}

		// 状态码颜色
		var statusColor string
		switch {
		case status >= 200 && status < 300:
			statusColor = green
		case status >= 300 && status < 400:
			statusColor = cyan
		case status >= 400 && status < 500:
			statusColor = yellow
		default:
			statusColor = red
		}

		// 延时颜色
		var latencyColor string
		switch {
		case latency < 100*time.Millisecond:
			latencyColor = green
		case latency < 500*time.Millisecond:
			latencyColor = yellow
		default:
			latencyColor = red
		}

		// 时间戳
		ts := time.Now().Format("15:04:05")

		fmt.Printf(dim+"  %s"+reset+" %s"+bold+"%-7s"+reset+" %s"+bold+"%d"+reset+" "+latencyColor+"%8s"+reset+" "+dim+"%s"+reset+"\n",
			ts, methodColor, method, statusColor, status, latency.Round(time.Microsecond), path)
	}
}

func main() {
	// 打印启动 Banner
	printBanner()

	// 初始化数据库
	fmt.Printf("  %s⏳ 初始化数据库...%s\n", yellow, reset)
	config.InitDB()
	fmt.Printf("  %s✅ 数据库初始化完成%s\n", green, reset)

	// 使用自定义日志，关闭 Gin 默认日志
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(coloredLogger())

	// 全局 CORS 中间件
	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type,Authorization")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	// API 路由组
	v1 := r.Group("/api")
	{
		// 认证（不需要 JWT）
		auth := v1.Group("/auth")
		{
			auth.POST("/login", api.Login)
			auth.POST("/logout", api.Logout)
		}

		// 需要认证的路由
		protected := v1.Group("/")
		protected.Use(middleware.AuthMiddleware())
		{
			// 修改密码
			protected.PUT("/auth/password", api.ChangePassword)

			// 服务器管理
			servers := protected.Group("/servers")
			{
				servers.GET("", api.GetServers)
				servers.POST("", api.CreateServer)
				servers.GET("/stats/batch", api.GetBatchStats)
				servers.GET("/:id", api.GetServer)
				servers.PUT("/:id", api.UpdateServer)
				servers.DELETE("/:id", api.DeleteServer)
				servers.POST("/:id/test", api.TestConnection)
				servers.GET("/:id/stats", api.GetStats)
			}

			// 服务器分组
			groups := protected.Group("/groups")
			{
				groups.GET("", api.GetGroups)
				groups.POST("", api.CreateGroup)
				groups.PUT("/:id", api.UpdateGroup)
				groups.DELETE("/:id", api.DeleteGroup)
			}

			// Docker 容器管理
			protected.GET("/servers/:id/docker/containers", api.GetDockerContainers)
			protected.POST("/servers/:id/docker/containers/:cid/:action", api.ContainerAction)
			protected.GET("/servers/:id/docker/containers/:cid/logs", api.GetContainerLogs)

			// 脚本管理
			protected.GET("/scripts", api.GetScripts)
			protected.POST("/scripts", api.CreateScript)
			protected.PUT("/scripts/:id", api.UpdateScript)
			protected.DELETE("/scripts/:id", api.DeleteScript)
			protected.POST("/servers/:id/scripts/:script_id/run", api.RunScriptOnServer)
		}
	}

	// WebSocket 终端（通过查询参数 ?token=xxx 进行认证）
	r.GET("/ws/servers/:id/terminal", func(c *gin.Context) {
		tokenStr := c.Query("token")
		if tokenStr == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "未提供认证令牌"})
			return
		}
		claims := &middleware.Claims{}
		token, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
			return middleware.GetJWTSecret(), nil
		})
		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "令牌无效或已过期"})
			return
		}
		c.Set("user_id", claims.UserID)
		api.TerminalWS(c)
	})

	// 健康检查
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok", "service": "Server Manager API"})
	})

	// 打印路由表
	printRouteTable()

	// 启动信息
	port := ":8080"
	fmt.Printf("  %s🚀 Server Manager 已启动%s\n", green+bold, reset)
	fmt.Printf("  %s📍 监听地址: %shttp://localhost%s%s\n", dim, reset+bold+cyan, port, reset)
	fmt.Printf("  %s📋 健康检查: %shttp://localhost%s/health%s\n", dim, reset+cyan, port, reset)
	fmt.Printf("  %s⏱  启动时间: %s%s%s\n\n", dim, reset+white, time.Now().Format("2006-01-02 15:04:05"), reset)
	fmt.Println(dim + "  ─────────────────────────────────────────────────" + reset)
	fmt.Println(dim + "  等待请求中..." + reset)
	fmt.Println()

	if err := r.Run(port); err != nil {
		log.Fatal(err)
	}
}
