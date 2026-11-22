import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/source_transfer_service.dart';

const _code = '123-456';
const _token = '0123456789abcdefghijklmnopqrstuv';

void main() {
  late HttpServer server;
  late SourceTransferService service;
  late List<({String method, String path, String? token})> requests;
  late Map<String, Object?> payload;
  late bool protectedSlot;
  late bool waitOnePoll;

  setUp(() async {
    requests = [];
    payload = {'kind': 'm3u', 'url': 'https://example.test/a.m3u'};
    protectedSlot = true;
    waitOnePoll = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add((
        method: request.method,
        path: request.uri.toString(),
        token: request.headers.value('X-Klipa-Claim-Token'),
      ));
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (request.uri.path == '/pair/new') {
        response.statusCode = HttpStatus.created;
        response.write(
          jsonEncode({
            'code': _code,
            'claimToken': _token,
            'claimTokenRequired':
                protectedSlot &&
                request.headers.value('X-Klipa-Require-Claim-Token') == '1',
            'ttlSeconds': 300,
          }),
        );
      } else if (waitOnePoll) {
        waitOnePoll = false;
        response.statusCode = HttpStatus.noContent;
      } else {
        response.write(jsonEncode({'payload': payload}));
      }
      await response.close();
    });
    service = SourceTransferService(
      endpoint: Uri.http('127.0.0.1:${server.port}'),
    );
  });

  tearDown(() async {
    service.close();
    await server.close(force: true);
  });

  test(
    'requests only after a code is generated and sends the token on each poll',
    () async {
      expect(requests, isEmpty);
      waitOnePoll = true;
      final slot = await service.createSlot();
      expect(slot.code, _code);
      final source = await service.waitForSource(slot);
      expect(source.address, Uri.parse('https://example.test/a.m3u'));
      expect(source.xtreamLogin, isNull);
      expect(requests, [
        (method: 'POST', path: '/pair/new', token: null),
        (method: 'GET', path: '/pair/claim?code=$_code', token: _token),
        (method: 'GET', path: '/pair/claim?code=$_code', token: _token),
      ]);
    },
  );

  test('leaves Xtream password characters intact', () async {
    payload = {
      'kind': 'xtream',
      'server': 'https://example.test',
      'username': 'example',
      'password': ' x+y ',
    };
    final source = await service.waitForSource(await service.createSlot());
    expect(source.address.host, 'example.test');
    expect(source.xtreamLogin, (username: 'example', password: ' x+y '));
  });

  test('requires the relay to acknowledge protected codes', () async {
    protectedSlot = false;
    await expectLater(
      service.createSlot(),
      throwsA(isA<SourceTransferException>()),
    );
    expect(requests, hasLength(1));
  });

  test('rejects a playlist with custom request headers', () async {
    payload['headers'] = {'User-Agent': 'Example client'};
    final slot = await service.createSlot();
    await expectLater(
      service.waitForSource(slot),
      throwsA(
        isA<SourceTransferException>().having(
          (error) => error.message,
          'message',
          contains('custom request headers'),
        ),
      ),
    );
  });

  test('stops polling after close during the backoff delay', () async {
    waitOnePoll = true;
    final slot = await service.createSlot();
    final future = service.waitForSource(slot);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    service.close();
    await expectLater(future, throwsA(isA<SourceTransferException>()));
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(requests, [
      (method: 'POST', path: '/pair/new', token: null),
      (method: 'GET', path: '/pair/claim?code=$_code', token: _token),
    ]);
  });
}
