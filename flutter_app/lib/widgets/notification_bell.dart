import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../providers/notification_provider.dart';
import '../screens/gst_summary_screen.dart';
import '../screens/tally_list_screen.dart';
import 'update_dialog.dart';

/// The bell in the Home header: a red number for what needs a look; tap for the list.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = context.read<NotificationProvider>();
      n.attach();
      n.setLanguage(context.read<LanguageProvider>().currentLanguage);
      n.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bn = context.watch<LanguageProvider>().currentLanguage == 'bn';
    final n = context.watch<NotificationProvider>();
    return IconButton(
      tooltip: bn ? 'নোটিফিকেশন' : 'Notifications',
      onPressed: () => showNotificationSheet(context),
      icon: Stack(clipBehavior: Clip.none, children: [
        const Icon(Icons.notifications_none_rounded, color: Color(0xFF334155), size: 27),
        if (n.unread > 0)
          Positioned(
            right: -4,
            top: -3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(9), border: Border.all(color: Colors.white, width: 1.6)),
              child: Center(child: Text(n.unread > 9 ? '9+' : '${n.unread}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1.1))),
            ),
          ),
      ]),
    );
  }
}

String _ago(DateTime? t, bool bn) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return bn ? 'এইমাত্র' : 'just now';
  if (d.inMinutes < 60) return bn ? '${d.inMinutes} মিনিট আগে' : '${d.inMinutes} min ago';
  if (d.inHours < 24) return bn ? '${d.inHours} ঘণ্টা আগে' : '${d.inHours} h ago';
  if (d.inDays < 2) return bn ? 'গতকাল' : 'yesterday';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${m[t.month - 1]}';
}

Future<void> showNotificationSheet(BuildContext context) async {
  final n = context.read<NotificationProvider>();
  n.load();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider<NotificationProvider>.value(value: n, child: const _NotificationSheet()),
  );
}

class _NotificationSheet extends StatefulWidget {
  const _NotificationSheet();

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  @override
  void initState() {
    super.initState();
    // a glance is enough to count the notices as read
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) context.read<NotificationProvider>().markSeen();
    });
  }

  void _go(AppNotice i) {
    final nav = Navigator.of(context);
    final n = context.read<NotificationProvider>();
    switch (i.link) {
      case 'update':
        nav.pop();
        if (n.pendingUpdate != null) showUpdateDialog(context, n.pendingUpdate!);
        break;
      case 'gst':
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => const GstSummaryScreen()));
        break;
      case 'tally':
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => const TallyListScreen()));
        break;
      case 'rate':
        nav.pop(); // the rate is changed from the box at the top of Home
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bn = context.watch<LanguageProvider>().currentLanguage == 'bn';
    final n = context.watch<NotificationProvider>();
    final update = n.pendingUpdate;
    final rows = <Widget>[];
    if (update != null) {
      rows.add(_Row(
        icon: Icons.system_update_rounded,
        color: const Color(0xFF2563EB),
        title: bn ? 'নতুন আপডেট · v${update.latestVersion}' : 'Update available · v${update.latestVersion}',
        body: update.forceUpdate ? (bn ? 'এই আপডেট দিতেই হবে' : 'This update is required') : '',
        meta: bn ? 'আপডেট' : 'Update',
        highlight: true,
        onTap: () => _go(AppNotice(id: 'u', kind: 'reminder', level: 'update', title: '', body: '', at: null, read: false, link: 'update')),
      ));
    }
    for (final i in n.items) {
      // the server's own "update available" notice is replaced by the live line above
      if (i.link == 'update' && update != null) continue;
      final reminder = i.kind == 'reminder';
      rows.add(_Row(
        icon: reminder ? (i.level == 'bad' ? Icons.error_rounded : Icons.alarm_rounded) : (i.level == 'update' ? Icons.system_update_rounded : Icons.notifications_rounded),
        color: reminder ? (i.level == 'bad' ? const Color(0xFFDC2626) : const Color(0xFFD97706)) : (i.level == 'update' ? const Color(0xFF2563EB) : const Color(0xFF475569)),
        title: i.title,
        body: i.body,
        meta: reminder ? (bn ? 'করণীয়' : 'To do') : _ago(i.at, bn),
        highlight: !i.read && !reminder,
        onTap: i.link.isEmpty ? null : () => _go(i),
      ));
    }
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.94,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(color: Color(0xFFF6F7FB), borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(children: [
              Expanded(child: Text(bn ? 'নোটিফিকেশন' : 'Notifications', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)))),
              if (n.loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle_outline_rounded, size: 54, color: Colors.grey[400]),
                      const SizedBox(height: 10),
                      Text(bn ? 'সব ঠিক আছে' : 'You are all caught up', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    ]),
                  )
                : ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => rows[i],
                  ),
          ),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.color, required this.title, required this.body, required this.meta, required this.highlight, this.onTap});
  final IconData icon;
  final Color color;
  final String title, body, meta;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlight ? const Color(0xFFFFF7F8) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: highlight ? color.withOpacity(0.35) : Colors.grey.shade200)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 21)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B), height: 1.25)),
                if (body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.3))),
                const SizedBox(height: 4),
                Text(meta, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
              ]),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
          ]),
        ),
      ),
    );
  }
}
