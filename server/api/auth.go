package api

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"log"
	"net/http"
	"os"
	"server-manager/config"
	"server-manager/middleware"
	"server-manager/models"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

var (
	privateKey   *rsa.PrivateKey
	publicKey    *rsa.PublicKey
	publicKeyPEM string
)

func InitRSAKeys() {
	keyPath := "data/private_key.pem"

	// 确保目录存在
	os.MkdirAll("data", 0755)

	// 尝试从文件加载
	if data, err := os.ReadFile(keyPath); err == nil {
		block, _ := pem.Decode(data)
		if block != nil && block.Type == "RSA PRIVATE KEY" {
			if key, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
				privateKey = key
				publicKey = &privateKey.PublicKey
				generatePublicKeyPEM()
				log.Println("RSA: Loaded existing private key from", keyPath)
				return
			}
		}
	}

	// 生成新密钥
	var err error
	privateKey, err = rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		log.Fatal("Failed to generate RSA keys:", err)
	}
	publicKey = &privateKey.PublicKey

	// 保存私钥
	privBytes := x509.MarshalPKCS1PrivateKey(privateKey)
	privBlock := &pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: privBytes,
	}
	if err := os.WriteFile(keyPath, pem.EncodeToMemory(privBlock), 0600); err != nil {
		log.Printf("Warning: Failed to persist RSA key: %v", err)
	}

	generatePublicKeyPEM()
	log.Println("RSA: Generated and saved new 2048-bit key pair")
}

func generatePublicKeyPEM() {
	pubASN1, err := x509.MarshalPKIXPublicKey(publicKey)
	if err != nil {
		log.Fatal("Failed to marshal public key:", err)
	}

	pubBytes := pem.EncodeToMemory(&pem.Block{
		Type:  "PUBLIC KEY",
		Bytes: pubASN1,
	})
	publicKeyPEM = string(pubBytes)
}

func DecryptPassword(encrypted string) (string, error) {
	decoded, err := base64.StdEncoding.DecodeString(encrypted)
	if err != nil {
		return "", err
	}
	decrypted, err := rsa.DecryptPKCS1v15(rand.Reader, privateKey, decoded)
	if err != nil {
		return "", err
	}
	return string(decrypted), nil
}

func GetLoginPublicKey(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"public_key": publicKeyPEM})
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type ChangePasswordRequest struct {
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=6"`
}

// Login 登录
func Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	var user models.User
	if err := config.DB.Where("username = ?", req.Username).First(&user).Error; err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
		return
	}

	// 解密前端传来的加密密码
	password, err := DecryptPassword(req.Password)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "解密失败，请刷新页面重试"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
		return
	}

	token, err := middleware.GenerateToken(user.ID, user.Username)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "生成令牌失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token":    token,
		"username": user.Username,
		"user_id":  user.ID,
		"role":     user.Role,
	})
}

// Logout 登出（客户端清除 token 即可）
func Logout(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "已登出"})
}

// ChangePassword 修改密码
func ChangePassword(c *gin.Context) {
	userID := c.GetUint("user_id")
	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.OldPassword)); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "原密码错误"})
		return
	}

	newHash, _ := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	config.DB.Model(&user).Update("password", string(newHash))

	c.JSON(http.StatusOK, gin.H{"message": "密码修改成功"})
}
