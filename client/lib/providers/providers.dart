import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:server_manager/models/server.dart';
import 'package:server_manager/services/api_service.dart';

class ServerProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<Server> _servers = [];
  List<ServerGroup> _groups = [];
  bool _loading = false;
  String? _error;
  int? _selectedGroupId;

  // 批量状态缓存与轮询定时器
  Map<int, ServerStats> _batchStats = {};
  Timer? _pollingTimer;

  List<Server> get servers => _servers;
  List<ServerGroup> get groups => _groups;
  bool get loading => _loading;
  String? get error => _error;
  int? get selectedGroupId => _selectedGroupId;
  Map<int, ServerStats> get batchStats => _batchStats;

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  // ── 批量指标定时轮询 ──
  void startBatchStatsPolling() {
    if (_pollingTimer != null) return;
    _fetchBatchStats(); // 立即执行一次
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchBatchStats();
    });
  }

  void stopBatchStatsPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _fetchBatchStats() async {
    if (_servers.isEmpty) return;
    try {
      final ids = _servers.map((e) => e.id!).toList();
      final dataList = await _api.getBatchServerStats(ids);
      for (final item in dataList) {
        final map = item as Map<String, dynamic>;
        final id = map['id'] as int;
        if (map['error'] != null || map['stats'] == null) {
          continue;
        }
        _batchStats[id] = ServerStats.fromJson(map['stats']);
      }
      notifyListeners();
    } catch (_) {
      // 轮询失败暂不抛出以防打断 UI
    }
  }

  void setSelectedGroup(int? groupId) {
    _selectedGroupId = groupId;
    notifyListeners();
    fetchServers();
  }

  Future<void> fetchServers() async {
    _setLoading(true);
    _error = null;
    try {
      final data = await _api.getServers(groupId: _selectedGroupId);
      _servers = data.map((e) => Server.fromJson(e)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchGroups() async {
    try {
      final data = await _api.getGroups();
      _groups = data.map((e) => ServerGroup.fromJson(e)).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> createServer(Map<String, dynamic> data) async {
    try {
      final res = await _api.createServer(data);
      _servers.add(Server.fromJson(res));
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    }
  }

  Future<bool> updateServer(int id, Map<String, dynamic> data) async {
    try {
      final res = await _api.updateServer(id, data);
      final updated = Server.fromJson(res);
      final idx = _servers.indexWhere((s) => s.id == id);
      if (idx >= 0) _servers[idx] = updated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    }
  }

  Future<bool> deleteServer(int id) async {
    try {
      await _api.deleteServer(id);
      _servers.removeWhere((s) => s.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    }
  }

  Future<Map<String, dynamic>?> testConnection(int id) async {
    try {
      return await _api.testConnection(id);
    } catch (e) {
      return {'status': 'offline', 'error': e.toString()};
    }
  }

  Future<ServerStats?> getStats(int serverId) async {
    try {
      final data = await _api.getServerStats(serverId);
      return ServerStats.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<bool> createGroup(String name) async {
    try {
      final res = await _api.createGroup(name);
      _groups.add(ServerGroup.fromJson(res));
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteGroup(int id) async {
    try {
      await _api.deleteGroup(id);
      _groups.removeWhere((g) => g.id == id);
      if (_selectedGroupId == id) {
        _selectedGroupId = null;
      }
      notifyListeners();
      fetchServers();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  bool _isLoggedIn = false;
  String _username = '';
  bool _loading = false;

  bool get isLoggedIn => _isLoggedIn;
  String get username => _username;
  bool get loading => _loading;

  Future<void> checkAuth() async {
    _isLoggedIn = await _api.isLoggedIn();
    notifyListeners();
  }

  Future<String?> login(String username, String password) async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.login(username, password);
      _isLoggedIn = true;
      _username = res['username'] ?? username;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _api.logout();
    _isLoggedIn = false;
    _username = '';
    notifyListeners();
  }
}
