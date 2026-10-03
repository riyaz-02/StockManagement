import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_stock_app/models/stock_summary_models.dart';

Map<String, dynamic> _fx(String name) =>
    Map<String, dynamic>.from(json.decode(File('test/fixtures/$name').readAsStringSync()) as Map)['data'] as Map<String, dynamic>;

void main() {
  test('the summary reads the server answer, and the balance adds up', () {
    final s = StockSummary.fromJson(_fx('stock_summary.json'));
    for (final m in [s.gold, s.silver]) {
      expect(m.receiptsTotal, closeTo(m.purchased + m.allowance + m.oldMetal + m.rawMetal, 0.0015));
      expect(m.stockTotal, closeTo(m.inShop + m.withOthers + m.bulk, 0.0015));
      expect(m.variance, closeTo(m.receiptsTotal - (m.stockTotal + m.sold + m.wastage), 0.0025));
    }
    expect(s.confidenceText.of('bn'), isNotEmpty);
    expect(s.goldInsight.headline.of('en'), isNotEmpty);
    expect(['reliable', 'check', 'fix'], contains(s.confidenceLevel));
  });

  test('a text in both languages falls back to English when Bengali is missing', () {
    expect(const LText('Hello', '').of('bn'), 'Hello');
    expect(const LText('Hello', 'নমস্কার').of('bn'), 'নমস্কার');
    expect(const LText('Hello', 'নমস্কার').of('en'), 'Hello');
  });

  test('history and wastage lists parse', () {
    final h = StockHistory.fromJson(_fx('stock_history.json'));
    expect(h.rows, isA<List<HistoryRow>>());
    final w = _fx('wastage_list.json');
    final reports = (w['reports'] as List).map((e) => WastageReport.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    for (final r in reports) {
      expect(r.amount, greaterThan(0));
      expect(['pending', 'approved', 'rejected'], contains(r.status));
    }
  });
}
