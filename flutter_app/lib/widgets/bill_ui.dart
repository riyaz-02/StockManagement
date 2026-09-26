import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Indian-style money: 1,23,456.00 with the rupee sign.
final NumberFormat _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
String inr(num v) => _inr.format(v);

/// Weight in grams with 3 decimals.
String grams(num v) => v.toStringAsFixed(3);

const Color kBillAccent = Color(0xFFD97706); // same amber as the GST Invoice card

/// Small coloured label, e.g. "Paid", "Due ₹1,000".
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, this.color, {super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

/// Section card with a tinted header (same look as the Users forms).
class BillCard extends StatelessWidget {
  const BillCard({super.key, required this.title, required this.icon, required this.color, required this.child, this.trailing});
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: color.withOpacity(0.28)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.10), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: color.withOpacity(0.09),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 15, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13.5)),
                ),
                if (trailing != null) trailing!,
              ]),
            ),
            Container(height: 2.5, color: color),
            Padding(padding: const EdgeInsets.all(12), child: child),
          ]),
        ),
      ),
    );
  }
}

/// Compact outlined field decoration used across the billing screens.
InputDecoration billDec(String label, Color accent, {Widget? suffix, String? prefixText, String? hint}) {
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixText: prefixText,
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 0),
    labelStyle: const TextStyle(fontSize: 12.5),
    floatingLabelStyle: TextStyle(fontSize: 12, color: accent),
    counterText: '',
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    border: b(Colors.black26),
    enabledBorder: b(Colors.black26),
    focusedBorder: b(accent, 1.6),
    errorBorder: b(Colors.red.shade600),
    focusedErrorBorder: b(Colors.red.shade600, 1.6),
    errorStyle: const TextStyle(fontSize: 10.5, height: 1),
  );
}

/// One "label ........ value" row.
class MoneyRow extends StatelessWidget {
  const MoneyRow(this.label, this.value, {super.key, this.bold = false, this.color, this.big = false});
  final String label;
  final String value;
  final bool bold;
  final bool big;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontSize: big ? 16 : 13,
        fontWeight: bold || big ? FontWeight.w800 : FontWeight.w500,
        color: color ?? Colors.black87);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(children: [
        Expanded(child: Text(label, style: style.copyWith(color: color ?? Colors.black54, fontWeight: FontWeight.w500))),
        Text(value, style: style),
      ]),
    );
  }
}
