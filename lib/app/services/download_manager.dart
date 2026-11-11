import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive/hive.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';
import '../models/download_task.dart';
import '../models/merge_job.dart';
import '../models/settings.dart';
import 'm3u8_parser.dart';
import 'merger_service.dart';
import 'settings_service.dart';

const String taskBoxName = 'download_tasks';
const Duration segTimeout = Duration(seconds: 30);
const int retryLimit = 5;
const int defaultConcurrency = 8;
const int maxConcurrency = 32;

/// AES-128 密钥长度（16字节）
const int _aes128KeyLength = 16;

/// AES-128 CBC 解密器（用于 HLS 加密分片）
/// 使用 pointycastle 实现标准 AES-CBC-PKCS7 解密
class _Aes128Decryptor {
  /// 使用提供的 key 和 iv 解密数据
  static Uint8List decrypt(Uint8List data, List<int> key, List<int> iv) {
    if (key.length != _aes128KeyLength) {
      throw ArgumentError('AES-128 key 长度错误: ${key.length}, 应为 $_aes128KeyLength');
    }
    if (iv.length != _aes128KeyLength) {
      throw ArgumentError('AES-128 IV 长度错误: ${iv.length}, 应为 $_aes128KeyLength');
    }

    /// 使用 pointycastle 实现 AES-CBC-PKCS7 解密
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    // PaddedBlockCipherParameters 需要两个参数：底层加密参数和填充参数
    // 对于 PKCS7 填充，填充参数为 null
    cipher.init(
      false,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(Uint8List.fromList(key)), Uint8List.fromList(iv)),
        null,
      ),
    );

    final output = cipher.process(data);
    return Uint8List.fromList(output);
  }
}

class DownloadManager extends ChangeNotifier {
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, _DownloadControl> _controls = {};
  late Box<DownloadTask> _taskBox;
  String _downloadRoot = '';
  final SettingsService settingsService;
  MergeService? _mergeService;

  DownloadManager(this.settingsService);
  
  void setMergeService(MergeService mergeService) {
    _mergeService = mergeService;
  }

  /// 获取设置（延迟初始化）
  Future<AppSettings> _getSettings() async {
    if (!settingsService.isInitialized) {
      await settingsService.init();
    }
    return settingsService.settings;
  }

  /// 初始化：打开 Hive box，恢复任务
  Future<void> init() async {
    _taskBox = await Hive.openBox<DownloadTask>(taskBoxName);
    await _restoreTasks();
    notifyListeners();
  }

  /// 获取下载根目录
  Future<String> getDownloadRoot() async {
    if (_downloadRoot.isNotEmpty) return _downloadRoot;
    final dir = await getApplicationSupportDirectory();
    _downloadRoot = '${dir.path}/downloads';
    final d = Directory(_downloadRoot);
    if (!await d.exists()) await d.create(recursive: true);
    return _downloadRoot;
  }

  /// 获取所有任务（按创建时间倒序）
  List<DownloadTask> get tasks {
    return _tasks.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 获取单个任务
  DownloadTask? getTask(String id) => _tasks[id];

  /// 新增下载任务
  Future<DownloadTask> addTask({
    required String url,
    String name = '',
    int? concurrency,
    String? saveDir,
    bool? autoMerge,
    String? outputDir,
    String? outputName,
  }) async {
    // 从 SettingsService 获取默认设置
    final settings = await _getSettings();
    final effectiveConcurrency = (concurrency ?? settings.concurrency).clamp(1, maxConcurrency);
    final effectiveAutoMerge = autoMerge ?? settings.autoMerge;
    final effectiveSaveDir = (saveDir?.isNotEmpty ?? false) ? saveDir : (settings.saveDir.isEmpty ? null : settings.saveDir);
    
    // 验证 URL
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw Exception('请输入 M3U8 链接');
    }
    
    // 支持多种协议
    final lowerUrl = trimmedUrl.toLowerCase();
    if (!lowerUrl.startsWith('http://') && 
        !lowerUrl.startsWith('https://') &&
        !lowerUrl.startsWith('m3u8://')) {
      throw Exception('请输入合法的 http(s) m3u8 地址');
    }

    final id = _generateId();
    final rawName = (name.isEmpty ? 'video_$id' : name)
        .replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
    final safeName = rawName.length > 80 ? rawName.substring(0, 80) : rawName;
    
    final rootDir = (effectiveSaveDir?.isNotEmpty ?? false) ? effectiveSaveDir! : await getDownloadRoot();
    final root = Directory(rootDir);
    if (!await root.exists()) await root.create(recursive: true);

    String workDir = '$rootDir/${safeName}_${id.substring(0, 4)}';
    int n = 1;
    while (await Directory(workDir).exists()) {
      workDir = '$rootDir/${safeName}_${id.substring(0, 4)}_$n';
      n++;
    }
    await Directory(workDir).create(recursive: true);
    await Directory('$workDir/segs').create(recursive: true);

    final task = DownloadTask(
      id: id,
      url: trimmedUrl,
      name: safeName,
      workDir: workDir,
      concurrency: effectiveConcurrency,
      autoMerge: effectiveAutoMerge,
      outputDir: outputDir,
      outputName: outputName,
    );

    _tasks[id] = task;
    _persistTask(task);
    notifyListeners();

    // 异步开始下载，带错误边界防止静默失败
    Future.microtask(() => _runTask(task)).catchError((e, stack) {
      debugPrint('_runTask 未捕获错误: $e\n$stack');
      if (_tasks.containsKey(id)) {
        final t = _tasks[id]!;
        t.status = DownloadStatus.error;
        t.message = '任务启动异常: $e';
        _persistTask(t);
        notifyListeners();
      }
    });

    return task;
  }

  /// 暂停任务
  Future<void> pauseTask(String id) async {
    final task = _tasks[id];
    final control = _controls[id];
    if (task != null && [DownloadStatus.downloading, DownloadStatus.parsing].contains(task.status)) {
      control?.paused = true;
      // 等待在途分片完成，任务会在检查 paused 后自行退出并标记 running = false
      task.status = DownloadStatus.paused;
      task.message = '暂停中，等待在途分片完成…';
      _persistTask(task);
      notifyListeners();
    }
  }

  /// 恢复/重试任务
  Future<void> resumeTask(String id) async {
    final task = _tasks[id];
    if (task == null) return;

    final control = _controls[id];
    // 只有当控制对象存在且仍在运行时（暂停态），才解除暂停
    if (control != null && control.running && !control.canceled) {
      control.paused = false;
      task.status = DownloadStatus.downloading;
      task.message = '';
      _persistTask(task);
      notifyListeners();
    } else if ([DownloadStatus.paused, DownloadStatus.error, DownloadStatus.completed].contains(task.status)) {
      // 控制对象不存在或已停止：重新启动任务（断点续传）
      _restartTask(task);
    }
  }

  /// 重试任务（同恢复）
  Future<void> retryTask(String id) => resumeTask(id);

  /// 删除任务
  Future<void> removeTask(String id, {bool deleteFiles = false}) async {
    final task = _tasks[id];
    if (task == null) return;

    final control = _controls[id];
    if (control != null) {
      control.canceled = true;
      control.paused = true;
      if (control.signal != null) control.signal!.cancel();
      if (control.timer != null) control.timer!.cancel();
    }

    _tasks.remove(id);
    _controls.remove(id);
    await _taskBox.delete(id);

    if (deleteFiles && await Directory(task.workDir).exists()) {
      await Directory(task.workDir).delete(recursive: true);
    }

    notifyListeners();
  }

  // ==================== 私有方法 ====================

  /// 生成 12 位十六进制 ID
  String _generateId() => DateTime.now().millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0');

  /// 恢复持久化任务（不过滤目录是否存在：任务记录本身即是历史记录）
  Future<void> _restoreTasks() async {
    try {
      for (final task in _taskBox.values) {
        // 将处于下载/解析中的任务重置为暂停态，等待用户选择继续或重试
        if ([DownloadStatus.downloading, DownloadStatus.parsing].contains(task.status)) {
          task.status = DownloadStatus.paused;
          task.message = '重启后自动暂停（原进行中）';
          
          // 断点续传：扫描已下载的分片文件，恢复进度
          final segsDir = Directory('${task.workDir}/segs');
          if (await segsDir.exists()) {
            int existingCount = 0;
            try {
              await for (final entity in segsDir.list()) {
                if (entity is File && entity.path.endsWith('.ts')) {
                  // 验证文件有效性（大小 >= 188 字节且以 0x47 开头）
                  if (await entity.length() >= 188) {
                    final bytes = await entity.openRead(0, 1).first;
                    if (bytes.isNotEmpty && bytes[0] == 0x47) {
                      existingCount++;
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('扫描分片目录失败: $e');
            }
            
            if (existingCount > 0 && existingCount <= task.total) {
              task.done = existingCount;
              task.progress = task.total > 0 ? existingCount / task.total : 0.0;
              task.message = '重启后自动暂停（原进行中），已恢复 $existingCount 个分片';
            } else {
              // 扫描结果异常，重置进度
              task.done = 0;
              task.progress = 0.0;
            }
          } else {
            // 分片目录不存在，重置进度
            task.done = 0;
            task.progress = 0.0;
          }
        }
        _tasks[task.id] = task;
      }
    } catch (e) {
      debugPrint('_restoreTasks error: $e');
    }
  }

  /// 重启任务（从断点继续）
  void _restartTask(DownloadTask task) {
    task.status = DownloadStatus.downloading;
    task.message = '';
    task.done = 0;
    task.progress = 0.0;
    notifyListeners();
    Future.microtask(() => _runTask(task)).catchError((e, stack) {
      debugPrint('_runTask 重启异常: $e\n$stack');
      if (_tasks.containsKey(task.id)) {
        task.status = DownloadStatus.error;
        task.message = '任务重启异常: $e';
        _persistTask(task);
        notifyListeners();
      }
    });
  }

  /// 持久化任务
  void _persistTask(DownloadTask task) {
    _taskBox.put(task.id, task);
  }

  /// 核心下载逻辑
  Future<void> _runTask(DownloadTask task) async {
    final control = _DownloadControl();
    _controls[task.id] = control;

    try {
      // 1. 解析播放列表
      task.status = DownloadStatus.parsing;
      task.message = '正在解析播放列表…';
      _persistTask(task);
      notifyListeners();

      // 使用 M3U8Parser 解析
      final parser = M3U8Parser();
      late ParsedM3U8 parsed;

      try {
        final text = await parser.fetchM3U8Text(task.url);
        parsed = parser.parse(text, baseUrl: task.url);

        // 如果是 Master Playlist，解析子列表
        if (parsed.isMaster && parsed.subPlaylists != null && parsed.subPlaylists!.isNotEmpty) {
          parsed = await parser.resolveMasterPlaylist(parsed);
        }
      } catch (e) {
        task.status = DownloadStatus.error;
        task.message = '解析失败: $e';
        _persistTask(task);
        notifyListeners();
        return;
      }

      // 检查是否解析到有效分片
      if (parsed.segments.isEmpty) {
        task.status = DownloadStatus.error;
        task.message = '未找到可下载的 TS 分片';
        _persistTask(task);
        notifyListeners();
        return;
      }

      // 2. 下载 TS 分片
      task.total = parsed.segments.length;
      // 断点续传：如果已有完成数，保持；否则从0开始
      if (task.done > task.total) task.done = 0;
      task.status = DownloadStatus.downloading;
      task.message = '开始下载 ${parsed.segments.length} 个分片…';
      _persistTask(task);
      notifyListeners();

      final segsDir = '${task.workDir}/segs';
      final dio = Dio();

      // 限制并发数
      final semaphore = Semaphore(task.concurrency);
      int completed = task.done; // 从已完成数继续
      int failed = 0;
      int totalBytesDownloaded = 0;
      final stopwatch = Stopwatch()..start();

      // 速度计算定时器：每秒更新一次速度
      Timer? speedTimer;
      void updateSpeed() {
        if (stopwatch.isRunning && stopwatch.elapsedMilliseconds > 0) {
          task.speed = totalBytesDownloaded / (stopwatch.elapsedMilliseconds / 1000);
          _persistTask(task);
          notifyListeners();
        }
      }

      speedTimer = Timer.periodic(const Duration(seconds: 1), (_) => updateSpeed());

      // 预获取密钥（如果有加密）
      List<int>? keyBytes;
      List<int>? keyIv;
      if (parsed.keyMethod?.toUpperCase() == 'AES-128' && parsed.keyUri != null) {
        try {
          final keyResp = await dio.get<List<int>>(
            parsed.keyUri!,
            options: Options(responseType: ResponseType.bytes),
          ).timeout(segTimeout);
          if (keyResp.statusCode == 200 && keyResp.data != null) {
            keyBytes = (keyResp.data as List<int>).sublist(0, 16);
          }
        } catch (e) {
          debugPrint('获取加密密钥失败: $e');
        }
        // 解析 IV：优先使用 #EXT-X-KEY 中的 IV，否则使用分片序列号
        if (parsed.keyIv != null && parsed.keyIv!.isNotEmpty) {
          final ivHex = parsed.keyIv!.replaceFirst(RegExp(r'^0x'), '');
          if (ivHex.length <= 32) {
            keyIv = Uint8List.fromList(ivHex.padLeft(32, '0')
                .split(RegExp(r'(..)')).where((s) => s.isNotEmpty)
                .map((s) => int.parse(s, radix: 16)).toList());
          }
        }
      }

      // 并发下载所有分片
      await Future.wait(
        parsed.segments.map((seg) async {
          // 将 semaphore.wait() 放入 try，确保 finally 中的 signal() 总是执行
          await semaphore.wait();
          try {
            // 在持有信号量期间检查取消/暂停，避免竞态
            if (control.canceled) {
              return;
            }
            if (control.paused) {
              // 暂停时释放信号量并返回，resume 时会重新运行 _runTask
              return;
            }

            // 二次检查（网络请求前）
            if (control.canceled || control.paused) {
              return;
            }

            final segPath = _segPath(segsDir, seg.seq);

            // 检查文件是否已下载（断点续传）
            if (await File(segPath).exists()) {
              completed++;
              task.done = completed;
              task.progress = completed / task.total;
              _persistTask(task);
              notifyListeners();
              return;
            }

            final response = await dio.get(
              seg.url,
              options: Options(
                responseType: ResponseType.bytes,
                followRedirects: true,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 30),
              ),
              onReceiveProgress: (count, total) {
                // 可以用于显示单个文件的进度
              },
            ).timeout(segTimeout);

            if (response.statusCode == 200) {
              var bytes = response.data as List<int>;
              
              // AES-128 解密（如果需要）
              if (keyBytes != null && bytes.isNotEmpty) {
                // 确定 IV：优先使用全局 IV，否则使用分片序列号作为 IV（大端序 16 字节）
                final iv = keyIv ?? _buildIvFromSeq(seg.seq);
                bytes = _Aes128Decryptor.decrypt(Uint8List.fromList(bytes), keyBytes, iv);
              }

              final file = File(segPath);
              await file.writeAsBytes(bytes);

              // 校验 TS 文件 (检查 0x47 同步字节)
              if (bytes.length >= 188 && bytes[0] == 0x47) {
                completed++;
                totalBytesDownloaded += bytes.length;
                task.done = completed;
                task.progress = completed / task.total;
                _persistTask(task);
                notifyListeners();
              } else {
                // 文件无效
                failed++;
                task.message = '分片 ${seg.seq} 下载失败: 无效TS格式';
              }
            } else {
              failed++;
              task.message = '分片 ${seg.seq} 下载失败: HTTP ${response.statusCode}';
            }
          } catch (e) {
            failed++;
            task.message = '分片 ${seg.seq} 下载失败: $e';
          } finally {
            semaphore.signal();
          }
        }),
      );

      // 3. 完成下载
      if (control.canceled) {
        task.status = DownloadStatus.removed;
        task.message = '已取消';
      } else if (control.paused) {
        // 暂停态下完成所有已下载分片
        task.status = DownloadStatus.paused;
        task.message = '已暂停，点击继续下载';
      } else if (failed > 0) {
        task.status = DownloadStatus.error;
        task.message = '下载失败，失败 $failed 个分片';
      } else {
        task.status = DownloadStatus.completed;
        task.message = '下载完成';

        // 自动合并
        if (task.autoMerge) {
          task.message = '即将合并…';
          _persistTask(task);
          notifyListeners();

          await _mergeTask(task, parsed.segments.map((s) => _segPath(segsDir, s.seq)).toList());
        }
      }

      _persistTask(task);
      notifyListeners();

    // 停止速度计算定时器并更新最终速度
      speedTimer?.cancel();
      stopwatch.stop();
      if (stopwatch.elapsedMilliseconds > 0) {
        task.speed = totalBytesDownloaded / (stopwatch.elapsedMilliseconds / 1000);
      }

    } finally {
      // 标记控制对象为已停止，防止 resume 时误判
      final control = _controls[task.id];
      control?.markStopped();
      _controls.remove(task.id);
    }
  }

  /// 合并任务（已内置 FFmpegKit → Process.run 后备逻辑，无需在此额外检查）
  Future<void> _mergeTask(DownloadTask task, List<String> tsFiles) async {
    // outputDir 为空字符串时视为未设置，回退到工作目录
    final effectiveOutputDir = (task.outputDir?.isNotEmpty ?? false) ? task.outputDir! : null;
    final outputPath = effectiveOutputDir != null
        ? '$effectiveOutputDir/${task.outputName ?? task.name}.mp4'
        : '${task.workDir}/${task.name}.mp4';

    // 路径校验：确保是合法路径且有文件扩展名
    if (!_isValidOutputPath(outputPath)) {
      task.status = DownloadStatus.error;
      task.message = '输出路径无效：$outputPath，请检查设置中的输出目录';
      _persistTask(task);
      notifyListeners();
      return;
    }

    // 确保输出目录存在
    final outputDir = Directory(outputPath).parent;
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    // 使用共享的 MergeService 实例（null guard：若未注入则报错而非静默创建孤立实例）
    if (_mergeService == null) {
      task.status = DownloadStatus.error;
      task.message = '合并服务未初始化';
      _persistTask(task);
      notifyListeners();
      return;
    }

    try {
      await _mergeService!.mergeTsFiles(
        tsFiles: tsFiles,
        outputPath: outputPath,
        job: MergeJob(
          id: 'merge_${task.id}',
          taskId: task.id,
          name: task.name,
          workDir: task.workDir,
          output: outputPath,
          status: MergeStatus.merging,
          percent: 0.0,
          total: 0,
          segIndex: 0,
          segTotal: tsFiles.length,
          segName: '合并中',
          message: '正在合并…',
        ),
        onProgress: (progress) {
          task.message = '合并进度: ${(progress * 100).toStringAsFixed(1)}%';
          _persistTask(task);
          notifyListeners();
        },
        onComplete: () {
          task.mp4File = outputPath;
          task.message = '合并完成: $outputPath';
          _persistTask(task);
          notifyListeners();
        },
        onError: (error) {
          task.status = DownloadStatus.error;
          task.message = '合并失败: $error';
          _persistTask(task);
          notifyListeners();
        },
      );
    } catch (e) {
      task.status = DownloadStatus.error;
      task.message = '合并异常: $e';
      _persistTask(task);
      notifyListeners();
    }
  }

  /// 构造分片文件路径（兼容 Windows / Unix 路径分隔符）
  static String _segPath(String segsDir, int seq) =>
      '$segsDir${Platform.pathSeparator}${seq.toString().padLeft(6, '0')}.ts';

  /// 校验输出路径是否合法（非空、有扩展名、不是根目录裸路径）
  static bool _isValidOutputPath(String path) {
    if (path.isEmpty) return false;
    // 必须包含 . 且不是纯 / 或 C: 等单字符路径
    final idx = path.lastIndexOf('.');
    if (idx < 0) return false;
    final ext = path.substring(idx + 1).toLowerCase();
    if (!['mp4', 'mkv', 'avi', 'mov', 'flv', 'wmv', 'ts'].contains(ext)) return false;
    // 跨平台校验
    if (Platform.isWindows) {
      // Windows: 必须包含盘符 (C:) 或是 UNC 路径 (\\server\share)
      if (!path.contains(':') && !path.startsWith(r'\\')) return false;
    } else {
      // Unix-like: 必须是绝对路径或相对路径，不能是裸 '/'
      if (path == '/' || path == '\\') return false;
    }
    return true;
  }

  /// 从分片序列号构建 IV（大端序 16 字节）
  /// HLS 规范：如果 #EXT-X-KEY 没有指定 IV，使用分片序列号作为 IV
  static Uint8List _buildIvFromSeq(int seq) {
    final iv = Uint8List(16);
    for (int i = 15; i >= 0; i--) {
      iv[i] = seq & 0xFF;
      seq >>= 8;
    }
    return iv;
  }
}

/// 下载控制对象
class _DownloadControl {
  bool paused = false;
  bool canceled = false;
  bool running = true;
  Timer? timer;
  CancelToken? signal = CancelToken();
  
  /// 标记任务已停止（正常完成、错误、取消、暂停）
  void markStopped() {
    running = false;
  }
}

/// 信号量类（用于控制并发）
class Semaphore {
  int _counter;
  final List<Completer<void>> _waitQueue = [];

  Semaphore(this._counter);

  Future<void> wait() async {
    if (_counter > 0) {
      _counter--;
    } else {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
    }
  }

  void signal() {
    if (_waitQueue.isEmpty) {
      _counter++;
    } else {
      // FIFO: 先等待的先被唤醒，防止饥饿
      final completer = _waitQueue.removeAt(0);
      try {
        completer.complete();
      } on StateError {
        // completer 已完成，忽略
      }
    }
  }
}