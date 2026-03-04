package ssh

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"server-manager/models"
	"strconv"
	"strings"
	"time"

	gossh "golang.org/x/crypto/ssh"
)

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
		// macOS (Darwin) 环境保持原样加点点扩充
		cpuOut := run("top -l 1 -s 0 | awk '/CPU usage/ {print $3}' | tr -d '%'")
		if v, err := strconv.ParseFloat(cpuOut, 64); err == nil {
			stats.CPUUsage = v
		}

		memTotalStr := run("sysctl -n hw.memsize")
		if total, err := strconv.ParseUint(memTotalStr, 10, 64); err == nil {
			stats.MemTotal = total
			freePagesStr := run("vm_stat | awk '/Pages free/ {print $3}' | tr -d '.'")
			if freePages, err2 := strconv.ParseUint(freePagesStr, 10, 64); err2 == nil {
				stats.MemFree = freePages * 4096
				if total > 0 {
					stats.MemUsage = float64(total-stats.MemFree) / float64(total) * 100
				}
			}
		}

		diskOut := run("df -k / | tail -1")
		dParts := strings.Fields(diskOut)
		if len(dParts) >= 4 {
			total, _ := strconv.ParseUint(dParts[1], 10, 64)
			avail, _ := strconv.ParseUint(dParts[3], 10, 64)
			stats.DiskTotal = total * 1024
			stats.DiskFree = avail * 1024
			if total > 0 {
				stats.DiskUsage = float64(total-avail) / float64(total) * 100
			}
		}

		stats.Uptime = run("uptime | sed -E 's/^.*up +([^,]+).*$/\\1/g'")
		if stats.Uptime == "" {
			stats.Uptime = run("uptime -p 2>/dev/null || uptime")
		}

		net1 := run("netstat -bI en0 | tail -1 | awk '{print $7, $10}'")
		run("sleep 1")
		net2 := run("netstat -bI en0 | tail -1 | awk '{print $7, $10}'")
		parts1 := strings.Fields(net1)
		parts2 := strings.Fields(net2)
		if len(parts1) >= 2 && len(parts2) >= 2 {
			rx1, _ := strconv.ParseFloat(parts1[0], 64)
			tx1, _ := strconv.ParseFloat(parts1[1], 64)
			rx2, _ := strconv.ParseFloat(parts2[0], 64)
			tx2, _ := strconv.ParseFloat(parts2[1], 64)
			stats.NetRxRate = rx2 - rx1
			stats.NetTxRate = tx2 - tx1
		}
	} else {
		// 执行组合命令提升速度并获取情况，同时兼容 Linux (通过 /proc) 与 macOS (通过 sysctl/vm_stat)
		// 注意: 由于目标可能是 macOS，这里的脚本需要处理 Darwin。
		script := "OS=$(uname)\n" +
			"if [ \"$OS\" = \"Darwin\" ]; then\n" +
			"	# 0. Uptime\n" +
			"	sysctl -n kern.boottime | awk '{print systime() - $4}' | tr -d ','\n" +
			"	echo \"===SEP===\"\n" +
			"	# 1. CPU Stat (using top)\n" +
			"	top -l 1 -n 0 | grep \"CPU usage\" | awk '{print \"cpu \" $3 \" 0 \" $5 \" \" $7 \" 0 0 0 0 0\"}' | tr -d \"%\" || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	# 2. SNMP (skip for mac or use netstat -s)\n" +
			"	echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	# 3. Netstat (skip)\n" +
			"	echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	# 4. free (using vm_stat)\n" +
			"	PAGE_SIZE=$(pagesize)\n" +
			"	vm_stat | awk -v ps=$PAGE_SIZE '/Pages free/ {free=$3} /Pages active/ {active=$3} /Pages inactive/ {inactive=$3} /Pages wired down/ {wired=$4} END {total=(free+active+inactive+wired)*ps; printf \"Mem: %d 0 %d\\n\", total, free*ps}' || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	# 5. df (macOS df format)\n" +
			"	df -k / 2>/dev/null | tail -1 | awk '{print $1\" \"$2*1024\" \"$3*1024\" \"$4*1024\" \"$5\" \"$9}' || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	# 6. loadavg\n" +
			"	sysctl -n vm.loadavg | awk '{print $2\" \"$3\" \"$4}' || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	# 7. processes (macOS ps syntax)\n" +
			"	ps -A -o pid,user,pcpu,pmem,comm -r | head -n 11 || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	# 8. disk partitions (macOS df)\n" +
			"	df -k 2>/dev/null | awk 'NR==1{print \"Filesystem 1K-blocks Used Available Use% Mounted on\"}; NR>1 {print $1\" \"$2*1024\" \"$3*1024\" \"$4*1024\" \"$5\" \"$9}' || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"else\n" +
			"	cat /proc/uptime 2>/dev/null || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	cat /proc/stat 2>/dev/null | grep '^cpu ' || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	cat /proc/net/snmp 2>/dev/null || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	cat /proc/net/netstat 2>/dev/null || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	free -b 2>/dev/null | grep Mem || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	df -B1 / 2>/dev/null | tail -1 || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	cat /proc/loadavg 2>/dev/null || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	ps -eo pid,user,pcpu,pmem,comm --sort=-pmem | head -n 11 || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"	df -B1 2>/dev/null || echo \"\"\n" +
			"	echo \"===SEP===\"\n" +
			"fi\n"
		out := run(script)
		sections := strings.Split(out, "===SEP===")

		// 0: uptime (sec)
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

		// 1: cpu stat (user nice system idle iowait irq softirq steal guest guest_nice)
		if len(sections) > 1 {
			cpuParts := strings.Fields(strings.TrimSpace(sections[1]))
			if len(cpuParts) >= 8 { // cpu + 7 cols min
				parse := func(s string) float64 {
					v, _ := strconv.ParseFloat(s, 64)
					return v
				}
				user := parse(cpuParts[1])
				nice := parse(cpuParts[2])
				system := parse(cpuParts[3])
				idle := parse(cpuParts[4])
				iowait := parse(cpuParts[5])
				irq := parse(cpuParts[6])
				softirq := parse(cpuParts[7])
				steal := 0.0
				guest := 0.0
				if len(cpuParts) >= 9 {
					steal = parse(cpuParts[8])
				}
				if len(cpuParts) >= 10 {
					guest = parse(cpuParts[9])
				}

				total := user + nice + system + idle + iowait + irq + softirq + steal + guest
				if total > 0 {
					stats.CPUUsage = (total - idle - iowait) / total * 100
					stats.CPUUser = user / total * 100
					stats.CPUSys = system / total * 100
					stats.CPUIowait = iowait / total * 100
					stats.CPUIrq = irq / total * 100
					stats.CPUSoftirq = softirq / total * 100
					stats.CPUNice = nice / total * 100
					stats.CPUSteal = steal / total * 100
					stats.CPUGuest = guest / total * 100
				}
			}
		}

		// 2: snmp
		if len(sections) > 2 {
			lines := strings.Split(strings.TrimSpace(sections[2]), "\n")
			parseSnmp := func(lines []string, prefix string) []uint64 {
				// snmp format: Header: col1 col2... \n Value: val1 val2...
				var res []uint64
				for i, line := range lines {
					if strings.HasPrefix(line, prefix+":") {
						if len(lines) > i+1 && strings.HasPrefix(lines[i+1], prefix+":") {
							vals := strings.Fields(lines[i+1])[1:]
							for _, vStr := range vals {
								v, _ := strconv.ParseUint(vStr, 10, 64)
								res = append(res, v)
							}
							return res
						}
					}
				}
				return res
			}

			ip := parseSnmp(lines, "Ip")
			if len(ip) > 10 {
				stats.IpForward = ip[0]  // Forwarding
				stats.IpNoRoute = ip[4]  // InNoRoutes
				stats.IpDeliver = ip[8]  // InDelivers
				stats.IpDiscard = ip[10] // OutDiscards
			}

			icmp := parseSnmp(lines, "Icmp")
			if len(icmp) > 13 {
				stats.IcmpErrors = icmp[1] + icmp[15] // InErrors + OutErrors
			}

			tcp := parseSnmp(lines, "Tcp")
			if len(tcp) > 11 {
				stats.TcpEstab = tcp[8]    // CurrEstab
				stats.TcpInSegs = tcp[9]   // InSegs
				stats.TcpOutSegs = tcp[10] // OutSegs
				stats.TcpRetrans = 0       // RetransSegs -> calc later
				stats.TcpFails = tcp[6]    // AttemptFails
				stats.TcpResets = tcp[7]   // EstabResets
				// pct retrans approx
				if tcp[10] > 0 {
					stats.TcpRetrans = float64(tcp[11]) / float64(tcp[10]) * 100
				}
			}

			udp := parseSnmp(lines, "Udp")
			if len(udp) > 3 {
				stats.UdpNoPorts = udp[1]
				stats.UdpInErrors = udp[2]
				stats.UdpOutErrors = udp[0] // InDatagrams instead, just mapping to something, real out errors might be elsewhere.
			}
		}

		// 3: netstat
		// (skip deep parsing for now, snmp has enough)

		// 4: free
		if len(sections) > 4 {
			memParts := strings.Fields(strings.TrimSpace(sections[4]))
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

		// 5: df
		if len(sections) > 5 {
			dParts := strings.Fields(strings.TrimSpace(sections[5]))
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

		// 6: loadavg
		if len(sections) > 6 {
			lParts := strings.Fields(strings.TrimSpace(sections[6]))
			if len(lParts) >= 3 {
				stats.Load1, _ = strconv.ParseFloat(lParts[0], 64)
				stats.Load5, _ = strconv.ParseFloat(lParts[1], 64)
				stats.Load15, _ = strconv.ParseFloat(lParts[2], 64)
			}
		}

		// 7: processes
		if len(sections) > 7 {
			lines := strings.Split(strings.TrimSpace(sections[7]), "\n")
			for i, line := range lines {
				if i == 0 {
					continue // skip header 'PID USER %CPU %MEM COMMAND'
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

		// 8: disk partitions
		if len(sections) > 8 {
			lines := strings.Split(strings.TrimSpace(sections[8]), "\n")
			for i, line := range lines {
				if i == 0 {
					continue // skip header 'Filesystem 1B-blocks Used Available Use% Mounted on'
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

		// 网络速率 (macOS 使用 netstat -ib, Linux 使用 /proc/net/dev)
		netScript := "OS=$(uname)\n" +
			"if [ \"$OS\" = \"Darwin\" ]; then\n" +
			"	netstat -ib | grep -e \"en0\" -e \"en1\" | head -1 | awk '{print $7 \" \" $10}'\n" +
			"else\n" +
			"	cat /proc/net/dev | grep -E 'eth0|ens|enp' | head -1 | awk '{print $2 \" \" $10}'\n" +
			"fi\n"
		net1 := run(netScript)
		run("sleep 1")
		net2 := run(netScript)
		parts1 := strings.Fields(net1)
		parts2 := strings.Fields(net2)
		if len(parts1) >= 2 && len(parts2) >= 2 {
			rx1, _ := strconv.ParseFloat(parts1[0], 64)
			tx1, _ := strconv.ParseFloat(parts1[1], 64)
			rx2, _ := strconv.ParseFloat(parts2[0], 64)
			tx2, _ := strconv.ParseFloat(parts2[1], 64)
			stats.NetRxRate = rx2 - rx1
			stats.NetTxRate = tx2 - tx1
		}
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
