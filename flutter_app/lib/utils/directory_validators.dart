import 'package:flutter/services.dart';

/// Field validation + small automations for the Users forms. The backend
/// (`backend/utils/directoryValidators.js`) applies the same rules and is the
/// source of truth; these give instant feedback while typing.
class DV {
  DV._();

  static String digits(String? v) => (v ?? '').replaceAll(RegExp(r'\D'), '');

  /// "+91 98765-43210", "098765 43210" and "9876543210" all become 10 digits.
  static String normalizePhone(String? v) {
    var d = digits(v);
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    return d;
  }

  static bool isMobile10(String d) => RegExp(r'^[6-9]\d{9}$').hasMatch(d);

  // ── validators (return an error string, or null when fine) ────────────────
  static String? mobile(String? v, {bool required = true}) {
    final d = normalizePhone(v);
    if (d.isEmpty) return required ? 'Enter a 10-digit mobile number' : null;
    if (d.length != 10) return 'Must be exactly 10 digits';
    if (!isMobile10(d)) return 'Mobile numbers start with 6, 7, 8 or 9';
    return null;
  }

  /// Landline / office numbers: any 10 digits.
  static String? phone10(String? v) {
    final d = normalizePhone(v);
    if (d.isEmpty) return null;
    return d.length == 10 ? null : 'Must be exactly 10 digits';
  }

  static String? pan(String? v) {
    final t = (v ?? '').trim().toUpperCase();
    if (t.isEmpty) return null;
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(t) ? null : 'Format: ABCDE1234F';
  }

  static String? gst(String? v) {
    final t = (v ?? '').trim().toUpperCase();
    if (t.isEmpty) return null;
    return RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(t)
        ? null
        : 'Not a valid 15-character GST number';
  }

  static String? aadhaar(String? v) {
    final t = digits(v);
    if (t.isEmpty) return null;
    return RegExp(r'^[2-9]\d{11}$').hasMatch(t) ? null : 'Aadhaar must be 12 digits';
  }

  static String? ifsc(String? v) {
    final t = (v ?? '').trim().toUpperCase();
    if (t.isEmpty) return null;
    return RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(t) ? null : 'Format: SBIN0001234';
  }

  static String? pincode(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return RegExp(r'^[1-9]\d{5}$').hasMatch(t) ? null : 'Pincode must be 6 digits';
  }

  static String? email(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(t) ? null : 'Enter a valid email address';
  }

  // ── small automations ─────────────────────────────────────────────────────
  /// "rAHUL das" / "RAHUL DAS" -> "Rahul Das" (keeps short initials like "S." as typed).
  static String titleCase(String v) {
    final t = v.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return t;
    return t.split(' ').map((w) {
      if (w.isEmpty) return w;
      final isBengali = RegExp(r'[ঀ-৿]').hasMatch(w);
      if (isBengali) return w;
      // keep an all-caps token that already looks like initials ("SK", "R.K.")
      if (w.length <= 2 && w == w.toUpperCase()) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Guess gender from an honorific in a name: "Smt. Rina Das" -> Female.
  /// Returns null when there is no clear hint.
  static String? genderFromName(String name) {
    final first = name.trim().toLowerCase().split(RegExp(r'[\s.]+')).first;
    const female = {'mrs', 'ms', 'miss', 'smt', 'srimati', 'shrimati', 'kumari', 'km'};
    const male = {'mr', 'shri', 'sri', 'shree', 'sh'};
    if (female.contains(first)) return 'Female';
    if (male.contains(first)) return 'Male';
    return null;
  }

  /// Age in whole years for a date of birth, or null if it is in the future.
  static int? ageOn(DateTime dob, [DateTime? now]) {
    final n = now ?? DateTime.now();
    var a = n.year - dob.year;
    if (n.month < dob.month || (n.month == dob.month && n.day < dob.day)) a--;
    return a < 0 ? null : a;
  }

  // ── GST-driven automation ─────────────────────────────────────────────────
  static const gstState = {
    '01': 'Jammu & Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh',
    '05': 'Uttarakhand', '06': 'Haryana', '07': 'Delhi', '08': 'Rajasthan', '09': 'Uttar Pradesh',
    '10': 'Bihar', '11': 'Sikkim', '12': 'Arunachal Pradesh', '13': 'Nagaland', '14': 'Manipur',
    '15': 'Mizoram', '16': 'Tripura', '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal',
    '20': 'Jharkhand', '21': 'Odisha', '22': 'Chhattisgarh', '23': 'Madhya Pradesh', '24': 'Gujarat',
    '26': 'Dadra & Nagar Haveli and Daman & Diu', '27': 'Maharashtra', '29': 'Karnataka', '30': 'Goa',
    '31': 'Lakshadweep', '32': 'Kerala', '33': 'Tamil Nadu', '34': 'Puducherry',
    '35': 'Andaman & Nicobar Islands', '36': 'Telangana', '37': 'Andhra Pradesh', '38': 'Ladakh',
  };
}

/// Cleans pasted phone numbers as they are typed: digits only, and a leading
/// +91 / 0 is dropped, capped at 10 digits.
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = DV.digits(newValue.text);
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    if (d.length > 10) d = d.substring(0, 10);
    return TextEditingValue(
      text: d,
      selection: TextSelection.collapsed(offset: d.length),
    );
  }
}
