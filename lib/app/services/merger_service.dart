import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/merge_job.dart';

// 诊断日志文件（release 下 debugPrint 不可见，写入文件）
final _diagLog = File('${Directory.systemTemp.path}/m3u8_merge_diag.txt');
void _log(String msg) => _diagLog.writeAsStringSync('[$DateTime] $msg\n', mode: FileMode.append);

/// Merge Service - 使用系统 FFmpeg 进行 TS 文件合并
class MergeService with ChangeNotifier {
  static const String _boxName = 'merge_jobs';
  
  final Map<String, MergeJob> _jobs = {};
  String _customFfmpegPath = '';
  
  /// 正在运行的 ffmpeg 进程，用于取消操作
  final Map<String, Process> _runningProcesses = {};
  
  /// Hive box 引用（复用避免重复打开）
  late Box<MergeJob> _box;

  /// 初始化 Hive box 并恢复任务状态
  Future<void> init() async {
    _box = await Hive.openBox<MergeJob>(_boxName);
    for (final job in _box.values) {
      _jobs[job.id] = job;
    }
    notifyListeners();
  }

  /// 设置自定义 FFmpeg 路径
  void setCustomFfmpegPath(String path) {
    _customFfmpegPath = path;
    notifyListeners();
  }

  /// 清除自定义 FFmpeg 路径（使用内置）
  void clearCustomFfmpegPath() {
    _customFfmpegPath = '';
    notifyListeners();
  }

  /// 获取可用的 FFmpeg 路径
  String getFfmpegPath() {
    if (_customFfmpegPath.isNotEmpty) {
      return _customFfmpegPath;
    }
    return 'ffmpeg'; // 系统 PATH 或 ffmpeg_kit_flutter 内置
  }

  /// 检测 FFmpeg 是否可用
  Future<bool> checkFfmpegAvailable() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      if (result.exitCode == 0) return true;
    } catch (_) {}
    return false;
  }

  /// 获取实际可用的 ffmpeg 可执行路径
  Future<String> _resolveFfmpegPath() async {
    // 尝试系统 PATH (Windows)
    if (Platform.isWindows) {
      try {
        final whereResult = await Process.run('where.exe', ['ffmpeg']);
        if (whereResult.exitCode == 0) {
          final path = whereResult.stdout.toString().trim().split('\n').first.trim();
          if (path.isNotEmpty) return path;
        }
      } catch (_) {}
    }
    // Unix-like: 使用 which
    try {
      final whichResult = await Process.run('which', ['ffmpeg']);
      if (whichResult.exitCode == 0) {
        final path = whichResult.stdout.toString().trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}
    return 'ffmpeg';
  }

  /// 执行 TS 文件合并（先探测每个分片参数，根据实际差异选择策略）
  Future<void> mergeTsFiles({
    required List<String> tsFiles,
    required String outputPath,
    required MergeJob job,
    ProgressCallback? onProgress,
    VoidCallback? onComplete,
    void Function(String error)? onError,
    String? ffmpegPath,
  }) async {
    // 1. 验证输入文件
    final validFiles = _validateTsFiles(tsFiles);
    if (validFiles.isEmpty) {
      onError?.call('没有有效的 TS 文件');
      return;
    }
    _log('=== 开始合并 ${validFiles.length} 个分片 ===');

    // 2. 创建 concat 列表文件
    final listFile = '${outputPath}_concat.txt';
    try {
      await _createConcatList(validFiles, listFile);
    } catch (e) {
      onError?.call('创建 concat 列表失败: $e');
      return;
    }

    // 3. 更新任务状态
    job.status = MergeStatus.merging;
    job.total = tsFiles.length;
    _jobs[job.id] = job;
    await _persistJob(job);
    notifyListeners();

    // 4. 探测第一个分片的完整参数作为基准
    final bin = ffmpegPath?.isNotEmpty == true ? ffmpegPath! : await _resolveFfmpegPath();
    final baseline = await _probeStreamParams(validFiles.first, bin);
    _log('🔍 merge: baseline=${baseline['width']}x${baseline['height']} fps=${baseline['r_frame_rate']} codec=${baseline['codec_name']}');

    // 5. 检测各分片帧率和分辨率一致性
    final frameRates = await _probeFrameRates(validFiles, bin);
    final targetFps = _pickTargetFps(frameRates);
    final frameRatesConsistent = _allSameFrameRate(frameRates);
    final resolutionsConsistent = await _allSameResolution(validFiles, bin);
    final hasAudio = await _hasAudioStream(bin, validFiles);
    _log('🔍 merge: fpsConsistent=$frameRatesConsistent resConsistent=$resolutionsConsistent hasAudio=$hasAudio targetFps=$targetFps');

    // 6. 全部分片完全一致 → copy 模式（无损、极速）
    // 不一致 → 重编码模式（尊重原始分辨率和帧率，按需适配）
    final needsReencode = !(frameRatesConsistent && resolutionsConsistent);
    _log('🔍 merge: needsReencode=$needsReencode');

    await _mergeTsFilesViaProcess(
      tsFiles: validFiles,
      outputPath: outputPath,
      job: job,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
      ffmpegPath: bin,
      baseline: baseline,
      targetFps: targetFps,
      needsReencode: needsReencode,
      hasAudio: hasAudio,
    );
  }

  /// 通过 Process.start 直接调用系统 ffmpeg（支持进度、取消）
  /// 全部分片参数一致 → copy 模式（无损极速）；不一致 → 重编码（尊重原始参数）
  Future<void> _mergeTsFilesViaProcess({
    required List<String> tsFiles,
    required String outputPath,
    required MergeJob job,
    ProgressCallback? onProgress,
    VoidCallback? onComplete,
    void Function(String error)? onError,
    required String ffmpegPath,
    required Map<String, dynamic> baseline,
    required double targetFps,
    required bool needsReencode,
    required bool hasAudio,
  }) async {
    final listFile = '${outputPath}_concat.txt';

    // 路径安全校验
    if (!outputPath.contains('.') || outputPath == '/' || outputPath == '\\') {
      onError?.call('无效的输出路径: $outputPath');
      return;
    }

    final bin = ffmpegPath;
    final w = baseline['width'] as int? ?? 0;
    final h = baseline['height'] as int? ?? 0;
    final wEven = (w % 2 == 0) ? w : w + 1;
    final hEven = (h % 2 == 0) ? h : h + 1;
    final fpsStr = targetFps.toStringAsPrecision(5).replaceAll(RegExp(r'\.?0+$'), '');
    _log('🔍 mergeProc: w=$w h=$h wEven=$wEven hEven=$hEven fpsStr=$fpsStr needsReencode=$needsReencode');

    String? lastFfmpegError;

    try {
      if (!needsReencode) {
        // ═══ Copy 模式：所有分片参数完全一致，直接拼接，无损极速 ═══
        // -c copy 不重编码；-fflags +genpts 确保输出 PTS 连续
        final audioArgs = hasAudio ? ['-c:a', 'copy'] : ['-an'];
        await _runFfmpegProcess(
          bin: bin,
          args: [
            '-y', '-hide_banner', '-loglevel', 'info', '-stats', '-progress', 'pipe:1',
            '-f', 'concat', '-safe', '0',
            '-i', listFile,
            '-fflags', '+genpts', // 重新生成连续 PTS，修复 HLS 分片时间戳跳变
            '-movflags', '+faststart',
            '-c:v', 'copy', // 视频无损复制
            ...audioArgs,
            outputPath,
          ],
          job: job,
          onProgress: onProgress,
          onComplete: onComplete,
          onError: onError,
          onLastError: (e) => lastFfmpegError = e,
        );
        if (job.status != MergeStatus.completed && job.status != MergeStatus.canceled) {
          _log('🔍 copy failed, falling back to re-encode');
          // copy 失败，自动降级到重编码
          await _reencodeMerge(
            bin: bin,
            listFile: listFile,
            validFiles: tsFiles,
            outputPath: outputPath,
            job: job,
            onProgress: onProgress,
            onComplete: onComplete,
            onError: onError,
            fpsStr: fpsStr,
            wEven: wEven,
            hEven: hEven,
            hasAudio: hasAudio,
            onLastError: (e) => lastFfmpegError = e,
          );
        }
      } else {
        _log('🔍 primary re-encode path selected');
        // ═══ 重编码模式：参数不一致，按需处理 ═══
        await _reencodeMerge(
          bin: bin,
          listFile: listFile,
          validFiles: tsFiles,
          outputPath: outputPath,
          job: job,
          onProgress: onProgress,
          onComplete: onComplete,
          onError: onError,
          fpsStr: fpsStr,
          wEven: wEven,
          hEven: hEven,
          hasAudio: hasAudio,
          onLastError: (e) => lastFfmpegError = e,
        );
      }
    } catch (e) {
      await _cleanup(listFile);
      _runningProcesses.remove(job.id);
      if (job.status == MergeStatus.canceled) return;
      lastFfmpegError ??= e.toString();
    }

    // 所有策略都失败
    if (job.status != MergeStatus.completed && job.status != MergeStatus.canceled) {
      final errMsg = lastFfmpegError?.trim() ?? 'FFmpeg 合并失败，请检查输入文件是否完整';
      job.status = MergeStatus.error;
      job.message = errMsg;
      await _persistJob(job);
      notifyListeners();
      onError?.call(errMsg);
    }
  }

  /// 执行 FFmpeg 进程并监听进度/错误
  Future<void> _runFfmpegProcess({
    required String bin,
    required List<String> args,
    required MergeJob job,
    ProgressCallback? onProgress,
    VoidCallback? onComplete,
    void Function(String error)? onError,
    required void Function(String error) onLastError,
  }) async {
    final listFile = args.where((a) => a.endsWith('_concat.txt')).isEmpty
        ? ''
        : args.firstWhere((a) => a.contains('_concat.txt'), orElse: () => '');
    Process? process;
    try {
      process = await Process.start(bin, args);
      _runningProcesses[job.id] = process;

      final stdoutSub = process.stdout.transform(utf8.decoder).listen((data) {
        _parseProgress(data, job, onProgress);
      });
      final stderrSub = process.stderr.transform(utf8.decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.toLowerCase().contains('error') ||
              line.startsWith('[error') || line.startsWith('Error')) {
            onLastError(line.trim());
          }
        }
      });

      final exitCode = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();
      if (listFile.isNotEmpty) await _cleanup(listFile);
      _runningProcesses.remove(job.id);

      if (job.status == MergeStatus.canceled) return;
      if (exitCode == 0 && await File(args.last).exists()) {
        _log('🔍 FFmpeg exitCode=0 output exists');
        // 探测输出文件的实际分辨率，记录到日志
        try {
          final outProbeBin = bin.contains('ffmpeg') ? '${Directory(bin).parent.path}${Platform.pathSeparator}ffprobe.exe' : 'ffprobe';
          final pr = await Process.run(outProbeBin, ['-v', 'quiet', '-select_streams', 'v:0',
            '-show_entries', 'stream=width,height,r_frame_rate,codec_name', '-of', 'csv=p=0', args.last]);
          _log('🔍 output probe: ${pr.stdout.trim()}');
        } catch (_) {}
        job.status = MergeStatus.completed;
        job.percent = 1.0;
        await _updateMergeJobOutput(job.id, args.last);
        onProgress?.call(1.0);
        onComplete?.call();
      }
    } catch (e) {
      _log('🔍 FFmpeg exception: $e');
      if (process != null) _runningProcesses.remove(job.id);
      onLastError(e.toString());
    }
  }

  /// 重编码合并：使用 setpts+scale 滤镜处理 PTS 归零和分辨率对齐
  Future<void> _reencodeMerge({
    required String bin,
    required String listFile,
    required List<String> validFiles,
    required String outputPath,
    required MergeJob job,
    ProgressCallback? onProgress,
    VoidCallback? onComplete,
    void Function(String error)? onError,
    required String fpsStr,
    required int wEven,
    required int hEven,
    required bool hasAudio,
    required void Function(String error) onLastError,
  }) async {
    // 只有探测到有效分辨率时才应用 scale/pad；否则仅做 PTS 归零，保持原始分辨率
    final hasValidResolution = wEven > 0 && hEven > 0;
    const baseFilter = 'setpts=PTS-STARTPTS';
    final videoFilter = hasValidResolution
        ? '$baseFilter,scale=$wEven:$hEven:force_original_aspect_ratio=decrease,pad=$wEven:$hEven:(ow-iw)/2:(oh-ih)/2'
        : baseFilter;
    _log('🔍 reencode: hasValidResolution=$hasValidResolution filter=$videoFilter');
    final filterParts = <String>[];
    if (hasAudio) {
      filterParts.add("[0:v]$videoFilter[v];[0:a]aresample=async=1000:first_pts=0[a]");
    } else {
      filterParts.add("[0:v]$videoFilter[v]");
    }
    final filterComplex = filterParts.join(';');
    final args = <String>[
      '-y', '-hide_banner', '-loglevel', 'info', '-stats', '-progress', 'pipe:1',
      '-f', 'concat', '-safe', '0',
      '-i', listFile,
      '-filter_complex', filterComplex,
      '-map', '[v]', if (hasAudio) '-map', '[a]',
      '-c:v', 'libx264',
      '-preset', 'veryfast',
      '-crf', '18',
      '-pix_fmt', 'yuv420p',
      '-r', fpsStr,
      '-movflags', '+faststart',
      if (hasAudio) ...[
        '-c:a', 'aac',
        '-b:a', '128k',
        '-ar', '44100',
        '-ac', '2',
      ] else '-an',
      outputPath,
    ];
    await _runFfmpegProcess(
      bin: bin,
      args: args,
      job: job,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
      onLastError: onLastError,
    );
  }

  /// 解析 ffmpeg 进度输出
  void _parseProgress(String output, MergeJob job, ProgressCallback? onProgress) {
    // ffmpeg -progress pipe:1 输出格式：
    // out_time=00:00:01.234567
    // out_time_ms=1234567
    // progress=continue
    final lines = output.split('\n');
    int? outTimeMs;
    for (final line in lines) {
      if (line.startsWith('out_time_ms=')) {
        outTimeMs = int.tryParse(line.substring('out_time_ms='.length));
      }
    }
    if (outTimeMs != null && outTimeMs > 0) {
      // 估算：基于已处理时间 / 总文件数（concat copy 模式每文件约 0.05s）
      final estimatedFilesProcessed = (outTimeMs / 50).ceil();
      final totalFiles = job.total > 0 ? job.total : 1;
      final progress = (estimatedFilesProcessed / totalFiles).clamp(0.0, 0.99);
      if (progress != job.percent) {
        job.percent = progress;
        onProgress?.call(progress);
      }
    }
  }

  /// 取消合并任务（杀掉 ffmpeg 进程）
  Future<void> cancelJob(String jobId) async {
    final job = _jobs[jobId];
    if (job == null) return;

    // 标记为取消，阻止后续 ffmpeg 退出回调覆盖状态
    job.status = MergeStatus.canceled;
    _jobs[jobId] = job;
    await _persistJob(job);

    // 杀掉正在运行的进程
    final process = _runningProcesses.remove(jobId);
    if (process != null) {
      try {
        process.kill();
      } catch (_) {}
    }

    notifyListeners();
  }

  /// 保存合并任务
  Future<void> _persistJob(MergeJob job) async {
    await _box.put(job.id, job);
  }

  /// 更新合并任务输出路径
  Future<void> _updateMergeJobOutput(String jobId, String outputPath) async {
    final job = _jobs[jobId];
    if (job != null) {
      job.output = outputPath;
      await _persistJob(job);
    }
  }

  /// 获取所有任务
  List<MergeJob> getAllJobs() => _jobs.values.toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  /// 获取任务
  MergeJob? getJob(String id) => _jobs[id];

  /// 验证 TS 文件
  List<String> _validateTsFiles(List<String> files) {
    return files.where((file) {
      final f = File(file);
      if (!f.existsSync()) return false;
      
      // 检查文件大小 (TS 包至少 188 字节)
      try {
        if (f.lengthSync() < 188) return false;
      } catch (_) {
        return false;
      }
      
      return true;
    }).toList();
  }

  /// 创建 concat 列表文件
  Future<void> _createConcatList(List<String> files, String listFile) async {
    final buffer = StringBuffer();
    for (final file in files) {
      // 使用平台路径分隔符
      final absolutePath = File(file).absolute.path;
      // FFmpeg concat demuxer 要求路径用单引号包裹，单引号本身需转义为 '\'' 
      // 即：将 ' 替换为 '\''，然后整体用单引号包裹
      final escapedPath = absolutePath
          .replaceAll(Platform.pathSeparator, '/')
          .replaceAll("'", r"'\''");
      buffer.writeln("file '$escapedPath'");
    }
    await File(listFile).writeAsString(buffer.toString(), encoding: utf8);
  }

  /// 清理临时文件
  Future<void> _cleanup(String listFile) async {
    try {
      final file = File(listFile);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// 检测单个文件的帧率（通过 ffprobe）
  Future<double?> _probeFrameRate(String filePath, String ffmpegBin) async {
    // 先尝试直接找 ffprobe，如果和 ffmpeg 在同一目录就用同一路径前缀替换后缀
    String ffprobeBin;
    if (ffmpegBin == 'ffmpeg' || !ffmpegBin.contains('\\') && !ffmpegBin.contains('/')) {
      // 仅名字，尝试系统 PATH 中的 ffprobe
      ffprobeBin = 'ffprobe';
    } else {
      // 完整路径：例如 C:\bin\ffmpeg.exe → C:\bin\ffprobe.exe
      final dir = Directory(ffmpegBin).parent.path;
      final base = ffmpegBin.split(Platform.pathSeparator).last;
      ffprobeBin = '$dir${Platform.pathSeparator}${base.replaceAll('ffmpeg', 'ffprobe')}';
      // 如果没有 ffprobe 但目录里有，直接用
      if (!File(ffprobeBin).existsSync()) {
        ffprobeBin = ffmpegBin; // fallback: 用 ffmpeg 自身也能 probe
      }
    }
    try {
      final result = await Process.run(ffprobeBin, [
        '-v', 'error',
        '-select_streams', 'v:0',
        '-show_entries', 'stream=r_frame_rate',
        '-of', 'csv=p=0',
        filePath,
      ]);
      if (result.exitCode == 0) {
        // 取第一非空行，避免重复行干扰（某些 ffprobe 版本会输出多行）
        String output = '';
        for (final l in result.stdout.toString().split('\n')) {
          if (l.trim().isNotEmpty) {
            output = l.trim();
            break;
          }
        }
        if (output.isNotEmpty && output != 'N/A') {
          if (output.contains('/')) {
            final parts = output.split('/');
            final num = double.tryParse(parts[0]);
            final den = double.tryParse(parts[1]);
            if (num != null && den != null && den > 0) return num / den;
          }
          return double.tryParse(output);
        }
      }
    } catch (_) {}
    return null;
  }

  /// 检测所有分片的帧率
  Future<List<double?>> _probeFrameRates(List<String> files, String ffmpegBin) async {
    final results = <double?>[];
    for (final f in files) {
      results.add(await _probeFrameRate(f, ffmpegBin));
    }
    return results;
  }

  /// 选择目标帧率：取众数（出现最多的帧率），没有则用 30
  double _pickTargetFps(List<double?> frameRates) {
    final valid = frameRates.where((r) => r != null).toList();
    if (valid.isEmpty) return 30.0;
    
    // 统计每个帧率出现的次数
    final counts = <double, int>{};
    for (final r in valid) {
      final rounded = double.parse(r!.toStringAsFixed(1));
      counts[rounded] = (counts[rounded] ?? 0) + 1;
    }
    
    // 返回出现次数最多的帧率
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.key;
  }

  /// 判断所有分片帧率是否一致（容差 ±0.5 fps）
  bool _allSameFrameRate(List<double?> frameRates) {
    final valid = frameRates.where((r) => r != null).toList();
    if (valid.isEmpty) return false;
    final first = valid.first;
    return valid.every((r) => (r! - first!).abs() < 0.5);
  }

  /// 检测文件列表是否包含音频流（用于决定重编码策略）
  Future<bool> _hasAudioStream(String ffmpegBin, List<String> files) async {
    try {
      final result = await Process.run(ffmpegBin, [
        '-v', 'error',
        '-select_streams', 'a:0',
        '-show_entries', 'stream=codec_type',
        '-of', 'csv=p=0',
        files.first,
      ]);
      if (result.exitCode == 0) {
        // 取第一非空行，避免重复行干扰
        final line = result.stdout
            .toString()
            .split('\n')
            .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        return line.trim() == 'audio';
      }
    } catch (_) {}
    return false;
  }

  /// 探测单个 TS 分片的关键参数（分辨率、帧率、编码器）
  /// 返回 Map：{width, height, r_frame_rate, codec_name}
  Future<Map<String, dynamic>> _probeStreamParams(String filePath, String ffmpegBin) async {
    // 尝试 ffprobe，失败则用 ffmpeg 自身
    String probeBin;
    if (ffmpegBin == 'ffmpeg' || !ffmpegBin.contains('\\') && !ffmpegBin.contains('/')) {
      probeBin = 'ffprobe';
    } else {
      final dir = Directory(ffmpegBin).parent.path;
      final base = ffmpegBin.split(Platform.pathSeparator).last;
      probeBin = '$dir${Platform.pathSeparator}${base.replaceAll('ffmpeg', 'ffprobe')}';
      if (!File(probeBin).existsSync()) probeBin = ffmpegBin;
    }
    try {
      // ffprobe -of csv=p=0 输出顺序固定为：codec_name,width,height,pix_fmt,r_frame_rate
      // （与 -show_entries 参数中的字段顺序无关）
      final result = await Process.run(probeBin, [
        '-v', 'quiet',
        '-select_streams', 'v:0',
        '-show_entries', 'stream=codec_name,width,height,r_frame_rate,pix_fmt',
        '-of', 'csv=p=0',
        filePath,
      ]);
      if (result.exitCode == 0) {
        // 取第一非空行，避免某些版本输出了重复行导致解析出错
        final line = result.stdout
            .toString()
            .split('\n')
            .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        // 格式：codec_name,width,height,pix_fmt,r_frame_rate (5列)
        final parts = line.split(',');
        if (parts.length >= 5) {
          return {
            'width': int.tryParse(parts[1]) ?? 0,
            'height': int.tryParse(parts[2]) ?? 0,
            'r_frame_rate': parts[4],
            'codec_name': parts[0],
          };
        }
      }
    } catch (_) {}
    // 默认值：未知时保守处理（宽/高为0会触发重编码而非copy模式）
    return {'width': 0, 'height': 0, 'r_frame_rate': '', 'codec_name': ''};
  }

  /// 判断所有 TS 分片分辨率是否一致（容差：允许宽高差异 < 2px）
  Future<bool> _allSameResolution(List<String> files, String ffmpegBin) async {
    if (files.isEmpty) return false;
    try {
      final first = await _probeStreamParams(files.first, ffmpegBin);
      final fw = first['width'] as int;
      final fh = first['height'] as int;
      for (int i = 1; i < files.length; i++) {
        final p = await _probeStreamParams(files[i], ffmpegBin);
        final pw = p['width'] as int;
        final ph = p['height'] as int;
        if ((pw - fw).abs() > 2 || (ph - fh).abs() > 2) return false;
      }
      return true;
    } catch (_) {}
    return false;
  }
}

/// 合并进度回调
typedef ProgressCallback = void Function(double progress);

/// 合并结果
class MergeResult {
  final bool success;
  final String? outputPath;
  final String? error;

  MergeResult({required this.success, this.outputPath, this.error});

  factory MergeResult.success(String outputPath) => 
      MergeResult(success: true, outputPath: outputPath);

  factory MergeResult.failure(String error) => 
      MergeResult(success: false, error: error);
}