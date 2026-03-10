package utils

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const (
	BackupDir     = "./data/backups"
	SourceDB      = "./data/server_manager.db"
	MaxRetainDays = 7
)

// InitBackupScheduler starts a daily backup job
func InitBackupScheduler() {
	if err := os.MkdirAll(BackupDir, 0755); err != nil {
		log.Println("Failed to create backup directory:", err)
		return
	}

	go func() {
		for {
			now := time.Now()
			// Calculate time until next 3 AM
			next := time.Date(now.Year(), now.Month(), now.Day(), 3, 0, 0, 0, now.Location())
			if now.After(next) {
				next = next.Add(24 * time.Hour)
			}

			time.Sleep(next.Sub(now))

			log.Println("Starting scheduled database backup...")
			if err := CreateBackup(); err != nil {
				log.Println("Scheduled backup failed:", err)
			} else {
				log.Println("Scheduled backup completed successfully.")
			}
			CleanOldBackups()
		}
	}()
}

// CreateBackup creates a copy of the sqlite database
func CreateBackup() error {
	if err := os.MkdirAll(BackupDir, 0755); err != nil {
		return err
	}

	timestamp := time.Now().Format("2006-01-02_15-04-05")
	destPath := filepath.Join(BackupDir, fmt.Sprintf("sqlite-%s.db", timestamp))

	return copyFile(SourceDB, destPath)
}

// GetBackups returns a list of available backups, sorted newest first
func GetBackups() ([]map[string]interface{}, error) {
	var backups []map[string]interface{}

	entries, err := os.ReadDir(BackupDir)
	if err != nil {
		if os.IsNotExist(err) {
			return backups, nil
		}
		return nil, err
	}

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".db") {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		backups = append(backups, map[string]interface{}{
			"filename": entry.Name(),
			"size":     info.Size(),
			"time":     info.ModTime().Format(time.RFC3339),
		})
	}

	// Sort newest first
	sort.Slice(backups, func(i, j int) bool {
		timeI, _ := time.Parse(time.RFC3339, backups[i]["time"].(string))
		timeJ, _ := time.Parse(time.RFC3339, backups[j]["time"].(string))
		return timeI.After(timeJ)
	})

	return backups, nil
}

// RestoreBackup restores a specific database backup
func RestoreBackup(filename string) error {
	backupPath := filepath.Join(BackupDir, filename)

	// Ensure the backup exists
	if _, err := os.Stat(backupPath); os.IsNotExist(err) {
		return fmt.Errorf("backup file does not exist")
	}

	// Move current db to a temporary safety copy just in case
	tempSafety := SourceDB + ".tmp"
	if err := copyFile(SourceDB, tempSafety); err != nil {
		return fmt.Errorf("failed to create safety copy of current db: %v", err)
	}

	// Copy backup to current db
	if err := copyFile(backupPath, SourceDB); err != nil {
		// Rollback on failure
		os.Rename(tempSafety, SourceDB)
		return fmt.Errorf("failed to restore backup: %v", err)
	}

	// Remove safety copy on success
	os.Remove(tempSafety)
	return nil
}

// CleanOldBackups removes backups older than MaxRetainDays
func CleanOldBackups() {
	entries, err := os.ReadDir(BackupDir)
	if err != nil {
		return
	}

	threshold := time.Now().AddDate(0, 0, -MaxRetainDays)

	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil {
			continue
		}
		if info.ModTime().Before(threshold) {
			os.Remove(filepath.Join(BackupDir, entry.Name()))
			log.Printf("Cleaned up old backup: %s\n", entry.Name())
		}
	}
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	if _, err = io.Copy(out, in); err != nil {
		return err
	}
	// Explicitly close before sync to catch errors
	if err := out.Sync(); err != nil {
		return err
	}
	return nil
}
