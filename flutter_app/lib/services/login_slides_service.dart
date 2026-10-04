import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_constants.dart';

class LoginSlide {
  const LoginSlide({required this.imageUrl, this.captionEn = '', this.captionBn = ''});
  final String imageUrl, captionEn, captionBn;

  String caption(bool bn) => (bn && captionBn.isNotEmpty) ? captionBn : captionEn;

  factory LoginSlide.fromJson(Map<String, dynamic> j) => LoginSlide(
        imageUrl: (j['imageUrl'] ?? '').toString(),
        captionEn: (j['captionEn'] ?? '').toString(),
        captionBn: (j['captionBn'] ?? '').toString(),
      );
  Map<String, dynamic> toJson() => {'imageUrl': imageUrl, 'captionEn': captionEn, 'captionBn': captionBn};
}

/// The pictures of the sign-in screen (uploaded on the website: Admin Control > Login screen). They are needed before anyone
/// is signed in, so the list is public; the last one received is kept on the phone, so the screen shows at once, even offline.
class LoginSlidesService {
  LoginSlidesService._();
  static final LoginSlidesService instance = LoginSlidesService._();

  static const _cacheKey = 'login_slides_cache';
  final ValueNotifier<List<LoginSlide>> slides = ValueNotifier<List<LoginSlide>>(const []);
  bool _loadedCache = false;

  /// What the phone already has (instant).
  Future<List<LoginSlide>> cached() async {
    if (!_loadedCache) {
      _loadedCache = true;
      try {
        final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
        if (raw != null) slides.value = _parse(json.decode(raw));
      } catch (_) {/* no cache yet */}
    }
    return slides.value;
  }

  /// Asks the server; keeps the answer for next time. Silent on any failure: the old list stays.
  Future<void> refresh() async {
    await cached();
    try {
      final r = await http.get(Uri.parse('${AppConstants.baseUrl}/app-assets/login-slides')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final list = (json.decode(r.body)['data']?['slides'] as List?) ?? const [];
      final next = _parse(list);
      slides.value = next;
      await (await SharedPreferences.getInstance()).setString(_cacheKey, json.encode(next.map((s) => s.toJson()).toList()));
    } catch (_) {/* offline or server asleep: keep what we have */}
  }

  static List<LoginSlide> _parse(dynamic list) =>
      (list as List).whereType<Map>().map((m) => LoginSlide.fromJson(Map<String, dynamic>.from(m))).where((s) => s.imageUrl.startsWith('http')).toList();
}
