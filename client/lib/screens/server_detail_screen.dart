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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppTheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 概览卡片
            Row(
              children: [
                Expanded(
                    child: _MetricCard(
                  label: 'CPU',
                  value: '${stats.cpuUsage.toStringAsFixed(1)}%',
                  icon: Icons.memory,
                  color: AppTheme.primary,
                  percent: stats.cpuUsage / 100,
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: _MetricCard(
                  label: '内存',
                  value: '${stats.memUsage.toStringAsFixed(1)}%',
                  icon: Icons.storage,
                  color: AppTheme.accent,
                  percent: stats.memUsage / 100,
                  sub:
                      '${stats.memUsedFormatted} / ${stats.memTotalFormatted}',
                )),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _MetricCard(
                  label: '磁盘',
                  value: '${stats.diskUsage.toStringAsFixed(1)}%',
                  icon: Icons.disc_full_rounded,
                  color: AppTheme.warning,
                  percent: stats.diskUsage / 100,
                  sub:
                      '${stats.diskUsedFormatted} / ${stats.diskTotalFormatted}',
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: _InfoCard(
                  label: '运行时间',
                  value: stats.uptime,
                  icon: Icons.timer_outlined,
                  color: AppTheme.success,
                )),
              ],
            ),
            const SizedBox(height: 12),
            // CPU 详细信息折叠面板
            if (stats.cpuUser > 0 || stats.cpuSys > 0)
              _buildExpansionCard(
                title: 'CPU 详细拆分',
                icon: Icons.memory,
                color: AppTheme.primary,
                children: [
                  _buildDetailRow('用户使用率 (us)', '${stats.cpuUser.toStringAsFixed(1)}%'),
                  _buildDetailRow('系统使用率 (sy)', '${stats.cpuSys.toStringAsFixed(1)}%'),
                  _buildDetailRow('I/O 等待 (wa)', '${stats.cpuIowait.toStringAsFixed(1)}%'),
                  _buildDetailRow('软中断 (si)', '${stats.cpuSoftirq.toStringAsFixed(1)}%'),
                  _buildDetailRow('硬中断 (hi)', '${stats.cpuIrq.toStringAsFixed(1)}%'),
                  _buildDetailRow('虚拟化 (st)', '${stats.cpuSteal.toStringAsFixed(1)}%'),
                ],
              ),
            const SizedBox(height: 12),
            // 网络 I/O 卡片
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    label: '下载速率',
                    value: _formatBytesRate(stats.netRxRate),
                    icon: Icons.arrow_downward_rounded,
                    color: const Color(0xFF42A5F5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoCard(
                    label: '上传速率',
                    value: _formatBytesRate(stats.netTxRate),
                    icon: Icons.arrow_upward_rounded,
                    color: const Color(0xFFAB47BC),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 网络协议栈详细信息
            if (stats.tcpEstab > 0 || stats.udpNoPorts > 0)
              _buildExpansionCard(
                title: '网络协议栈统计',
                icon: Icons.network_check,
                color: const Color(0xFF42A5F5),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 4),
                    child: Text('TCP 连接', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                  ),
                  _buildDetailRow('已建立连接 (ESTAB)', '${stats.tcpEstab}'),
                  _buildDetailRow('重传率', '${stats.tcpRetransPct.toStringAsFixed(2)}%'),
                  _buildDetailRow('尝试失败', '${stats.tcpFails}'),
                  _buildDetailRow('连接重置', '${stats.tcpResets}'),
                  const Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 4),
                    child: Text('UDP 通信', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                  ),
                  _buildDetailRow('无端口', '${stats.udpNoPorts}'),
                  _buildDetailRow('接收错误', '${stats.udpInErrors}'),
                  const Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 4),
                    child: Text('IP / ICMP', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                  ),
                  _buildDetailRow('ICMP 错误', '${stats.icmpErrors}'),
                  _buildDetailRow('无路由', '${stats.ipNoRoute}'),
                  _buildDetailRow('转发报文', '${stats.ipForward}'),
                ],
              ),
            const SizedBox(height: 20),
            // CPU 历史图表
            if (cpuHistory.length > 1) ...[
              _ChartCard(
                  title: 'CPU 使用率趋势',
                  data: cpuHistory,
                  color: AppTheme.primary),
              const SizedBox(height: 12),
              _ChartCard(
                  title: '内存使用率趋势',
                  data: memHistory,
                  color: AppTheme.accent),
              const SizedBox(height: 12),
              // 网络趋势图 (双线)
              _DualChartCard(
                title: '网络 I/O 趋势',
                data1: netRxHistory,
                data2: netTxHistory,
                color1: const Color(0xFF42A5F5),
                color2: const Color(0xFFAB47BC),
                label1: '↓ 下载',
                label2: '↑ 上传',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExpansionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          collapsedIconColor: AppTheme.textSecondary,
          iconColor: AppTheme.primary,
          title: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Text(title, style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              )),
            ],
          ),
          childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text(value, style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double percent;
  final String? sub;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.percent,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              Text(value,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent.clamp(0, 1),
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
          if (sub != null)
            Text(sub!,
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 10)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _InfoCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value.isEmpty ? '未知' : value,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final List<double> data;
  final Color color;

  const _ChartCard(
      {required this.title, required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              )),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppTheme.border,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 25,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 10),
                      ),
                      reservedSize: 36,
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: color,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 双线图表（网络 I/O）
class _DualChartCard extends StatelessWidget {
  final String title;
  final List<double> data1;
  final List<double> data2;
  final Color color1;
  final Color color2;
  final String label1;
  final String label2;

  const _DualChartCard({
    required this.title,
    required this.data1,
    required this.data2,
    required this.color1,
    required this.color2,
    required this.label1,
    required this.label2,
  });

  @override
  Widget build(BuildContext context) {
    final spots1 = data1
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value / 1024))
        .toList();
    final spots2 = data2
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value / 1024))
        .toList();

    // 动态计算最大值
    final allValues = [
      ...data1.map((v) => v / 1024),
      ...data2.map((v) => v / 1024)
    ];
    final maxY =
        allValues.isEmpty ? 100.0 : (allValues.reduce((a, b) => a > b ? a : b) * 1.2).clamp(1.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  )),
              const Spacer(),
              _LegendDot(color: color1, label: label1),
              const SizedBox(width: 12),
              _LegendDot(color: color2, label: label2),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppTheme.border,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: maxY / 4,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()} KB',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 9),
                      ),
                      reservedSize: 40,
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots1,
                    isCurved: true,
                    color: color1,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color1.withValues(alpha: 0.1),
                    ),
                  ),
                  LineChartBarData(
                    spots: spots2,
                    isCurved: true,
                    color: color2,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color2.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: AppTheme.textMuted, fontSize: 11)),
      ],
    );
  }
}
