/// GST return periods, mirroring backend/services/gstReports.js so the app and the server always agree.
///   monthly   "2026-08"
///   quarterly "2026-Q2" = financial-year quarter (the FY starts in April: Q1 = Apr-Jun)
library;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsFull = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

class GstPeriod {
  const GstPeriod(this.key, this.from, this.to, this.label, this.short, this.quarter);
  final String key, label, short;
  final DateTime from, to;
  final bool quarter;
}

String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Financial year that a date belongs to, as the year it started in (Jan 2027 -> 2026).
int fyStartYear(DateTime d) => d.month >= 4 ? d.year : d.year - 1;
String fyLabel(int startYear) => '$startYear-${((startYear + 1) % 100).toString().padLeft(2, '0')}';

String periodKeyFor(String frequency, DateTime d) {
  if (frequency == 'quarterly') {
    final q = ((d.month - 4 + 12) % 12) ~/ 3 + 1;
    return '${fyStartYear(d)}-Q$q';
  }
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

GstPeriod? periodOf(String key) {
  final q = RegExp(r'^(\d{4})-Q([1-4])$').firstMatch(key);
  if (q != null) {
    final fy = int.parse(q.group(1)!), n = int.parse(q.group(2)!);
    final start = DateTime(fy, 4 + (n - 1) * 3, 1); // DateTime normalises month overflow
    final end = DateTime(start.year, start.month + 3, 0);
    return GstPeriod(key, start, end, 'Q$n FY ${fyLabel(fy)} (${_months[start.month - 1]}–${_months[end.month - 1]} ${end.year})', 'Q$n ${fyLabel(fy)}', true);
  }
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(key);
  if (m != null) {
    final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
    if (mo < 1 || mo > 12) return null;
    return GstPeriod(key, DateTime(y, mo, 1), DateTime(y, mo + 1, 0), '${_monthsFull[mo - 1]} $y', '${_months[mo - 1]} $y', false);
  }
  return null;
}

String previousPeriodKey(String key) {
  final p = periodOf(key)!;
  final before = p.from.subtract(const Duration(days: 1));
  return periodKeyFor(p.quarter ? 'quarterly' : 'monthly', before);
}

/// The last [count] periods up to and including the one that contains [today], newest first.
List<GstPeriod> recentPeriods(String frequency, DateTime today, {int count = 14}) {
  final out = <GstPeriod>[];
  var key = periodKeyFor(frequency, today);
  for (var i = 0; i < count; i++) {
    out.add(periodOf(key)!);
    key = previousPeriodKey(key);
  }
  return out;
}

/// Statutory due date of a return: due dates trail the period by one month.
DateTime dueDay(String type, String key, {int qrmpDay = 24}) {
  final p = periodOf(key)!;
  final nx = DateTime(p.to.year, p.to.month + 1, 1);
  if (type == 'PMT-06') return DateTime(nx.year, nx.month, 25);
  if (p.quarter) return DateTime(nx.year, nx.month, type == 'GSTR-1' ? 13 : qrmpDay);
  return DateTime(nx.year, nx.month, type == 'GSTR-1' ? 11 : 20);
}
