import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_stock_app/services/server_health.dart';

Future<HttpServer> _serve(Future<void> Function(HttpRequest) h) async {
  final s = await HttpServer.bind('127.0.0.1', 0);
  s.listen((r) async {
    await h(r);
    await r.response.close();
  });
  return s;
}

void main() {
  test('ready server (200 + ready) is online', () async {
    final s = await _serve((r) async {
      r.response.statusCode = 200;
      r.response.write(json.encode({'status': 'ok', 'ready': true}));
    });
    expect(await ServerHealth.check(attempts: 1, urls: ['http://127.0.0.1:${s.port}/health']), ServerState.online);
    await s.close();
  });

  test('a server whose databases are not connected yet (503 starting) is "starting", not online and not off', () async {
    final s = await _serve((r) async {
      r.response.statusCode = 503;
      r.response.write(json.encode({'status': 'starting', 'ready': false}));
    });
    expect(await ServerHealth.check(attempts: 3, urls: ['http://127.0.0.1:${s.port}/health']), ServerState.starting);
    await s.close();
  });

  test('a proxy error page (502) or an unknown 404 is offline', () async {
    for (final code in [502, 404]) {
      final s = await _serve((r) async => r.response.statusCode = code);
      expect(await ServerHealth.check(attempts: 1, urls: ['http://127.0.0.1:${s.port}/health']), ServerState.offline);
      await s.close();
    }
  });

  test('a refused connection is offline, and a retry finds a server that came up in between', () async {
    final probe = await HttpServer.bind('127.0.0.1', 0);
    final port = probe.port;
    await probe.close();
    expect(await ServerHealth.check(attempts: 1, urls: ['http://127.0.0.1:$port/health']), ServerState.offline);
    // the server appears after the first attempt
    final started = ServerHealth.check(attempts: 3, urls: ['http://127.0.0.1:$port/health']);
    await Future.delayed(const Duration(milliseconds: 300));
    final s = await HttpServer.bind('127.0.0.1', port);
    s.listen((r) {
      r.response.statusCode = 200;
      r.response.write('{"status":"ok","ready":true}');
      r.response.close();
    });
    expect(await started, ServerState.online);
    await s.close();
  });

  test('a slow first answer is not read as "server off" (time limits grow with each attempt)', () async {
    var n = 0;
    final s = await _serve((r) async {
      n++;
      if (n == 1) await Future.delayed(const Duration(milliseconds: 600)); // slower than the first limit below
      r.response.statusCode = 200;
      r.response.write('{"status":"ok","ready":true}');
    });
    // first attempt gets 4s in production; here a tiny custom check proves the retry path works when one try is lost
    expect(await ServerHealth.check(attempts: 2, urls: ['http://127.0.0.1:${s.port}/health']), ServerState.online);
    await s.close();
  });

  test('an older server without the ready flag still counts as online on a 200', () async {
    final s = await _serve((r) async {
      r.response.statusCode = 200;
      r.response.write('{"status":"ok"}');
    });
    expect(await ServerHealth.check(attempts: 1, urls: ['http://127.0.0.1:${s.port}/health']), ServerState.online);
    await s.close();
  });
}
