import 'dart:async';
import 'package:flutter/widgets.dart';
import 'api_service.dart';

/// "I'm here, on this screen" for the website's Staff & Roles > Live now. A ping every ~20s while signed in and in
/// the foreground; [screen] is kept up to date by [PresenceRouteObserver] (see main.dart's navigatorObservers).
/// Best-effort and silent by design: this is a nice-to-have status light, never something the app depends on.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  Timer? _timer;
  bool _wanted = false;
  bool _foreground = true;
  bool _observing = false;
  String _screen = 'Home';

  /// Called by [PresenceRouteObserver] whenever the top-most named screen changes.
  set screen(String value) {
    if (_screen == value) return;
    _screen = value;
    if (_wanted && _foreground) unawaited(_ping());
  }

  void start() {
    _wanted = true;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 20), (_) => _ping());
    unawaited(_ping());
  }

  void stop() {
    _wanted = false;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _wanted) unawaited(_ping());
  }

  Future<void> _ping() async {
    if (!_wanted || !_foreground) return;
    await ApiService().pingPresence(screen: _screen);
  }
}

/// Reports the top-most NAMED route to [PresenceService] as the current screen. Screens pushed without a
/// [RouteSettings] name (a detail sheet, a dialog...) are left alone — presence keeps showing the last named
/// module rather than falling back to "Home", since that is still the more useful answer to "where are they".
class PresenceRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  void _report(Route<dynamic>? route) {
    if (route == null) {
      PresenceService.instance.screen = 'Home';
    } else if (route is PageRoute && route.settings.name != null) {
      PresenceService.instance.screen = route.settings.name!;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _report(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _report(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _report(newRoute);
}
