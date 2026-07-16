import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import '../core/network/bounded_http_client.dart';
import '../domain/channel.dart';
import '../domain/playlist_source.dart';
import 'm3u_parser.dart';
import 'xtream_client.dart';

class PlaylistImportResult {
  const PlaylistImportResult({
    required this.source,
    required this.channels,
    required this.warnings,
  });

  final PlaylistSource source;
  final List<Channel> channels;
  final List<String> warnings;
}

class PlaylistImportService {
  PlaylistImportService({
    BoundedHttpClient? httpClient,
    M3uParser parser = const M3uParser(),
  }) : _httpClient = httpClient ?? BoundedHttpClient(),
       _xtreamClient = XtreamClient(httpClient: httpClient),
       _parser = parser;

  final BoundedHttpClient _httpClient;
  final XtreamClient _xtreamClient;
  final M3uParser _parser;

  Future<PlaylistImportResult> fromUrl(
    Uri uri, {
    required bool allowPrivateNetwork,
  }) async {
    final bytes = await _httpClient.getPlaylist(
      uri,
      allowPrivateNetwork: allowPrivateNetwork,
    );
    return _finish(
      bytes,
      name: uri.host,
      kind: PlaylistSourceKind.remoteUrl,
      location: uri.toString(),
      allowPrivateNetwork: allowPrivateNetwork,
    );
  }

  Future<PlaylistImportResult?> fromFilePicker() async {
    if (!Platform.isWindows && !Platform.isLinux) {
      throw const PlaylistFormatException(
        'Local file selection requires Windows or Linux.',
      );
    }
    const playlistType = XTypeGroup(
      label: 'M3U playlists',
      extensions: ['m3u', 'm3u8'],
    );
    final selection = await openFile(acceptedTypeGroups: const [playlistType]);
    if (selection == null) return null;

    return _fromFile(File(selection.path));
  }

  Future<PlaylistImportResult> refresh(
    PlaylistSource source, {
    String? username,
    String? password,
  }) async {
    switch (source.kind) {
      case PlaylistSourceKind.remoteUrl:
        final uri = Uri.parse(source.location);
        final bytes = await _httpClient.getPlaylist(
          uri,
          allowPrivateNetwork: source.allowsPrivateNetwork,
        );
        return _finish(
          bytes,
          name: source.name,
          kind: source.kind,
          location: source.location,
          allowPrivateNetwork: source.allowsPrivateNetwork,
          sourceId: source.id,
          importedAt: source.importedAt,
        );
      case PlaylistSourceKind.localFile:
        return _fromFile(File(source.location), existingSource: source);
      case PlaylistSourceKind.xtream:
        if (username == null || password == null) {
          throw const XtreamException(
            'The saved Xtream login is incomplete. Re-add this source.',
          );
        }
        final imported = await fromXtream(
          server: Uri.parse(source.location),
          username: username,
          password: password,
          allowPrivateNetwork: source.allowsPrivateNetwork,
        );
        return _rebindToExistingSource(imported, source);
    }
  }

  Future<PlaylistImportResult> _fromFile(
    File file, {
    PlaylistSource? existingSource,
  }) async {
    final length = await file.length();
    if (length > M3uParser.maxBytes) {
      throw const PlaylistFormatException(
        'The playlist exceeds the 25 MiB limit.',
      );
    }
    final bytes = await file.readAsBytes();
    final name = file.uri.pathSegments.isEmpty
        ? 'Local playlist'
        : file.uri.pathSegments.last;
    return _finish(
      bytes,
      name: existingSource?.name ?? name,
      kind: PlaylistSourceKind.localFile,
      location: file.path,
      allowPrivateNetwork: false,
      sourceId: existingSource?.id,
      importedAt: existingSource?.importedAt,
    );
  }

  Future<PlaylistImportResult> fromXtream({
    required Uri server,
    required String username,
    required String password,
    required bool allowPrivateNetwork,
  }) async {
    final result = await _xtreamClient.loadLiveChannels(
      server: server,
      username: username,
      password: password,
      allowPrivateNetwork: allowPrivateNetwork,
    );
    final compatible = await _applyXtreamPlaylistCompatibility(
      result,
      username: username,
      password: password,
      allowPrivateNetwork: allowPrivateNetwork,
    );
    return PlaylistImportResult(
      source: PlaylistSource(
        id: result.sourceId,
        name: result.server.host,
        kind: PlaylistSourceKind.xtream,
        location: result.server.origin,
        allowsPrivateNetwork: allowPrivateNetwork,
        importedAt: DateTime.now().toUtc(),
      ),
      channels: compatible.channels,
      warnings: compatible.warnings,
    );
  }

  Future<_CompatibleXtreamChannels> _applyXtreamPlaylistCompatibility(
    XtreamImportData result, {
    required String username,
    required String password,
    required bool allowPrivateNetwork,
  }) async {
    try {
      final playlistUri = result.server.replace(
        path: '/get.php',
        queryParameters: {
          'username': username,
          'password': password,
          'type': 'm3u_plus',
          'output': 'mpegts',
        },
      );
      final bytes = await _httpClient.getPlaylist(
        playlistUri,
        allowPrivateNetwork: allowPrivateNetwork,
      );
      final parsed = await _parse(
        bytes,
        sourceId: result.sourceId,
        allowPrivateNetwork: allowPrivateNetwork,
      );
      final compatibleByStreamId = <String, Channel>{};
      for (final channel in parsed.channels) {
        final streamId = _streamId(channel.streamUri);
        if (streamId != null) compatibleByStreamId[streamId] = channel;
      }

      var replacements = 0;
      final channels = result.channels
          .map((channel) {
            final streamId = _streamId(channel.streamUri);
            final compatible = streamId == null
                ? null
                : compatibleByStreamId[streamId];
            if (compatible == null) return channel;
            replacements++;
            return Channel(
              id: channel.id,
              name: channel.name,
              streamUri: compatible.streamUri,
              sourceId: channel.sourceId,
              allowsPrivateNetwork: channel.allowsPrivateNetwork,
              guideId: channel.guideId ?? compatible.guideId,
              group: channel.group,
              logoUri: channel.logoUri ?? compatible.logoUri,
              httpHeaders: compatible.httpHeaders,
            );
          })
          .toList(growable: false);
      if (replacements == 0) {
        return _CompatibleXtreamChannels(
          channels: result.channels,
          warnings: [
            ...result.warnings,
            'Provider playlist compatibility data did not match the live catalog.',
          ],
        );
      }
      return _CompatibleXtreamChannels(
        channels: List.unmodifiable(channels),
        warnings: result.warnings,
      );
    } on PlaylistDownloadException {
      return _compatibilityUnavailable(result);
    } on PlaylistFormatException {
      return _compatibilityUnavailable(result);
    }
  }

  _CompatibleXtreamChannels _compatibilityUnavailable(
    XtreamImportData result,
  ) => _CompatibleXtreamChannels(
    channels: result.channels,
    warnings: [
      ...result.warnings,
      'Provider playlist compatibility data was unavailable.',
    ],
  );

  String? _streamId(Uri uri) {
    if (uri.pathSegments.isEmpty) return null;
    final last = uri.pathSegments.last;
    final match = RegExp(r'^(\d+)(?:\.[A-Za-z0-9]{1,8})?$').firstMatch(last);
    return match?.group(1);
  }

  Future<PlaylistImportResult> _finish(
    Uint8List bytes, {
    required String name,
    required PlaylistSourceKind kind,
    required String location,
    required bool allowPrivateNetwork,
    String? sourceId,
    DateTime? importedAt,
  }) async {
    final resolvedSourceId =
        sourceId ??
        sha256
            .convert(utf8.encode('source\u0000${kind.name}\u0000$location'))
            .toString();
    final parsed = await _parse(
      bytes,
      sourceId: resolvedSourceId,
      allowPrivateNetwork: allowPrivateNetwork,
    );
    return PlaylistImportResult(
      source: PlaylistSource(
        id: resolvedSourceId,
        name: name,
        kind: kind,
        location: location,
        allowsPrivateNetwork: allowPrivateNetwork,
        importedAt: importedAt ?? DateTime.now().toUtc(),
      ),
      channels: parsed.channels,
      warnings: parsed.warnings,
    );
  }

  PlaylistImportResult _rebindToExistingSource(
    PlaylistImportResult result,
    PlaylistSource existing,
  ) {
    final channels = result.source.id == existing.id
        ? result.channels
        : result.channels
              .map(
                (channel) => Channel(
                  id: _reboundChannelId(existing.id, channel),
                  name: channel.name,
                  streamUri: channel.streamUri,
                  sourceId: existing.id,
                  allowsPrivateNetwork: existing.allowsPrivateNetwork,
                  guideId: channel.guideId,
                  group: channel.group,
                  logoUri: channel.logoUri,
                  httpHeaders: channel.httpHeaders,
                ),
              )
              .toList(growable: false);
    return PlaylistImportResult(
      source: PlaylistSource(
        id: existing.id,
        name: existing.name,
        kind: existing.kind,
        location: existing.location,
        allowsPrivateNetwork: existing.allowsPrivateNetwork,
        importedAt: existing.importedAt,
      ),
      channels: List.unmodifiable(channels),
      warnings: result.warnings,
    );
  }

  String _reboundChannelId(String sourceId, Channel channel) {
    final streamId = _streamId(channel.streamUri);
    final identity = streamId ?? '${channel.streamUri}\u0000${channel.name}';
    return sha256.convert(utf8.encode('$sourceId\u0000$identity')).toString();
  }

  Future<M3uParseResult> _parse(
    Uint8List bytes, {
    required String sourceId,
    required bool allowPrivateNetwork,
  }) {
    final parser = _parser;
    return Isolate.run(
      () => parser.parse(
        bytes,
        sourceId: sourceId,
        allowPrivateNetwork: allowPrivateNetwork,
      ),
    );
  }
}

class _CompatibleXtreamChannels {
  const _CompatibleXtreamChannels({
    required this.channels,
    required this.warnings,
  });

  final List<Channel> channels;
  final List<String> warnings;
}
