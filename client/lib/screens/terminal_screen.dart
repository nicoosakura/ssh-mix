import 'dart:convert';
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

class ServerFileSystemItem {
  final String name;
  final int size;
  final bool isDir;

  ServerFileSystemItem({required this.name, required this.size, required this.isDir});

  factory ServerFileSystemItem.fromJson(Map<String, dynamic> json) {
    return ServerFileSystemItem(
      name: json['name'],
      size: json['size'],
      isDir: json['is_dir'],
    );
  }
}

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
  double _timeCounter = 0; // 用于图表X轴滚动
  bool _showSidebar = true;
  
  // 文件系统
  // 文件系统
  List<ServerFileSystemItem> _files = [];
  String _currentPath = '/';

  // 排序状态
  String _processSortCol = ''; // 'cpu', 'mem'
  bool _processSortAsc = false;
  String _fileSortCol = ''; // 'name', 'size'
  bool _fileSortAsc = false;

  int _cols = 220;
  int _rows = 50;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 5000,
      onResize: (cols, rows, pixelW, pixelH) {
        if (cols != _cols || rows != _rows) {
          _cols = cols;
          _rows = rows;
          _sendResize(cols, rows);
        }
      },
    );
    _terminalController = TerminalController();
    _connect();
    _startStatsPolling();
  }

  void _sendResize(int cols, int rows) {
    if (_channel == null || _isDisposed) return;
    _channel!.sink.add(jsonEncode({
      'type': 'resize',
      'cols': cols,
      'rows': rows,
    }));
  }

  void _startStatsPolling() {
    _fetchStats();
    _fetchFiles();
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchStats();
      _fetchFiles();
    });
  }

  void _fetchFiles() {
    if (_channel != null && _connected && !_isDisposed) {
      _channel!.sink.add(jsonEncode({'type': 'fetch_files', 'data': _currentPath}));
    }
  }

  Future<void> _fetchStats() async {
    if (!mounted || _isDisposed) return;
    final provider = context.read<ServerProvider>();
    final stats = await provider.getStats(widget.server.id!);
    if (stats != null && mounted && !_isDisposed) {
      setState(() {
        _stats = stats;
        _timeCounter++;
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
            _handleWebSocketMessage(data);
          } else if (data is Uint8List) {
            _handleWebSocketMessage(String.fromCharCodes(data));
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

      // 终端输入 → 发送到后端（JSON 格式）
      String _currentCommand = '';
      _terminal.onOutput = (data) {
        if (_channel != null && !_isDisposed) {
          _channel!.sink.add(jsonEncode({'type': 'input', 'data': data}));
          
          // 简易判断：提取 cd 命令
          if (data == '\r' || data == '\n') {
            final cmd = _currentCommand.trim();
            if (cmd.startsWith('cd ')) {
              final parts = cmd.split(' ');
              if (parts.length > 1) {
                final target = parts[1].trim();
                if (target.isNotEmpty) {
                  // 如果是相对路径直接替换可能不太对，但这只是简易辅助。最好依靠后端 PWD，但由于 Go 实现受限这里先取此法
                  if (target.startsWith('/')) {
                    _currentPath = target;
                  } else if (target == '..') {
                    final p = _currentPath.split('/');
                    if (p.length > 2) {
                      p.removeLast();
                      _currentPath = p.join('/');
                    } else {
                      _currentPath = '/';
                    }
                  } else {
                    _currentPath = _currentPath.endsWith('/') 
                        ? '$_currentPath$target' 
                        : '$_currentPath/$target';
                  }
                  _fetchFiles(); // 立即刷新
                }
              }
            }
            _currentCommand = '';
          } else if (data == '\x7F') { // backspace
            if (_currentCommand.isNotEmpty) {
              _currentCommand = _currentCommand.substring(0, _currentCommand.length - 1);
            }
          } else {
            _currentCommand += data;
          }
        }
      };

      // 连接成功后立即同步当前窗口大小与文件列表
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!_isDisposed) {
          _sendResize(_cols, _rows);
          _fetchFiles();
        }
      });
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() => _error = e.toString());
      }
    }
  }

  void _handleWebSocketMessage(String raw) {
    // 拦截后端的特殊 JSON 控制信息（如 pwd/files）
    if (raw.startsWith('{"_type":')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded['_type'] == 'files' && mounted && !_isDisposed) {
          setState(() {
            _currentPath = decoded['pwd'] ?? '/';
            _files = (decoded['files'] as List)
                .map((e) => ServerFileSystemItem.fromJson(e))
                .toList();
          });
        }
      } catch (_) {}
      return;
    }
    // 普通的终端输出
    _terminal.write(raw);
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
    final terminalFontSize = context.watch<SettingsProvider>().terminalFontSize;

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
          // 右侧终端区域
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
                : Column(
                    children: [
                      // 快捷指令栏
                      Container(
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E1E1E),
                          border: Border(bottom: BorderSide(color: Colors.black, width: 2)),
                        ),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          children: [
                            _buildQuickCommand('htop', 'htop\n'),
                            _buildQuickCommand('ll', 'ls -la\n'),
                            _buildQuickCommand('docker ps', 'docker ps -a\n'),
                            _buildQuickCommand('nvidia-smi', 'nvidia-smi\n'),
                            _buildQuickCommand('clear', 'clear\n'),
                            _buildQuickCommand('Ctrl+C', '\x03'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TerminalView(
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
                          textStyle: TerminalStyle(
                            fontFamily: 'Courier New',
                            fontSize: terminalFontSize,
                          ),
                          autofocus: true,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }


  Widget _buildQuickCommand(String label, String command) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: () {
          if (_channel != null && _connected && !_isDisposed) {
            _channel!.sink.add(jsonEncode({'type': 'input', 'data': command}));
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF3A3A3A)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFE8E8F0), fontSize: 12),
          ),
        ),
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
            children: [
              Expanded(
                flex: 2, 
                child: GestureDetector(
                  onTap: () => _toggleProcessSort('mem'),
                  child: Row(children: [Text('内存', style: const TextStyle(color: Colors.white, fontSize: 11)), _sortIcon(_processSortCol, 'mem', _processSortAsc)])
                )
              ),
              Expanded(
                flex: 2, 
                child: GestureDetector(
                  onTap: () => _toggleProcessSort('cpu'),
                  child: Row(children: [Text('CPU', style: const TextStyle(color: Colors.white, fontSize: 11)), _sortIcon(_processSortCol, 'cpu', _processSortAsc)])
                )
              ),
              const Expanded(flex: 4, child: Text('命令', style: TextStyle(color: Colors.white, fontSize: 11))),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: ListView.builder(
            itemCount: _sortedProcesses(s.processes).length,
            itemBuilder: (context, i) {
              final p = _sortedProcesses(s.processes)[i];
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
                children: [
                  const Icon(Icons.arrow_upward, color: Colors.redAccent, size: 10),
                  Text(' ${_formatBytesRate(s.netTxRate)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_downward, color: Colors.greenAccent, size: 10),
                  Text(' ${_formatBytesRate(s.netRxRate)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
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
                    minX: _timeCounter > 20 ? _timeCounter - 20 : 0,
                    maxX: _timeCounter > 20 ? _timeCounter : 20,
                    minY: 0,
                    lineBarsData: [
                      LineChartBarData(
                        spots: _netRxHistory.asMap().entries.map((e) {
                          // 将 x轴与 _timeCounter 对齐，实现向左推移
                          double x = _timeCounter > 20 ? (_timeCounter - 20 + e.key) : e.key.toDouble();
                          return FlSpot(x, e.value);
                        }).toList(),
                        isCurved: true,
                        color: Colors.greenAccent.withValues(alpha: 0.6),
                        barWidth: 1.5,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, color: Colors.greenAccent.withValues(alpha: 0.1)),
                      ),
                      LineChartBarData(
                        spots: _netTxHistory.asMap().entries.map((e) {
                          double x = _timeCounter > 20 ? (_timeCounter - 20 + e.key) : e.key.toDouble();
                          return FlSpot(x, e.value);
                        }).toList(),
                        isCurved: true,
                        color: Colors.redAccent.withValues(alpha: 0.6),
                        barWidth: 1.5,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, color: Colors.redAccent.withValues(alpha: 0.1)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.black54),

        // 4. 磁盘/文件 列表
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: const Color(0xFF1E1E1E),
          child: Row(
            children: [
              Expanded(
                flex: 3, 
                child: GestureDetector(
                  onTap: () => _toggleFileSort('name'),
                  child: Row(children: [Text('路径', style: const TextStyle(color: Colors.white54, fontSize: 10)), _sortIcon(_fileSortCol, 'name', _fileSortAsc)])
                )
              ),
              Expanded(
                flex: 5, 
                child: GestureDetector(
                  onTap: () => _toggleFileSort('size'),
                  child: Row(children: [Text('大小 / 可用', style: const TextStyle(color: Colors.white54, fontSize: 10)), _sortIcon(_fileSortCol, 'size', _fileSortAsc)])
                )
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Builder(
            builder: (context) {
              final sortedFiles = _sortedFiles(_files);
              return ListView.builder(
                itemCount: sortedFiles.length + (_currentPath != '/' ? 1 : 0),
                itemBuilder: (context, i) {
                  final isRoot = _currentPath == '/';
                  final isBackItem = !isRoot && i == 0;
                  final f = isBackItem ? ServerFileSystemItem(name: '..', size: 0, isDir: true) : sortedFiles[isRoot ? i : i - 1];
              
              return GestureDetector(
                onDoubleTap: () {
                  if (f.isDir) {
                    setState(() {
                      if (isBackItem) {
                        final p = _currentPath.split('/');
                        p.removeLast();
                        _currentPath = p.join('/');
                        if (_currentPath.isEmpty) _currentPath = '/';
                      } else {
                        if (_currentPath.endsWith('/')) {
                          _currentPath += f.name;
                        } else {
                          _currentPath += '/${f.name}';
                        }
                      }
                    });
                    _fetchFiles();
                  }
                },
                child: Container(
                  color: Colors.transparent, // 确保整个区域可点击
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3, 
                        child: Row(
                          children: [
                            Icon(f.isDir ? Icons.folder : Icons.insert_drive_file, size: 14, color: f.isDir ? Colors.amber : Colors.white70),
                            const SizedBox(width: 4),
                            Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                          ],
                        )
                      ),
                      Expanded(
                        flex: 5,
                        child: Text(
                          f.isDir ? '-' : _formatBytes(f.size), 
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.white70, fontSize: 11)
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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

  Widget _sortIcon(String currentCol, String expectedCol, bool isAsc) {
    if (currentCol != expectedCol) return const SizedBox.shrink();
    return Icon(isAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 10, color: Colors.amber);
  }

  void _toggleProcessSort(String col) {
    setState(() {
      if (_processSortCol == col) {
        _processSortAsc = !_processSortAsc;
      } else {
        _processSortCol = col;
        _processSortAsc = false;
      }
    });
  }

  List<ServerProcess> _sortedProcesses(List<ServerProcess> src) {
    if (_processSortCol.isEmpty) return src;
    final list = List<ServerProcess>.from(src);
    list.sort((a, b) {
      if (_processSortCol == 'mem') {
        return _processSortAsc ? a.mem.compareTo(b.mem) : b.mem.compareTo(a.mem);
      } else if (_processSortCol == 'cpu') {
        return _processSortAsc ? a.cpu.compareTo(b.cpu) : b.cpu.compareTo(a.cpu);
      }
      return 0;
    });
    return list;
  }

  void _toggleFileSort(String col) {
    setState(() {
      if (_fileSortCol == col) {
        _fileSortAsc = !_fileSortAsc;
      } else {
        _fileSortCol = col;
        _fileSortAsc = false;
      }
    });
  }

  List<ServerFileSystemItem> _sortedFiles(List<ServerFileSystemItem> src) {
    if (_fileSortCol.isEmpty) return src;
    final list = List<ServerFileSystemItem>.from(src);
    list.sort((a, b) {
      if (_fileSortCol == 'size') {
        return _fileSortAsc ? a.size.compareTo(b.size) : b.size.compareTo(a.size);
      } else if (_fileSortCol == 'name') {
        return _fileSortAsc ? a.name.compareTo(b.name) : b.name.compareTo(a.name);
      }
      return 0;
    });
    return list;
  }
}
