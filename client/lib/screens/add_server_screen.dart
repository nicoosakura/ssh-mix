import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/providers.dart';
import '../models/server.dart';
import '../theme/app_theme.dart';

class AddServerScreen extends StatefulWidget {
  final Server? editServer; // 若传入则为编辑模式
  const AddServerScreen({super.key, this.editServer});

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _host;
  late TextEditingController _port;
  late TextEditingController _username;
  late TextEditingController _password;
  late TextEditingController _privateKey;
  late TextEditingController _desc;
  late TextEditingController _tags;
  bool _useKey = false;
  bool _saving = false;
  bool _obscure = true;
  int? _selectedGroupId;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  bool get _isEdit => widget.editServer != null;

  @override
  void initState() {
    super.initState();
    final s = widget.editServer;
    _name = TextEditingController(text: s?.name ?? '');
    _host = TextEditingController(text: s?.host ?? '');
    _port = TextEditingController(text: '${s?.port ?? 22}');
    _username = TextEditingController(text: s?.username ?? '');
    _password = TextEditingController(text: s?.password ?? '');
    _privateKey = TextEditingController(text: s?.privateKey ?? '');
    _desc = TextEditingController(text: s?.description ?? '');
    _tags = TextEditingController(text: s?.tags ?? '');
    _selectedGroupId = s?.groupId;
    if (s != null && (s.privateKey ?? '').isNotEmpty) {
      _useKey = true;
    }

    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServerProvider>().fetchGroups();
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    for (final c in [_name, _host, _port, _username, _password, _privateKey, _desc, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final data = {
      'name': _name.text.trim(),
      'host': _host.text.trim(),
      'port': int.tryParse(_port.text) ?? 22,
      'username': _username.text.trim(),
      'password': _useKey ? '' : _password.text,
      'private_key': _useKey ? _privateKey.text : '',
      'description': _desc.text.trim(),
      'tags': _tags.text.trim(),
      'group_id': _selectedGroupId,
    };

    final provider = context.read<ServerProvider>();
    final ok = _isEdit
        ? await provider.updateServer(widget.editServer!.id!, data)
        : await provider.createServer(data);

    if (mounted) {
      if (ok) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('操作失败，请检查参数'),
            backgroundColor: AppTheme.danger,
          ),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: Text(_isEdit ? '编辑服务器' : '添加服务器'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(_isEdit ? '更新' : '保存'),
            ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle('基本信息'),
                const SizedBox(height: 12),
                _field(_name, '服务器名称', Icons.label_outline,
                    validator: _required),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      flex: 3,
                      child: _field(_host, '主机地址/IP', Icons.router_outlined,
                          validator: _required)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field(_port, '端口', Icons.numbers,
                          keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                _field(_desc, '描述（可选）', Icons.description_outlined),
                const SizedBox(height: 12),
                _field(_tags, '标签（逗号分隔）', Icons.sell_outlined),
                const SizedBox(height: 12),
                // 分组选择
                Consumer<ServerProvider>(
                  builder: (_, provider, __) {
                    return DropdownButtonFormField<int?>(
                      value: _selectedGroupId,
                      decoration: const InputDecoration(
                        labelText: '所属分组（可选）',
                        prefixIcon: Icon(Icons.folder_outlined,
                            color: AppTheme.textSecondary),
                      ),
                      dropdownColor: AppTheme.bgCard,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('无分组'),
                        ),
                        ...provider.groups.map((g) => DropdownMenuItem<int?>(
                              value: g.id,
                              child: Text(g.name),
                            )),
                      ],
                      onChanged: (v) => setState(() => _selectedGroupId = v),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _SectionTitle('认证信息'),
                const SizedBox(height: 12),
                _field(_username, 'SSH 用户名', Icons.person_outline,
                    validator: _required),
                const SizedBox(height: 12),
                // 切换认证方式
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      _AuthTab('密码', !_useKey,
                          () => setState(() => _useKey = false)),
                      _AuthTab(
                          '私钥', _useKey, () => setState(() => _useKey = true)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (!_useKey)
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline,
                          color: AppTheme.textSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppTheme.textSecondary,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                  )
                else
                  TextFormField(
                    controller: _privateKey,
                    maxLines: 6,
                    style: GoogleFonts.sourceCodePro(
                        color: AppTheme.textPrimary, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: '私钥 (PEM 格式)',
                      prefixIcon: Icon(Icons.vpn_key_outlined,
                          color: AppTheme.textSecondary),
                      alignLabelWithHint: true,
                    ),
                    validator: _useKey ? _required : null,
                  ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {String? Function(String?)? validator,
      TextInputType? keyboardType}) =>
      TextFormField(
        controller: ctrl,
        style: const TextStyle(color: AppTheme.textPrimary),
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppTheme.textSecondary),
        ),
        validator: validator,
      );

  String? _required(String? v) =>
      v == null || v.isEmpty ? '此项为必填项' : null;
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.inter(
          color: AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      );
}

class _AuthTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _AuthTab(this.label, this.active, this.onTap);

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppTheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : AppTheme.textSecondary,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
}
