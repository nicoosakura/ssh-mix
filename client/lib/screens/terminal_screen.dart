import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/server.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';

class TerminalScreen extends StatefulWidget {
  final Server server;
  const TerminalScreen({super.key, required this.server});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late Terminal _terminal;
  late TerminalController _terminalController;
  WebSocketChannel? _channel;
  bool _connected = false;
  String? _error;
  bool _isDisposed = false;
  
  // 侧边栏及监控数据
  ServerStats? _stats;
  Timer? _statsTimer;
  final List<double> _netRxHistory = [];
  final List<double> _netTxHistory = [];
  bool _showSidebar = true;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 5000);
    _terminalController = TerminalController();
    _connect();
    _startStatsPolling();
  }

  void _startStatsPolling() {
    _fetchStats();
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchStats();
    });
  }

  Future<void> _fetchStats() async {
    if (!mounted || _isDisposed) return;
    final provider = context.read<ServerProvider>();
    final stats = await provider.getStats(widget.server.id!);
    if (stats != null && mounted && !_isDisposed) {
      setState(() {
        _stats = stats;
        _netRxHistory.add(stats.netRxRate);
        _netTxHistory.add(stats.netTxRate);
        if (_netRxHistory.length > 20) _netRxHistory.removeAt(0);
        if (_netTxHistory.length > 20) _netTxHistory.removeAt(0);
      });
    }
  }

  Future<void> _connect() async {
    try {
      final url = await ApiService().getTerminalWsUrl(widget.server.id!);
      _channel = WebSocketChannel.connect(Uri.parse(url));
      if (mounted && !_isDisposed) {
        setState(() {
          _connected = true;
          _error = null;
        });
      }

      // 接收来自后端的数据 → 写入终端
      _channel!.stream.listen(
        (data) {
          if (_isDisposed) return;
          if (data is String) {
            _terminal.write(data);
          } else if (data is Uint8List) {
            _terminal.write(String.fromCharCodes(data));
          }
        },
        onDone: () {
          if (mounted && !_isDisposed) {
            _terminal.write('\r\n\x1b[31m[连接已断开]\x1b[0m\r\n');
            setState(() => _connected = false);
          }
        },
        onError: (e) {
          if (mounted && !_isDisposed) {
            setState(() {
              _error = e.toString();
              _connected = false;
            });
          }
        },
      );

      // 终端输入 → 发送到后端
      _terminal.onOutput = (data) {
        if (_channel != null && !_isDisposed) {
          _channel!.sink.add(data);
        }
      };
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() => _error = e.toString());
      }
    }
  }

  void _reconnect() {
    if (_channel != null) {
      _channel!.sink.close();
    }
    _terminal.write('\r\n\x1b[33m[重新连接...]\x1b[0m\r\n');
    _connect();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _channel?.sink.close();
    _statsTimer?.cancel();
    _terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _connected ? AppTheme.success : AppTheme.danger,
                shape: BoxShape.circle,
                boxShadow: _connected
                    ? [
                        BoxShadow(
                          color: AppTheme.success.withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        )
                      ]
                    : [],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              widget.server.name,
              style: GoogleFonts.sourceCodePro(fontSize: 14),
            ),
            const SizedBox(width: 8),
            Text(
              '${widget.server.username}@${widget.server.host}',
              style: GoogleFonts.sourceCodePro(
                  fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showSidebar ? Icons.featured_play_list_rounded : Icons.featured_play_list_outlined,
              color: _showSidebar ? AppTheme.primary : Colors.grey,
            ),
            tooltip: '切换侧边栏',
            onPressed: () {
              setState(() => _showSidebar = !_showSidebar);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            tooltip: '重新连接',
            onPressed: _reconnect,
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            tooltip: '关闭',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Row(
        children: [
          // 左侧 FinalShell 风格看板
          if (_showSidebar)
            Container(
              width: 250,
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                border: Border(right: BorderSide(color: Colors.black, width: 2)),
              ),
              child: _buildSidebar(),
            ),
          // 右侧终端
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppTheme.danger, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          '连接失败\n$_error',
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _reconnect,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : TerminalView(
                    _terminal,
                    controller: _terminalController,
                    theme: const TerminalTheme(
                      cursor: Color(0xFF6C63FF),
                      selection: Color(0x806C63FF),
                      foreground: Color(0xFFE8E8F0),
                      background: Colors.black,
                      black: Color(0xFF000000),
                      red: Color(0xFFFF5252),
                      green: Color(0xFF4CAF50),
                      yellow: Color(0xFFFFB74D),
                      blue: Color(0xFF1E90FF),
                      magenta: Color(0xFFE040FB),
                      cyan: Color(0xFF00D4AA),
                      white: Color(0xFFE8E8F0),
                      brightBlack: Color(0xFF555570),
                      brightRed: Color(0xFFFF6B6B),
                      brightGreen: Color(0xFF69F0AE),
                      brightYellow: Color(0xFFFFD54F),
                      brightBlue: Color(0xFF8D8BFF),
                      brightMagenta: Color(0xFFEA80FC),
                      brightCyan: Color(0xFF18FFFF),
                      brightWhite: Color(0xFFFFFFFF),
                      searchHitBackground: Color(0x80FFB74D),
                      searchHitBackgroundCurrent: Color(0x80FFB74D),
                      searchHitForeground: Color(0xFF000000),
                    ),
                    textStyle: const TerminalStyle(
                      fontFamily: 'Courier New',
                      fontSize: 13,
                    ),
                    autofocus: true,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    if (_stats == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
      );
    }
    final s = _stats!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 基础信息汇总（CPU, Mem, Uptime）
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CPU ${s.cpuUsage.toStringAsFixed(1)}%   运行 ${s.uptime}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 4),
              Text('内存 ${s.memUsage.toStringAsFixed(1)}%   可用 ${_formatBytes(s.memFree)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.black54),
        
        // 2. 进程列表
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: const Color(0xFF2C6C9C), // 模拟 FinalShell 蓝色表头
          child: Row(
            children: const [
              Expanded(flex: 2, child: Text('内存', style: TextStyle(color: Colors.white, fontSize: 11))),
              Expanded(flex: 2, child: Text('CPU', style: TextStyle(color: Colors.white, fontSize: 11))),
              Expanded(flex: 4, child: Text('命令', style: TextStyle(color: Colors.white, fontSize: 11))),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: ListView.builder(
            itemCount: s.processes.length,
            itemBuilder: (context, i) {
              final p = s.processes[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                color: i.isEven ? const Color(0xFF1A1A1A) : const Color(0xFF161616),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text('${p.mem.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white70, fontSize: 11))),
                    Expanded(flex: 2, child: Text('${p.cpu.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white70, fontSize: 11))),
                    Expanded(
                      flex: 4,
                      child: Text(
                        p.command,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const Divider(height: 1, color: Colors.black54),

        // 3. 网络图表与速率
        Container(
          color: const Color(0xFF1E1E1E),
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.arrow_upward, color: Colors.redAccent, size: 10),
                      Text(' ${_formatBytesRate(s.netTxRate)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_downward, color: Colors.greenAccent, size: 10),
                      Text(' ${_formatBytesRate(s.netRxRate)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                  const Text('eth0', style: TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 50,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(show: false),
                    titlesData: FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _netRxHistory.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                        isCurved: true,
                        color: Colors.greenAccent.withValues(alpha: 0.6),
                        barWidth: 1.5,
                        dotData: FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: _netTxHistory.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                        isCurved: true,
                        color: Colors.redAccent.withValues(alpha: 0.6),
                        barWidth: 1.5,
                        dotData: FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.black54),

        // 4. 磁盘列表
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: const Color(0xFF1E1E1E),
          child: Row(
            children: const [
              Expanded(flex: 3, child: Text('路径', style: TextStyle(color: Colors.white54, fontSize: 10))),
              Expanded(flex: 5, child: Text('大小 / 可用', style: TextStyle(color: Colors.white54, fontSize: 10))),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: ListView.builder(
            itemCount: s.diskPartitions.length,
            itemBuilder: (context, i) {
              final d = s.diskPartitions[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text(d.mountedOn, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${_formatBytes(d.size)} / ${_formatBytes(d.avail)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          const SizedBox(height: 2),
                          LinearProgressIndicator(
                            value: d.size > 0 ? (d.used / d.size) : 0,
                            backgroundColor: Colors.white12,
                            color: d.usePercent > 80 ? AppTheme.danger : AppTheme.success,
                            minHeight: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatBytesRate(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    int i = 0;
    double val = bytesPerSec;
    while (val >= 1024 && i < units.length - 1) {
      val /= 1024;
      i++;
    }
    return '${val.toStringAsFixed(1)} ${units[i]}';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'K', 'M', 'G', 'T'];
    int i = 0;
    double val = bytes.toDouble();
    while (val >= 1024 && i < units.length - 1) {
      val /= 1024;
      i++;
    }
    return '${val.toStringAsFixed(1)}${units[i]}';
  }
}
