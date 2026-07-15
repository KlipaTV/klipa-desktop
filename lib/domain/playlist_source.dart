enum PlaylistSourceKind { localFile, remoteUrl, xtream }

class PlaylistSource {
  const PlaylistSource({
    required this.id,
    required this.name,
    required this.kind,
    required this.location,
    required this.allowsPrivateNetwork,
    required this.importedAt,
  });

  final String id;
  final String name;
  final PlaylistSourceKind kind;
  final String location;
  final bool allowsPrivateNetwork;
  final DateTime importedAt;
}
