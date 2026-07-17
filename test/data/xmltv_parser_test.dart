import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/xmltv_parser.dart';

void main() {
  const parser = XmltvParser();
  final now = DateTime.utc(2026, 7, 16, 10, 30);

  test('parses bounded now/next data with explicit XMLTV time zones', () {
    final result = parser.parse(
      _bytes('''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20260716120000 +0200" stop="20260716130000 +0200" channel="news.es">
    <title lang="es">Noticias</title>
    <desc>Resumen local</desc>
  </programme>
  <programme start="20260801120000 +0200" stop="20260801130000 +0200" channel="news.es">
    <title>Outside window</title>
  </programme>
  <programme start="bad" stop="20260716140000 +0200" channel="news.es">
    <title>Malformed</title>
  </programme>
</tv>'''),
      sourceId: 'source-1',
      nowUtc: now,
    );

    expect(result.programmes, hasLength(1));
    final programme = result.programmes.single;
    expect(programme.sourceId, 'source-1');
    expect(programme.guideId, 'news.es');
    expect(programme.title, 'Noticias');
    expect(programme.description, 'Resumen local');
    expect(programme.startUtc, DateTime.utc(2026, 7, 16, 10));
    expect(programme.endUtc, DateTime.utc(2026, 7, 16, 11));
    expect(result.outsideWindowEntries, 1);
    expect(result.skippedEntries, 1);
    expect(result.truncated, isFalse);
  });

  test('captures CDATA titles and descriptions', () {
    final result = parser.parse(
      _bytes('''<tv>
  <programme start="20260716100000 Z" stop="20260716110000 Z" channel="one">
    <title><![CDATA[Morning & News]]></title>
    <desc><![CDATA[First]]> and <![CDATA[second]]></desc>
  </programme>
</tv>'''),
      sourceId: 'source-1',
      nowUtc: now,
    );

    final programme = result.programmes.single;
    expect(programme.title, 'Morning & News');
    expect(programme.description, 'First and second');
  });

  test('accepts truncated timestamps and reads absent zones as UTC', () {
    final result = parser.parse(
      _bytes('''<tv>
  <programme start="20260716100000" stop="202607161130" channel="one">
    <title>No zone</title>
  </programme>
</tv>'''),
      sourceId: 'source-1',
      nowUtc: now,
    );

    final programme = result.programmes.single;
    expect(programme.startUtc, DateTime.utc(2026, 7, 16, 10));
    expect(programme.endUtc, DateTime.utc(2026, 7, 16, 11, 30));
  });

  test('applies negative timestamp offsets', () {
    final result = parser.parse(
      _bytes('''<tv>
  <programme start="20260716060000 -0500" stop="20260716070000 -0500"
      channel="one">
    <title>Morning</title>
  </programme>
</tv>'''),
      sourceId: 'source-1',
      nowUtc: now,
    );

    final programme = result.programmes.single;
    expect(programme.startUtc, DateTime.utc(2026, 7, 16, 11));
    expect(programme.endUtc, DateTime.utc(2026, 7, 16, 12));
  });

  test('skips programmes with invalid calendar dates', () {
    final result = parser.parse(
      _bytes('''<tv>
  <programme start="20260230100000 Z" stop="20260716110000 Z" channel="one">
    <title>Bad date</title>
  </programme>
</tv>'''),
      sourceId: 'source-1',
      nowUtc: now,
    );

    expect(result.programmes, isEmpty);
    expect(result.skippedEntries, 1);
  });

  test('parses gzip in a background isolate', () async {
    final compressed = Uint8List.fromList(
      gzip.encode(
        _bytes('''<tv>
  <programme start="20260716100000 Z" stop="20260716110000 Z" channel="one">
    <title>Morning</title>
  </programme>
</tv>'''),
      ),
    );

    final result = await parser.parseInBackground(
      compressed,
      sourceId: 'source-1',
      nowUtc: now,
    );

    expect(result.programmes.single.title, 'Morning');
  });

  test('rejects DTD and custom entity declarations', () {
    expect(
      () => parser.parse(
        _bytes('''<!DOCTYPE tv [<!ENTITY secret SYSTEM "file:///etc/passwd">]>
<tv><channel id="one"><display-name>&secret;</display-name></channel></tv>'''),
        sourceId: 'source-1',
        nowUtc: now,
      ),
      throwsA(
        isA<XmltvFormatException>().having(
          (error) => error.message,
          'message',
          contains('DTD'),
        ),
      ),
    );
  });

  test('bounds decompression before parsing a gzip bomb', () {
    const constrained = XmltvParser(decompressedByteLimit: 128);
    final compressed = Uint8List.fromList(
      gzip.encode(List<int>.filled(1024, 0x20)),
    );

    expect(
      () => constrained.parse(compressed, sourceId: 'source-1', nowUtc: now),
      throwsA(
        isA<XmltvFormatException>().having(
          (error) => error.message,
          'message',
          contains('decompressed'),
        ),
      ),
    );
  });

  test('truncates programmes beyond the limit and keeps the guide', () {
    const constrained = XmltvParser(programmeLimit: 1);
    const programme = '''
<programme start="20260716100000 Z" stop="20260716110000 Z" channel="one">
  <title>Morning</title>
</programme>''';

    final result = constrained.parse(
      _bytes('<tv>$programme$programme</tv>'),
      sourceId: 'source-1',
      nowUtc: now,
    );

    expect(result.programmes, hasLength(1));
    expect(result.truncated, isTrue);
  });

  test('enforces the nesting limit', () {
    final nested = List.filled(XmltvParser.maxDepth + 1, '<x>').join();
    final unnested = List.filled(XmltvParser.maxDepth + 1, '</x>').join();
    expect(
      () => parser.parse(
        _bytes('<tv>$nested$unnested</tv>'),
        sourceId: 'source-1',
        nowUtc: now,
      ),
      throwsA(
        isA<XmltvFormatException>().having(
          (error) => error.message,
          'message',
          contains('nesting'),
        ),
      ),
    );
  });
}

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));
