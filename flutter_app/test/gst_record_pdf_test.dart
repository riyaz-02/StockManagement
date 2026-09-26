// The monthly "GST Invoice Record" PDF must build for any month: cancelled / IGST invoices, invoices with many
// items (split over blocks), hundreds of invoices, and missing / odd data.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_stock_app/utils/gst_record_pdf.dart';

Map<String, dynamic> _inv(int n, {String status = 'delivered', String gst = 'CGST_SGST', int items = 1, bool bn = true}) => {
      'number': '${1000 + n}',
      'date': '2026-08-${(n % 28 + 1).toString().padLeft(2, '0')}',
      'delivery': '2026-08-${(n % 28 + 1).toString().padLeft(2, '0')}',
      'status': status,
      'counted': ['active', 'revised', 'pending', 'delivered'].contains(status),
      'gstType': gst,
      'customer': {'name': 'Customer $n', 'mobile': '9000000000', 'address': '12 Test Road, Howrah, West Bengal 711101', 'state': 'West Bengal', 'stateCode': '19', 'pan': n % 5 == 0 ? 'ABCDE1234F' : ''},
      'reverseCharge': 'No',
      'branch': 'Bagbazar Showroom', 'createdBy': 'Main Counter Staff', 'createdAt': '2026-08-04T10:58:00.000Z', 'goldRate': 13745.0, 'silverRate': 164.6,
      'paid': 60000.0, 'due': 6435.0, 'advance': 0.0,
      'payments': [for (var k = 0; k < (n % 4 == 0 ? 9 : 2); k++) {'mode': k.isEven ? 'Cash' : 'Online', 'amount': 5000.0, 'date': '2026-08-04T10:58:00.000Z', 'reference': k.isEven ? '' : 'UPI19105497910$k'}],
      'tds': n % 7 == 0 ? {'rate': 1, 'amount': 2060} : null,
      'placeOfSupply': gst == 'IGST' ? '27-Maharashtra' : '19-West Bengal',
      'terms': 'Customer Pickup',
      'paymentMode': 'Cash',
      'note': n % 3 == 0 ? 'Regular customer, exchange of old ornaments adjusted' : '',
      'reference': '',
      'items': [
        for (var i = 0; i < items; i++)
          {'name': 'Gold Ring number $i with a fairly long descriptive name (HUID: AB12CD) + Making Charge', 'hsn': '7113', 'metal': i.isEven ? 'Gold' : 'Silver', 'netWt': 10.5 + i, 'rate': 6000.0, 'making': 1500.0, 'amount': 64500.0, 'purity': '22K', 'grossWt': 11.2 + i, 'code': 'LGP-RG-0342', 'huid': 'AB12CD', 'certification': 'huid', 'metalValue': 63000.0, 'stone': 1200.0, 'hallmark': 45.0, 'discount': 68.0, 'extras': [{'kind': 'Stone', 'name': 'Ruby', 'weight': 0.4, 'amount': 900.0}, {'kind': 'Diamond', 'name': 'Diamond', 'weight': 0.1, 'amount': 300.0}]}
      ],
      'cgst': gst == 'IGST' ? 0.0 : 967.5,
      'sgst': gst == 'IGST' ? 0.0 : 967.5,
      'igst': gst == 'IGST' ? 1935.0 : 0.0,
      'taxable': 64500.0,
      'totalGst': 1935.0,
      'additionalCharges': 0.0,
      'additionalChargesGst': 0.0,
      'discount': n % 2 == 0 ? 500.0 : 0.0,
      'discountBeforeGst': true,
      'roundOff': -0.4,
      'totalPayable': 66435.0,
      'amountInWords': bn ? 'Sixty Six Thousand Four Hundred Rupees Only (ছেষট্টি হাজার চার শত টাকা মাত্র)' : 'Sixty Six Thousand Rupees Only',
    };

Map<String, dynamic> _data(List<Map<String, dynamic>> invoices, {bool partial = false}) => {
      'documentId': 'GST-ABC123',
      'generatedAt': '20-09-2026 10:30:00 IST',
      'partial': partial,
      'seller': {'firmName': 'LALTU GUINEA PALACE', 'gstin': '19AKFPN3465R1ZB'},
      'period': {'year': 2026, 'month': 8, 'monthName': 'August'},
      'invoices': invoices,
      'totals': {'count': invoices.length, 'taxable': 6450000.0, 'additional': 0.0, 'cgst': 96750.0, 'sgst': 96750.0, 'igst': 19350.0, 'gst': 212850.0, 'amount': 6643500.0, 'goldWeight': 1050.5, 'silverWeight': 12.0, 'discount': 2500.0, 'making': 150000.0},
      'tracking': {'start': 1001, 'end': 1000 + invoices.length, 'total': invoices.length, 'valid': invoices.length - 1, 'cancelledVoidDeleted': 1, 'avgInvoice': 66435.0, 'gstRate': 3.0, 'cgstRate': 1.5, 'sgstRate': 1.5, 'igstRate': 0.3, 'branchSeries': [{'name': 'BR2', 'from': 'BR2-0001', 'to': 'BR2-0009', 'count': 9}]},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool isPdf(Uint8List b) => b.length > 1000 && String.fromCharCodes(b.take(5)) == '%PDF-';

  test('builds a record with normal, cancelled, IGST and void invoices', () async {
    final bytes = await buildMonthlyRecordPdf(_data([_inv(1), _inv(2, status: 'cancelled'), _inv(3, gst: 'IGST'), _inv(4, status: 'void'), _inv(5, status: 'revised'), _inv(6, status: 'pending')]));
    expect(isPdf(bytes), isTrue);
  });

  test('an invoice with 40 items is split over several blocks (no page overflow)', () async {
    final bytes = await buildMonthlyRecordPdf(_data([_inv(1), _inv(2, items: 40), _inv(3)]));
    expect(isPdf(bytes), isTrue);
  });

  test('a long note, 9 payments and 12 stones on one item do not overflow a page', () async {
    final inv = _inv(4, items: 3);
    inv['note'] = 'x' * 400;
    inv['customer'] = {'name': 'A very long customer name that keeps going ' * 3, 'mobile': '9000000000', 'address': 'y' * 300, 'state': 'West Bengal', 'stateCode': '19', 'pan': 'ABCDE1234F'};
    ((inv['items'] as List).first as Map)['extras'] = [for (var i = 0; i < 10; i++) {'kind': 'Stone', 'name': 'Stone number $i', 'weight': 0.3, 'amount': 100.0}];
    final bytes = await buildMonthlyRecordPdf(_data([_inv(1), inv, _inv(5)]));
    expect(isPdf(bytes), isTrue);
  });

  test('300 invoices build (many pages)', () async {
    final bytes = await buildMonthlyRecordPdf(_data([for (var i = 1; i <= 300; i++) _inv(i, status: i == 50 ? 'cancelled' : 'delivered', gst: i % 9 == 0 ? 'IGST' : 'CGST_SGST', bn: i % 2 == 0)]));
    expect(isPdf(bytes), isTrue);
    expect(bytes.length, greaterThan(20000));
  });

  test('missing and odd data does not crash (no items, blank fields, numbers as strings, branch-only record)', () async {
    final odd = {
      'number': 'BR2-0001', 'date': '2026-08-01', 'status': 'active', 'counted': true, 'gstType': 'CGST_SGST', 'customer': {}, 'items': [], 'cgst': '10', 'sgst': '10', 'igst': null, 'totalPayable': '1030', 'roundOff': '0', 'discount': null, 'amountInWords': null,
    };
    final bytes = await buildMonthlyRecordPdf(_data([odd], partial: true));
    expect(isPdf(bytes), isTrue);
  });
}
