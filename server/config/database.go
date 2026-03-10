package config

import (
	"log"
	"os"
	"path/filepath"
	"server-manager/models"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

var DB *gorm.DB

func InitDB() {
	// 确保数据目录存在
	dataDir := "./data"
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		log.Fatal("Failed to create data directory:", err)
	}

	dbPath := filepath.Join(dataDir, "server_manager.db")
	db, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{})
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}

	// 自动迁移
	if err := db.AutoMigrate(&models.User{}, &models.ServerGroup{}, &models.Server{}, &models.Script{}, &models.AuditLog{}); err != nil {
		log.Fatal("Failed to migrate database:", err)
	}

	DB = db

	// 创建默认管理员账号
	seedAdmin()
}

func seedAdmin() {
	var user models.User
	hash, _ := bcrypt.GenerateFromPassword([]byte("admin123"), bcrypt.DefaultCost)

	// 如果 admin 用户不存在就创建，存在就强制更新密码与权限
	if err := DB.Where("username = ?", "admin").First(&user).Error; err != nil {
		DB.Create(&models.User{
			Username: "admin",
			Password: string(hash),
			Role:     "admin",
		})
		log.Println("Default admin account created: admin/admin123")
	} else {
		// 确保角色也是 admin，防止权限丢失
		DB.Model(&user).Updates(map[string]interface{}{
			"password": string(hash),
			"role":     "admin",
		})
		log.Println("Admin account forced reset: password=admin123, role=admin")
	}
}
