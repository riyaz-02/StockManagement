import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_constants.dart';

/// What the server said.
enum ServerState {
  /// Ready: databases connected, safe to log in.
  online,

  /// The machine answers but is still starting (its databases are not connected yet). Keep waiting; do not open the app yet.
  starting,

  /// Nothing answered (stopped, or no network).
  offline,
}

/// One place that decides "is the server up?", used by the splash and the startup screen.
///
/// Why this exists: a single 5-second try made the app say "server is off" while the server was up (a slow first connection,
/// a DNS lookup, a weak signal). So:
///  - a check retries a few times with growing time limits, and a refused connection is retried at once;
///  - only a real "ready" answer counts as online (a proxy error page or a half-started server does not);
///  - the address the wake service gave us is remembered on the phone and tried as well, so a stale DNS answer for
///    api.laltuguineapalace.com cannot hide a server that is running.
class ServerHealth {
  static const _prefKey = 'server_runtime_url';

  /// Load the address remembered from the last time the server was woken (call once at app start).
  static Future<void> restore() async {
    if (AppConstants.isLocal) return;
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_prefKey);
      if (saved != null && saved.trim().isNotEmpty) AppConstants.setRuntimeProductionUrl(saved);
    } catch (_) {/* the default address is used */}
  }

  /// Remember an address that the wake service returned, and use it from now on.
  static Future<void> remember(String url) async {
    if (AppConstants.isLocal || url.trim().isEmpty) return;
    AppConstants.setRuntimeProductionUrl(url);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, AppConstants.baseUrl);
    } catch (_) {}
  }

  static String _healthOf(String apiBase) {
    final b = apiBase.endsWith('/api') ? apiBase.substring(0, apiBase.length - 4) : apiBase;
    return '$b/health';
  }

  /// One request. 200 + ready = online, 503 = starting, anything else / no answer = offline.
  static Future<ServerState> _once(String url, Duration limit) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(limit);
      if (r.statusCode == 200) {
        try {
          final j = json.decode(r.body);
          if (j is Map && j['ready'] == false) return ServerState.starting;
        } catch (_) {/* an older server without the "ready" flag: a 200 is enough */}
        return ServerState.online;
      }
      if (r.statusCode == 503) {
        try {
          final j = json.decode(r.body);
          if (j is Map && j['status'] == 'starting') return ServerState.starting;
        } catch (_) {}
      }
      return ServerState.offline;
    } catch (_) {
      return ServerState.offline;
    }
  }

  /// Check the server. [attempts] tries, each with a longer time limit; stops at the first sign of life.
  static Future<ServerState> check({int attempts = 3, List<String>? urls, Duration step = const Duration(seconds: 3)}) async {
    final own = urls != null;
    urls ??= <String>[AppConstants.healthCheckUrl];
    if (!own && !AppConstants.isLocal) {
      // the default address as well, in case a remembered one has gone stale (and the other way round)
      const def = 'https://api.laltuguineapalace.com/api';
      final d = _healthOf(def);
      if (!urls.contains(d)) urls.add(d);
    }
    var best = ServerState.offline;
    for (var i = 0; i < attempts; i++) {
      final limit = Duration(milliseconds: 4000 + i * step.inMilliseconds); // 4s, 7s, 10s
      for (final u in urls) {
        final s = await _once(u, limit);
        if (s == ServerState.online) {
          // an address that works becomes the one we use
          if (!own && u != AppConstants.healthCheckUrl && !AppConstants.isLocal) {
            await remember(u.substring(0, u.length - '/health'.length));
          }
          return s;
        }
        if (s == ServerState.starting) best = ServerState.starting;
      }
      if (best == ServerState.starting) return best; // it answered: no need to hammer it, the caller keeps waiting
      if (i < attempts - 1) await Future.delayed(const Duration(milliseconds: 600));
    }
    return best;
  }
}
