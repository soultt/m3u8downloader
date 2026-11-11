import 'dart:async';
import 'package:dio/dio.dart';

class ParsedM3U8 {
  final bool isMaster;
  final List<SegmentInfo> segments;
  final List<String>? subPlaylists;
  final String? keyMethod;
  final String? keyUri;
  final String? keyIv;

  ParsedM3U8({
    this.isMaster = false,
    this.segments = const [],
    this.subPlaylists,
    this.keyMethod,
    this.keyUri,
    this.keyIv,
  });
}

class SegmentInfo {
  final String url;
  final String? keyMethod;
  final String? keyUri;
  final String? keyIv;
  final int seq;

  SegmentInfo({
    required this.url,
    this.keyMethod,
    this.keyUri,
    this.keyIv,
    this.seq = 0,
  });
}

class KeyInfo {
  final String method;
  final String? uri;
  final String? iv;

  KeyInfo({
    required this.method,
    this.uri,
    this.iv,
  });
}

class M3U8Parser {
  final dio = Dio(BaseOptions(
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) M3u8Down/1.0',
      'Accept': '*/*',
    },
    followRedirects: true,
    maxRedirects: 5,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// 获取 M3U8 文本内容（支持重定向）
  Future<String> fetchM3U8Text(String url) async {
    try {
      // 使用 per-request options 避免全局 headers 被并发请求污染
      final response = await dio.get<String>(
        url,
        options: Options(
          headers: {
            'Referer': url,
            'User-Agent': dio.options.headers['User-Agent'],
            'Accept': dio.options.headers['Accept'],
          },
        ),
      );
      final text = response.data ?? '';
      
      if (text.isEmpty) {
        throw Exception('HTTP ${response.statusCode}: 返回内容为空');
      }
      
      // 检查是否返回了 HTML 错误页面而不是 M3U8
      final trimmed = text.trim();
      if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html') || trimmed.startsWith('<HTML')) {
        // 提取 HTML 中的错误信息
        String errorMsg = '服务器返回 HTML 页面而非 M3U8';
        final titleMatch = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(trimmed);
        if (titleMatch != null) {
          errorMsg += ' - ${titleMatch.group(1)}';
        }
        throw Exception('HTTP ${response.statusCode}: $errorMsg');
      }
      
      return text;
    } on DioException catch (e) {
      String errorMessage;
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
          errorMessage = '连接超时';
          break;
        case DioExceptionType.sendTimeout:
          errorMessage = '发送超时';
          break;
        case DioExceptionType.receiveTimeout:
          errorMessage = '接收超时';
          break;
        case DioExceptionType.badResponse:
          errorMessage = 'HTTP ${e.response?.statusCode}: ${e.message}';
          break;
        case DioExceptionType.cancel:
          errorMessage = '请求已取消';
          break;
        default:
          errorMessage = e.message ?? '未知错误';
          break;
      }
      throw Exception('$errorMessage ($url)');
    } catch (e) {
      throw Exception('请求失败: $e ($url)');
    }
  }

  /// 解析完整 M3U8 文本
  ParsedM3U8 parse(String text, {String baseUrl = ''}) {
    // 验证是否是有效的 M3U8 内容
    final firstLine = text.split(RegExp(r'\r?\n')).firstOrNull ?? '';
    if (!firstLine.startsWith('#EXTM3U')) {
      throw Exception('不是有效的 M3U8 格式 (首行应为 #EXTM3U，实际: "${firstLine.substring(0, firstLine.length > 50 ? 50 : firstLine.length)}")');
    }
    final lines = text.split(RegExp(r'\r?\n'));
    String? keyMethod;
    String? keyUri;
    String? keyIv;
    int seq = 0;
    final segments = <SegmentInfo>[];
    final subPlaylists = <String>[];
    bool isMaster = false;

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trim();

      if (line.isEmpty || line.startsWith('#')) {
        if (line.startsWith('#EXT-X-KEY')) {
          final key = _parseExtXKey(line, baseUrl);
          keyMethod = key?.method;
          keyUri = key?.uri;
          keyIv = key?.iv;
        } else if (line.startsWith('#EXT-X-MEDIA-SEQUENCE')) {
          final parts = line.split(':');
          seq = int.tryParse(parts[1]) ?? 0;
        } else if (line.startsWith('#EXT-X-STREAM-INF')) {
          isMaster = true;
        }
        continue;
      }

      // URI 行
      if (line.startsWith('#')) continue;

      final absUrl = _resolveUrl(line, baseUrl);
      if (line.toLowerCase().contains('.m3u8') || absUrl.toLowerCase().contains('.m3u8')) {
        subPlaylists.add(absUrl);
      } else {
        segments.add(SegmentInfo(
          url: absUrl,
          keyMethod: keyMethod,
          keyUri: keyUri,
          keyIv: keyIv,
          seq: seq,
        ));
        seq++;
      }
    }

    if (subPlaylists.isNotEmpty) {
      isMaster = true;
    }

    return ParsedM3U8(
      isMaster: isMaster,
      segments: segments,
      subPlaylists: subPlaylists.isNotEmpty ? subPlaylists : null,
      keyMethod: keyMethod,
      keyUri: keyUri,
      keyIv: keyIv,
    );
  }

  /// 解析 #EXT-X-KEY 标签
  KeyInfo? _parseExtXKey(String line, String baseUrl) {
    final methodMatch = RegExp(r'METHOD\s*=\s*("[^"]*"|[^,]+)', caseSensitive: false).firstMatch(line);
    if (methodMatch == null) return null;

    final method = methodMatch.group(1)!.replaceAll(RegExp(r'^"|"$'), '').trim().toUpperCase();
    if (method == 'NONE' || method.isEmpty) {
      return KeyInfo(method: 'NONE', uri: null, iv: null);
    }

    String? keyUri;
    final uriMatch = RegExp(r'URI\s*=\s*"([^"]*)"', caseSensitive: false).firstMatch(line);
    if (uriMatch != null && uriMatch.group(1)!.isNotEmpty) {
      final raw = uriMatch.group(1)!.trim();
      if (raw.startsWith('data:')) {
        keyUri = raw;
      } else {
        try {
          keyUri = _resolveUrl(raw, baseUrl);
        } catch (_) {
          keyUri = raw;
        }
      }
    }

    String? iv;
    final ivMatch = RegExp(r'IV\s*=\s*("[^"]*"|[^,]+)', caseSensitive: false).firstMatch(line);
    if (ivMatch != null) {
      final ivRaw = ivMatch.group(1)!.replaceAll(RegExp(r'^"|"$'), '').trim().replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
      if (ivRaw.isNotEmpty) {
        // 32位 hex 表示 16字节 IV
        iv = ivRaw.padLeft(32, '0');
      }
    }

    return KeyInfo(method: method, uri: keyUri, iv: iv);
  }

  String _resolveUrl(String relative, String baseUrl) {
    if (relative.startsWith('http://') || relative.startsWith('https://')) {
      return relative;
    }
    if (relative.startsWith('//')) {
      final base = Uri.parse(baseUrl);
      return '${base.scheme}:$relative';
    }
    if (relative.startsWith('/')) {
      final base = Uri.parse(baseUrl);
      return '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}$relative';
    }
    final base = Uri.parse(baseUrl);
    return base.resolve(relative).toString();
  }

  /// 解析 Master Playlist - 选择最高带宽的子列表
  Future<ParsedM3U8> resolveMasterPlaylist(ParsedM3U8 master, {int depth = 0}) async {
    if (depth > 3) throw Exception('播放列表嵌套过深');
    if (!master.isMaster || master.subPlaylists == null || master.subPlaylists!.isEmpty) {
      throw Exception('没有有效的子播放列表');
    }

    // 记录每个子列表的尝试结果
    final results = <String, String?>{};
    int bestIdx = 0;
    int bestBandwidth = 0;
    bool anySuccess = false;

    for (var i = 0; i < master.subPlaylists!.length; i++) {
      try {
        // 为每个子列表请求添加超时，防止单个卡住阻塞整个解析
        final text = await fetchM3U8Text(master.subPlaylists![i]).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception('请求超时 (15s)'),
        );
        final parsedSub = parse(text, baseUrl: master.subPlaylists![i]);
        
        if (parsedSub.segments.isEmpty) {
          results[master.subPlaylists![i]] = '解析为空';
          continue;
        }
        
        // 找到了有效分片，标记为成功
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(text);
        final bw = bwMatch != null ? int.parse(bwMatch.group(1)!) : 0;
        results[master.subPlaylists![i]] = '成功 (segments=${parsedSub.segments.length}, bw=$bw)';
        
        if (bw > bestBandwidth) {
          bestBandwidth = bw;
          bestIdx = i;
        }
        anySuccess = true;
      } catch (e) {
        results[master.subPlaylists![i]] = e.toString();
      }
    }

    if (!anySuccess) {
      final errorDetail = results.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      throw Exception('所有子播放列表都无法访问:\n$errorDetail\n\nURLs: ${master.subPlaylists}');
    }

    // 使用最佳可用子列表
    final selectedUrl = master.subPlaylists![bestIdx];
    final subText = await fetchM3U8Text(selectedUrl).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception('最佳子列表请求超时 (15s)'),
    );
    return parse(subText, baseUrl: selectedUrl);
  }
}