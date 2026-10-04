import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_version_model.dart';
import '../providers/language_provider.dart';
import '../utils/app_constants.dart';
import 'app_dialog.dart';

/// The link phones download from: a link that starts with "/" is on the shop's own server (the address the app already
/// talks to); anything else is used as it is.
String resolveUpdateUrl(String url) {
  if (url.startsWith('/')) {
    final base = AppConstants.baseUrl;
    return (base.endsWith('/api') ? base.substring(0, base.length - 4) : base) + url;
  }
  return url;
}

/// Shows the "update available" popup. When [config.forceUpdate] is true the popup cannot be dismissed and only offers
/// "Update". If the update file is on the shop's server, tapping Update downloads it inside the app (with progress),
/// checks it and hands it to Android to install: nobody needs the file sent to them.
Future<void> showUpdateDialog(BuildContext context, AppVersionConfig config) async {
  String mine = '';
  try {
    mine = (await PackageInfo.fromPlatform()).version;
  } catch (_) {}
  if (!context.mounted) return;
  return showModernDialog<void>(
    context,
    dismissible: !config.forceUpdate,
    child: _UpdateCard(config: config, mine: mine),
  );
}

enum _Phase { idle, downloading, installing, error }

class _UpdateCard extends StatefulWidget {
  const _UpdateCard({required this.config, required this.mine});
  final AppVersionConfig config;
  final String mine;

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  _Phase _phase = _Phase.idle;
  int _pct = 0;
  String _error = '';
  StreamSubscription<OtaEvent>? _sub;

  bool get _bn => context.read<LanguageProvider>().currentLanguage == 'bn';

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _openInBrowser() async {
    var opened = false;
    try {
      final link = widget.config.downloadUrl.trim();
      if (link.isNotEmpty) opened = await launchUrl(Uri.parse(resolveUpdateUrl(link)), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!mounted) return;
    if (!opened) {
      setState(() {
        _phase = _Phase.error;
        _error = _bn ? 'ডাউনলোড লিংক পাওয়া যাচ্ছে না। অ্যাডমিনকে জানান।' : 'The download link is not available yet. Tell the admin.';
      });
      return;
    }
    // a normal update lets the person carry on while the file downloads; a required one stays until the new app is opened
    if (!widget.config.forceUpdate) Navigator.of(context).pop();
  }

  void _start() {
    final c = widget.config;
    if (!c.apkFromServer) {
      _openInBrowser();
      return;
    }
    _sub?.cancel();
    setState(() {
      _phase = _Phase.downloading;
      _pct = 0;
      _error = '';
    });
    try {
      _sub = OtaUpdate()
          .execute(
            resolveUpdateUrl(c.downloadUrl),
            destinationFilename: 'LaltuGuineaPalace-${c.latestVersion}.apk',
            sha256checksum: c.apkSha256.isEmpty ? null : c.apkSha256,
          )
          .listen(_onEvent, onError: (_) => _fail(null));
    } catch (_) {
      _fail(null);
    }
  }

  void _onEvent(OtaEvent e) {
    if (!mounted) return;
    switch (e.status) {
      case OtaStatus.DOWNLOADING:
        setState(() {
          _phase = _Phase.downloading;
          _pct = int.tryParse('${e.value}') ?? _pct;
        });
        break;
      case OtaStatus.INSTALLING:
        setState(() => _phase = _Phase.installing);
        break;
      case OtaStatus.INSTALLATION_DONE:
        break;
      case OtaStatus.CHECKSUM_ERROR:
        _fail(_bn ? 'ফাইলটি নষ্ট হয়েছে। আবার চেষ্টা করুন।' : 'The file was damaged on the way. Try again.');
        break;
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _fail(_bn ? 'সেটিংসে এই অ্যাপকে ইনস্টলের অনুমতি দিন, তারপর আবার চেষ্টা করুন।' : 'Allow this app to install updates in Settings, then try again.');
        break;
      default:
        _fail(null);
    }
  }

  void _fail(String? message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _error = message ?? (_bn ? 'আপডেট হয়নি। ইন্টারনেট দেখে আবার চেষ্টা করুন।' : 'Could not update. Check the internet and try again.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final force = c.forceUpdate;
    final bn = _bn;
    const accent = Color(0xFF2F6BFF);
    final color = force ? const Color(0xFFE94560) : accent;
    final notes = c.updateMessage.trim();
    final busy = _phase == _Phase.downloading;
    final mb = c.apkSize > 0 ? ' · ${(c.apkSize / 1048576).toStringAsFixed(0)} MB' : '';
    Widget? body;
    switch (_phase) {
      case _Phase.downloading:
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: _pct > 0 ? _pct / 100 : null, minHeight: 8, color: color, backgroundColor: color.withOpacity(0.15))),
          const SizedBox(height: 6),
          Text(bn ? 'ডাউনলোড হচ্ছে… $_pct%' : 'Downloading… $_pct%', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
        ]);
        break;
      case _Phase.installing:
        body = Text(bn ? 'পরের স্ক্রিনে "Install" চাপুন' : 'Tap "Install" on the next screen', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade800, fontWeight: FontWeight.w600));
        break;
      case _Phase.error:
        body = Text(_error, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Colors.red.shade700, fontWeight: FontWeight.w600));
        break;
      case _Phase.idle:
        break;
    }
    return ModernDialogCard(
      icon: force ? Icons.lock_clock_rounded : Icons.system_update_rounded,
      accent: color,
      title: force ? (bn ? 'আপডেট জরুরি' : 'Update required') : (bn ? 'নতুন আপডেট' : 'Update available'),
      pill: widget.mine.isEmpty ? 'v${c.latestVersion}$mb' : 'v${widget.mine}  →  v${c.latestVersion}$mb',
      message: notes.isEmpty || notes == 'A new version of the app is available.' ? null : notes,
      body: body,
      primary: ModernDialogButton.primary(
        _phase == _Phase.error || _phase == _Phase.installing ? (bn ? 'আবার চেষ্টা' : 'Try again') : (bn ? 'আপডেট' : 'Update'),
        icon: Icons.download_rounded,
        color: color,
        busy: busy,
        onPressed: _start,
      ),
      secondary: force || busy ? null : ModernDialogButton.text(bn ? 'পরে' : 'Later', onPressed: () => Navigator.of(context).pop()),
    );
  }
}
