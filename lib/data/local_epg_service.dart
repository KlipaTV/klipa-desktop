import '../core/network/bounded_http_client.dart';
import '../domain/playlist_source.dart';
import '../domain/programme.dart';
import 'xmltv_parser.dart';

class EpgConfigurationException implements Exception {
  const EpgConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocalEpgRefreshResult {
  const LocalEpgRefreshResult({
    required this.programmes,
    required this.refreshedAt,
    required this.expiresAt,
    required this.skippedEntries,
    required this.outsideWindowEntries,
    required this.truncated,
  });

  final List<Programme> programmes;
  final DateTime refreshedAt;
  final DateTime expiresAt;
  final int skippedEntries;
  final int outsideWindowEntries;
  final bool truncated;
}

/// Downloads XMLTV directly from the provider selected by the user.
///
/// There is deliberately no Klipa endpoint, fallback proxy, discovery service,
/// or remote configuration path in this service.
class LocalEpgService {
  LocalEpgService({
    BoundedHttpClient? httpClient,
    XmltvParser parser = const XmltvParser(),
  }) : _httpClient = httpClient ?? BoundedHttpClient(),
       _parser = parser;

  static const Duration cacheLifetime = Duration(hours: 6);
  static const int maxCredentialLength = 1024;

  final BoundedHttpClient _httpClient;
  final XmltvParser _parser;

  Future<LocalEpgRefreshResult> refresh({
    required PlaylistSource source,
    required DateTime nowUtc,
    Uri? attachedGuideUri,
    String? username,
    String? password,
  }) async {
    final guideUri =
        attachedGuideUri ??
        _deriveXtreamGuideUri(source, username: username, password: password);
    final bytes = await _httpClient.getGuide(
      guideUri,
      allowPrivateNetwork: source.allowsPrivateNetwork,
    );
    final refreshedAt = nowUtc.toUtc();
    final parsed = await _parser.parseInBackground(
      bytes,
      sourceId: source.id,
      nowUtc: refreshedAt,
    );
    return LocalEpgRefreshResult(
      programmes: parsed.programmes,
      refreshedAt: refreshedAt,
      expiresAt: refreshedAt.add(cacheLifetime),
      skippedEntries: parsed.skippedEntries,
      outsideWindowEntries: parsed.outsideWindowEntries,
      truncated: parsed.truncated,
    );
  }

  Uri _deriveXtreamGuideUri(
    PlaylistSource source, {
    required String? username,
    required String? password,
  }) {
    if (source.kind != PlaylistSourceKind.xtream) {
      throw const EpgConfigurationException(
        'Attach an XMLTV address to this source before refreshing its guide.',
      );
    }
    _validateCredential('username', username);
    _validateCredential('password', password);
    final server = Uri.tryParse(source.location);
    if (server == null) {
      throw const EpgConfigurationException(
        'The saved provider address is invalid.',
      );
    }
    return server.replace(
      path: '/xmltv.php',
      queryParameters: {'username': username!, 'password': password!},
    );
  }

  void _validateCredential(String name, String? value) {
    if (value == null ||
        value.isEmpty ||
        value.length > maxCredentialLength ||
        value.contains('\r') ||
        value.contains('\n')) {
      throw EpgConfigurationException(
        'The saved Xtream $name is incomplete. Re-add this source.',
      );
    }
  }
}
