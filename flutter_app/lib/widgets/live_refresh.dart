import 'dart:async';
import 'package:flutter/widgets.dart';
import '../services/live_service.dart';

/// Give a screen "refresh yourself when this changes on the server".
///
///   class _OrdersScreenState extends State<OrdersScreen> with LiveRefresh<OrdersScreen> {
///     @override List<String> get liveModules => ['orders'];
///     @override void onLiveChange() => _load();
///     initState: initLive();      dispose: disposeLive();
///   }
///
/// Bursts of events (a bill touches several things) are merged into one refresh 0.7 s later.
mixin LiveRefresh<T extends StatefulWidget> on State<T> {
  StreamSubscription<LiveEvent>? _liveSub;
  Timer? _liveDebounce;

  /// The modules whose changes matter to this screen: billing, expenses, orders, estimates, oldmetal ...
  List<String> get liveModules;

  /// What to do when one of them changed (usually: load the list again).
  void onLiveChange();

  void initLive() {
    _liveSub = LiveService.instance.forModules(liveModules).listen((_) {
      _liveDebounce?.cancel();
      _liveDebounce = Timer(const Duration(milliseconds: 700), () {
        if (mounted) onLiveChange();
      });
    });
  }

  void disposeLive() {
    _liveDebounce?.cancel();
    _liveSub?.cancel();
  }
}
