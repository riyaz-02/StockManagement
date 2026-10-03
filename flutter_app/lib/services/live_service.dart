import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_constants.dart';

/// One thing that changed on the server (a rate, a setting, someone's access, a notification, an app update, or data in a module).
class LiveEvent {
  LiveEvent(this.seq, this.type, this.module, this.data, this.by);
  final int seq;
  final String type; // rate.changed, settings.changed, permissions.changed, app.update, notification.new, data.changed, reset
  final String module; // for data.changed: billing, expenses, orders, estimates, oldmetal ...
  final Map<String, dynamic> data;
  final String by;

  factory LiveEvent.fromJson(String type, Map<String, dynamic> j) => LiveEvent(
        (j['seq'] as num?)?.toInt() ?? 0,
        type,
        '${j['module'] ?? ''}',
        Map<String, dynamic>.from((j['data'] as Map?) ?? const {}),
        '${j['by'] ?? ''}',
      );
}

/// The live channel to the server (Server-Sent Events): the website and other phones change something, this app hears it
/// within about a second. While the app is in the foreground and signed in it keeps one connection open; in the background
/// it lets go after 45 seconds (saving battery and letting the server sleep) and, on return, asks for what it missed.
///
/// The connection does not wake a sleeping server: if it cannot connect it simply retries later (2 s, 4 s ... up to 60 s).
class LiveService with WidgetsBindingObserver {
  LiveService._();
  static final LiveService instance = LiveService._();

  static const _prefKey = 'live_seq';
  static const _events = ['rate.changed', 'settings.changed', 'permissions.changed', 'app.update', 'notification.new', 'data.changed'];

  final _ctl = StreamController<LiveEvent>.broadcast();
  Stream<LiveEvent> get events => _ctl.stream;

  /// Only "data changed" events of these modules (plus a reset after a long absence), for lists that refresh themselves.
  Stream<LiveEvent> forModules(List<String> modules) => events.where((e) => e.type == 'reset' || (e.type == 'data.changed' && modules.contains(e.module)));

  String? _token;
  bool _wanted = false;
  bool _foreground = true;
  bool _running = false;
  int _seq = 0;
  int _retry = 0;
  Timer? _timer;
  Timer? _pause;
  http.Client? _client;
  bool _observing = false;

  bool get connected => _connected;
  bool _connected = false;

  /// Start (or restart with a new token). Safe to call again.
  Future<void> start(String token) async {
    if (_token != token) {
      _disconnect();
    }
    _token = token;
    _wanted = true;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    try {
      final p = await SharedPreferences.getInstance();
      _seq = p.getInt(_prefKey) ?? _seq;
    } catch (_) {}
    _connect();
  }

  void stop() {
    _wanted = false;
    _token = null;
    _timer?.cancel();
    _pause?.cancel();
    _disconnect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pause?.cancel();
      _foreground = true;
      if (_wanted && !_connected) {
        _retry = 0;
        _connect();
      }
    } else if (state == AppLifecycleState.paused) {
      _pause?.cancel();
      _pause = Timer(const Duration(seconds: 45), () {
        _foreground = false;
        _disconnect();
      });
    }
  }

  void _disconnect() {
    _connected = false;
    _client?.close();
    _client = null;
  }

  void _scheduleRetry() {
    _timer?.cancel();
    if (!_wanted || !_foreground) return;
    _retry = (_retry + 1).clamp(1, 6);
    final wait = Duration(seconds: (2 * (1 << (_retry - 1))).clamp(2, 60));
    _timer = Timer(wait, _connect);
  }

  Future<void> _connect() async {
    if (!_wanted || !_foreground || _running || _token == null) return;
    _running = true;
    final client = http.Client();
    _client = client;
    try {
      final url = '${AppConstants.baseUrl}/live${_seq > 0 ? '?since=$_seq' : ''}';
      final req = http.Request('GET', Uri.parse(url))
        ..headers['Authorization'] = 'Bearer $_token'
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';
      final resp = await client.send(req).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 401) {
        // the login is no longer valid: the rest of the app handles signing in again
        _wanted = false;
        return;
      }
      if (resp.statusCode != 200) throw Exception('live ${resp.statusCode}');
      _connected = true;
      _retry = 0;
      var type = 'message';
      final data = StringBuffer();
      await for (final line in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) {
          if (data.isNotEmpty) _dispatch(type, data.toString());
          type = 'message';
          data.clear();
        } else if (line.startsWith('event:')) {
          type = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          if (data.isNotEmpty) data.write('\n');
          data.write(line.substring(5).trim());
        }
      }
    } catch (_) {
      // no connection (server asleep, no network): try again later
    } finally {
      _connected = false;
      client.close();
      if (identical(_client, client)) _client = null;
      _running = false;
      if (_wanted) _scheduleRetry();
    }
  }

  void _dispatch(String type, String raw) {
    Map<String, dynamic> j;
    try {
      j = Map<String, dynamic>.from(json.decode(raw) as Map);
    } catch (_) {
      return;
    }
    if (type == 'hello') {
      final latest = (j['latest'] as num?)?.toInt() ?? 0;
      if (j['reset'] == true) {
        _ctl.add(LiveEvent(0, 'reset', '', const {}, ''));
      }
      if (_seq == 0 || j['reset'] == true) _remember(latest);
      return;
    }
    if (!_events.contains(type)) return;
    final e = LiveEvent.fromJson(type, j);
    if (e.seq > _seq) _remember(e.seq);
    _ctl.add(e);
  }

  Future<void> _remember(int seq) async {
    _seq = seq;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_prefKey, seq);
    } catch (_) {}
  }
}
