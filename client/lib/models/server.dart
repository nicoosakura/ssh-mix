class Server {
  final int? id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String? description;
  final String? tags;
  final int? groupId;
  final String status;

  Server({
    this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.description,
    this.tags,
    this.groupId,
    this.status = 'unknown',
  });

  factory Server.fromJson(Map<String, dynamic> json) => Server(
        id: json['ID'] ?? json['id'],
        name: json['name'] ?? '',
        host: json['host'] ?? '',
        port: json['port'] ?? 22,
        username: json['username'] ?? '',
        password: json['password'],
        privateKey: json['private_key'],
        description: json['description'],
        tags: json['tags'],
        groupId: json['group_id'],
        status: json['status'] ?? 'unknown',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password ?? '',
        'private_key': privateKey ?? '',
        'description': description ?? '',
        'tags': tags ?? '',
        'group_id': groupId,
      };

  Server copyWith({
    int? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    String? description,
    String? tags,
    String? status,
  }) =>
      Server(
        id: id ?? this.id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        description: description ?? this.description,
        tags: tags ?? this.tags,
        status: status ?? this.status,
      );
}

class ServerStats {
  final int serverId;
  final DateTime timestamp;

  // Basic Hardware
  final double cpuUsage;
  final double memUsage;
  final int memTotal;
  final int memFree;
  final int memCached;
  final double diskUsage;
  final int diskTotal;
  final int diskFree;

  // Network IO
  final double netRxRate;
  final double netTxRate;

  // Uptime & Load
  final String uptime;
  final int uptimeSec;
  final double load1;
  final double load5;
  final double load15;

  // Detailed CPU
  final double cpuSys;
  final double cpuUser;
  final double cpuIowait;
  final double cpuNice;
  final double cpuIrq;
  final double cpuSoftirq;
  final double cpuSteal;
  final double cpuGuest;

  // TCP
  final double tcpRetransPct;
  final int tcpEstab;
  final int tcpResets;
  final int tcpFails;
  final int tcpInSegs;
  final int tcpOutSegs;

  // UDP
  final int udpNoPorts;
  final int udpInErrors;
  final int udpOutErrors;

  // IP / ICMP
  final int ipNoRoute;
  final int ipForward;
  final int ipDeliver;
  final int ipDiscard;
  final int icmpErrors;

  // Terminal Sidebar Extensions
  final List<ServerProcess> processes;
  final List<DiskPartition> diskPartitions;

  ServerStats({
    required this.serverId,
    required this.timestamp,
    required this.cpuUsage,
    required this.memUsage,
    required this.memTotal,
    required this.memFree,
    this.memCached = 0,
    required this.diskUsage,
    required this.diskTotal,
    required this.diskFree,
    required this.netRxRate,
    required this.netTxRate,
    required this.uptime,
    this.uptimeSec = 0,
    this.load1 = 0.0,
    this.load5 = 0.0,
    this.load15 = 0.0,
    this.cpuSys = 0.0,
    this.cpuUser = 0.0,
    this.cpuIowait = 0.0,
    this.cpuNice = 0.0,
    this.cpuIrq = 0.0,
    this.cpuSoftirq = 0.0,
    this.cpuSteal = 0.0,
    this.cpuGuest = 0.0,
    this.tcpRetransPct = 0.0,
    this.tcpEstab = 0,
    this.tcpResets = 0,
    this.tcpFails = 0,
    this.tcpInSegs = 0,
    this.tcpOutSegs = 0,
    this.udpNoPorts = 0,
    this.udpInErrors = 0,
    this.udpOutErrors = 0,
    this.ipNoRoute = 0,
    this.ipForward = 0,
    this.ipDeliver = 0,
    this.ipDiscard = 0,
    this.icmpErrors = 0,
    this.processes = const [],
    this.diskPartitions = const [],
  });

  factory ServerStats.fromJson(Map<String, dynamic> json) => ServerStats(
        serverId: json['server_id'] ?? 0,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'])
            : DateTime.now(),
        cpuUsage: (json['cpu_usage'] ?? 0.0).toDouble(),
        memUsage: (json['mem_usage'] ?? 0.0).toDouble(),
        memTotal: json['mem_total'] ?? 0,
        memFree: json['mem_free'] ?? 0,
        memCached: json['mem_cached'] ?? 0,
        diskUsage: (json['disk_usage'] ?? 0.0).toDouble(),
        diskTotal: json['disk_total'] ?? 0,
        diskFree: json['disk_free'] ?? 0,
        netRxRate: (json['net_rx_rate'] ?? 0.0).toDouble(),
        netTxRate: (json['net_tx_rate'] ?? 0.0).toDouble(),
        uptime: json['uptime'] ?? '',
        uptimeSec: json['uptime_sec'] ?? 0,
        load1: (json['load1'] ?? 0.0).toDouble(),
        load5: (json['load5'] ?? 0.0).toDouble(),
        load15: (json['load15'] ?? 0.0).toDouble(),
        
        cpuSys: (json['cpu_sys'] ?? 0.0).toDouble(),
        cpuUser: (json['cpu_user'] ?? 0.0).toDouble(),
        cpuIowait: (json['cpu_iowait'] ?? 0.0).toDouble(),
        cpuNice: (json['cpu_nice'] ?? 0.0).toDouble(),
        cpuIrq: (json['cpu_irq'] ?? 0.0).toDouble(),
        cpuSoftirq: (json['cpu_softirq'] ?? 0.0).toDouble(),
        cpuSteal: (json['cpu_steal'] ?? 0.0).toDouble(),
        cpuGuest: (json['cpu_guest'] ?? 0.0).toDouble(),

        tcpRetransPct: (json['tcp_retrans_pct'] ?? 0.0).toDouble(),
        tcpEstab: json['tcp_estab'] ?? 0,
        tcpResets: json['tcp_resets'] ?? 0,
        tcpFails: json['tcp_fails'] ?? 0,
        tcpInSegs: json['tcp_in_segs'] ?? 0,
        tcpOutSegs: json['tcp_out_segs'] ?? 0,

        udpNoPorts: json['udp_no_ports'] ?? 0,
        udpInErrors: json['udp_in_errors'] ?? 0,
        udpOutErrors: json['udp_out_errors'] ?? 0,

        ipNoRoute: json['ip_no_route'] ?? 0,
        ipForward: json['ip_forward'] ?? 0,
        ipDeliver: json['ip_deliver'] ?? 0,
        ipDiscard: json['ip_discard'] ?? 0,
        icmpErrors: json['icmp_errors'] ?? 0,
        processes: (json['processes'] as List<dynamic>? ?? [])
            .map((p) => ServerProcess.fromJson(p))
            .toList(),
        diskPartitions: (json['disk_partitions'] as List<dynamic>? ?? [])
            .map((d) => DiskPartition.fromJson(d))
            .toList(),
      );

  String get memUsedFormatted => _formatBytes(memTotal - memFree);
  String get memTotalFormatted => _formatBytes(memTotal);
  String get diskUsedFormatted => _formatBytes(diskTotal - diskFree);
  String get diskTotalFormatted => _formatBytes(diskTotal);
  String get diskFreeFormatted => _formatBytes(diskFree);

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double val = bytes.toDouble();
    while (val >= 1024 && i < units.length - 1) {
      val /= 1024;
      i++;
    }
    return '${val.toStringAsFixed(1)} ${units[i]}';
  }
}

class ServerGroup {
  final int? id;
  final String name;
  final List<Server> servers;

  ServerGroup({this.id, required this.name, this.servers = const []});

  factory ServerGroup.fromJson(Map<String, dynamic> json) => ServerGroup(
        id: json['ID'] ?? json['id'],
        name: json['name'] ?? '',
        servers: (json['servers'] as List<dynamic>? ?? [])
            .map((s) => Server.fromJson(s))
            .toList(),
      );
}

class ServerProcess {
  final int pid;
  final String user;
  final double cpu;
  final double mem;
  final String command;

  ServerProcess({
    required this.pid,
    required this.user,
    required this.cpu,
    required this.mem,
    required this.command,
  });

  factory ServerProcess.fromJson(Map<String, dynamic> json) => ServerProcess(
        pid: json['pid'] ?? 0,
        user: json['user'] ?? '',
        cpu: (json['cpu'] ?? 0.0).toDouble(),
        mem: (json['mem'] ?? 0.0).toDouble(),
        command: json['command'] ?? '',
      );
}

class DiskPartition {
  final String filesystem;
  final int size;
  final int used;
  final int avail;
  final double usePercent;
  final String mountedOn;

  DiskPartition({
    required this.filesystem,
    required this.size,
    required this.used,
    required this.avail,
    required this.usePercent,
    required this.mountedOn,
  });

  factory DiskPartition.fromJson(Map<String, dynamic> json) => DiskPartition(
        filesystem: json['filesystem'] ?? '',
        size: json['size'] ?? 0,
        used: json['used'] ?? 0,
        avail: json['avail'] ?? 0,
        usePercent: (json['use_percent'] ?? 0.0).toDouble(),
        mountedOn: json['mounted_on'] ?? '',
      );
}
