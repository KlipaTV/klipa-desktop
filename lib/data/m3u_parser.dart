import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/security/network_policy.dart';
import '../domain/channel.dart';

class PlaylistFormatException implements Exception {
  const PlaylistFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class M3uParseResult {
  const M3uParseResult({required this.channels, required this.warnings});

  final List<Channel> channels;
  final List<String> warnings;
}

class M3uParser {
  const M3uParser();

  static const int maxBytes = 25 * 1024 * 1024;
  static const int maxChannels = 100000;
  static const int maxLineLength = 64 * 1024;
  static const int maxFieldLength = 8192;
  static const int maxGuideIdLength = 512;

  M3uParseResult parse(
    Uint8List bytes, {
    required String sourceId,
    required bool allowPrivateNetwork,
  }) {
    if (bytes.isEmpty) {
      throw const PlaylistFormatException('The playlist is empty.');
    }
    if (bytes.length > maxBytes) {
      throw const PlaylistFormatException(
        'The playlist exceeds the 25 MiB limit.',
      );
    }

    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.contains('\u0000')) {
      throw const PlaylistFormatException('The playlist contains binary data.');
    }

    final lines = const LineSplitter().convert(text);
    final channels = <Channel>[];
    final warnings = <String>[];
    _PendingChannel? pending;
    String? pendingGroup;
    final pendingHeaders = <String, String>{};

    for (var index = 0; index < lines.length; index++) {
      final rawLine = lines[index];
      if (rawLine.length > maxLineLength) {
        throw PlaylistFormatException('Line ${index + 1} exceeds 64 KiB.');
      }

      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        pending = _parseExtInf(line.substring(8), index + 1);
        pendingGroup = null;
        pendingHeaders.clear();
        continue;
      }
      if (line.startsWith('#EXTGRP:')) {
        pendingGroup = _bounded(line.substring(8).trim());
        continue;
      }
      if (line.startsWith('#EXTVLCOPT:') || line.startsWith('#KODIPROP:')) {
        _parseHeaderDirective(line, pendingHeaders);
        continue;
      }
      if (line.startsWith('#')) continue;

      final parsed = Uri.tryParse(line);
      if (parsed == null ||
          (parsed.scheme != 'http' && parsed.scheme != 'https')) {
        warnings.add('Skipped line ${index + 1}: unsupported stream address.');
        pending = null;
        pendingGroup = null;
        pendingHeaders.clear();
        continue;
      }
      try {
        const NetworkPolicy().validateHttpUriShape(parsed);
      } on NetworkPolicyException {
        warnings.add('Skipped line ${index + 1}: invalid stream address.');
        pending = null;
        pendingGroup = null;
        pendingHeaders.clear();
        continue;
      }

      final name = _bounded(
        pending?.name.trim().isNotEmpty == true
            ? pending!.name.trim()
            : parsed.host,
      );
      final group = _boundedOrNull(
        pending?.attributes['group-title'] ?? pendingGroup,
      );
      final logo = _safeLogoUri(pending?.attributes['tvg-logo']);
      final digest = sha256.convert(
        utf8.encode('$sourceId\u0000${parsed.toString()}\u0000$name'),
      );
      channels.add(
        Channel(
          id: digest.toString(),
          name: name,
          streamUri: parsed,
          sourceId: sourceId,
          allowsPrivateNetwork: allowPrivateNetwork,
          guideId: _guideId(pending?.attributes['tvg-id']),
          group: group,
          logoUri: logo,
          httpHeaders: Map<String, String>.from(pendingHeaders),
        ),
      );

      if (channels.length >= maxChannels) {
        warnings.add('Stopped after the first $maxChannels channels.');
        break;
      }
      pending = null;
      pendingGroup = null;
      pendingHeaders.clear();
    }

    if (channels.isEmpty) {
      throw const PlaylistFormatException(
        'No playable HTTP or HTTPS channels were found.',
      );
    }
    return M3uParseResult(
      channels: List.unmodifiable(channels),
      warnings: List.unmodifiable(warnings),
    );
  }

  _PendingChannel _parseExtInf(String value, int lineNumber) {
    var quote = false;
    var comma = -1;
    for (var index = 0; index < value.length; index++) {
      final character = value[index];
      if (character == '"') quote = !quote;
      if (character == ',' && !quote) {
        comma = index;
        break;
      }
    }
    if (comma < 0) {
      throw PlaylistFormatException(
        'Malformed EXTINF entry on line $lineNumber.',
      );
    }

    final metadata = value.substring(0, comma);
    final attributes = <String, String>{};
    final attributePattern = RegExp(r'''([A-Za-z0-9_-]+)\s*=\s*"([^"]*)"''');
    for (final match in attributePattern.allMatches(metadata)) {
      final key = match.group(1)!.toLowerCase();
      attributes[key] = _bounded(match.group(2)!);
    }
    return _PendingChannel(
      name: _bounded(value.substring(comma + 1).trim()),
      attributes: attributes,
    );
  }

  void _parseHeaderDirective(String line, Map<String, String> headers) {
    final separator = line.indexOf(':');
    if (separator < 0) return;
    final value = line.substring(separator + 1);
    final equals = value.indexOf('=');
    if (equals < 1) return;

    final rawName = value.substring(0, equals).trim().toLowerCase();
    final headerName = switch (rawName) {
      'http-user-agent' || 'user-agent' => 'User-Agent',
      'http-referrer' || 'http-referer' || 'referer' => 'Referer',
      'http-origin' || 'origin' => 'Origin',
      _ => null,
    };
    if (headerName == null) return;
    final headerValue = value.substring(equals + 1).trim();
    if (headerValue.contains('\r') || headerValue.contains('\n')) return;
    headers[headerName] = _bounded(headerValue);
  }

  Uri? _safeLogoUri(String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    try {
      const NetworkPolicy().validateHttpUriShape(uri);
      return uri;
    } on NetworkPolicyException {
      return null;
    }
  }

  String _bounded(String value) => value.length <= maxFieldLength
      ? value
      : value.substring(0, maxFieldLength);

  String? _boundedOrNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _bounded(value.trim());
  }

  String? _guideId(String? value) {
    final normalized = value?.trim();
    return normalized != null &&
            normalized.isNotEmpty &&
            normalized.length <= maxGuideIdLength
        ? normalized
        : null;
  }
}

class _PendingChannel {
  const _PendingChannel({required this.name, required this.attributes});

  final String name;
  final Map<String, String> attributes;
}
