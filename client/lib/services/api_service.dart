import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static String _baseUrl = 'http://localhost:8080/api';
  static String _wsBaseUrl = 'ws://localhost:8080/ws';

  final Dio _dio;

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  ApiService._internal()
      : _dio = Dio(BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          contentType: 'application/json',
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('jwt_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        if (e.response != null && e.response!.data != null) {
          final data = e.response!.data;
          if (data is Map<String, dynamic>) {
            final errorMsg = data['error'] ?? '未知错误';
            final details = data['details'] ?? '';
            final fullMsg = details.isNotEmpty ? '$errorMsg: $details' : errorMsg;
            return handler.reject(DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: e.type,
              error: fullMsg,
              message: fullMsg,
            ));
          }
        }
        return handler.next(e);
      },
    ));
  }

  /// 更新 API 基础地址
  Future<void> updateBaseUrl(String url) async {
    _baseUrl = '$url/api';
    _wsBaseUrl = '${url.replaceFirst('http', 'ws')}/ws';
    _dio.options.baseUrl = _baseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', url);
  }

  /// 获取已保存的基础地址
  Future<String> getSavedBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_base_url') ?? 'http://localhost:8080';
  }

  /// 获取当前 token
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  // ── 认证 ──────────────────────────────────────────
  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await _dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    final token = res.data['token'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
    return res.data;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    return token != null && token.isNotEmpty;
  }

  Future<void> changePassword(String oldPwd, String newPwd) async {
    await _dio.put('/auth/password', data: {
      'old_password': oldPwd,
      'new_password': newPwd,
    });
  }

  // ── 服务器 ──────────────────────────────────────────
  Future<List<dynamic>> getServers({int? groupId, String? search}) async {
    final params = <String, dynamic>{};
    if (groupId != null) params['group_id'] = groupId;
    if (search != null && search.isNotEmpty) params['search'] = search;
    final res = await _dio.get('/servers',
        queryParameters: params.isNotEmpty ? params : null);
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getServer(int id) async {
    final res = await _dio.get('/servers/$id');
    return res.data;
  }

  Future<Map<String, dynamic>> createServer(Map<String, dynamic> data) async {
    final res = await _dio.post('/servers', data: data);
    return res.data;
  }

  Future<Map<String, dynamic>> updateServer(
      int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/servers/$id', data: data);
    return res.data;
  }

  Future<void> deleteServer(int id) async {
    await _dio.delete('/servers/$id');
  }

  Future<Map<String, dynamic>> testConnection(int id) async {
    final res = await _dio.post('/servers/$id/test');
    return res.data;
  }

  Future<Map<String, dynamic>> getServerStats(int id) async {
    final res = await _dio.get('/servers/$id/stats');
    return res.data;
  }

  Future<List<dynamic>> getBatchServerStats(List<int> ids) async {
    final res = await _dio.get('/servers/stats/batch', queryParameters: {
      'id': ids,
    });
    return res.data as List<dynamic>;
  }

  // ── 分组 ──────────────────────────────────────────
  Future<List<dynamic>> getGroups() async {
    final res = await _dio.get('/groups');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createGroup(String name) async {
    final res = await _dio.post('/groups', data: {'name': name});
    return res.data;
  }

  Future<Map<String, dynamic>> updateGroup(int id, String name) async {
    final res = await _dio.put('/groups/$id', data: {'name': name});
    return res.data;
  }

  Future<void> deleteGroup(int id) async {
    await _dio.delete('/groups/$id');
  }

  // ── WebSocket 终端 ──────────────────────────────────────────
  Future<String> getTerminalWsUrl(int serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    return '$_wsBaseUrl/servers/$serverId/terminal?token=$token';
  }

  // ── Docker 管理 ──────────────────────────────────────────
  Future<List<dynamic>> getDockerContainers(int serverId) async {
    final res = await _dio.get('/servers/$serverId/docker/containers');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> containerAction(int serverId, String containerId, String action) async {
    final res = await _dio.post('/servers/$serverId/docker/containers/$containerId/$action');
    return res.data;
  }

  Future<String> getContainerLogs(int serverId, String containerId) async {
    final res = await _dio.get('/servers/$serverId/docker/containers/$containerId/logs');
    return res.data['logs'] ?? '';
  }

  // ── 脚本管理 ──────────────────────────────────────────
  Future<List<dynamic>> getScripts() async {
    final res = await _dio.get('/scripts');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createScript(Map<String, dynamic> data) async {
    final res = await _dio.post('/scripts', data: data);
    return res.data;
  }

  Future<Map<String, dynamic>> updateScript(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/scripts/$id', data: data);
    return res.data;
  }

  Future<void> deleteScript(int id) async {
    await _dio.delete('/scripts/$id');
  }

  Future<String> runScriptOnServer(int serverId, int scriptId) async {
    final res = await _dio.post('/servers/$serverId/scripts/$scriptId/run');
    return res.data['output'] ?? '';
  }
}
