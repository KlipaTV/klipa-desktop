import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/features/player/playback_error_mapper.dart';

void main() {
  test('does not expose native error or provider address details', () {
    final message = PlaybackErrorMapper.userMessage(
      'tcp://provider.invalid/user/password failed with error -138',
    );

    expect(message, PlaybackErrorMapper.unavailableMessage);
    expect(message, isNot(contains('provider.invalid')));
    expect(message, isNot(contains('password')));
    expect(message, isNot(contains('-138')));
  });
}
