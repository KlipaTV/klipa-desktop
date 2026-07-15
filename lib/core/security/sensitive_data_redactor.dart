class SensitiveDataRedactor {
  const SensitiveDataRedactor();

  static const String replacement = '<redacted>';

  String uri(Uri value) {
    if (!value.hasAuthority) {
      return '${value.scheme}:$replacement';
    }

    final hasPath = value.path.isNotEmpty && value.path != '/';
    final authority = value.replace(
      userInfo: value.userInfo.isEmpty ? '' : replacement,
      path: '',
      query: null,
      fragment: null,
    );
    return '${authority.origin}${hasPath ? '/$replacement' : ''}'
        '${value.query.isEmpty ? '' : '?$replacement'}'
        '${value.fragment.isEmpty ? '' : '#$replacement'}';
  }

  String text(String value) {
    final urls = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);
    final fields = RegExp(
      r'(authorization|cookie|token|password|username)\s*[:=]\s*[^\s,;]+',
      caseSensitive: false,
    );
    final credentials = RegExp(
      r'(https?://)([^\s/@:]+):([^\s/@]+)@',
      caseSensitive: false,
    );
    return value
        .replaceAllMapped(urls, (match) {
          final value = Uri.tryParse(match.group(0)!);
          return value == null ? replacement : uri(value);
        })
        .replaceAllMapped(fields, (match) => '${match.group(1)}=$replacement')
        .replaceAllMapped(
          credentials,
          (match) => '${match.group(1)}$replacement@',
        );
  }
}
