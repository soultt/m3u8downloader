import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8_down/app/services/m3u8_parser.dart';

void main() {
  group('M3U8Parser', () {
    late M3U8Parser parser;

    setUp(() {
      parser = M3U8Parser();
    });

    test('解析普通播放列表', () {
      const content = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:10.0,
segment0.ts
#EXTINF:10.0,
segment1.ts
#EXT-X-ENDLIST
''';

      final result = parser.parse(content, baseUrl: 'https://example.com/playlist.m3u8');

      expect(result.isMaster, isFalse);
      expect(result.segments.length, equals(2));
      expect(result.segments[0].url, equals('https://example.com/segment0.ts'));
      expect(result.segments[1].url, equals('https://example.com/segment1.ts'));
      expect(result.segments[0].seq, equals(0));
      expect(result.segments[1].seq, equals(1));
    });

    test('解析带加密的播放列表', () {
      const content = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x12345678901234567890123456789012
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
segment0.ts
#EXT-X-ENDLIST
''';

      final result = parser.parse(content, baseUrl: 'https://example.com/playlist.m3u8');

      expect(result.keyMethod, equals('AES-128'));
      expect(result.keyUri, equals('https://example.com/key.bin'));
      expect(result.keyIv, equals('12345678901234567890123456789012'));
      expect(result.segments[0].keyMethod, equals('AES-128'));
      expect(result.segments[0].keyUri, equals('https://example.com/key.bin'));
      expect(result.segments[0].keyIv, equals('12345678901234567890123456789012'));
    });

    test('解析 Master Playlist', () {
      const content = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720
high.m3u8
''';

      final result = parser.parse(content, baseUrl: 'https://example.com/master.m3u8');

      expect(result.isMaster, isTrue);
      expect(result.subPlaylists, isNotNull);
      expect(result.subPlaylists!.length, equals(2));
    });

    test('解析相对路径', () {
      const content = '''
#EXTM3U
#EXTINF:10.0,
segment0.ts
''';

      final result = parser.parse(content, baseUrl: 'https://example.com/path/playlist.m3u8');

      expect(result.segments[0].url, equals('https://example.com/path/segment0.ts'));
    });

    test('解析 data URI key', () {
      const content = '''
#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="data:application/octet-stream;base64,ABCDEFGH"
#EXTINF:10.0,
segment0.ts
''';

      final result = parser.parse(content, baseUrl: 'https://example.com/playlist.m3u8');

      expect(result.keyMethod, equals('AES-128'));
      expect(result.keyUri!.startsWith('data:'), isTrue);
    });

    test('解析 METHOD=NONE', () {
      const content = '''
#EXTM3U
#EXT-X-KEY:METHOD=NONE
#EXTINF:10.0,
segment0.ts
''';

      final result = parser.parse(content, baseUrl: 'https://example.com/playlist.m3u8');

      expect(result.keyMethod, equals('NONE'));
      expect(result.keyUri, isNull);
    });

    test('非 M3U8 内容应抛出异常', () {
      expect(
        () => parser.parse('not a playlist\nsome content'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('不是有效的 M3U8'))),
      );
    });

    test('空内容应抛出异常', () {
      expect(
        () => parser.parse(''),
        throwsA(isA<Exception>()),
      );
    });
  });
}
