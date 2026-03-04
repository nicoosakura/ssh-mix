import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/server.dart';
import '../models/script.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ScriptsTab extends StatefulWidget {
  final Server server;
  const ScriptsTab({super.key, required this.server});

  @override
  State<ScriptsTab> createState() => _ScriptsTabState();
}

class _ScriptsTabState extends State<ScriptsTab> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<ServerScript> _scripts = [];

  @override
  void initState() {
    super.initState();
    _fetchScripts();
  }

  Future<void> _fetchScripts() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _api.getScripts();
      if (mounted) {
        setState(() {
          _scripts = res.map((e) => ServerScript.fromJson(e)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '获取脚本列表失败: $e';
          _loading = false;
        });
      }
    }
  }

  void _showScriptDialog([ServerScript? script]) {
    final isEdit = script != null;
    final nameCtrl = TextEditingController(text: script?.name ?? '');
    final descCtrl = TextEditingController(text: script?.description ?? '');
    final contentCtrl = TextEditingController(text: script?.content ?? '');

    showDialog(
      context: context,
      builder: (context) {
        bool saving = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: Text(isEdit ? '编辑脚本' : '新建脚本', style: const TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: '脚本名称'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: '描述 (可选)'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: contentCtrl,
                        style: GoogleFonts.sourceCodePro(color: Colors.white),
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Bash 脚本内容',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('取消', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (nameCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('名称和内容不能为空')));
                            return;
                          }
                          setState(() => saving = true);
                          try {
                            if (isEdit) {
                              await _api.updateScript(script.id!, {
                                'name': nameCtrl.text.trim(),
                                'description': descCtrl.text.trim(),
                                'content': contentCtrl.text.trim(),
                              });
                            } else {
                              await _api.createScript({
                                'name': nameCtrl.text.trim(),
                                'description': descCtrl.text.trim(),
                                'content': contentCtrl.text.trim(),
                              });
                            }
                            if (mounted) {
                              Navigator.pop(context);
                              _fetchScripts();
                            }
                          } catch (e) {
                            setState(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
                            }
                          }
                        },
                  child: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteScript(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('确认删除', style: TextStyle(color: Colors.white)),
        content: const Text('确定要删除这个脚本吗？所有服务器均将无法使用它。', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _api.deleteScript(id);
        _fetchScripts();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  Future<void> _runScript(ServerScript script) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 24),
            Text('正在向 ${widget.server.name} 注入并执行...', style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      final out = await _api.runScriptOnServer(widget.server.id!, script.id!);
      if (mounted) {
        Navigator.pop(context); // close progress dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Text('执行完毕 - ${script.name}', style: const TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: SingleChildScrollView(
                child: Text(
                  out.isEmpty ? '<没有输出>' : out,
                  style: GoogleFonts.sourceCodePro(color: out.contains('error') || out.contains('fail') ? Colors.redAccent : Colors.greenAccent, fontSize: 13),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('执行失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchScripts, child: const Text('重试')),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showScriptDialog(),
        backgroundColor: AppTheme.primary,
        tooltip: '新建脚本',
        child: const Icon(Icons.add),
      ),
      body: _scripts.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.code_off, size: 48, color: Colors.white24),
                  SizedBox(height: 16),
                  Text('暂无脚本，点击右下角添加', style: TextStyle(color: Colors.white54)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchScripts,
              child: ListView.builder(
                padding: const EdgeInsets.all(16).copyWith(bottom: 80),
                itemCount: _scripts.length,
                itemBuilder: (context, index) {
                  final s = _scripts[index];
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  s.name,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20, color: Colors.white54),
                                    onPressed: () => _showScriptDialog(s),
                                    tooltip: '编辑',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 20, color: AppTheme.danger),
                                    onPressed: () => _deleteScript(s.id!),
                                    tooltip: '删除',
                                  ),
                                ],
                              )
                            ],
                          ),
                          if (s.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(s.description, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2C6C9C),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.play_arrow, size: 18),
                              label: const Text('在此服务器上执行'),
                              onPressed: () => _runScript(s),
                            ),
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
