import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _oldPwd = TextEditingController();
  final _newPwd = TextEditingController();
  final _confirmPwd = TextEditingController();
  final _apiUrlCtrl = TextEditingController();
  bool _changing = false;
  bool _savingUrl = false;

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    final url = await ApiService().getSavedBaseUrl();
    if (mounted) _apiUrlCtrl.text = url;
  }

  @override
  void dispose() {
    _oldPwd.dispose();
    _newPwd.dispose();
    _confirmPwd.dispose();
    _apiUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_newPwd.text != _confirmPwd.text) {
      _showSnack('两次输入的新密码不一致', AppTheme.danger);
      return;
    }
    if (_newPwd.text.length < 6) {
      _showSnack('新密码至少 6 位', AppTheme.danger);
      return;
    }
    setState(() => _changing = true);
    try {
      await ApiService().changePassword(_oldPwd.text, _newPwd.text);
      if (!mounted) return;
      _showSnack('密码修改成功', AppTheme.success);
      _oldPwd.clear();
      _newPwd.clear();
      _confirmPwd.clear();
    } catch (e) {
      if (!mounted) return;
      _showSnack('修改失败: $e', AppTheme.danger);
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Future<void> _saveApiUrl() async {
    final url = _apiUrlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _savingUrl = true);
    try {
      await ApiService().updateBaseUrl(url);
      if (mounted) _showSnack('API 地址已保存，重新登录后生效', AppTheme.success);
    } finally {
      if (mounted) setState(() => _savingUrl = false);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('设置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用户信息
            _card(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.accent]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        auth.username.isNotEmpty
                            ? auth.username[0].toUpperCase()
                            : 'A',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.username,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '管理员',
                        style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('API 连接'),
            const SizedBox(height: 12),
            _card(
              child: Column(children: [
                TextFormField(
                  controller: _apiUrlCtrl,
                  style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: '后端 API 地址',
                    hintText: 'http://localhost:8080',
                    prefixIcon: Icon(Icons.link,
                        color: Theme.of(context).iconTheme.color),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: _savingUrl
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppTheme.primary))
                          : const Icon(Icons.save_outlined,
                              color: AppTheme.primary),
                      onPressed: _savingUrl ? null : _saveApiUrl,
                    ),
                  ),
                  onFieldSubmitted: (_) => _saveApiUrl(),
                ),
                const SizedBox(height: 8),
                Text(
                  '修改后需重新登录生效',
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5) ?? AppTheme.textMuted, fontSize: 11),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            _sectionTitle('修改密码'),
            const SizedBox(height: 12),
            _card(
              child: Column(children: [
                _pwdField(_oldPwd, '当前密码'),
                const SizedBox(height: 12),
                _pwdField(_newPwd, '新密码'),
                const SizedBox(height: 12),
                _pwdField(_confirmPwd, '确认新密码'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _changing ? null : _changePassword,
                    child: _changing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('确认修改'),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            _sectionTitle('终端显示'),
            const SizedBox(height: 12),
            _card(
              child: Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('深色模式', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary)),
                          Switch(
                            value: settings.isDarkMode,
                            activeColor: AppTheme.primary,
                            onChanged: (val) => settings.toggleTheme(val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('字体大小', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary)),
                          Text('${settings.terminalFontSize.toInt()} px', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary)),
                        ],
                      ),
                      Slider(
                        value: settings.terminalFontSize,
                        min: 8,
                        max: 32,
                        divisions: 24,
                        activeColor: AppTheme.primary,
                        inactiveColor: Theme.of(context).dividerTheme.color,
                        onChanged: (val) {
                          settings.setTerminalFontSize(val);
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('关于'),
            const SizedBox(height: 12),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('版本', '1.0.0', context),
                  Divider(color: Theme.of(context).dividerTheme.color, height: 20),
                  _infoRow('后端 API', _apiUrlCtrl.text, context),
                  Divider(color: Theme.of(context).dividerTheme.color, height: 20),
                  _infoRow('技术栈', 'Flutter + Go + SQLite', context),
                  Divider(color: Theme.of(context).dividerTheme.color, height: 20),
                  _infoRow('功能', 'SSH 终端 · 实时监控 · 分组管理', context),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // 退出登录
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  await auth.logout();
                  nav.popUntil((r) => r.isFirst);
                },
                icon: const Icon(Icons.logout),
                label: const Text('退出登录'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

      Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerTheme.color!),
        ),
        child: child,
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: GoogleFonts.inter(
          color: Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      );

  Widget _pwdField(TextEditingController ctrl, String label) =>
      TextFormField(
        controller: ctrl,
        obscureText: true,
        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(Icons.lock_outline,
              color: Theme.of(context).iconTheme.color),
          isDense: true,
        ),
      );

  Widget _infoRow(String label, String value, BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary)),
          Flexible(
            child: Text(value,
                style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textPrimary),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );
}
