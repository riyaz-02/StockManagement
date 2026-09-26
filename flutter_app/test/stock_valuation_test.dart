// The Dart valuation must give exactly what the server engine gives (backend/scripts/gen-valuation-vectors.js).
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_stock_app/utils/stock_valuation.dart';

void main() {
  final data = jsonDecode(File('test/valuation_vectors.json').readAsStringSync()) as Map<String, dynamic>;

  test('purity text gives the same percentage as the server', () {
    for (final p in data['purity'] as List) {
      expect(purityPercent((p as List)[0] as String), closeTo((p[1] as num).toDouble(), 0.0001), reason: 'purity "${p[0]}"');
    }
  });

  test('every generated case matches the server engine (80 cases)', () {
    var n = 0;
    for (final c in data['cases'] as List) {
      final got = computeStock(Map<String, dynamic>.from(c['input']), Map<String, dynamic>.from(c['rules'])).m;
      final want = Map<String, dynamic>.from(c['expect']);
      for (final k in want.keys) {
        expect(got[k], closeTo((want[k] as num).toDouble(), 0.011), reason: 'case $n, $k');
      }
      n++;
    }
    expect(n, 80);
  });

  test('every generated purchase case matches the server engine (60 cases)', () {
    var n = 0;
    for (final c in data['purchase'] as List) {
      final got = computePurchase(Map<String, dynamic>.from(c['input']), Map<String, dynamic>.from(c['rules']));
      final want = Map<String, dynamic>.from(c['expect']);
      for (final k in want.keys) {
        expect(got[k], closeTo((want[k] as num).toDouble(), 0.011), reason: 'purchase case $n, $k');
      }
      n++;
    }
    expect(n, 60);
  });

  test('every generated old-metal case matches the server engine (40 cases)', () {
    var n = 0;
    for (final c in data['oldMetal'] as List) {
      final got = computeOldMetal(Map<String, dynamic>.from(c['input']), Map<String, dynamic>.from(c['rules']));
      final want = Map<String, dynamic>.from(c['expect']);
      for (final k in want.keys) {
        if (k == 'basis') {
          expect(got[k], want[k], reason: 'old metal case $n');
        } else {
          expect((got[k] as num).toDouble(), closeTo((want[k] as num).toDouble(), 0.011), reason: 'old metal case $n, $k');
        }
      }
      n++;
    }
    expect(n, 40);
  });

  test('empty and text input never gives NaN', () {
    final r = computeStock({'gross': 'abc', 'less': -3, 'rate': -5}, {}).m;
    for (final v in r.values) {
      expect(v.isFinite, isTrue);
    }
    expect(r['finalPrice'], 0);
  });
}
