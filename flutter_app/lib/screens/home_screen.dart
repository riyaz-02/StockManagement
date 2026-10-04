import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/notification_provider.dart';
import '../services/api_service.dart';
import '../widgets/notification_bell.dart';
import '../widgets/rate_strip.dart';
import 'billing_screen.dart';
import 'booking_list_screen.dart';
import 'container_list_screen.dart';
import 'create_invoice_screen.dart';
import 'day_book_screen.dart';
import 'dues_screen.dart';
import 'estimates_screen.dart';
import 'expenses_screen.dart';
import 'general_scan_screen.dart';
import 'gst_summary_screen.dart';
import 'item_list_screen.dart';
import 'login_screen.dart';
import 'old_metal_screen.dart';
import 'orders_screen.dart';
import 'reports_screen.dart';
import 'store_management_screen.dart';
import 'tally_list_screen.dart';
import 'user_directory_screen.dart';

/// One thing the Home screen can open. Every tile has a plain-English and a Bengali name, a one-line
/// "what is this for", and extra words people might type to look for it.
class _Tile {
  const _Tile({
    required this.id,
    required this.icon,
    required this.color,
    required this.en,
    required this.bn,
    required this.descEn,
    required this.descBn,
    required this.open,
    this.perm,
    this.words = '',
    this.routeName,
  });
  final String id;
  final IconData icon;
  final Color color;
  final String en, bn, descEn, descBn;
  final String? perm; // permission key; null = everyone
  final String words; // search words (English and Bengali)
  final String? routeName;
  final Widget Function() open;

  String title(bool bn_) => bn_ ? bn : en;
  String desc(bool bn_) => bn_ ? descBn : descEn;
}

final List<_Tile> _tiles = [
  _Tile(id: 'newbill', icon: Icons.add_card_rounded, color: const Color(0xFFD97706), en: 'New bill', bn: 'নতুন বিল', descEn: 'Make a GST bill for a customer', descBn: 'গ্রাহকের জন্য জিএসটি বিল করুন', perm: 'billing.create', words: 'invoice sale sell create make bill বিল বিক্রি', routeName: 'New bill', open: () => const CreateInvoiceScreen()),
  _Tile(id: 'scan', icon: Icons.qr_code_scanner_rounded, color: const Color(0xFFE94560), en: 'Scan', bn: 'স্ক্যান', descEn: 'Scan a barcode tag', descBn: 'বারকোড ট্যাগ স্ক্যান করুন', perm: 'items.view', words: 'barcode tag camera look find স্ক্যান বারকোড', routeName: 'Scan', open: () => const GeneralScanScreen()),

  _Tile(id: 'bills', icon: Icons.receipt_long_rounded, color: const Color(0xFFB45309), en: 'Bills', bn: 'বিল', descEn: 'All bills, payments and returns', descBn: 'সব বিল, জমা ও ফেরত', perm: 'billing.view', words: 'invoice gst billing payment return credit note receipt বিল জিএসটি', routeName: 'GST Billing', open: () => const BillingScreen()),
  _Tile(id: 'dues', icon: Icons.hourglass_bottom_rounded, color: const Color(0xFFDC2626), en: 'Dues', bn: 'বাকি', descEn: 'Who owes you money', descBn: 'কার কাছে টাকা পাওনা', perm: 'billing.view', words: 'due balance owe udhar pending বাকি পাওনা বকেয়া', routeName: 'Pending dues', open: () => const PendingDuesScreen()),
  _Tile(id: 'estimates', icon: Icons.request_quote_rounded, color: const Color(0xFF7C3AED), en: 'Estimate', bn: 'এস্টিমেট', descEn: 'Quote a price, no bill yet', descBn: 'দাম জানান, বিল ছাড়া', perm: 'estimates.view', words: 'estimate quotation quote price এস্টিমেট দাম', routeName: 'Estimates', open: () => const EstimatesScreen()),
  _Tile(id: 'orders', icon: Icons.handyman_rounded, color: const Color(0xFF0E7490), en: 'Orders', bn: 'অর্ডার', descEn: 'Pieces made to order', descBn: 'বানিয়ে দেওয়ার গয়না', perm: 'orders.view', words: 'order advance karigar make custom অর্ডার অগ্রিম', routeName: 'Orders', open: () => const OrdersScreen()),
  _Tile(id: 'oldmetal', icon: Icons.recycling_rounded, color: const Color(0xFFB45309), en: 'Old Gold', bn: 'পুরনো গয়না', descEn: 'Old gold & silver taken in', descBn: 'পুরনো গয়না ও কাঁচা ধাতু নেওয়া', perm: 'oldMetal.view', words: 'old gold silver metal exchange raw urd purana পুরনো সোনা রূপা', routeName: 'Old Metal', open: () => const OldMetalScreen()),
  _Tile(id: 'bookings', icon: Icons.bookmark_added_rounded, color: const Color(0xFF00A3C4), en: 'Booking', bn: 'বুকিং', descEn: 'Pieces kept aside for customers', descBn: 'গ্রাহকের জন্য আলাদা রাখা', perm: 'bookings.view', words: 'booking reserve hold বুকিং', routeName: 'Bookings', open: () => const BookingListScreen()),

  _Tile(id: 'items', icon: Icons.diamond_rounded, color: const Color(0xFF11998E), en: 'Stock', bn: 'স্টক', descEn: 'Every piece in the shop', descBn: 'স্টকের সব পিস', perm: 'items.view', words: 'stock piece jewellery ring chain list weight স্টক গয়না', routeName: 'Stock', open: () => const ItemListScreen()),
  _Tile(id: 'boxes', icon: Icons.widgets_rounded, color: const Color(0xFF8B5CF6), en: 'Tray', bn: 'ট্রে', descEn: 'What is in which box', descBn: 'কোন বাক্সে কী আছে', perm: 'containers.view', words: 'container box tray showcase shelf storage বাক্স ট্রে', routeName: 'Boxes', open: () => const ContainerListScreen()),
  _Tile(id: 'tally', icon: Icons.fact_check_rounded, color: const Color(0xFFEF4444), en: 'Tally', bn: 'ট্যালি', descEn: 'Count the shop and match it with the stock', descBn: 'দোকানের স্টক গুনে মেলান', perm: 'tally.view', words: 'tally audit count verify inventory মেলান', routeName: 'Stock Tally', open: () => const TallyListScreen()),
  _Tile(id: 'store', icon: Icons.local_shipping_rounded, color: const Color(0xFF059669), en: 'Purchase', bn: 'ক্রয়', descEn: 'Buy metal, see the stock summary', descBn: 'ধাতু কেনা, স্টকের সারাংশ', perm: 'stock.view', words: 'purchase buy supplier summary difference discrepancy wastage balance store ক্রয় গড়মিল', routeName: 'Store', open: () => const StoreManagementScreen()),

  _Tile(id: 'daybook', icon: Icons.menu_book_rounded, color: const Color(0xFF0F766E), en: 'Day Book', bn: 'ডে বুক', descEn: 'Money in and out today', descBn: 'আজ টাকা কত এল-গেল', perm: 'daybook.view', words: 'cash book money income khata ledger খাতা', routeName: 'Day Book', open: () => const DayBookScreen()),
  _Tile(id: 'expenses', icon: Icons.payments_rounded, color: const Color(0xFF9333EA), en: 'Expenses', bn: 'খরচ', descEn: 'Tea, salary, rent…', descBn: 'চা, বেতন, ভাড়া…', perm: 'expenses.view', words: 'expense cost salary rent tea খরচ', routeName: 'Expenses', open: () => const ExpensesScreen()),
  _Tile(id: 'gst', icon: Icons.account_balance_rounded, color: const Color(0xFF4F46E5), en: 'GST', bn: 'জিএসটি', descEn: 'Returns, tax credit & due dates', descBn: 'রিটার্ন, ক্রেডিট ও শেষ তারিখ', perm: 'gst.viewReports', words: 'gst tax return gstr itc filing due date জিএসটি রিটার্ন', routeName: 'GST Summary', open: () => const GstSummaryScreen()),
  _Tile(id: 'reports', icon: Icons.bar_chart_rounded, color: const Color(0xFFDB2777), en: 'Reports', bn: 'রিপোর্ট', descEn: 'Sales and stock insights', descBn: 'বিক্রি ও স্টকের হিসাব', perm: 'reports.view', words: 'analytics chart report insight sales রিপোর্ট', routeName: 'Reports', open: () => const ReportsScreen()),
  _Tile(id: 'people', icon: Icons.contacts_rounded, color: const Color(0xFF2563EB), en: 'Party', bn: 'পার্টি', descEn: 'Customers, suppliers, karigars and staff', descBn: 'গ্রাহক, সরবরাহকারী, কারিগর ও কর্মী', perm: 'directory.view', words: 'party customer supplier karigar staff user phone contact directory গ্রাহক সরবরাহকারী কারিগর', routeName: 'Customers & suppliers', open: () => const UserDirectoryScreen()),
];

/// The two big buttons at the top: what is done all day.
const List<String> _hero = ['newbill', 'scan'];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _timer;
  DateTime _now = DateTime.now();
  bool _multiBranch = false; // the branch switcher only appears once the firm really has more than one shop
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searching = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    _checkBranches();
  }

  Future<void> _checkBranches() async {
    try {
      final r = await ApiService().getDirectoryBranches();
      final n = (r['data'] as List? ?? const []).length;
      if (mounted) setState(() => _multiBranch = n > 1);
    } catch (_) {/* stay hidden */}
  }

  void _open(_Tile t) {
    FocusScope.of(context).unfocus();
    Navigator.push(context, MaterialPageRoute(settings: RouteSettings(name: t.routeName ?? t.en), builder: (_) => t.open()));
  }

  /// A long press says what the tile is for (the screen itself shows only a name and a picture).
  void _explain(_Tile t, bool bn) {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${t.title(bn)}: ${t.desc(bn)}'), duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      setState(() => _now = DateTime.now());
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  String _greeting(bool bn) {
    final h = _now.hour;
    if (bn) return h < 12 ? 'শুভ সকাল' : h < 17 ? 'শুভ অপরাহ্ন' : 'শুভ সন্ধ্যা';
    return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
  }

  String _date(bool bn) {
    const d = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const dBn = ['রবি', 'সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি'];
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${(bn ? dBn : d)[_now.weekday % 7]}, ${_now.day} ${m[_now.month - 1]}';
  }

  bool _allowed(AuthProvider a, _Tile t) => t.perm == null || a.can(t.perm!);

  List<_Tile> _matches(AuthProvider a) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _tiles.where((t) => _allowed(a, t) && '${t.en} ${t.bn} ${t.descEn} ${t.descBn} ${t.words}'.toLowerCase().contains(q)).toList();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _q = '';
        FocusScope.of(context).unfocus();
      }
    });
    if (_searching) Future.delayed(const Duration(milliseconds: 80), () => _searchFocus.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final bn = context.watch<LanguageProvider>().currentLanguage == 'bn';
    final byId = {for (final t in _tiles) t.id: t};
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 900 ? 9 : width >= 600 ? 7 : 5;
    final heroes = [for (final id in _hero) if (_allowed(auth, byId[id]!)) byId[id]!];
    final grid = [for (final t in _tiles) if (!_hero.contains(t.id) && _allowed(auth, t)) t];
    final found = _matches(auth);
    final showingSearch = _searching && _q.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F2),
      body: Stack(children: [
        // the picture behind everything: soft gold gems, rings and sparkles on a warm page
        const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _BackdropPainter()))),
        SafeArea(
          bottom: false,
          child: Column(children: [
            // header: logo, then the bell, search and log-out
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                // the logo gives way (shrinks) when the branch button, bell, search and log-out need the room
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Image.asset(
                      'assets/images/lgp_logo_red.png',
                      height: 38,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: Color(0xFFE94560), size: 32),
                    ),
                  ),
                ),
                if (auth.canSwitchBranch && _multiBranch) _BranchSwitcher(auth: auth),
                const NotificationBell(),
                IconButton(tooltip: bn ? 'খুঁজুন' : 'Search', icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded, color: const Color(0xFF334155), size: 26), onPressed: _toggleSearch),
                IconButton(
                  tooltip: bn ? 'বের হন' : 'Log out',
                  icon: const Icon(Icons.logout_rounded, color: Color(0xFF9F1239), size: 23),
                  onPressed: () async {
                    context.read<NotificationProvider>().clear();
                    await auth.logout();
                    if (context.mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
                  },
                ),
              ]),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (_searching)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextField(
                              controller: _search,
                              focusNode: _searchFocus,
                              onChanged: (v) => setState(() => _q = v),
                              style: const TextStyle(fontSize: 16),
                              decoration: InputDecoration(
                                hintText: bn ? 'খুঁজুন…' : 'Search…',
                                prefixIcon: const Icon(Icons.search_rounded),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF9F1239), width: 1.6)),
                              ),
                            ),
                          ),
                        if (!showingSearch) ...[
                          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_greeting(bn), style: TextStyle(fontSize: 12.5, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                                Text(auth.user?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), height: 1.15)),
                              ]),
                            ),
                            Text(_date(bn), style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                          ]),
                          const SizedBox(height: 12),
                          const RateStrip(compact: true),
                          const SizedBox(height: 14),
                          if (heroes.isNotEmpty)
                            Row(children: [
                              for (var i = 0; i < heroes.length; i++) ...[
                                if (i > 0) const SizedBox(width: 12),
                                Expanded(child: _HeroButton(tile: heroes[i], bn: bn, dark: i > 0, onTap: () => _open(heroes[i]), onLong: () => _explain(heroes[i], bn))),
                              ],
                            ]),
                          const SizedBox(height: 18),
                        ],
                      ]),
                    ),
                  ),
                  if (showingSearch)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                      sliver: found.isEmpty
                          ? SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Icon(Icons.search_off_rounded, size: 52, color: Colors.grey[400])))
                          : _grid([...found], bn, cols),
                    )
                  else
                    SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), sliver: _grid(grid, bn, cols)),
                ],
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  SliverGrid _grid(List<_Tile> list, bool bn, int cols) => SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 84),
        delegate: SliverChildBuilderDelegate((_, i) => _IconTile(tile: list[i], bn: bn, onTap: () => _open(list[i]), onLong: () => _explain(list[i], bn)), childCount: list.length),
      );
}

/// The two everyday buttons: large, one deep colour each, a big faint picture of the job behind the name.
class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.tile, required this.bn, required this.dark, required this.onTap, required this.onLong});
  final _Tile tile;
  final bool bn, dark;
  final VoidCallback onTap, onLong;

  @override
  Widget build(BuildContext context) {
    // New bill: the shop's red, deepened. Scan: deep slate with a gold picture. Calm, not loud.
    final colors = dark ? const [Color(0xFF3B4558), Color(0xFF1E2535)] : const [Color(0xFFC63A55), Color(0xFF8E1B34)];
    final glyph = dark ? const Color(0xFFE9C87A) : Colors.white;
    return SizedBox(
      height: 124,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLong,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
              boxShadow: [BoxShadow(color: colors.last.withOpacity(0.32), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(children: [
                // the watermark: the same picture, huge and faint, falling off the corner
                Positioned(right: -22, bottom: -26, child: Icon(tile.icon, size: 138, color: glyph.withOpacity(0.15))),
                Positioned(left: 0, right: 0, top: 0, height: 44, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withOpacity(0.14), Colors.white.withOpacity(0)])))),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withOpacity(0.28))),
                      child: Icon(tile.icon, color: glyph, size: 24),
                    ),
                    Text(tile.title(bn), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain tile: white card, a bronze picture on a cream disc, the name. No colour per tile, no shadow.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.tile, required this.bn, required this.onTap, required this.onLong});
  final _Tile tile;
  final bool bn;
  final VoidCallback onTap, onLong;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLong,
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, 9, 2, 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE9E4DA))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFBF1DC), Color(0xFFF3E4C2)])),
              child: Icon(tile.icon, color: const Color(0xFF8A5A14), size: 21),
            ),
            const SizedBox(height: 6),
            Text(tile.title(bn), maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E293B), height: 1.1)),
          ]),
        ),
      ),
    );
  }
}

/// The page behind Home: a warm gradient, faint gold gem outlines, rings and sparkles. Painted once, never repainted.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  void _gem(Canvas c, Offset center, double w, Paint p) {
    // a brilliant-cut diamond seen from the side: table, crown, girdle, pavilion
    final h = w * 0.82;
    final top = center.dy - h / 2, left = center.dx - w / 2, right = center.dx + w / 2;
    final girdle = top + h * 0.34, tableL = center.dx - w * 0.26, tableR = center.dx + w * 0.26;
    final path = Path()
      ..moveTo(tableL, top)
      ..lineTo(tableR, top)
      ..lineTo(right, girdle)
      ..lineTo(center.dx, top + h)
      ..lineTo(left, girdle)
      ..close();
    c.drawPath(path, p);
    c.drawLine(Offset(left, girdle), Offset(right, girdle), p);
    for (final x in [tableL, center.dx, tableR]) {
      c.drawLine(Offset(x, top), Offset(x == center.dx ? center.dx : (x < center.dx ? left + w * 0.22 : right - w * 0.22), girdle), p);
    }
    c.drawLine(Offset(left + w * 0.22, girdle), Offset(center.dx, top + h), p);
    c.drawLine(Offset(right - w * 0.22, girdle), Offset(center.dx, top + h), p);
    c.drawLine(Offset(center.dx, girdle), Offset(center.dx, top + h), p);
  }

  void _sparkle(Canvas c, Offset o, double r, Paint p) {
    final path = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
      ..close();
    c.drawPath(path, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // page colour: cream at the top, a cool off-white at the bottom
    canvas.drawRect(Offset.zero & size, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFAF5EA), Color(0xFFF5F4F1), Color(0xFFF1F3F8)], stops: [0.0, 0.45, 1.0]).createShader(Offset.zero & size));

    final gold = const Color(0xFFB8860B);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeJoin = StrokeJoin.round
      ..color = gold.withOpacity(0.15);
    final fine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = gold.withOpacity(0.10);

    // a big gem, top right, falling off the edge, with a smaller one beside it
    _gem(canvas, Offset(w * 0.86, h * 0.10), w * 0.62, line);
    _gem(canvas, Offset(w * 0.20, h * 0.30), w * 0.28, fine);
    // rings: concentric circles, bottom left
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(Offset(w * 0.02, h * 0.92), w * (0.10 + i * 0.075), fine);
    }
    canvas.drawCircle(Offset(w * 0.96, h * 0.62), w * 0.20, fine);
    canvas.drawCircle(Offset(w * 0.96, h * 0.62), w * 0.26, fine);
    // a soft warm glow behind the header
    canvas.drawCircle(Offset(w * 0.9, h * 0.06), w * 0.5, Paint()..shader = RadialGradient(colors: [gold.withOpacity(0.10), gold.withOpacity(0)]).createShader(Rect.fromCircle(center: Offset(w * 0.9, h * 0.06), radius: w * 0.5)));
    // sparkles
    final spark = Paint()..color = gold.withOpacity(0.32);
    for (final s in const [
      [0.12, 0.07, 6.0], [0.52, 0.045, 4.0], [0.93, 0.27, 5.0], [0.07, 0.52, 4.5], [0.60, 0.40, 3.5], [0.36, 0.78, 4.0], [0.90, 0.86, 6.0], [0.70, 0.95, 3.5],
    ]) {
      _sparkle(canvas, Offset(w * s[0], h * s[1]), s[2], spark);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// For admins / every-branch users: work as one branch (its stock, its invoices, its numbering) or see the whole firm.
class _BranchSwitcher extends StatelessWidget {
  const _BranchSwitcher({required this.auth});
  final AuthProvider auth;

  Future<void> _open(BuildContext context) async {
    List<Map<String, dynamic>> branches = [];
    try {
      final r = await ApiService().getDirectoryBranches();
      branches = (r['data'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {}
    if (!context.mounted) return;
    final current = ApiService.activeBranch;
    final pick = await showModalBottomSheet<Map<String, String>>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 6), child: Align(alignment: Alignment.centerLeft, child: Text('Work as which branch?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))),
          const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text('New items and invoices are filed under this branch, and lists show only its records.', style: TextStyle(fontSize: 12, color: Colors.black54)))),
          RadioListTile<String>(value: '', groupValue: current, title: const Text('Whole firm (all branches)'), onChanged: (_) => Navigator.pop(context, {'id': '', 'name': ''})),
          for (final b in branches)
            RadioListTile<String>(
              value: '${b['_id'] ?? b['id'] ?? ''}',
              groupValue: current,
              title: Text('${b['name'] ?? 'Branch'}'),
              subtitle: (b['gstin'] ?? '').toString().isEmpty ? null : Text('GSTIN ${b['gstin']}', style: const TextStyle(fontSize: 11.5)),
              onChanged: (v) => Navigator.pop(context, {'id': v ?? '', 'name': '${b['name'] ?? ''}'}),
            ),
        ]),
      ),
    );
    if (pick == null) return;
    await auth.setActiveBranch(pick['id'] ?? '', pick['name'] ?? '');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pick['id']!.isEmpty ? 'Showing the whole firm' : 'Working as ${pick['name']}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = auth.activeBranchName;
    return Tooltip(
      message: 'Switch branch',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _open(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          constraints: const BoxConstraints(maxWidth: 150),
          decoration: BoxDecoration(color: const Color(0xFFE94560).withOpacity(0.10), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE94560).withOpacity(0.45))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.storefront_outlined, size: 16, color: Color(0xFFE94560)),
            const SizedBox(width: 5),
            Flexible(child: Text(name.isEmpty ? 'All branches' : name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFE94560), fontSize: 12, fontWeight: FontWeight.w700))),
            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFFE94560)),
          ]),
        ),
      ),
    );
  }
}
