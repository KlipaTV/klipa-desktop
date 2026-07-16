import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../core/network/bounded_http_client.dart';
import '../core/security/network_policy.dart';
import '../domain/channel.dart';

class XtreamException implements Exception {
  const XtreamException(this.message);

  final String message;

  @override
  String toString() => message;
}

class XtreamImportData {
  const XtreamImportData({
    required this.sourceId,
    required this.server,
    required this.channels,
    required this.warnings,
  });

  final String sourceId;
  final Uri server;
  final List<Channel> channels;
  final List<String> warnings;
}

/// Minimal, live-TV-only Xtream-compatible client.
///
/// Credentials remain in memory and are sent only to the server selected by
/// the user. VOD, series, and catch-up endpoints are intentionally absent.
class XtreamClient {
  XtreamClient({BoundedHttpClient? httpClient})
    : _httpClient = httpClient ?? BoundedHttpClient();

  static const int maxChannels = 100000;
  static const int maxFieldLength = 8192;
  static const int maxGuideIdLength = 512;
  static const int maxCredentialLength = 1024;

  final BoundedHttpClient _httpClient;

  Future<XtreamImportData> loadLiveChannels({
    required Uri server,
    required String username,
    required String password,
    required bool allowPrivateNetwork,
  }) async {
    final normalizedServer = normalizeServer(server);
    _validateCredential('username', username);
    _validateCredential('password', password);

    final account = await _getJson(
      _apiUri(normalizedServer, username, password),
      allowPrivateNetwork: allowPrivateNetwork,
    );
    _validateAccount(account);

    final responses = await Future.wait([
      _getJson(
        _apiUri(
          normalizedServer,
          username,
          password,
          action: 'get_live_categories',
        ),
        allowPrivateNetwork: allowPrivateNetwork,
      ),
      _getJson(
        _apiUri(
          normalizedServer,
          username,
          password,
          action: 'get_live_streams',
        ),
        allowPrivateNetwork: allowPrivateNetwork,
      ),
    ]);

    final sourceId = sha256
        .convert(
          utf8.encode('xtream\u0000${normalizedServer.origin}\u0000$username'),
        )
        .toString();
    final categories = _parseCategories(responses[0]);
    final parsed = _parseStreams(
      responses[1],
      server: normalizedServer,
      username: username,
      password: password,
      sourceId: sourceId,
      categories: categories,
      allowPrivateNetwork: allowPrivateNetwork,
    );

    return XtreamImportData(
      sourceId: sourceId,
      server: normalizedServer,
      channels: parsed.channels,
      warnings: parsed.warnings,
    );
  }

  Uri normalizeServer(Uri value) {
    const NetworkPolicy().validateHttpUriShape(value);
    return value.replace(path: '', query: null, fragment: null);
  }

  void _validateCredential(String name, String value) {
    if (value.isEmpty) {
      throw XtreamException('Enter an Xtream $name.');
    }
    if (value.length > maxCredentialLength ||
        value.contains('\r') ||
        value.contains('\n')) {
      throw XtreamException('The Xtream $name is not valid.');
    }
  }

  Uri _apiUri(Uri server, String username, String password, {String? action}) =>
      server.replace(
        path: '/player_api.php',
        queryParameters: {
          'username': username,
          'password': password,
          'action': ?action,
        },
      );

  Future<Object?> _getJson(Uri uri, {required bool allowPrivateNetwork}) async {
    final bytes = await _httpClient.getPlaylist(
      uri,
      allowPrivateNetwork: allowPrivateNetwork,
    );
    try {
      return await Isolate.run(() => jsonDecode(utf8.decode(bytes)));
    } on FormatException {
      throw const XtreamException(
        'The provider returned an invalid Xtream response.',
      );
    }
  }

  void _validateAccount(Object? response) {
    final root = _asMap(response);
    final userInfo = _asMap(root?['user_info']);
    final auth = userInfo?['auth']?.toString();
    if (auth != '1') {
      throw const XtreamException('The provider rejected these credentials.');
    }

    final status = userInfo?['status']?.toString().toLowerCase();
    if (status != null && status.isNotEmpty && status != 'active') {
      final safeStatus = switch (status) {
        'expired' => 'expired',
        'disabled' => 'disabled',
        'banned' => 'banned',
        _ => 'inactive',
      };
      throw XtreamException(
        'The provider reports this account as $safeStatus.',
      );
    }
  }

  Map<String, String> _parseCategories(Object? response) {
    if (response is! List) return const {};
    final categories = <String, String>{};
    for (final item in response) {
      final category = _asMap(item);
      final id = _bounded(category?['category_id']?.toString());
      final name = _bounded(category?['category_name']?.toString());
      if (id != null && name != null) categories[id] = name;
    }
    return categories;
  }

  _ParsedStreams _parseStreams(
    Object? response, {
    required Uri server,
    required String username,
    required String password,
    required String sourceId,
    required Map<String, String> categories,
    required bool allowPrivateNetwork,
  }) {
    if (response is! List) {
      throw const XtreamException(
        'The provider returned an invalid live-channel list.',
      );
    }

    final channels = <Channel>[];
    final warnings = <String>[];
    for (final item in response) {
      if (channels.length >= maxChannels) {
        warnings.add('Stopped after the first $maxChannels channels.');
        break;
      }
      final stream = _asMap(item);
      final streamId = _bounded(stream?['stream_id']?.toString());
      final name = _bounded(stream?['name']?.toString());
      if (streamId == null || name == null) {
        warnings.add('Skipped an invalid live-channel entry.');
        continue;
      }

      final extension = _safeExtension(
        stream?['container_extension']?.toString(),
      );
      final streamUri =
          _safeUri(stream?['direct_source']?.toString()) ??
          server.replace(
            pathSegments: ['live', username, password, '$streamId.$extension'],
          );
      final categoryId = _bounded(stream?['category_id']?.toString());
      final guideId = _guideId(stream?['epg_channel_id']?.toString());
      final logoUri = _safeUri(stream?['stream_icon']?.toString());
      final channelId = sha256
          .convert(utf8.encode('$sourceId\u0000$streamId'))
          .toString();
      channels.add(
        Channel(
          id: channelId,
          name: name,
          streamUri: streamUri,
          sourceId: sourceId,
          allowsPrivateNetwork: allowPrivateNetwork,
          guideId: guideId,
          group: categoryId == null ? null : categories[categoryId],
          logoUri: logoUri,
        ),
      );
    }

    if (channels.isEmpty) {
      throw const XtreamException('No live channels were returned.');
    }
    return _ParsedStreams(
      channels: List.unmodifiable(channels),
      warnings: List.unmodifiable(warnings),
    );
  }

  Map<String, Object?>? _asMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  String? _bounded(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= maxFieldLength
        ? trimmed
        : trimmed.substring(0, maxFieldLength);
  }

  String? _guideId(String? value) {
    final normalized = value?.trim();
    return normalized != null &&
            normalized.isNotEmpty &&
            normalized.length <= maxGuideIdLength
        ? normalized
        : null;
  }

  String _safeExtension(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized != null && RegExp(r'^[a-z0-9]{1,8}$').hasMatch(normalized)) {
      return normalized;
    }
    return 'ts';
  }

  Uri? _safeUri(String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    try {
      const NetworkPolicy().validateHttpUriShape(uri);
      return uri;
    } on NetworkPolicyException {
      return null;
    }
  }
}

class _ParsedStreams {
  const _ParsedStreams({required this.channels, required this.warnings});

  final List<Channel> channels;
  final List<String> warnings;
}
