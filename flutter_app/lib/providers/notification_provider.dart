import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_version_model.dart';
import '../services/api_service.dart';
import '../services/live_service.dart';

/// One line in the bell: a notice that was sent (kind 'notice') or something that needs doing now (kind 'reminder').
class AppNotice {
  AppNotice({required this.id, required this.kind, required this.level, required this.title, required this.body, required this.at, required this.read, required this.link});
  final String id, kind, level, title, body, link; // level: info | warn | bad | update
  final DateTime? at;
  final bool read;

  factory AppNotice.fromJson(Map<String, dynamic> j) => AppNotice(
        id: '${j['id'] ?? ''}',
        kind: '${j['kind'] ?? 'notice'}',
        level: '${j['level'] ?? 'info'}',
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        at: DateTime.tryParse('${j['at'] ?? ''}')?.toLocal(),
        read: j['read'] == true,
        link: '${j['link'] ?? ''}',
      );
}

/// What the bell shows: the server's feed (notices + live reminders) plus "a newer app is ready" worked out on the phone
/// (only the phone knows which version it runs). Refreshes by itself when the server says something new arrived.
class NotificationProvider with ChangeNotifier {
  List<AppNotice> _items = [];
  int _serverUnread = 0;
  AppVersionConfig? _update;
  bool _loading = false;
  String _lang = 'en';
  StreamSubscription<LiveEvent>? _sub;

  List<AppNotice> get items => _items;
  bool get loading => _loading;
  AppVersionConfig? get pendingUpdate => _update;
  int get unread => _serverUnread + (_update != null ? 1 : 0);

  /// Start listening once the person is signed in (safe to call again).
  void attach() {
    _sub ??= LiveService.instance.events.where((e) => e.type == 'notification.new' || e.type == 'app.update' || e.type == 'reset').listen((_) => load());
  }

  void setLanguage(String lang) {
    if (lang != _lang) {
      _lang = lang;
      load();
    }
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final r = await ApiService().getNotificationFeed(lang: _lang);
      if (r['success'] == true) {
        final d = Map<String, dynamic>.from(r['data'] as Map);
        _items = (d['items'] as List? ?? []).map((e) => AppNotice.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        _serverUnread = (d['unread'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {/* keep what is shown; the next refresh tries again */}
    await _checkUpdate();
    _loading = false;
    notifyListeners();
  }

  Future<void> _checkUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final mine = int.tryParse(info.buildNumber) ?? 0;
      final r = await ApiService().getAppVersion();
      if (r['success'] == true) {
        final cfg = AppVersionConfig.fromJson(Map<String, dynamic>.from(r['data']['appVersion'] as Map));
        _update = cfg.latestVersionCode > mine ? cfg : null;
      }
    } catch (_) {/* not known now */}
  }

  /// The person opened the bell: the notices count as read (reminders stay until the job is done).
  Future<void> markSeen() async {
    if (_serverUnread == 0 && !_items.any((i) => i.kind == 'notice' && !i.read)) return;
    try {
      await ApiService().markNotificationsSeen();
      _items = [for (final i in _items) i.kind == 'notice' && !i.read ? AppNotice(id: i.id, kind: i.kind, level: i.level, title: i.title, body: i.body, at: i.at, read: true, link: i.link) : i];
      _serverUnread = _items.where((i) => i.kind == 'reminder').length;
      notifyListeners();
    } catch (_) {/* shown as new again next time */}
  }

  void clear() {
    _items = [];
    _serverUnread = 0;
    _update = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
