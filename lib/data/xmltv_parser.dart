import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:xml/xml_events.dart';

import '../domain/programme.dart';

class XmltvFormatException implements Exception {
  const XmltvFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class XmltvParseResult {
  const XmltvParseResult({
    required this.programmes,
    required this.skippedEntries,
    required this.outsideWindowEntries,
    required this.truncated,
  });

  final List<Programme> programmes;
  final int skippedEntries;
  final int outsideWindowEntries;
  final bool truncated;
}

class XmltvParser {
  const XmltvParser({
    this.compressedByteLimit = maxCompressedBytes,
    this.decompressedByteLimit = maxDecompressedBytes,
    this.programmeLimit = maxProgrammes,
  }) : assert(compressedByteLimit > 0),
       assert(compressedByteLimit <= maxCompressedBytes),
       assert(decompressedByteLimit > 0),
       assert(decompressedByteLimit <= maxDecompressedBytes),
       assert(programmeLimit > 0),
       assert(programmeLimit <= maxProgrammes);

  static const int maxCompressedBytes = 32 * 1024 * 1024;
  static const int maxDecompressedBytes = 256 * 1024 * 1024;
  static const int maxProgrammes = 500000;
  static const int maxFieldLength = 8192;
  static const int maxGuideIdLength = 512;
  static const int maxDepth = 32;

  final int compressedByteLimit;
  final int decompressedByteLimit;
  final int programmeLimit;

  Future<XmltvParseResult> parseInBackground(
    Uint8List bytes, {
    required String sourceId,
    required DateTime nowUtc,
  }) => Isolate.run(() => parse(bytes, sourceId: sourceId, nowUtc: nowUtc));

  XmltvParseResult parse(
    Uint8List bytes, {
    required String sourceId,
    required DateTime nowUtc,
  }) {
    if (bytes.isEmpty) {
      throw const XmltvFormatException('The XMLTV guide is empty.');
    }
    if (sourceId.isEmpty || sourceId.length > maxFieldLength) {
      throw const XmltvFormatException('The XMLTV source identity is invalid.');
    }
    final decodedBytes = _decodeBytes(bytes);
    final String input;
    try {
      input = utf8.decode(decodedBytes, allowMalformed: false);
    } on FormatException {
      throw const XmltvFormatException('The XMLTV guide is not valid UTF-8.');
    }
    if (input.contains('\u0000')) {
      throw const XmltvFormatException('The XMLTV guide contains binary data.');
    }
    if (RegExp(
      r'<!\s*(?:DOCTYPE|ENTITY)\b',
      caseSensitive: false,
    ).hasMatch(input)) {
      throw const XmltvFormatException(
        'XMLTV DTD and entity declarations are not supported.',
      );
    }

    final windowStart = nowUtc.toUtc().subtract(const Duration(hours: 12));
    final windowEnd = nowUtc.toUtc().add(const Duration(days: 7));
    final programmes = <Programme>[];
    var skipped = 0;
    var outsideWindow = 0;
    var truncated = false;
    var depth = 0;
    var programmeDepth = 0;
    var captureDepth = 0;
    String? captureName;
    StringBuffer? capture;
    _PendingProgramme? pending;

    void finishElement(String name) {
      if (captureDepth == depth && captureName == name) {
        final value = capture.toString().trim();
        if (pending != null && !pending!.invalid && value.isNotEmpty) {
          if (name == 'title') {
            pending!.title = value;
          } else if (name == 'desc') {
            pending!.description = value;
          }
        }
        captureDepth = 0;
        captureName = null;
        capture = null;
      }
      if (programmeDepth == depth && name == 'programme') {
        final current = pending;
        if (current == null || !current.isValid) {
          skipped++;
        } else if (!current.endUtc!.isAfter(windowStart) ||
            !current.startUtc!.isBefore(windowEnd)) {
          outsideWindow++;
        } else if (programmes.length >= programmeLimit) {
          truncated = true;
        } else {
          programmes.add(
            Programme(
              sourceId: sourceId,
              guideId: current.guideId!,
              title: current.title!,
              startUtc: current.startUtc!,
              endUtc: current.endUtc!,
              description: current.description,
            ),
          );
        }
        pending = null;
        programmeDepth = 0;
      }
    }

    void captureText(String value) {
      if (capture != null && pending != null && !pending!.invalid) {
        if (capture!.length + value.length > maxFieldLength) {
          pending!.invalid = true;
          capture = null;
          captureName = null;
          captureDepth = 0;
        } else {
          capture!.write(value);
        }
      }
    }

    try {
      for (final event in parseEvents(
        input,
        validateDocument: true,
        validateNesting: true,
      )) {
        switch (event) {
          case XmlDoctypeEvent():
            throw const XmltvFormatException(
              'XMLTV DTD and entity declarations are not supported.',
            );
          case XmlStartElementEvent():
            depth++;
            if (depth > maxDepth) {
              throw const XmltvFormatException(
                'The XMLTV guide exceeds the nesting limit.',
              );
            }
            if (event.name == 'programme') {
              if (pending != null) {
                throw const XmltvFormatException(
                  'The XMLTV guide contains nested programme entries.',
                );
              }
              pending = _PendingProgramme(
                guideId: _attribute(event, 'channel'),
                startUtc: _parseTimestamp(_attribute(event, 'start')),
                endUtc: _parseTimestamp(_attribute(event, 'stop')),
              );
              programmeDepth = depth;
            } else if (pending != null &&
                depth == programmeDepth + 1 &&
                (event.name == 'title' || event.name == 'desc')) {
              captureDepth = depth;
              captureName = event.name;
              capture = StringBuffer();
            }
            if (event.isSelfClosing) {
              finishElement(event.name);
              depth--;
            }
          case XmlTextEvent():
            captureText(event.value);
          case XmlCDATAEvent():
            captureText(event.value);
          case XmlEndElementEvent():
            finishElement(event.name);
            depth--;
            if (depth < 0) {
              throw const XmltvFormatException(
                'The XMLTV guide contains invalid element nesting.',
              );
            }
          default:
            break;
        }
        if (truncated) break;
      }
    } on XmltvFormatException {
      rethrow;
    } on Object {
      throw const XmltvFormatException('The XMLTV guide is malformed.');
    }
    if (!truncated && (depth != 0 || pending != null)) {
      throw const XmltvFormatException('The XMLTV guide is malformed.');
    }

    programmes.sort((left, right) {
      final byGuide = left.guideId.compareTo(right.guideId);
      return byGuide != 0 ? byGuide : left.startUtc.compareTo(right.startUtc);
    });
    return XmltvParseResult(
      programmes: List.unmodifiable(programmes),
      skippedEntries: skipped,
      outsideWindowEntries: outsideWindow,
      truncated: truncated,
    );
  }

  Uint8List _decodeBytes(Uint8List bytes) {
    final gzipEncoded =
        bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
    if (!gzipEncoded) {
      if (bytes.length > decompressedByteLimit) {
        throw const XmltvFormatException(
          'The XMLTV guide exceeds the 256 MiB limit.',
        );
      }
      return bytes;
    }
    if (bytes.length > compressedByteLimit) {
      throw const XmltvFormatException(
        'The compressed XMLTV guide exceeds the 32 MiB limit.',
      );
    }
    final sink = _BoundedByteSink(decompressedByteLimit);
    try {
      final decoder = gzip.decoder.startChunkedConversion(sink);
      decoder
        ..add(bytes)
        ..close();
      return sink.bytes;
    } on XmltvFormatException {
      rethrow;
    } on Object {
      throw const XmltvFormatException(
        'The compressed XMLTV guide is invalid.',
      );
    }
  }

  static String? _attribute(XmlStartElementEvent event, String name) {
    for (final attribute in event.attributes) {
      if (attribute.name == name) {
        final value = attribute.value.trim();
        return value.isNotEmpty && value.length <= maxFieldLength
            ? value
            : null;
      }
    }
    return null;
  }

  static DateTime? _parseTimestamp(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?(\d{2})?\s*(Z|[+-]\d{4})?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4) ?? '0');
    final minute = int.parse(match.group(5) ?? '0');
    final second = int.parse(match.group(6) ?? '0');
    final local = DateTime.utc(year, month, day, hour, minute, second);
    if (local.year != year ||
        local.month != month ||
        local.day != day ||
        local.hour != hour ||
        local.minute != minute ||
        local.second != second) {
      return null;
    }
    // XMLTV allows omitting the zone; without provider zone information an
    // absent zone is read as UTC.
    final zone = match.group(7);
    if (zone == null || zone == 'Z') return local;
    final sign = zone.startsWith('-') ? -1 : 1;
    final offsetHours = int.parse(zone.substring(1, 3));
    final offsetMinutes = int.parse(zone.substring(3, 5));
    if (offsetHours > 23 || offsetMinutes > 59) return null;
    final offset = Duration(hours: offsetHours, minutes: offsetMinutes);
    return sign > 0 ? local.subtract(offset) : local.add(offset);
  }
}

class _PendingProgramme {
  _PendingProgramme({
    required this.guideId,
    required this.startUtc,
    required this.endUtc,
  });

  final String? guideId;
  final DateTime? startUtc;
  final DateTime? endUtc;
  String? title;
  String? description;
  var invalid = false;

  bool get isValid =>
      !invalid &&
      guideId != null &&
      guideId!.length <= XmltvParser.maxGuideIdLength &&
      title != null &&
      startUtc != null &&
      endUtc != null &&
      endUtc!.isAfter(startUtc!);
}

class _BoundedByteSink extends ByteConversionSinkBase {
  _BoundedByteSink(this.limit);

  final int limit;
  final _builder = BytesBuilder(copy: false);
  var _length = 0;

  Uint8List get bytes => _builder.takeBytes();

  @override
  void add(List<int> chunk) {
    _length += chunk.length;
    if (_length > limit) {
      throw const XmltvFormatException(
        'The decompressed XMLTV guide exceeds the 256 MiB limit.',
      );
    }
    _builder.add(chunk);
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    add(chunk.sublist(start, end));
    if (isLast) close();
  }

  @override
  void close() {}
}
