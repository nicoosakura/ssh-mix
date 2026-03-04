package models

import (
	"time"

	"gorm.io/gorm"
)

// User 用户模型
type User struct {
	gorm.Model
	Username string `json:"username" gorm:"uniqueIndex;not null"`
	Password string `json:"-" gorm:"not null"`
}

// ServerGroup 服务器分组
type ServerGroup struct {
	gorm.Model
	Name    string   `json:"name" gorm:"not null"`
	Servers []Server `json:"servers,omitempty" gorm:"foreignKey:GroupID"`
}

// Server 服务器模型
type Server struct {
	gorm.Model
	Name        string       `json:"name" gorm:"not null"`
	Host        string       `json:"host" gorm:"not null"`
	Port        int          `json:"port" gorm:"default:22"`
	Username    string       `json:"username" gorm:"not null"`
	Password    string       `json:"password,omitempty"`
	PrivateKey  string       `json:"private_key,omitempty"`
	Description string       `json:"description"`
	Tags        string       `json:"tags"`
	GroupID     *uint        `json:"group_id"`
	Group       *ServerGroup `json:"group,omitempty" gorm:"foreignKey:GroupID"`
	Status      string       `json:"status" gorm:"default:'unknown'"` // online, offline, unknown
	LastChecked *time.Time   `json:"last_checked,omitempty"`
}

// ServerStats 服务器实时状态
type ServerStats struct {
	ServerID  uint      `json:"server_id"`
	Timestamp time.Time `json:"timestamp"`

	// 基础硬件占用
	CPUUsage  float64 `json:"cpu_usage"`
	MemUsage  float64 `json:"mem_usage"`
	MemTotal  uint64  `json:"mem_total"`
	MemFree   uint64  `json:"mem_free"`
	MemCached uint64  `json:"mem_cached"`
	DiskUsage float64 `json:"disk_usage"`
	DiskTotal uint64  `json:"disk_total"`
	DiskFree  uint64  `json:"disk_free"`

	// 网络速率
	NetRxRate float64 `json:"net_rx_rate"`
	NetTxRate float64 `json:"net_tx_rate"`

	// 运行时间与负载
	Uptime    string  `json:"uptime"`
	UptimeSec uint64  `json:"uptime_sec"`
	Load1     float64 `json:"load1"`
	Load5     float64 `json:"load5"`
	Load15    float64 `json:"load15"`

	// CPU 详细划分 (%)
	CPUSys     float64 `json:"cpu_sys"`
	CPUUser    float64 `json:"cpu_user"`
	CPUIowait  float64 `json:"cpu_iowait"`
	CPUNice    float64 `json:"cpu_nice"`
	CPUIrq     float64 `json:"cpu_irq"`
	CPUSoftirq float64 `json:"cpu_softirq"`
	CPUSteal   float64 `json:"cpu_steal"`
	CPUGuest   float64 `json:"cpu_guest"`
	CPUIp      float64 `json:"cpu_ip"` // Placeholder if needed

	// TCP
	TcpRetrans float64 `json:"tcp_retrans_pct"`
	TcpEstab   uint64  `json:"tcp_estab"`
	TcpResets  uint64  `json:"tcp_resets"`
	TcpFails   uint64  `json:"tcp_fails"`
	TcpInSegs  uint64  `json:"tcp_in_segs"`
	TcpOutSegs uint64  `json:"tcp_out_segs"`

	// UDP
	UdpNoPorts   uint64 `json:"udp_no_ports"`
	UdpInErrors  uint64 `json:"udp_in_errors"`
	UdpOutErrors uint64 `json:"udp_out_errors"`

	// IP / ICMP
	IpNoRoute  uint64 `json:"ip_no_route"`
	IpForward  uint64 `json:"ip_forward"`
	IpDeliver  uint64 `json:"ip_deliver"`
	IpDiscard  uint64 `json:"ip_discard"`
	IcmpErrors uint64 `json:"icmp_errors"`

	// 终端侧边栏扩展
	Processes      []ServerProcess `json:"processes,omitempty"`
	DiskPartitions []DiskPartition `json:"disk_partitions,omitempty"`
}

// ServerProcess 实时进程信息
type ServerProcess struct {
	Pid     int     `json:"pid"`
	User    string  `json:"user"`
	CPU     float64 `json:"cpu"`
	Mem     float64 `json:"mem"`
	Command string  `json:"command"`
}

// DiskPartition 详细磁盘分区
type DiskPartition struct {
	FileSystem string  `json:"filesystem"`
	Size       uint64  `json:"size"`
	Used       uint64  `json:"used"`
	Avail      uint64  `json:"avail"`
	UsePercent float64 `json:"use_percent"`
	MountedOn  string  `json:"mounted_on"`
}

// Script 快捷脚本集
type Script struct {
	gorm.Model
	Name        string `json:"name" gorm:"not null"`
	Description string `json:"description"`
	Content     string `json:"content" gorm:"type:text;not null"`
}
