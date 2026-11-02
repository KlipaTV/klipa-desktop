// Checks the Microsoft Store listing in packaging/windows/store against the
// Partner Center field limits and Klipa's listing rules: every locale is
// complete, no "free IPTV" construction appears in any language, no em or en
// dash is used, and links point only to Klipa's own sites.
//
// Run from the repository root: dart run tool/check_store_listing.dart

import 'dart:io';

const locales = [
  'en',
  'es',
  'pt',
  'fr',
  'de',
  'it',
  'eu',
  'pl',
  'tr',
  'ar',
  'zh',
];

const limits = {
  'description.txt': 10000,
  'short_description.txt': 1000,
  'release_notes.txt': 1500,
};
const featureLimit = 200;
const maxFeatures = 20;
const searchTermLimit = 30;
const maxSearchTerms = 7;
const maxSearchWords = 21;
const shared = {
  'additional_license_terms.txt': 10000,
  'copyright.txt': 200,
  'certification_notes.txt': 2000,
};

const _free =
    r'free|gratis|gratuit\w*|kostenlos\w*|darmow\w*|bezpłatn\w*|'
    r'ücretsiz|doan|dohainik\w*|musutruk|مجان\w*|免费';
final _freeIptv = RegExp(
  '($_free)\\W{0,3}iptv|iptv\\W{0,3}($_free)',
  caseSensitive: false,
  unicode: true,
);
// U+2013 en dash and U+2014 em dash.
final _dash = RegExp('[${String.fromCharCodes(const [0x2013, 0x2014])}]');
final _url = RegExp(r'https?://\S+');
const _allowedUrls = [
  'https://github.com/KlipaTV/',
  'https://raw.githubusercontent.com/KlipaTV/',
  'https://klipa.tv/',
  'https://www.gnu.org/licenses/',
];

void main() {
  final root = Directory('packaging/windows/store');
  final problems = <String>[];

  void checkText(String where, String text) {
    if (_freeIptv.hasMatch(text)) {
      problems.add('$where: "free IPTV" construction');
    }
    if (_dash.hasMatch(text)) problems.add('$where: em or en dash');
    for (final match in _url.allMatches(text)) {
      final url = match.group(0)!;
      if (!_allowedUrls.any(url.startsWith)) {
        problems.add('$where: link outside Klipa: $url');
      }
    }
  }

  String? read(String path) {
    final file = File('${root.path}/$path');
    if (!file.existsSync()) {
      problems.add('$path: missing');
      return null;
    }
    final text = file.readAsStringSync().trim();
    if (text.isEmpty) problems.add('$path: empty');
    return text;
  }

  for (final entry in shared.entries) {
    final text = read(entry.key);
    if (text == null) continue;
    if (text.runes.length > entry.value) {
      problems.add('${entry.key}: over ${entry.value} characters');
    }
    checkText(entry.key, text);
  }

  for (final locale in locales) {
    for (final entry in limits.entries) {
      final path = 'listing/$locale/${entry.key}';
      final text = read(path);
      if (text == null) continue;
      if (text.runes.length > entry.value) {
        problems.add('$path: over ${entry.value} characters');
      }
      checkText(path, text);
    }

    final featuresPath = 'listing/$locale/features.txt';
    final features = read(featuresPath)?.split('\n') ?? const <String>[];
    if (features.length > maxFeatures) {
      problems.add('$featuresPath: more than $maxFeatures features');
    }
    for (final feature in features) {
      if (feature.trim().isEmpty) problems.add('$featuresPath: blank line');
      if (feature.runes.length > featureLimit) {
        problems.add('$featuresPath: feature over $featureLimit characters');
      }
      checkText(featuresPath, feature);
    }

    final termsPath = 'listing/$locale/search_terms.txt';
    final terms = read(termsPath)?.split('\n') ?? const <String>[];
    if (terms.length > maxSearchTerms) {
      problems.add('$termsPath: more than $maxSearchTerms terms');
    }
    var words = 0;
    for (final term in terms) {
      if (term.runes.length > searchTermLimit) {
        problems.add('$termsPath: "$term" over $searchTermLimit characters');
      }
      words += term.trim().split(RegExp(r'\s+')).length;
      checkText(termsPath, term);
    }
    if (words > maxSearchWords) {
      problems.add('$termsPath: $words words, the limit is $maxSearchWords');
    }
  }

  if (problems.isEmpty) {
    stdout.writeln('Store listing: ${locales.length} locales pass.');
    return;
  }
  problems.forEach(stderr.writeln);
  exitCode = 1;
}
