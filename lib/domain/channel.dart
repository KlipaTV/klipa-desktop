import 'dart:collection';

/// A single playable entry imported from a user-provided playlist.
class Channel {
  Channel({
    required this.id,
    required this.name,
    required this.streamUri,
    required this.sourceId,
    required this.allowsPrivateNetwork,
    this.guideId,
    this.group,
    this.logoUri,
    Map<String, String> httpHeaders = const {},
  }) : httpHeaders = UnmodifiableMapView(httpHeaders);

  final String id;
  final String name;
  final Uri streamUri;
  final String sourceId;
  final bool allowsPrivateNetwork;
  final String? guideId;
  final String? group;
  final Uri? logoUri;
  final Map<String, String> httpHeaders;
}
