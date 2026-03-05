import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/server.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import 'terminal_screen.dart';
import 'add_server_screen.dart';
import 'scripts_tab.dart';
import 'containers_tab.dart';

class ServerDetailScreen extends StatefulWidget {
  final Server server;
  const ServerDetailScreen({super.key, required this.server});

  @override
  State<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends State<ServerDetailScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  ServerStats? _stats;
  bool _loading = true;
  String? _error;
  bool _isDisposed = false;
  Timer? _refreshTimer;

  // 历史数据（最多 20 个点）
  final List<double> _cpuHistory = [];
  final List<double> _memHistory = [];
  final List<double> _netRxHistory = [];
  final List<double> _netTxHistory = [];

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);

    _loadStats();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isDisposed) {
        _loadStats(isRefresh: true);
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _refreshTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats({bool isRefresh = false}) async {
    if (!isRefresh) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final stats =
        await context.read<ServerProvider>().getStats(widget.server.id!);

    if (mounted && !_isDisposed) {
      setState(() {
        _stats = stats;
        if (!isRefresh) {
          _loading = false;
          _animCtrl.forward();
        }

        if (stats != null) {
          _error = null;
          _cpuHistory.add(stats.cpuUsage);
          _memHistory.add(stats.memUsage);
          _netRxHistory.add(stats.netRxRate);
          _netTxHistory.add(stats.netTxRate);
          if (_cpuHistory.length > 20) _cpuHistory.removeAt(0);
          if (_memHistory.length > 20) _memHistory.removeAt(0);
          if (_netRxHistory.length > 20) _netRxHistory.removeAt(0);
          if (_netTxHistory.length > 20) _netTxHistory.removeAt(0);
        } else if (!isRefresh) {
          _error = '无法获取服务器状态（请确保服务器在线或检测网络）';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: _currentIndex != 3 ? AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.server.name,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            Text(
              '${widget.server.host}:${widget.server.port}',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: AppTheme.textSecondary),
            tooltip: '编辑',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AddServerScreen(editServer: widget.server),
                ),
              );
              if (result == true && mounted) {
                Navigator.pop(context, true);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
            onPressed: _loadStats,
          ),
        ],
      ) : null, // 终端自带 AppBar
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // 0: 指标
          _buildMetricsTab(),
          // 1: 脚本
          ScriptsTab(server: widget.server),
          // 2: 容器
          ContainersTab(server: widget.server),
          // 3: 终端
          TerminalScreen(server: widget.server),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
        ),
        child: BottomNavigationBar(
          backgroundColor: AppTheme.bgCard,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.textSecondary,
          currentIndex: _currentIndex,
          onTap: (idx) {
            setState(() {
              _currentIndex = idx;
            });
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: '指标'),
            BottomNavigationBarItem(icon: Icon(Icons.code), label: '脚本'),
            BottomNavigationBarItem(icon: Icon(Icons.layers), label: '容器'),
            BottomNavigationBarItem(icon: Icon(Icons.terminal), label: '终端'),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _loadStats);
    }
    return FadeTransition(
      opacity: _fadeAnim,
      child: _StatsView(
        stats: _stats!,
        cpuHistory: _cpuHistory,
        memHistory: _memHistory,
        netRxHistory: _netRxHistory,
        netTxHistory: _netTxHistory,
        onRefresh: _loadStats,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.signal_wifi_off,
                  color: AppTheme.danger, size: 56),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                  onPressed: onRetry, child: const Text('重新获取')),
            ],
          ),
        ),
      );
}

class _StatsView extends StatelessWidget {
  final ServerStats stats;
  final List<double> cpuHistory;
  final List<double> memHistory;
  final List<double> netRxHistory;
  final List<double> netTxHistory;
  final VoidCallback onRefresh;

  const _StatsView({
    required this.stats,
    required this.cpuHistory,
    required this.memHistory,
    required this.netRxHistory,
    required this.netTxHistory,
    required this.onRefresh,
  });

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
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double val = bytes.toDouble();
    while (val >= 1024 && i < units.length - 1) {
      val /= 1024;
      i++;
    }
    return '${val.toStringAsFixed(1)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppTheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 负载 / Unknown 板块 ──
            _SectionCard(
              color: Colors.grey,
              icon: Icons.device_hub,
              title: '系统负载',
              initiallyExpanded: true,
              child: Column(
                children: [
                  Row(
                    children: [
                      _LoadItem(label: '1 分钟', value: stats.load1.toStringAsFixed(2)),
                      _LoadItem(label: '5 分钟', value: stats.load5.toStringAsFixed(2)),
                      _LoadItem(label: '15 分钟', value: stats.load15.toStringAsFixed(2)),
                      _LoadItem(label: '开机时长', value: stats.uptime.isEmpty ? '未知' : stats.uptime),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── CPU 板块 ──
            _SectionCard(
              color: AppTheme.primary,
              icon: Icons.memory,
              title: 'CPU',
              trailingWidget: _CirclePercent(
                percent: stats.cpuUsage / 100,
                color: AppTheme.primary,
                label: '${stats.cpuUsage.toStringAsFixed(0)}%',
              ),
              initiallyExpanded: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CPU 分项 2列 grid
                  _buildTwoColGrid([
                    _StatCell(dot: Colors.red, label: '系统', value: '${stats.cpuSys.toStringAsFixed(1)} %'),
                    _StatCell(dot: Colors.orange, label: '用户', value: '${stats.cpuUser.toStringAsFixed(1)} %'),
                    _StatCell(dot: Colors.green, label: 'I/O 等待', value: '${stats.cpuIowait.toStringAsFixed(1)} %'),
                    _StatCell(dot: Colors.teal, label: 'nice', value: '${stats.cpuNice.toStringAsFixed(1)} %'),
                    _StatCell(dot: Colors.purple, label: '硬中断', value: '${stats.cpuIrq.toStringAsFixed(1)} %'),
                    _StatCell(dot: Colors.blue, label: '软中断', value: '${stats.cpuSoftirq.toStringAsFixed(1)} %'),
                    _StatCell(dot: Colors.amber, label: '抢占', value: '${stats.cpuSteal.toStringAsFixed(1)} %'),
                    _StatCell(dot: Colors.grey, label: 'idle', value: '${(100 - stats.cpuUsage).clamp(0, 100).toStringAsFixed(1)} %'),
                  ]),
                  if (cpuHistory.length > 1) ...[
                    const SizedBox(height: 12),
                    _MiniChart(data: cpuHistory, color: AppTheme.primary, maxY: 100),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── 内存板块 ──
            _SectionCard(
              color: AppTheme.accent,
              icon: Icons.developer_board,
              title: '内存',
              trailingWidget: _CirclePercent(
                percent: stats.memUsage / 100,
                color: AppTheme.accent,
                label: '${stats.memUsage.toStringAsFixed(0)}%',
              ),
              initiallyExpanded: false,
              child: _buildTwoColGrid([
                _StatCell(dot: Colors.red, label: '已用', value: _formatBytes(stats.memTotal - stats.memFree - stats.memCached)),
                _StatCell(dot: Colors.orange, label: '缓冲/缓存', value: _formatBytes(stats.memCached)),
                _StatCell(dot: Colors.green, label: '空闲', value: _formatBytes(stats.memFree)),
                _StatCell(dot: Colors.grey, label: '总计', value: _formatBytes(stats.memTotal)),
              ]),
            ),
            const SizedBox(height: 10),

            // ── 磁盘板块 ──
            _SectionCard(
              color: AppTheme.warning,
              icon: Icons.storage,
              title: '磁盘',
              initiallyExpanded: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTwoColGrid([
                    _StatCell(dot: Colors.orange, label: '已用', value: stats.diskUsedFormatted),
                    _StatCell(dot: Colors.green, label: '可用', value: stats.diskFreeFormatted),
                    _StatCell(dot: Colors.grey, label: '总计', value: stats.diskTotalFormatted),
                    _StatCell(dot: Colors.red, label: '使用率', value: '${stats.diskUsage.toStringAsFixed(1)}%'),
                  ]),
                  if (stats.diskPartitions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(color: AppTheme.border, height: 1),
                    const SizedBox(height: 8),
                    ...stats.diskPartitions.map((p) => _DiskPartitionRow(partition: p)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── 网卡板块 ──
            _SectionCard(
              color: const Color(0xFF42A5F5),
              icon: Icons.wifi,
              title: '网卡',
              initiallyExpanded: false,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _StatCell(dot: Colors.blue, label: '↓ 下载', value: _formatBytesRate(stats.netRxRate))),
                      Expanded(child: _StatCell(dot: Colors.purple, label: '↑ 上传', value: _formatBytesRate(stats.netTxRate))),
                    ],
                  ),
                  if (netRxHistory.length > 1) ...[
                    const SizedBox(height: 12),
                    _DualMiniChart(
                      data1: netRxHistory,
                      data2: netTxHistory,
                      color1: const Color(0xFF42A5F5),
                      color2: const Color(0xFFAB47BC),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── 网络协议统计 ──
            _SectionCard(
              color: const Color(0xFF26C6DA),
              icon: Icons.network_check,
              title: '网络协议',
              initiallyExpanded: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProtocolBlock(
                    tag: 'TCP',
                    tagColor: Colors.blue,
                    items: [
                      _StatCell(label: 'retrans %', value: stats.tcpRetransPct.toStringAsFixed(4)),
                      _StatCell(label: 'estab / resets', value: '${stats.tcpEstab} / ${stats.tcpResets}'),
                      _StatCell(label: '↓ segs', value: '${stats.tcpInSegs}'),
                      _StatCell(label: 'fails', value: '${stats.tcpFails}'),
                      _StatCell(label: '↑ segs', value: '${stats.tcpOutSegs}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ProtocolBlock(
                    tag: 'UDP',
                    tagColor: Colors.orange,
                    items: [
                      _StatCell(label: 'no ports', value: '${stats.udpNoPorts}'),
                      _StatCell(label: '↓ buf errors', value: '${stats.udpInErrors}'),
                      _StatCell(label: '↓ errors', value: '${stats.udpOutErrors}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ProtocolBlock(
                    tag: 'IP',
                    tagColor: Colors.green,
                    items: [
                      _StatCell(label: 'no route', value: '${stats.ipNoRoute}'),
                      _StatCell(label: 'deliver', value: '${stats.ipDeliver}'),
                      _StatCell(label: '↓/↑ discard', value: '${stats.ipDiscard}'),
                      _StatCell(label: 'forward', value: '${stats.ipForward}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ProtocolBlock(
                    tag: 'ICMP',
                    tagColor: Colors.red,
                    items: [
                      _StatCell(label: 'errors', value: '${stats.icmpErrors}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── 进程列表 ──
            if (stats.processes.isNotEmpty)
              _SectionCard(
                color: Colors.purple,
                icon: Icons.list_alt,
                title: '进程列表 (Top ${stats.processes.length})',
                initiallyExpanded: false,
                child: Column(
                  children: [
                    // 表头
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(width: 50, child: Text('PID', style: _headerStyle)),
                          SizedBox(width: 60, child: Text('用户', style: _headerStyle)),
                          SizedBox(width: 50, child: Text('CPU%', style: _headerStyle, textAlign: TextAlign.right)),
                          SizedBox(width: 50, child: Text('MEM%', style: _headerStyle, textAlign: TextAlign.right)),
                          Expanded(child: Text('命令', style: _headerStyle)),
                        ],
                      ),
                    ),
                    const Divider(color: AppTheme.border, height: 1),
                    ...stats.processes.map((p) => _ProcessRow(process: p)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const _headerStyle = TextStyle(
    color: AppTheme.textMuted,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  Widget _buildTwoColGrid(List<_StatCell> cells) {
    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 2) {
      rows.add(Row(
        children: [
          Expanded(child: cells[i]),
          if (i + 1 < cells.length) Expanded(child: cells[i + 1]),
        ],
      ));
      if (i + 2 < cells.length) rows.add(const SizedBox(height: 6));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

// ─────────────────────────────────────────────
// 新辅助 Widgets（NeoServer 风格）
// ─────────────────────────────────────────────


/// 统一折叠卡片 – 左侧带色条，标题行，可折叠内容
class _SectionCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final Widget child;
  final bool initiallyExpanded;
  final Widget? trailingWidget;

  const _SectionCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.hardEdge,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          collapsedIconColor: AppTheme.textSecondary,
          iconColor: color,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (trailingWidget != null) ...[
                trailingWidget!,
                const SizedBox(width: 4),
              ],
            ],
          ),
          children: [child],
        ),
      ),
    );
  }
}

/// 负载项：标签 + 大数值
class _LoadItem extends StatelessWidget {
  final String label;
  final String value;
  const _LoadItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// 小圆形百分比指示器（用于 CPU/内存标题右侧）
class _CirclePercent extends StatelessWidget {
  final double percent;
  final Color color;
  final String label;
  const _CirclePercent({required this.percent, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: percent.clamp(0.0, 1.0),
            strokeWidth: 4,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个数据项：可选彩点 + 标签 + 值
class _StatCell extends StatelessWidget {
  final Color? dot;
  final String label;
  final String value;
  const _StatCell({this.dot, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                Text(value, style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 嵌入式迷你折线图（单线，用于 CPU 卡片内）
class _MiniChart extends StatelessWidget {
  final List<double> data;
  final Color color;
  final double maxY;
  const _MiniChart({required this.data, required this.color, required this.maxY});

  @override
  Widget build(BuildContext context) {
    final spots = data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    return SizedBox(
      height: 80,
      child: LineChart(LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.15)),
          ),
        ],
      )),
    );
  }
}

/// 嵌入式迷你折线图（双线，用于网卡卡片内）
class _DualMiniChart extends StatelessWidget {
  final List<double> data1;
  final List<double> data2;
  final Color color1;
  final Color color2;
  const _DualMiniChart({required this.data1, required this.data2, required this.color1, required this.color2});

  @override
  Widget build(BuildContext context) {
    final spots1 = data1.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value / 1024)).toList();
    final spots2 = data2.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value / 1024)).toList();
    final allVals = [...data1.map((v) => v / 1024), ...data2.map((v) => v / 1024)];
    final maxY = allVals.isEmpty ? 10.0 : (allVals.reduce((a, b) => a > b ? a : b) * 1.3).clamp(1.0, double.infinity);
    return SizedBox(
      height: 80,
      child: LineChart(LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots1,
            isCurved: true,
            color: color1,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: color1.withValues(alpha: 0.1)),
          ),
          LineChartBarData(
            spots: spots2,
            isCurved: true,
            color: color2,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: color2.withValues(alpha: 0.1)),
          ),
        ],
      )),
    );
  }
}

/// 网络协议分组块：带 tag 标签 + 2列数据
class _ProtocolBlock extends StatelessWidget {
  final String tag;
  final Color tagColor;
  final List<_StatCell> items;
  const _ProtocolBlock({required this.tag, required this.tagColor, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tagColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(tag, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 2列 grid
          ...() {
            final rows = <Widget>[];
            for (int i = 0; i < items.length; i += 2) {
              rows.add(Row(
                children: [
                  Expanded(child: items[i]),
                  if (i + 1 < items.length) Expanded(child: items[i + 1]),
                ],
              ));
              if (i + 2 < items.length) rows.add(const SizedBox(height: 4));
            }
            return rows;
          }(),
        ],
      ),
    );
  }
}

/// 磁盘分区行
class _DiskPartitionRow extends StatelessWidget {
  final DiskPartition partition;
  const _DiskPartitionRow({required this.partition});

  String _fmt(int b) {
    if (b <= 0) return '0 B';
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double v = b.toDouble();
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
    return '${v.toStringAsFixed(1)} ${u[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  partition.mountedOn,
                  style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${partition.usePercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: partition.usePercent > 90 ? AppTheme.danger : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (partition.usePercent / 100).clamp(0, 1),
              backgroundColor: AppTheme.warning.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(
                partition.usePercent > 90 ? AppTheme.danger : AppTheme.warning,
              ),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${_fmt(partition.used)} / ${_fmt(partition.size)}  ·  ${partition.filesystem}',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// 进程行
class _ProcessRow extends StatelessWidget {
  final ServerProcess process;
  const _ProcessRow({required this.process});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text('${process.pid}', style: GoogleFonts.jetBrainsMono(color: AppTheme.textSecondary, fontSize: 11)),
          ),
          SizedBox(
            width: 60,
            child: Text(process.user, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 50,
            child: Text('${process.cpu.toStringAsFixed(1)}', style: TextStyle(
              color: process.cpu > 50 ? AppTheme.danger : AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ), textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 50,
            child: Text('${process.mem.toStringAsFixed(1)}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11), textAlign: TextAlign.right),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              process.command,
              style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
