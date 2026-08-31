import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/core/security/network_policy.dart';

void main() {
  const policy = NetworkPolicy();

  test('accepts only complete HTTP and HTTPS addresses', () {
    expect(
      () => policy.validateHttpUriShape(
        Uri.parse('https://example.com/list.m3u'),
      ),
      returnsNormally,
    );
    expect(
      () => policy.validateHttpUriShape(Uri.parse('file:///tmp/list.m3u')),
      throwsA(isA<NetworkPolicyException>()),
    );
    expect(
      () => policy.validateHttpUriShape(
        Uri.parse('https://user:password@example.com/list.m3u'),
      ),
      throwsA(isA<NetworkPolicyException>()),
    );
  });

  test('local targets require explicit permission', () async {
    await expectLater(
      policy.validateHttpTarget(
        Uri.parse('http://127.0.0.1/list.m3u'),
        allowPrivateNetwork: false,
      ),
      throwsA(isA<NetworkPolicyException>()),
    );
    await expectLater(
      policy.validateHttpTarget(
        Uri.parse('http://127.0.0.1/list.m3u'),
        allowPrivateNetwork: true,
      ),
      completion(NetworkTargetKind.privateOrLocal),
    );
  });

  test(
    'classifies reserved IPv4 and mapped IPv6 literals as non-public',
    () async {
      const nonPublic = [
        '0.0.0.0',
        '100.64.0.1',
        '192.0.0.1',
        '192.0.2.1',
        '198.18.0.1',
        '198.51.100.1',
        '203.0.113.1',
        '224.0.0.1',
        '240.0.0.1',
        '::ffff:127.0.0.1',
        '::ffff:192.168.1.1',
      ];
      for (final host in nonPublic) {
        await expectLater(
          policy.classifyHost(host),
          completion(NetworkTargetKind.privateOrLocal),
          reason: host,
        );
      }
    },
  );

  test('classifies reserved IPv6 literals as non-public', () async {
    for (final host in ['::', '100::1', '2001:db8::1', 'fec0::1', 'fd00::1']) {
      await expectLater(
        policy.classifyHost(host),
        completion(NetworkTargetKind.privateOrLocal),
        reason: host,
      );
    }
  });

  test('keeps globally routable literals public', () async {
    for (final host in ['1.1.1.1', '8.8.8.8', '2606:4700:4700::1111']) {
      await expectLater(
        policy.classifyHost(host),
        completion(NetworkTargetKind.public),
        reason: host,
      );
    }
  });

  test('resolveHttpTarget returns the classified addresses to pin', () async {
    final addresses = await policy.resolveHttpTarget(
      Uri.parse('http://8.8.8.8/list.m3u'),
      allowPrivateNetwork: false,
    );
    expect(addresses, [InternetAddress('8.8.8.8')]);
  });

  test(
    'resolveHttpTarget rejects private targets without permission',
    () async {
      await expectLater(
        policy.resolveHttpTarget(
          Uri.parse('http://192.168.1.10/list.m3u'),
          allowPrivateNetwork: false,
        ),
        throwsA(isA<NetworkPolicyException>()),
      );
      final allowed = await policy.resolveHttpTarget(
        Uri.parse('http://192.168.1.10/list.m3u'),
        allowPrivateNetwork: true,
      );
      expect(allowed, [InternetAddress('192.168.1.10')]);
    },
  );
}
