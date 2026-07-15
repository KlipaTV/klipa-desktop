abstract final class PlaybackErrorMapper {
  static const unavailableMessage =
      'This channel could not be opened. Check the source and try again.';

  static String userMessage(Object _) => unavailableMessage;
}
