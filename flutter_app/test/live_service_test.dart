import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_stock_app/services/live_service.dart';
import 'package:jewellery_stock_app/utils/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tiny stand-in for the server's /api/live stream (plain socket: full control of what is written and when).
class FakeLive {
  late ServerSocket server;
  final requests = <Uri>[];
  final headers = <Map<String, String>>[];
  int status = 200;
  final List<Socket> open = [];

  Future<void> start() async {
    server = await ServerSocket.bind('127.0.0.1', 0);
    server.listen((sock) {
      final buf = StringBuffer();
      late StreamSubscription sub;
      sub = sock.listen((data) {
        buf.write(latin1.decode(data));
        final text = buf.toString();
        if (!text.contains('\r\n\r\n')) return;
        sub.pause();
        final lines = text.split('\r\n');
        final path = lines.first.split(' ')[1];
        requests.add(Uri.parse('http://x$path'));
        final h = <String, String>{};
        for (final l in lines.skip(1)) {
          final i = l.indexOf(':');
          if (i > 0) h[l.substring(0, i).toLowerCase()] = l.substring(i + 1).trim();
        }
        headers.add(h);
        if (status != 200) {
          sock.write('HTTP/1.1 $status X\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
          sock.flush().then((_) => sock.close());
          return;
        }
        sock.write('HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n');
        sock.write('retry: 3000\n\n');
        sock.write('event: hello\ndata: {"latest":5,"reset":false}\n\n');
        // only offer the socket for sending once the greeting is flushed (writing while a flush runs throws "StreamSink is bound to a stream")
        sock.flush().then((_) => open.add(sock), onError: (_) {});
      }, onError: (_) {}, onDone: () => open.remove(sock));
    });
    AppConstants.setRuntimeProductionUrl('http://127.0.0.1:${server.port}/api');
  }

  Future<void> send(String type, Map<String, dynamic> data) async {
    for (final s in List<Socket>.from(open)) {
      s.write('id: ${data['seq']}\nevent: $type\ndata: ${json.encode(data)}\n\n');
      await s.flush();
    }
  }

  Future<void> closeAll() async {
    for (final s in List<Socket>.from(open)) {
      try {
        await s.close();
      } catch (_) {}
    }
    open.clear();
  }

  Future<void> stop() async {
    await closeAll();
    await server.close();
  }
}

Future<void> until(bool Function() ok, {int ms = 4000}) async {
  for (var i = 0; i < ms ~/ 25 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real network calls; this test talks to a local fake server

  test('connects with the login, says hello, and delivers events as they happen', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakeLive();
    await fake.start();
    final got = <LiveEvent>[];
    final sub = LiveService.instance.events.listen(got.add);
    await LiveService.instance.start('tok123');
    await until(() => fake.open.isNotEmpty);
    expect(fake.headers.first['authorization'], 'Bearer tok123');
    expect(fake.headers.first['accept'], 'text/event-stream');
    await until(() => LiveService.instance.connected);
    await fake.send('rate.changed', {'seq': 6, 'type': 'rate.changed', 'data': {'gold': 9300}, 'by': 'Admin'});
    await fake.send('data.changed', {'seq': 7, 'type': 'data.changed', 'module': 'orders', 'data': {'module': 'orders'}});
    await until(() => got.length >= 2);
    expect(got.map((e) => e.type), ['rate.changed', 'data.changed']);
    expect(got[0].data['gold'], 9300);
    expect(got[0].by, 'Admin');
    expect(got[1].module, 'orders');
    // a list that cares about orders hears it; one that cares about billing does not
    final orders = <LiveEvent>[];
    final billing = <LiveEvent>[];
    final s1 = LiveService.instance.forModules(['orders']).listen(orders.add);
    final s2 = LiveService.instance.forModules(['billing']).listen(billing.add);
    await fake.send('data.changed', {'seq': 8, 'type': 'data.changed', 'module': 'orders', 'data': {}});
    await until(() => orders.isNotEmpty);
    expect(orders.length, 1);
    expect(billing, isEmpty);
    await s1.cancel();
    await s2.cancel();
    LiveService.instance.stop();
    await sub.cancel();
    await fake.stop();
  });

  test('after the connection drops it reconnects and asks only for what it missed (since = last event number)', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakeLive();
    await fake.start();
    await LiveService.instance.start('tok');
    await until(() => fake.open.isNotEmpty);
    await fake.send('rate.changed', {'seq': 12, 'type': 'rate.changed', 'data': {}});
    await until(() => false, ms: 300);
    await fake.closeAll(); // the server went away
    await until(() => fake.requests.length >= 2, ms: 6000); // retry after about 2 seconds
    expect(fake.requests.length, greaterThanOrEqualTo(2));
    expect(fake.requests.last.queryParameters['since'], '12');
    LiveService.instance.stop();
    await fake.stop();
  });

  test('a rejected login (401) stops it for good: it never hammers the server', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakeLive()..status = 401;
    await fake.start();
    await LiveService.instance.start('old-token');
    await until(() => fake.requests.isNotEmpty);
    await until(() => false, ms: 2600); // longer than the first retry wait
    expect(fake.requests.length, 1);
    LiveService.instance.stop();
    await fake.stop();
  });

  test('when the server is not there at all it just retries later (nothing thrown)', () async {
    SharedPreferences.setMockInitialValues({});
    final probe = await HttpServer.bind('127.0.0.1', 0);
    final port = probe.port;
    await probe.close();
    AppConstants.setRuntimeProductionUrl('http://127.0.0.1:$port/api');
    await LiveService.instance.start('tok');
    await until(() => false, ms: 500);
    expect(LiveService.instance.connected, isFalse);
    LiveService.instance.stop();
  });
}
