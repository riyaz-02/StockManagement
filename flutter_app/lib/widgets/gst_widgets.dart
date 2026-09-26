import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'bill_ui.dart';

double gd(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

final NumberFormat _n0 = NumberFormat('#,##,##0', 'en_IN');

/// ₹ with no decimals, Indian grouping.
String inr0(num v) => '${v < 0 ? '−' : ''}₹${_n0.format(v.abs().round())}';

/// Compact money for headline figures: ₹2.36 L, ₹1.25 Cr.
String inrShort(num v) {
  final a = v.abs();
  final sign = v < 0 ? '−' : '';
  if (a >= 10000000) return '$sign₹${(a / 10000000).toStringAsFixed(2)} Cr';
  if (a >= 100000) return '$sign₹${(a / 100000).toStringAsFixed(2)} L';
  return '$sign₹${_n0.format(a.round())}';
}

/// Weight: grams up to 1 kg, then kilograms.
String weightShort(num g) => g.abs() >= 1000 ? '${(g / 1000).toStringAsFixed(3)} kg' : '${g.toStringAsFixed(g == g.roundToDouble() ? 0 : 2)} g';

const Color kGstIndigo = Color(0xFF4F46E5);
const Color kGstAmber = Color(0xFFD97706);
const Color kGstGreen = Color(0xFF16A34A);
const Color kGstRed = Color(0xFFDC2626);
const Color kGstTeal = Color(0xFF0F766E);
const Color kGstPurple = Color(0xFF7C3AED);
const Color kGstSlate = Color(0xFF475569);

/// Up / down arrow against the previous period.
class DeltaChip extends StatelessWidget {
  const DeltaChip(this.now, this.before, {super.key, this.upIsGood = true});
  final double now, before;
  final bool upIsGood;

  @override
  Widget build(BuildContext context) {
    if (before <= 0 && now <= 0) return const SizedBox.shrink();
    if (before <= 0) return const StatusPill('new', kGstIndigo);
    final pct = (now - before) / before * 100;
    if (pct.abs() < 0.05) return const StatusPill('no change', kGstSlate);
    final up = pct > 0;
    final good = up == upIsGood;
    return StatusPill('${up ? '▲' : '▼'} ${pct.abs().toStringAsFixed(pct.abs() < 10 ? 1 : 0)}%', good ? kGstGreen : kGstRed);
  }
}

/// A headline number: icon, big value, label, optional sub-line and delta.
class GstKpi extends StatelessWidget {
  const GstKpi({super.key, required this.label, required this.value, required this.icon, required this.color, this.sub, this.delta, this.onTap});
  final String label, value;
  final String? sub;
  final IconData icon;
  final Color color;
  final Widget? delta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.22)),
              gradient: LinearGradient(colors: [color.withOpacity(0.09), Colors.white], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(width: 28, height: 28, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)), child: Icon(icon, size: 16, color: Colors.white)),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (delta != null) delta!,
              ]),
              const SizedBox(height: 8),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3))),
              if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: const TextStyle(fontSize: 11, color: Colors.black54), maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      );
}

/// Column of a [GstTable].
class GstCol {
  const GstCol(this.label, this.key, {this.numeric = true, this.fmt, this.width = 96, this.bold = false});
  final String label, key;
  final bool numeric, bold;
  final String Function(dynamic)? fmt;
  final double width;
}

/// A sortable table on wide screens, a list of cards on phones. The first column is the row's title.
class GstTable extends StatefulWidget {
  const GstTable({super.key, required this.cols, required this.rows, this.sortKey, this.asc = false, this.footer, this.empty = 'Nothing here yet', this.onTap, this.color = kGstIndigo, this.maxCardStats = 8});
  final List<GstCol> cols;
  final List<Map<String, dynamic>> rows;
  final String? sortKey;
  final bool asc;
  final Map<String, dynamic>? footer;
  final String empty;
  final void Function(Map<String, dynamic>)? onTap;
  final Color color;
  final int maxCardStats;

  @override
  State<GstTable> createState() => _GstTableState();
}

class _GstTableState extends State<GstTable> {
  late String? _key = widget.sortKey;
  late bool _asc = widget.asc;

  String _fmt(GstCol c, dynamic v) => c.fmt != null ? c.fmt!(v) : '${v ?? ''}';

  List<Map<String, dynamic>> get _sorted {
    final list = [...widget.rows];
    final k = _key;
    if (k == null) return list;
    list.sort((a, b) {
      final x = a[k], y = b[k];
      final c = (x is num && y is num) ? x.compareTo(y) : '${x ?? ''}'.toLowerCase().compareTo('${y ?? ''}'.toLowerCase());
      return _asc ? c : -c;
    });
    return list;
  }

  void _sortBy(String k) => setState(() {
        if (_key == k) {
          _asc = !_asc;
        } else {
          _key = k;
          _asc = !widget.cols.firstWhere((c) => c.key == k).numeric;
        }
      });

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Center(child: Text(widget.empty, style: const TextStyle(color: Colors.black45, fontSize: 13))));
    }
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 640;
      final rows = _sorted;
      return wide ? _wide(rows, box.maxWidth) : _narrow(rows, box.maxWidth);
    });
  }

  // ── wide: real table with sortable headers ──
  Widget _wide(List<Map<String, dynamic>> rows, double maxW) {
    final cols = widget.cols;
    final fixed = cols.skip(1).fold<double>(0, (a, c) => a + c.width);
    final firstW = math.max(150.0, maxW - fixed - 8);
    final total = firstW + fixed;
    Widget cell(GstCol c, int i, Widget child) => SizedBox(width: i == 0 ? firstW : c.width, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7), child: child));
    final header = Row(children: [
      for (var i = 0; i < cols.length; i++)
        InkWell(
          onTap: () => _sortBy(cols[i].key),
          child: cell(
            cols[i],
            i,
            Row(mainAxisAlignment: cols[i].numeric ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
              Flexible(child: Text(cols[i].label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: widget.color), overflow: TextOverflow.ellipsis)),
              if (_key == cols[i].key) Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: widget.color),
            ]),
          ),
        ),
    ]);
    Widget line(Map<String, dynamic> r, int idx, {bool foot = false}) => InkWell(
          onTap: (widget.onTap == null || foot) ? null : () => widget.onTap!(r),
          child: Container(
            color: foot ? widget.color.withOpacity(0.08) : (idx.isOdd ? const Color(0xFFF8F9FC) : Colors.white),
            child: Row(children: [
              for (var i = 0; i < cols.length; i++)
                cell(cols[i], i, Text(_fmt(cols[i], r[cols[i].key]), textAlign: cols[i].numeric ? TextAlign.right : TextAlign.left, style: TextStyle(fontSize: 12.5, fontWeight: (foot || i == 0 || cols[i].bold) ? FontWeight.w700 : FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 2)),
            ]),
          ),
        );
    final table = SizedBox(
      width: total,
      child: Column(children: [
        Container(color: widget.color.withOpacity(0.08), child: header),
        for (var i = 0; i < rows.length; i++) line(rows[i], i),
        if (widget.footer != null) line(widget.footer!, 0, foot: true),
      ]),
    );
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(10)), child: total > maxW ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: table) : table));
  }

  // ── narrow: cards ──
  Widget _narrow(List<Map<String, dynamic>> rows, double maxW) {
    final cols = widget.cols;
    final stats = cols.skip(1).take(widget.maxCardStats).toList();
    final per = maxW < 420 ? 2 : (maxW < 640 ? 3 : 4);
    final w = (maxW - 24 - 8.0 * (per - 1) - 1) / per;
    Widget stat(GstCol c, Map<String, dynamic> r, {double? width}) => SizedBox(
          width: width ?? w,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.label, style: const TextStyle(fontSize: 10.5, color: Colors.black45), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(_fmt(c, r[c.key]), style: TextStyle(fontSize: 12.5, fontWeight: c.bold ? FontWeight.w800 : FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          const Padding(padding: EdgeInsets.only(right: 6), child: Text('Sort', style: TextStyle(fontSize: 11.5, color: Colors.black45))),
          for (final c in cols)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text('${c.label}${_key == c.key ? (_asc ? ' ↑' : ' ↓') : ''}', style: const TextStyle(fontSize: 11.5)),
                selected: _key == c.key,
                selectedColor: widget.color.withOpacity(0.16),
                onSelected: (_) => _sortBy(c.key),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      for (final r in rows)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onTap == null ? null : () => widget.onTap!(r),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_fmt(cols.first, r[cols.first.key]), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [for (final c in stats) stat(c, r)]),
            ]),
          ),
        ),
      if (widget.footer != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          decoration: BoxDecoration(color: widget.color.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_fmt(cols.first, widget.footer![cols.first.key]), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [for (final c in stats) stat(c, widget.footer!)]),
          ]),
        ),
    ]);
  }
}

/// Simple bar chart. Tap a bar to read its value.
class MiniBars extends StatefulWidget {
  const MiniBars({super.key, required this.items, this.color = kGstIndigo, this.height = 160, this.format});
  final List<(String, double)> items;
  final Color color;
  final double height;
  final String Function(double)? format;

  @override
  State<MiniBars> createState() => _MiniBarsState();
}

class _MiniBarsState extends State<MiniBars> {
  int? _sel;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox(height: 60, child: Center(child: Text('No data in this range', style: TextStyle(color: Colors.black45, fontSize: 13))));
    return LayoutBuilder(builder: (context, box) {
      const minBar = 30.0;
      final needed = widget.items.length * minBar;
      final width = math.max(box.maxWidth, needed);
      final chart = GestureDetector(
        onTapDown: (d) {
          final i = (d.localPosition.dx / (width / widget.items.length)).floor();
          setState(() => _sel = (i >= 0 && i < widget.items.length) ? (i == _sel ? null : i) : null);
        },
        child: CustomPaint(size: Size(width, widget.height), painter: _BarsPainter(widget.items, widget.color, _sel, widget.format ?? (v) => inrShort(v))),
      );
      return needed > box.maxWidth ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: chart) : chart;
    });
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.items, this.color, this.sel, this.fmt);
  final List<(String, double)> items;
  final Color color;
  final int? sel;
  final String Function(double) fmt;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 22.0, bottom = 22.0;
    final h = size.height - top - bottom;
    final maxV = items.map((e) => e.$2).fold<double>(0, math.max);
    final slot = size.width / items.length;
    final barW = math.min(34.0, slot * 0.62);
    final base = Paint()..color = Colors.black12..strokeWidth = 1;
    canvas.drawLine(Offset(0, top + h), Offset(size.width, top + h), base);
    for (var i = 0; i < items.length; i++) {
      final v = items[i].$2;
      final bh = maxV <= 0 ? 0.0 : (v / maxV) * h;
      final x = slot * i + (slot - barW) / 2;
      final r = RRect.fromRectAndCorners(Rect.fromLTWH(x, top + h - bh, barW, math.max(bh, v > 0 ? 2 : 0)), topLeft: const Radius.circular(6), topRight: const Radius.circular(6));
      canvas.drawRRect(r, Paint()..color = (sel == null || sel == i) ? color : color.withOpacity(0.35));
      final label = TextPainter(text: TextSpan(text: items[i].$1, style: const TextStyle(fontSize: 10, color: Colors.black54)), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')..layout(maxWidth: slot);
      label.paint(canvas, Offset(slot * i + (slot - label.width) / 2, top + h + 5));
      if (sel == i || (sel == null && items.length <= 8 && v > 0)) {
        final tp = TextPainter(text: TextSpan(text: fmt(v), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: sel == i ? color : Colors.black87)), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(math.max(0, math.min(size.width - tp.width, x + barW / 2 - tp.width / 2)), top + h - bh - 15));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.items != items || old.sel != sel || old.color != color;
}

/// A single stacked strip showing parts of a whole (payment modes, tax heads).
class SplitBar extends StatelessWidget {
  const SplitBar({super.key, required this.parts, this.format});
  final List<(String, double, Color)> parts;
  final String Function(double)? format;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<double>(0, (a, p) => a + p.$2);
    if (total <= 0) return const Text('Nothing recorded', style: TextStyle(color: Colors.black45, fontSize: 13));
    final f = format ?? inr0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 14,
          child: Row(children: [for (final p in parts) if (p.$2 > 0) Expanded(flex: math.max(1, (p.$2 / total * 1000).round()), child: Container(color: p.$3))]),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: [
        for (final p in parts)
          if (p.$2 > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: p.$3, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('${p.$1} ${f(p.$2)} · ${(p.$2 / total * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11.5)),
            ]),
      ]),
    ]);
  }
}

/// A label/value line used inside cards.
class KV extends StatelessWidget {
  const KV(this.k, this.v, {super.key, this.bold = false, this.color});
  final String k, v;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontSize: 12.5, color: color ?? Colors.black54, fontWeight: FontWeight.w500))),
          Text(v, style: TextStyle(fontSize: bold ? 14 : 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
        ]),
      );
}

/// A soft banner (info / warning / error).
class GstNotice extends StatelessWidget {
  const GstNotice(this.text, {super.key, this.color = kGstAmber, this.icon = Icons.info_outline, this.action, this.onAction});
  final String text;
  final Color color;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(color: color.withOpacity(0.09), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.35))),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
          if (action != null) TextButton(onPressed: onAction, style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: color), child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}
