import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/server.dart';
import '../models/script.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ContainersTab extends StatefulWidget {
  final Server server;
  const ContainersTab({super.key, required this.server});

  @override
  State<ContainersTab> createState() => _ContainersTabState();
}

class _ContainersTabState extends State<ContainersTab> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<DockerContainer> _containers = [];

  @override
  void initState() {
    super.initState();
    _fetchContainers();
  }

  Future<void> _fetchContainers() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _api.getDockerContainers(widget.server.id!);
      if (mounted) {
        setState(() {
          _containers = res.map((e) => DockerContainer.fromJson(e)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '获取容器列表失败: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _containerAction(String cid, String action) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      await _api.containerAction(widget.server.id!, cid, action);
      if (mounted) Navigator.pop(context); // close dialog
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作 $action 成功')));
      _fetchContainers();
    } catch (e) {
      if (mounted) Navigator.pop(context); // close dialog
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  Future<void> _showLogs(String cid, String name) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      final logs = await _api.getContainerLogs(widget.server.id!, cid);
      if (mounted) Navigator.pop(context);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: Text('$name - Logs', style: const TextStyle(color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: SingleChildScrollView(
                  child: Text(
                    logs,
                    style: GoogleFonts.sourceCodePro(color: Colors.greenAccent, fontSize: 12),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取日志失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      final isNotInstalled = _error!.contains('该服务器未安装 Docker');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isNotInstalled ? Icons.extension_off : Icons.error_outline,
              size: 48,
              color: isNotInstalled ? Colors.white38 : AppTheme.danger,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchContainers,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_containers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.layers_clear, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            const Text('没有找到容器', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _fetchContainers,
              child: const Text('刷新'),
            )
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchContainers,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _containers.length,
        itemBuilder: (context, index) {
          final c = _containers[index];
          final isUp = c.isRunning;
          return Card(
            color: const Color(0xFF1E1E1E),
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isUp ? AppTheme.success : AppTheme.danger,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          c.names,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white54),
                        color: const Color(0xFF2C2C2C),
                        onSelected: (val) {
                          if (val == 'logs') {
                            _showLogs(c.id, c.names);
                          } else {
                            _containerAction(c.id, val);
                          }
                        },
                        itemBuilder: (context) => [
                          if (!isUp)
                            const PopupMenuItem(value: 'start', child: Text('启动', style: TextStyle(color: Colors.white))),
                          if (isUp)
                            const PopupMenuItem(value: 'stop', child: Text('停止', style: TextStyle(color: Colors.white))),
                          if (isUp)
                            const PopupMenuItem(value: 'restart', child: Text('重启', style: TextStyle(color: Colors.white))),
                          const PopupMenuItem(value: 'logs', child: Text('日志', style: TextStyle(color: Colors.white))),
                          const PopupMenuItem(value: 'rm', child: Text('删除', style: TextStyle(color: AppTheme.danger))),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('镜像: ${c.image}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('状态: ${c.status}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  if (c.ports.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('端口: ${c.ports}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
