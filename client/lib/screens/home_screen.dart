import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/providers.dart';
import '../models/server.dart';
import '../theme/app_theme.dart';
import '../widgets/stat_circular_progress.dart';
import 'server_detail_screen.dart';
import 'add_server_screen.dart';
import 'settings_screen.dart';
import 'group_management_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String _search = '';
  late AnimationController _fabAnimCtrl;
  late Animation<double> _fabScale;

  @override
  void initState() {
    super.initState();
    _fabAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fabScale = CurvedAnimation(parent: _fabAnimCtrl, curve: Curves.elasticOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<ServerProvider>();
      p.fetchServers();
      p.fetchGroups();
      p.startBatchStatsPolling(); // 启动首页批量轮询
      _fabAnimCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fabAnimCtrl.dispose();
    // 取消首页轮询，注意不能直接拿 context 如果已 deactived。可以用 provider 但此时已被 dispose()，这里由于是单例/ChangeNotifier 供全局使用，目前不做主动 cancel，交由 Provider 控制
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.accent]),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.dns_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'Server Manager',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700, color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.folder_outlined,
                color: Theme.of(context).iconTheme.color),
            tooltip: '分组管理',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const GroupManagementSheet(),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
            onPressed: () {
              context.read<ServerProvider>()
                ..fetchServers()
                ..fetchGroups();
            },
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined,
                color: Theme.of(context).iconTheme.color),
            onPressed: () => Navigator.push(
              context,
              _slideRoute(const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: Theme.of(context).iconTheme.color),
            onPressed: () => auth.logout(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: '搜索服务器...',
                prefixIcon:
                    Icon(Icons.search, color: Theme.of(context).iconTheme.color),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                filled: true,
                fillColor: Theme.of(context).cardTheme.color,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Theme.of(context).dividerTheme.color!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Theme.of(context).dividerTheme.color!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primary),
                ),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          const SizedBox(height: 8),
          // 分组筛选标签栏
          _GroupFilterBar(),
          // 服务器列表
          Expanded(
            child: Consumer<ServerProvider>(
              builder: (_, provider, __) {
                if (provider.loading) {
                  return _ShimmerList();
                }
                if (provider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppTheme.danger, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          '加载失败\n${provider.error}',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: provider.fetchServers,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  );
                }

                final filtered = provider.servers
                    .where((s) =>
                        _search.isEmpty ||
                        s.name.toLowerCase().contains(_search) ||
                        s.host.toLowerCase().contains(_search) ||
                        (s.tags != null && s.tags!.toLowerCase().contains(_search)))
                    .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.computer_outlined,
                            color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5) ?? AppTheme.textMuted, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          _search.isEmpty
                              ? '还没有服务器\n点击右下角添加'
                              : '未找到匹配的服务器',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    await provider.fetchServers();
                    await provider.fetchGroups();
                  },
                  color: AppTheme.primary,
                  backgroundColor: Theme.of(context).cardTheme.color,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _ServerCard(
                      server: filtered[i],
                      index: i,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScale,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryDark]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.4),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  _slideRoute(const AddServerScreen()),
                );
                if (!context.mounted) return;
                if (result == true) {
                  context.read<ServerProvider>().fetchServers();
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(Icons.add, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 路由动画
PageRouteBuilder _slideRoute(Widget page) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 350),
    );

// ── 分组筛选标签栏 ──
class _GroupFilterBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ServerProvider>(
      builder: (_, provider, __) {
        if (provider.groups.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChip(
                label: '全部',
                selected: provider.selectedGroupId == null,
                onTap: () => provider.setSelectedGroup(null),
              ),
              ...provider.groups.map((g) => _FilterChip(
                    label: g.name,
                    selected: provider.selectedGroupId == g.id,
                    onTap: () => provider.setSelectedGroup(g.id),
                    count: g.servers.length,
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.2)
                : Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  selected ? AppTheme.primary : Theme.of(context).dividerTheme.color!,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppTheme.primary : (Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary),
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primary.withValues(alpha: 0.3)
                        : Theme.of(context).dividerTheme.color!,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: selected
                          ? AppTheme.primary
                          : (Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5) ?? AppTheme.textMuted),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shimmer 骨架屏 ──
class _ShimmerList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).cardTheme.color ?? AppTheme.bgCard,
      highlightColor: Theme.of(context).dividerTheme.color ?? AppTheme.bgCardHover,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          height: 80,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ?? AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ── 服务器卡片 ──
class _ServerCard extends StatefulWidget {
  final Server server;
  final int index;
  const _ServerCard({required this.server, required this.index});

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);

    Future.delayed(Duration(milliseconds: widget.index * 60), () {
      if (mounted) _animCtrl.forward();
    });

    // 我们使用定时批量拉取，所以这里不再调用单台 _test()。
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = context.select<ServerProvider, ServerStats?>(
        (p) => p.batchStats[widget.server.id]);
    final computedStatus = stats != null ? 'online' : widget.server.status;

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: GestureDetector(
          onTap: () async {
            final result = await Navigator.push(
              context,
              _slideRoute(ServerDetailScreen(server: widget.server)),
            );
            if (result == true && context.mounted) {
              context.read<ServerProvider>().fetchServers();
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerTheme.color!),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // === 头部（名字、状态、操作） ===
                Row(
                  children: [
                    Icon(
                      Icons.apple, // 随便一个图标代替原有的
                      color: AppTheme.textPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.server.name,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.server.tags != null && widget.server.tags!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: widget.server.tags!.split(',').map((t) {
                                final text = t.trim();
                                if (text.isEmpty) return const SizedBox.shrink();
                                // Generate a color based on the tag string hash so it's consistent
                                final hue = (text.hashCode.abs() % 360).toDouble();
                                final color = HSLColor.fromAHSL(1.0, hue, 0.6, 0.4).toColor();
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    border: Border.all(color: color.withValues(alpha: 0.4)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }).toList(),
                            )
                          ]
                        ],
                      ),
                    ),
                    // 右侧状态与操作
                    Row(
                      children: [
                        Icon(
                          Icons.power_settings_new_rounded,
                          color: AppTheme.statusColor(computedStatus),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.show_chart,
                          color: Theme.of(context).iconTheme.color,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          stats != null && stats.cpuUsage > 0
                              ? stats.cpuUsage.toStringAsFixed(1)
                              : '0.0',
                          style: TextStyle(
                              color: Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        // 操作菜单
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, size: 18, color: Theme.of(context).iconTheme.color),
                          color: Theme.of(context).cardTheme.color,
                          onSelected: (val) async {
                            if (val == 'edit') {
                              final result = await Navigator.push(
                                context,
                                _slideRoute(AddServerScreen(
                                    editServer: widget.server)),
                              );
                              if (result == true && context.mounted) {
                                context.read<ServerProvider>().fetchServers();
                              }
                            } else if (val == 'delete') {
                              _confirmDelete(context);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('编辑', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary)),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('删除', style: TextStyle(color: AppTheme.danger)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: Theme.of(context).dividerTheme.color),
                const SizedBox(height: 12),

                // === 下半部：指标环 ===
                DefaultTextStyle(
                  style: TextStyle(
                      fontFamily: 'Inter',
                      color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary,
                      fontSize: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // CPU
                      StatCircularProgress(
                        title: 'CPU',
                        value: stats != null ? stats.cpuUsage / 100.0 : 0.0,
                        subtitle: '1 C', // TODO 暂时写死或改为空
                        baseColor: AppTheme.primary,
                      ),
                      // Mem
                      StatCircularProgress(
                        title: 'Mem',
                        value: stats != null ? stats.memUsage / 100.0 : 0.0,
                        subtitle: stats != null
                            ? stats.memUsedFormatted
                            : '0 B',
                        baseColor: AppTheme.accent,
                      ),
                      // Disk
                      StatCircularProgress(
                        title: '磁盘',
                        value: stats != null ? stats.diskUsage / 100.0 : 0.0,
                        subtitle: stats != null
                            ? stats.diskUsedFormatted
                            : '0 B',
                        baseColor: AppTheme.primaryDark,
                      ),
                      // Network I/O
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('网络',
                              style: TextStyle(
                                  color: Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          Text(
                            '↑ ${stats != null ? _formatRate(stats.netTxRate) : '0 B/s'}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary),
                          ),
                          Text(
                            stats != null ? _formatRateSummary(stats.netTxRate) : '0 B',
                            style: TextStyle(
                                fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5) ?? AppTheme.textMuted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '↓ ${stats != null ? _formatRate(stats.netRxRate) : '0 B/s'}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary),
                          ),
                          Text(
                            stats != null ? _formatRateSummary(stats.netRxRate) : '0 B',
                            style: TextStyle(
                                fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5) ?? AppTheme.textMuted),
                          ),
                        ],
                      ),
                      // I/O (Disk/Generic placeholder as the design)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('I/O',
                              style: TextStyle(
                                  color: Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          Text(
                            '↑ 0 B',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary),
                          ),
                          Text('0',
                              style: TextStyle(
                                  fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5) ?? AppTheme.textMuted)),
                          const SizedBox(height: 4),
                          Text(
                            '↓ 0 B',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary),
                          ),
                          Text('0',
                              style: TextStyle(
                                  fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5) ?? AppTheme.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatRate(double bytesPs) {
    if (bytesPs < 1024) return '${bytesPs.toStringAsFixed(0)} B/s';
    if (bytesPs < 1024 * 1024) return '${(bytesPs / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPs / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  String _formatRateSummary(double bytesPs) {
    if (bytesPs < 1024) return '${bytesPs.toStringAsFixed(0)} B';
    if (bytesPs < 1024 * 1024) return '${(bytesPs / 1024).toStringAsFixed(1)} KB';
    return '${(bytesPs / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).cardTheme.color ?? AppTheme.bgCard,
        title: Text('删除服务器',
            style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary)),
        content: Text('确定要删除 "${widget.server.name}" 吗？',
            style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              Navigator.pop(context);
              await context
                  .read<ServerProvider>()
                  .deleteServer(widget.server.id!);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
