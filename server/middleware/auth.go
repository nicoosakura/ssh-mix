package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/time/rate"
)

var jwtSecret []byte

func init() {
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		// 生成随机 secret 并打印警告
		b := make([]byte, 32)
		rand.Read(b)
		secret = hex.EncodeToString(b)
		log.Printf("⚠️  JWT_SECRET 未设置，已自动生成临时密钥（重启后失效）。生产环境请设置 JWT_SECRET 环境变量。")
	}
	jwtSecret = []byte(secret)
}

// ─── Rate Limiter ────────────────────────────────────────────────

type ipLimiter struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

var (
	limiters   = make(map[string]*ipLimiter)
	limitersMu sync.Mutex
)

func getLimiter(ip string) *rate.Limiter {
	limitersMu.Lock()
	defer limitersMu.Unlock()

	if il, ok := limiters[ip]; ok {
		il.lastSeen = time.Now()
		return il.limiter
	}

	// 每分钟最多 10 次请求
	l := rate.NewLimiter(rate.Every(6*time.Second), 10)
	limiters[ip] = &ipLimiter{limiter: l, lastSeen: time.Now()}

	// 定期清理过期记录
	go func() {
		time.Sleep(time.Minute * 5)
		limitersMu.Lock()
		for k, v := range limiters {
			if time.Since(v.lastSeen) > time.Minute*5 {
				delete(limiters, k)
			}
		}
		limitersMu.Unlock()
	}()

	return l
}

// LoginRateLimiter 登录速率限制中间件
func LoginRateLimiter() gin.HandlerFunc {
	return func(c *gin.Context) {
		ip, _, err := net.SplitHostPort(c.Request.RemoteAddr)
		if err != nil {
			ip = c.ClientIP()
		}
		if !getLimiter(ip).Allow() {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "请求过于频繁，请稍后再试（每分钟最多尝试 10 次）",
			})
			c.Abort()
			return
		}
		c.Next()
	}
}

// ─── JWT ─────────────────────────────────────────────────────────

type Claims struct {
	UserID   uint   `json:"user_id"`
	Username string `json:"username"`
	jwt.RegisteredClaims
}

func GenerateToken(userID uint, username string) (string, error) {
	claims := Claims{
		UserID:   userID,
		Username: username,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(jwtSecret)
}

func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "未提供认证令牌"})
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "令牌格式错误"})
			c.Abort()
			return
		}

		tokenStr := parts[1]
		claims := &Claims{}
		token, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
			return jwtSecret, nil
		})

		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "令牌无效或已过期"})
			c.Abort()
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("username", claims.Username)
		c.Next()
	}
}

// GetJWTSecret 导出 JWT 密钥供其他包使用
func GetJWTSecret() []byte {
	return jwtSecret
}
