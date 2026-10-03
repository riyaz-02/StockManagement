import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_version_model.dart';
import '../utils/app_toast.dart';
import '../widgets/update_dialog.dart';
import 'api_service.dart';
import 'live_service.dart';

/// What the app does, wherever the person is, when the server says something changed:
///  - a new app version was published -> the update popup;
///  - a notification was sent -> a banner at the top.
/// (Rates, lists and permissions refresh themselves where they live: see LiveRefresh and AuthProvider.)
class LiveReactions {
  static StreamSubscription<LiveEvent>? _sub;
  static bool _askingUpdate = false;

  static void attach() {
    _sub ??= LiveService.instance.events.listen((e) {
      if (e.type == 'notification.new') {
        // No navigator yet (e.g. a push lands before the app has finished starting) — nothing to show it on, so drop it.
        final ctx = appNavigatorKey.currentContext;
        if (ctx == null) return;
        final title = '${e.data['title'] ?? ''}';
        final body = '${e.data['body'] ?? ''}';
        showAppSnackBar(
          ctx,
          SnackBar(content: Text(title.isEmpty ? body : (body.isEmpty ? title : '$title\n$body')), backgroundColor: const Color(0xFF1F2937), duration: const Duration(seconds: 6)),
        );
      } else if (e.type == 'app.update') {
        unawaited(checkAppUpdate());
      }
    });
  }

  /// Looks up the published app version and shows the update popup if this build is behind. Safe to call from
  /// anywhere (splash start-up, or a live "app.update" push) — re-entrant calls while one check is already running
  /// are ignored, so the popup is never shown twice.
  static Future<void> checkAppUpdate() => _checkUpdate();

  static Future<void> _checkUpdate() async {
    if (_askingUpdate) return;
    _askingUpdate = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final mine = int.tryParse(info.buildNumber) ?? 0;
      final r = await ApiService().getAppVersion();
      if (r['success'] != true) return;
      final cfg = AppVersionConfig.fromJson(r['data']['appVersion']);
      final ctx = appNavigatorKey.currentContext;
      if (cfg.latestVersionCode > mine && ctx != null && ctx.mounted) {
        await showUpdateDialog(ctx, cfg);
      }
    } catch (_) {
      // best effort: the next start checks again
    } finally {
      _askingUpdate = false;
    }
  }
}
