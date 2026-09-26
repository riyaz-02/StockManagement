// The phone's period maths must agree with the server (backend/scripts/gst-reports.test.js).
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_stock_app/utils/gst_periods.dart';

void main() {
  test('period keys: monthly and financial-year quarters', () {
    expect(periodKeyFor('monthly', DateTime(2026, 8, 15)), '2026-08');
    expect(periodKeyFor('quarterly', DateTime(2026, 4, 1)), '2026-Q1');
    expect(periodKeyFor('quarterly', DateTime(2026, 8, 15)), '2026-Q2');
    expect(periodKeyFor('quarterly', DateTime(2026, 12, 31)), '2026-Q3');
    expect(periodKeyFor('quarterly', DateTime(2027, 1, 1)), '2026-Q4');
    expect(periodKeyFor('quarterly', DateTime(2027, 3, 31)), '2026-Q4');
  });

  test('period ranges and labels', () {
    final q = periodOf('2026-Q4')!;
    expect([ymd(q.from), ymd(q.to)], ['2027-01-01', '2027-03-31']);
    expect(q.short, 'Q4 2026-27');
    final m = periodOf('2028-02')!;
    expect([ymd(m.from), ymd(m.to)], ['2028-02-01', '2028-02-29']);
    expect(periodOf('2026-13'), isNull);
    expect(periodOf('nonsense'), isNull);
  });

  test('previous period and the recent list', () {
    expect(previousPeriodKey('2026-01'), '2025-12');
    expect(previousPeriodKey('2026-Q1'), '2025-Q4');
    expect(recentPeriods('monthly', DateTime(2026, 9, 20), count: 3).map((p) => p.key), ['2026-09', '2026-08', '2026-07']);
    expect(recentPeriods('quarterly', DateTime(2026, 9, 20), count: 3).map((p) => p.key), ['2026-Q2', '2026-Q1', '2025-Q4']);
  });

  test('due dates match the server', () {
    expect(ymd(dueDay('GSTR-1', '2026-08')), '2026-09-11');
    expect(ymd(dueDay('GSTR-3B', '2026-08')), '2026-09-20');
    expect(ymd(dueDay('GSTR-1', '2026-Q2')), '2026-10-13');
    expect(ymd(dueDay('GSTR-3B', '2026-Q2', qrmpDay: 24)), '2026-10-24');
    expect(ymd(dueDay('GSTR-3B', '2026-Q2', qrmpDay: 22)), '2026-10-22');
    expect(ymd(dueDay('PMT-06', '2026-07')), '2026-08-25');
  });
}
