package ssh

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"server-manager/models"
	"strconv"
	"strings"
	"sync"
	"time"

	gossh "golang.org/x/crypto/ssh"
)

// RawStats 缓存上一次抓取的总量数据与时间戳，用于计算瞬时速率
type RawStats struct {
	Timestamp time.Time
	// CPU ticks
	U, Ni, Sy, Id, Wa, Hi, Si, St, Gu float64
	// NetRx, NetTx (macOS: value; Linux: map[iface]{rx, tx})
	MacRx, MacTx float64
	LinuxNet     map[string][2]float64
}

var statsCache sync.Map // map[uint]RawStats

// NewClient 创建 SSH 客户端
func NewClient(server models.Server) (*gossh.Client, error) {
	var authMethods []gossh.AuthMethod

	if server.PrivateKey != "" {
		signer, err := gossh.ParsePrivateKey([]byte(server.PrivateKey))
		if err == nil {
			authMethods = append(authMethods, gossh.PublicKeys(signer))
		}
	}
	if server.Password != "" {
		authMethods = append(authMethods, gossh.Password(server.Password))
	}
	if len(authMethods) == 0 {
		return nil, fmt.Errorf("未提供认证方式（密码或私钥）")
	}

	config := &gossh.ClientConfig{
		User:            server.Username,
		Auth:            authMethods,
		HostKeyCallback: gossh.InsecureIgnoreHostKey(),
		Timeout:         15 * time.Second,
	}

	addr := net.JoinHostPort(server.Host, strconv.Itoa(server.Port))
	return gossh.Dial("tcp", addr, config)
}

// RunCommand 执行单条命令并返回输出
func RunCommand(server models.Server, command string) (string, error) {
	client, err := NewClient(server)
	if err != nil {
		return "", err
	}
	defer client.Close()

	session, err := client.NewSession()
	if err != nil {
		return "", err
	}
	defer session.Close()

	var buf bytes.Buffer
	session.Stdout = &buf
	session.Stderr = &buf

	if err := session.Run(command); err != nil {
		return buf.String(), err
	}
	return buf.String(), nil
}

// GetStats 获取服务器系统状态 (支持跨平台兼容，参考 WindTerm 逻辑)
func GetStats(server models.Server) (*models.ServerStats, error) {
	client, err := NewClient(server)
	if err != nil {
		return nil, err
	}
	defer client.Close()

	run := func(cmd string) string {
		session, err := client.NewSession()
		if err != nil {
			return ""
		}
		defer session.Close()
		var buf bytes.Buffer
		session.Stdout = &buf
		session.Run(cmd)
		return strings.TrimSpace(buf.String())
	}

	stats := &models.ServerStats{
		ServerID:  server.ID,
		Timestamp: time.Now(),
	}

	// 1. 判断操作系统类型
	osType := run("uname -s")

	if osType == "Darwin" {
		script := `
sysctl -n hw.logicalcpu 2>/dev/null || echo "1"
echo "===SEP==="
ps -A -o %cpu | awk '{s+=$1} END {print s}' 2>/dev/null || echo "0"
echo "===SEP==="
sysctl -n hw.memsize 2>/dev/null || echo "0"
echo "===SEP==="
vm_stat | awk '/Pages free/ {print $3}' | tr -d '.' 2>/dev/null || echo "0"
echo "===SEP==="
df -k 2>/dev/null || echo ""
echo "===SEP==="
uptime | sed -E 's/^.*up +([^,]+).*$/\1/g' 2>/dev/null || echo ""
echo "===SEP==="
netstat -ib | awk '$1 !~ /lo|gif|stf|awdl|llw|utun/ && $3 ~ /<Link/ {rx+=$7; tx+=$10} END {print rx, tx}' 2>/dev/null || echo ""
echo "===SEP==="
ps -A -o pid,user,%cpu,%mem,command -r | head -n 11 2>/dev/null || echo ""
echo "===SEP==="
`
		out := run(script)
		sections := strings.Split(out, "===SEP===")

		// 0: logical cpu
		// 1: total %cpu sum
		if len(sections) > 1 {
			cpusStr := strings.TrimSpace(sections[0])
			sumStr := strings.TrimSpace(sections[1])
			if cpus, err := strconv.ParseFloat(cpusStr, 64); err == nil && cpus > 0 {
				if sum, err := strconv.ParseFloat(sumStr, 64); err == nil {
					stats.CPUUsage = sum / cpus
				}
			}
		}

		// 2: mem total, 3: mem free
		if len(sections) > 3 {
			memTotalStr := strings.TrimSpace(sections[2])
			memFreeStr := strings.TrimSpace(sections[3])
			if total, err := strconv.ParseUint(memTotalStr, 10, 64); err == nil {
				stats.MemTotal = total
				if freePages, err := strconv.ParseUint(memFreeStr, 10, 64); err == nil {
					stats.MemFree = freePages * 4096
					if total > 0 {
						stats.MemUsage = float64(total-stats.MemFree) / float64(total) * 100
					}
				}
			}
		}

		// 4: df -k multi lines
		if len(sections) > 4 {
			for i, line := range strings.Split(strings.TrimSpace(sections[4]), "\n") {
				if i == 0 || line == "" {
					continue
				}
				dParts := strings.Fields(line)
				if len(dParts) >= 6 {
					if strings.HasPrefix(dParts[0], "devfs") || strings.HasPrefix(dParts[0], "map") {
						continue
					}
					sizeK, _ := strconv.ParseUint(dParts[1], 10, 64)
					usedK, _ := strconv.ParseUint(dParts[2], 10, 64)
					availK, _ := strconv.ParseUint(dParts[3], 10, 64)

					size := sizeK * 1024
					used := usedK * 1024
					avail := availK * 1024

					var usePercent float64
					if size > 0 {
						usePercent = float64(used) / float64(size) * 100
					}

					// 累加做整体使用量（取 / 的数据）
					if dParts[len(dParts)-1] == "/" || (dParts[len(dParts)-1] == "Volumes" && stats.DiskTotal == 0) {
						stats.DiskTotal = size
						stats.DiskFree = avail
						stats.DiskUsage = usePercent
					}

					// 收集到 Partitions 中
					mountedOn := dParts[len(dParts)-1]
					// 特殊处理如果挂载点带空格，那就简单合并后面
					if len(dParts) > 8 {
						mountedOn = strings.Join(dParts[8:], " ")
					}

					stats.DiskPartitions = append(stats.DiskPartitions, models.DiskPartition{
						FileSystem: dParts[0],
						Size:       size,
						Used:       used,
						Avail:      avail,
						UsePercent: usePercent,
						MountedOn:  mountedOn,
					})
				}
			}
		}

		// 5: uptime
		if len(sections) > 5 {
			stats.Uptime = strings.TrimSpace(sections[5])
			if stats.Uptime == "" {
				stats.Uptime = run("uptime -p 2>/dev/null || uptime")
			}
		}

		// 6: net
		now := time.Now()
		if len(sections) > 6 {
			netStr := strings.TrimSpace(sections[6])
			parts := strings.Fields(netStr)
			if len(parts) >= 2 {
				rx, _ := strconv.ParseFloat(parts[0], 64)
				tx, _ := strconv.ParseFloat(parts[1], 64)

				if cVal, ok := statsCache.Load(server.ID); ok {
					prev := cVal.(RawStats)
					dt := now.Sub(prev.Timestamp).Seconds()
					if dt > 0 {
						stats.NetRxRate = (rx - prev.MacRx) / dt
						stats.NetTxRate = (tx - prev.MacTx) / dt
						if stats.NetRxRate < 0 {
							stats.NetRxRate = 0
						}
						if stats.NetTxRate < 0 {
							stats.NetTxRate = 0
						}
					}
				}
				statsCache.Store(server.ID, RawStats{
					Timestamp: now,
					MacRx:     rx,
					MacTx:     tx,
				})
			}
		}

		// 7: 进程
		if len(sections) > 7 {
			for i, line := range strings.Split(strings.TrimSpace(sections[7]), "\n") {
				line = strings.TrimSpace(line)
				if i == 0 || line == "" {
					continue
				}
				pParts := strings.Fields(line)
				if len(pParts) >= 5 {
					pid, _ := strconv.Atoi(pParts[0])
					cpu, _ := strconv.ParseFloat(pParts[2], 64)
					mem, _ := strconv.ParseFloat(pParts[3], 64)
					stats.Processes = append(stats.Processes, models.ServerProcess{
						Pid:     pid,
						User:    pParts[1],
						CPU:     cpu,
						Mem:     mem,
						Command: strings.Join(pParts[4:], " "),
					})
				}
			}
		}
	} else {
		// Linux: 组合脚本，无 sleep 的一站式采集
		script := `
cat /proc/uptime 2>/dev/null || echo ""
echo "===SEP==="
cat /proc/stat 2>/dev/null | grep '^cpu '
echo "===SEP==="
ss -s 2>/dev/null || echo ""
echo "===SEP==="
free -b 2>/dev/null | grep Mem || echo ""
echo "===SEP==="
df -B1 / 2>/dev/null | tail -1 || echo ""
echo "===SEP==="
cat /proc/loadavg 2>/dev/null || echo ""
echo "===SEP==="
ps -eo pid,user,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -n 11 || echo ""
echo "===SEP==="
df -B1 2>/dev/null || echo ""
echo "===SEP==="
cat /proc/net/dev 2>/dev/null | awk 'NR>2{print $1,$2,$10}' | grep -v 'lo:' | head -3
echo "===SEP==="
`
		out := run(script)
		sections := strings.Split(out, "===SEP===")

		now := time.Now()
		var currentRaw RawStats
		currentRaw.Timestamp = now
		var hasCache bool
		var prevRaw RawStats
		if cVal, ok := statsCache.Load(server.ID); ok {
			hasCache = true
			prevRaw = cVal.(RawStats)
		}

		// 0: uptime
		if len(sections) > 0 {
			upParts := strings.Fields(strings.TrimSpace(sections[0]))
			if len(upParts) > 0 {
				if sec, err := strconv.ParseFloat(upParts[0], 64); err == nil {
					stats.UptimeSec = uint64(sec)
					d := stats.UptimeSec / 86400
					h := (stats.UptimeSec % 86400) / 3600
					m := (stats.UptimeSec % 3600) / 60
					stats.Uptime = fmt.Sprintf("%d天 %d时 %d分", d, h, m)
				}
			}
		}

		// 1: CPU
		if len(sections) > 1 {
			cpuRaw := strings.TrimSpace(sections[1])
			f := strings.Fields(cpuRaw)
			if len(f) >= 8 {
				p := func(s string) float64 { v, _ := strconv.ParseFloat(s, 64); return v }
				u := p(f[1])
				ni := p(f[2])
				sy := p(f[3])
				id := p(f[4])
				wa := p(f[5])
				hi := p(f[6])
				si := p(f[7])
				var st, gu float64
				if len(f) >= 9 {
					st = p(f[8])
				}
				if len(f) >= 10 {
					gu = p(f[9])
				}

				currentRaw.U, currentRaw.Ni, currentRaw.Sy, currentRaw.Id = u, ni, sy, id
				currentRaw.Wa, currentRaw.Hi, currentRaw.Si, currentRaw.St, currentRaw.Gu = wa, hi, si, st, gu

				if hasCache {
					dUser := u - prevRaw.U
					dNice := ni - prevRaw.Ni
					dSys := sy - prevRaw.Sy
					dIdle := id - prevRaw.Id
					dIowait := wa - prevRaw.Wa
					dIrq := hi - prevRaw.Hi
					dSoftirq := si - prevRaw.Si
					dSteal := st - prevRaw.St
					dGuest := gu - prevRaw.Gu

					dTotal := dUser + dNice + dSys + dIdle + dIowait + dIrq + dSoftirq + dSteal + dGuest
					if dTotal > 0 {
						stats.CPUUsage = (dTotal - dIdle - dIowait) / dTotal * 100
						stats.CPUUser = dUser / dTotal * 100
						stats.CPUSys = dSys / dTotal * 100
						stats.CPUIowait = dIowait / dTotal * 100
						stats.CPUIrq = dIrq / dTotal * 100
						stats.CPUSoftirq = dSoftirq / dTotal * 100
						stats.CPUNice = dNice / dTotal * 100
						stats.CPUSteal = dSteal / dTotal * 100
						stats.CPUGuest = dGuest / dTotal * 100
					}
				}
			}
		}

		// 2: 网络协议统计，使用 ss -s 替代 /proc/net/snmp（容器兼容性更好）
		// ss -s 输出样例：
		// Total: 123
		// TCP:   45 (estab 12, closed 8, timewait 3, ...)
		// Transport Total  IP  IPv6
		// *         123    -    -
		// RAW       0      0    0
		// UDP       10     8    2
		// TCP       37     30   7
		// INET      47     38   9
		// FRAG      0      0    0
		if len(sections) > 2 {
			ssOut := strings.TrimSpace(sections[2])
			for _, line := range strings.Split(ssOut, "\n") {
				line = strings.TrimSpace(line)
				// 解析 TCP estab/timewait 等 from "TCP:   45 (estab 12, closed 8, timewait 3, ...)"
				if strings.HasPrefix(line, "TCP:") {
					// 提取括号内内容
					if idx := strings.Index(line, "("); idx >= 0 {
						inner := line[idx+1:]
						if end := strings.Index(inner, ")"); end >= 0 {
							inner = inner[:end]
						}
						for _, part := range strings.Split(inner, ",") {
							part = strings.TrimSpace(part)
							kv := strings.Fields(part)
							if len(kv) >= 2 {
								val, _ := strconv.ParseUint(kv[1], 10, 64)
								switch kv[0] {
								case "estab":
									stats.TcpEstab = val
								case "timewait":
									stats.TcpResets = val // 复用 resets 字段显示 timewait
								case "closed":
									stats.TcpFails = val
								}
							}
						}
					}
					// 解析总 TCP 数量（括号前的数字）
					parts := strings.Fields(line)
					if len(parts) >= 2 {
						total, _ := strconv.ParseUint(parts[1], 10, 64)
						stats.TcpInSegs = total
					}
				}
				// 解析 UDP 行 "UDP       10     8    2"
				if strings.HasPrefix(line, "UDP") {
					parts := strings.Fields(line)
					if len(parts) >= 2 {
						val, _ := strconv.ParseUint(parts[1], 10, 64)
						stats.UdpNoPorts = val
					}
				}
			}
			// 兼容：若 ss -s 不可用，尝试解析 /proc/net/snmp
			if stats.TcpEstab == 0 && stats.TcpInSegs == 0 {
				parseSnmp := func(lines []string, prefix string) []uint64 {
					var res []uint64
					for i, l := range lines {
						if strings.HasPrefix(l, prefix+":") {
							if len(lines) > i+1 && strings.HasPrefix(lines[i+1], prefix+":") {
								for _, vStr := range strings.Fields(lines[i+1])[1:] {
									v, _ := strconv.ParseUint(vStr, 10, 64)
									res = append(res, v)
								}
								return res
							}
						}
					}
					return res
				}
				snmpLines := strings.Split(ssOut, "\n")
				tcp := parseSnmp(snmpLines, "Tcp")
				if len(tcp) > 11 {
					stats.TcpEstab = tcp[8]
					stats.TcpInSegs = tcp[9]
					stats.TcpOutSegs = tcp[10]
					stats.TcpFails = tcp[6]
					stats.TcpResets = tcp[7]
					if tcp[10] > 0 {
						stats.TcpRetrans = float64(tcp[11]) / float64(tcp[10]) * 100
					}
				}
				udp := parseSnmp(snmpLines, "Udp")
				if len(udp) > 3 {
					stats.UdpNoPorts = udp[1]
					stats.UdpInErrors = udp[2]
				}
				ip := parseSnmp(snmpLines, "Ip")
				if len(ip) > 10 {
					stats.IpForward = ip[0]
					stats.IpNoRoute = ip[4]
					stats.IpDeliver = ip[8]
					stats.IpDiscard = ip[10]
				}
			}
		}

		// 3: free
		if len(sections) > 3 {
			memParts := strings.Fields(strings.TrimSpace(sections[3]))
			if len(memParts) >= 4 {
				total, _ := strconv.ParseUint(memParts[1], 10, 64)
				free, _ := strconv.ParseUint(memParts[3], 10, 64)
				stats.MemTotal = total
				stats.MemFree = free
				if len(memParts) >= 6 {
					cached, _ := strconv.ParseUint(memParts[5], 10, 64)
					stats.MemCached = cached
				}
				if total > 0 {
					stats.MemUsage = float64(total-free) / float64(total) * 100
				}
			}
		}

		// 4: df /
		if len(sections) > 4 {
			dParts := strings.Fields(strings.TrimSpace(sections[4]))
			if len(dParts) >= 4 {
				total, _ := strconv.ParseUint(dParts[1], 10, 64)
				avail, _ := strconv.ParseUint(dParts[3], 10, 64)
				stats.DiskTotal = total
				stats.DiskFree = avail
				if total > 0 {
					stats.DiskUsage = float64(total-avail) / float64(total) * 100
				}
			}
		}

		// 5: loadavg
		if len(sections) > 5 {
			lParts := strings.Fields(strings.TrimSpace(sections[5]))
			if len(lParts) >= 3 {
				stats.Load1, _ = strconv.ParseFloat(lParts[0], 64)
				stats.Load5, _ = strconv.ParseFloat(lParts[1], 64)
				stats.Load15, _ = strconv.ParseFloat(lParts[2], 64)
			}
		}

		// 6: processes
		if len(sections) > 6 {
			lines := strings.Split(strings.TrimSpace(sections[6]), "\n")
			for i, line := range lines {
				if i == 0 {
					continue
				}
				pParts := strings.Fields(line)
				if len(pParts) >= 5 {
					pid, _ := strconv.Atoi(pParts[0])
					cpu, _ := strconv.ParseFloat(pParts[2], 64)
					mem, _ := strconv.ParseFloat(pParts[3], 64)
					stats.Processes = append(stats.Processes, models.ServerProcess{
						Pid:     pid,
						User:    pParts[1],
						CPU:     cpu,
						Mem:     mem,
						Command: strings.Join(pParts[4:], " "),
					})
				}
			}
		}

		// 7: disk partitions
		if len(sections) > 7 {
			lines := strings.Split(strings.TrimSpace(sections[7]), "\n")
			for i, line := range lines {
				if i == 0 {
					continue
				}
				dParts := strings.Fields(line)
				if len(dParts) >= 6 && !strings.HasPrefix(dParts[0], "tmpfs") && !strings.HasPrefix(dParts[0], "devtmpfs") {
					size, _ := strconv.ParseUint(dParts[1], 10, 64)
					used, _ := strconv.ParseUint(dParts[2], 10, 64)
					avail, _ := strconv.ParseUint(dParts[3], 10, 64)
					var usePercent float64
					if size > 0 {
						usePercent = float64(used) / float64(size) * 100
					}
					stats.DiskPartitions = append(stats.DiskPartitions, models.DiskPartition{
						FileSystem: dParts[0],
						Size:       size,
						Used:       used,
						Avail:      avail,
						UsePercent: usePercent,
						MountedOn:  dParts[5],
					})
				}
			}
		}

		// 8: 网络速率
		if len(sections) > 8 {
			netRaw := strings.TrimSpace(sections[8])
			currentRaw.LinuxNet = make(map[string][2]float64)
			for _, l := range strings.Split(netRaw, "\n") {
				f := strings.Fields(l)
				if len(f) >= 3 {
					iface := strings.TrimSuffix(f[0], ":")
					rx, _ := strconv.ParseFloat(f[1], 64)
					tx, _ := strconv.ParseFloat(f[2], 64)
					currentRaw.LinuxNet[iface] = [2]float64{rx, tx}
				}
			}

			if hasCache {
				dt := now.Sub(prevRaw.Timestamp).Seconds()
				if dt > 0 {
					for iface, v2 := range currentRaw.LinuxNet {
						if v1, ok := prevRaw.LinuxNet[iface]; ok {
							stats.NetRxRate = (v2[0] - v1[0]) / dt
							stats.NetTxRate = (v2[1] - v1[1]) / dt
							if stats.NetRxRate < 0 {
								stats.NetRxRate = 0
							}
							if stats.NetTxRate < 0 {
								stats.NetTxRate = 0
							}
							break // 取第一个有效接口
						}
					}
				}
			}
		}
		statsCache.Store(server.ID, currentRaw)
	}

	return stats, nil
}

// OpenInteractiveSession 打开交互式 SSH 会话
func OpenInteractiveSession(client *gossh.Client) (*gossh.Session, io.Reader, io.WriteCloser, error) {
	session, err := client.NewSession()
	if err != nil {
		return nil, nil, nil, err
	}

	// 设置 PTY
	modes := gossh.TerminalModes{
		gossh.ECHO:          1,
		gossh.TTY_OP_ISPEED: 14400,
		gossh.TTY_OP_OSPEED: 14400,
	}
	if err := session.RequestPty("xterm-256color", 40, 80, modes); err != nil {
		session.Close()
		return nil, nil, nil, err
	}

	stdout, _ := session.StdoutPipe()
	stdin, _ := session.StdinPipe()
	session.Stderr = nil

	if err := session.Shell(); err != nil {
		session.Close()
		return nil, nil, nil, err
	}
	return session, stdout, stdin, nil
}

// RunClientCommand 在指定客户端上运行一条短促的命令并返回其输出
func RunClientCommand(client *gossh.Client, cmd string) (string, error) {
	session, err := client.NewSession()
	if err != nil {
		return "", err
	}
	defer session.Close()

	out, err := session.CombinedOutput(cmd)
	return string(out), err
}
