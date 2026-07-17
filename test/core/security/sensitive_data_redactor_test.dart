import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/core/security/sensitive_data_redactor.dart';

void main() {
  const redactor = SensitiveDataRedactor();

  test('redacts URI credentials, path, query and fragment', () {
    final result = redactor.uri(
      Uri.parse('https://alice:secret@example.com/list?token=secret#part'),
    );

    expect(result, isNot(contains('alice')));
    expect(result, isNot(contains('secret')));
    expect(result, isNot(contains('list')));
    expect(result, contains('redacted'));
  });

  test('redacts common secret fields in errors', () {
    final result = redactor.text(
      'Authorization:Bearer-abc password=hunter2 '
      'https://alice:secret@example.com/live/alice/path-secret?token=url-secret',
    );

    expect(result, isNot(contains('Bearer-abc')));
    expect(result, isNot(contains('hunter2')));
    expect(result, isNot(contains('alice')));
    expect(result, isNot(contains('secret@example')));
    expect(result, isNot(contains('path-secret')));
    expect(result, isNot(contains('url-secret')));
  });

  test('does not throw when redacting a host-less URL in an error', () {
    expect(
      () => redactor.text('open failed: http://:8080/live/token-secret'),
      returnsNormally,
    );
    final result = redactor.text('open failed: http://:8080/live/token-secret');
    expect(result, isNot(contains('token-secret')));
  });
}
