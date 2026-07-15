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
}
