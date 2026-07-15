import 'playlist_source.dart';

/// Source metadata safe to keep in UI state and list queries.
///
/// Provider locations and credentials live only in the encrypted source-secret
/// table and are loaded transiently for refresh.
class LibrarySource {
  const LibrarySource({
    required this.id,
    required this.name,
    required this.kind,
    required this.allowsPrivateNetwork,
    required this.importedAt,
    required this.refreshedAt,
  });

  factory LibrarySource.fromImported(
    PlaylistSource source, {
    DateTime? refreshedAt,
  }) => LibrarySource(
    id: source.id,
    name: source.name,
    kind: source.kind,
    allowsPrivateNetwork: source.allowsPrivateNetwork,
    importedAt: source.importedAt,
    refreshedAt: refreshedAt ?? DateTime.now().toUtc(),
  );

  final String id;
  final String name;
  final PlaylistSourceKind kind;
  final bool allowsPrivateNetwork;
  final DateTime importedAt;
  final DateTime refreshedAt;

  LibrarySource copyWith({String? name, DateTime? refreshedAt}) =>
      LibrarySource(
        id: id,
        name: name ?? this.name,
        kind: kind,
        allowsPrivateNetwork: allowsPrivateNetwork,
        importedAt: importedAt,
        refreshedAt: refreshedAt ?? this.refreshedAt,
      );
}
