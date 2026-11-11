import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import '../services/merger_service.dart';
import '../services/settings_service.dart';
import '../models/merge_job.dart';

/// 待合并的一批 TS 文件
class MergeBatch {
  final String id;
  final String mode; // 'dir' | 'files'
  final List<String> files;
  final String label;
  String state; // 'pending' | 'merging' | 'done' | 'error'
  double percent;
  String? message;
  String? outputPath;

  MergeBatch({
    required this.id,
    required this.mode,
    required this.files,
    required this.label,
    this.state = 'pending',
    this.percent = 0.0,
    this.message,
    this.outputPath,
  });
}

class MergePage extends StatefulWidget {
  const MergePage({super.key});

  @override
  State<MergePage> createState() => _MergePageState();
}

class _MergePageState extends State<MergePage> {
  final List<MergeBatch> _batches = [];

  // 不再使用 _currentIndex 进行串行追踪，而是让每个批次独立管理状态

  // ── 添加批次（任何时候都可调用）──
  Future<void> _addDirectory() async {
    final dir = await FilePickerPlatform.instance.getDirectoryPath(
      dialogTitle: '选择包含 TS 分片的目录',
    );
    if (dir == null) return;
    final files = <String>[];
    try {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.ts')) files.add(f.path);
      }
    } catch (_) {}
    files.sort();
    if (!mounted || files.isEmpty) return;
    setState(() {
      _batches.add(MergeBatch(
        id: 'batch_${DateTime.now().millisecondsSinceEpoch}',
        mode: 'dir',
        files: files,
        label: '${files.length} 个 TS · ${dir.split('/').last}',
      ));
    });
    // 不再自动启动下一个，由用户控制
  }

  Future<void> _addFiles() async {
    final files = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ts'],
    );
    if (files.isEmpty) return;
    final paths = files.map((f) => f.path!).toList();
    if (!mounted || paths.isEmpty) return;
    setState(() {
      _batches.add(MergeBatch(
        id: 'batch_${DateTime.now().millisecondsSinceEpoch}',
        mode: 'files',
        files: paths,
        label: '${paths.length} 个文件 · ${paths.take(2).map((p) => p.split('/').last).join(', ')}${paths.length > 2 ? '…' : ''}',
      ));
    });
    // 不再自动启动下一个，由用户控制
  }

  Future<void> _removeBatch(int idx) async {
    // 可以移除 pending 态的批次，或是不再处理中的批次
    // (移除进行中的批次会中断合并，这里保留原防护逻辑的宽松版本)
    final b = _batches[idx];
    if (b.state == 'merging') {
      // 进行中的批次询问确认
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认移除'),
          content: const Text('进行中的合并将被中断，确认要移除吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('移除')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _batches.removeAt(idx));
  }

  void _clearAll() {
    // 只清除 pending 态的批次，进行中的和已完成/错误的保留
    setState(() {
      _batches.removeWhere((b) => b.state == 'pending');
    });
  }

  /// 跨平台打开路径（文件或目录）
  Future<void> _openPath(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', path], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isAndroid || Platform.isIOS) {
        final file = File(path);
        if (await file.exists()) {
          final result = await OpenFilex.open(path);
          if (result.type != ResultType.done) {
            final uri = Uri.file(path);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            } else {
              throw Exception('无法打开文件: ${result.message}');
            }
          }
        } else {
          final uri = Uri.directory(path);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          } else {
            throw Exception('目录不存在或无法打开');
          }
        }
      } else {
        await Process.run('xdg-open', [path]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败: $e')),
        );
      }
    }
  }

  // ── 打开输出目录 ──
  Future<void> _openOutputDir(String path) async {
    final dir = Directory(path).parent.path;
    await _openPath(dir);
  }

  // ── 播放视频 ──
  Future<void> _playVideo(String path) async {
    await _openPath(path);
  }

  // ── 启动合并（批次索引）──
  /// 启动指定批次的合并。多个批次可同时合并。
  Future<void> _startMerge(int idx) async {
    final b = _batches[idx];
    if (b.state != 'pending') return; // 只能开始 pending 态的批次

    setState(() {
      b.state = 'merging';
      b.percent = 0.0;
      b.message = '合并中…';
    });

    try {
      final settings = context.read<SettingsService>().settings;
      // 优先使用设置中的合并输出目录，其次用保存目录，最后用系统临时目录
      final outputBase = settings.outputDir.isNotEmpty
          ? settings.outputDir
          : (settings.saveDir.isNotEmpty ? settings.saveDir : Directory.systemTemp.path);
      // 确保输出目录存在（读取 service 先于 await，避免跨 async gap 使用 context）
      final service = context.read<MergeService>();
      await Directory(outputBase).create(recursive: true);
      final doneCount = _batches.where((x) => x.state == 'done').length;
      final num = doneCount + 1;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '$outputBase/merged_${num}_$ts.mp4';

      await service.mergeTsFiles(
        tsFiles: b.files,
        outputPath: outputPath,
        job: MergeJob(
          id: b.id,
          taskId: '',
          name: b.label.split('·').first.trim(),
          workDir: '',
          output: outputPath,
          status: MergeStatus.merging,
        ),
        onProgress: (p) {
          if (!mounted) return;
          setState(() => b.percent = p);
        },
        onComplete: () {
          if (!mounted) return;
          setState(() {
            b.state = 'done';
            b.percent = 1.0;
            b.message = outputPath.split('/').last;
            b.outputPath = outputPath;
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            b.state = 'error';
            b.message = e.toString();
            b.percent = 0.0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('合并失败：$e'), backgroundColor: Colors.red.shade700),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        b.state = 'error';
        b.message = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('合并异常：$e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  int get _pendingCount => _batches.where((x) => x.state == 'pending').length;
  int get _mergingCount => _batches.where((x) => x.state == 'merging').length;
  int get _doneCount => _batches.where((x) => x.state == 'done').length;
  int get _errCount => _batches.where((x) => x.state == 'error').length;

  @override
  Widget build(BuildContext context) {
    // 只要没有批次正在合并，就认为是空闲状态
    final isIdle = _batches.every((b) => b.state != 'merging');
    return Scaffold(
      appBar: AppBar(
        title: isIdle
            ? const Text('TS 合并')
            : Text('合并中 $_mergingCount'),
        centerTitle: true,
        actions: [
          if (_batches.any((b) => b.state == 'pending') && isIdle)
            TextButton(
              onPressed: _clearAll,
              child: const Text('清空已选'),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth > 600 ? 24.0 : 12.0;
            return Column(
              children: [
                // ── 顶部操作栏（始终可用）──
                Container(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
                  color: Colors.grey.shade50,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(fontSize: 12),
                            children: [
                              if (_doneCount > 0)
                                TextSpan(text: '✓$_doneCount ', style: const TextStyle(color: Colors.green)),
                              if (_errCount > 0)
                                TextSpan(text: '✗$_errCount ', style: const TextStyle(color: Colors.red)),
                              if (_pendingCount > 0)
                                TextSpan(text: '待合$_pendingCount', style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('目录'),
                        onPressed: _addDirectory,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.attach_file, size: 16),
                        label: const Text('文件'),
                        onPressed: _addFiles,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── 批次列表 ──
                Expanded(
                  child: _batches.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.video_library,
                                  size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text('选择目录或文件加入合并队列',
                                  style: TextStyle(color: Colors.grey.shade500)),
                              const SizedBox(height: 4),
                              Text('可同时多次选择，统一按序合并',
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12),
                          itemCount: _batches.length,
                          itemBuilder: (context, idx) {
                            final b = _batches[idx];
                            final isErr = b.state == 'error';
                            final isDone = b.state == 'done';
                            final isMerging = b.state == 'merging';
                            // 判断是否为活跃状态（合并中）
                            final active = isMerging;
                            return Card(
                              elevation: active ? 3 : 0.5,
                              color: active
                                  ? Colors.blue.shade50
                                  : isErr
                                      ? Colors.red.shade50
                                      : isDone
                                          ? Colors.green.shade50
                                          : null,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    // 状态圆圈
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: active
                                          ? Colors.blue
                                          : isErr
                                              ? Colors.red
                                              : isDone
                                                  ? Colors.green
                                                  : Colors.grey.shade200,
                                      child: active
                                          ? const SizedBox(
                                              width: 14, height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : Icon(
                                              isErr ? Icons.error_outline : isDone ? Icons.check_circle : Icons.folder,
                                              size: 18,
                                              color: active ? Colors.white : isErr ? Colors.red : isDone ? Colors.green : Colors.grey,
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    // 标签
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            b.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w500),
                                          ),
                                          if (b.message != null)
                                            Text(
                                              b.message!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isErr ? Colors.red.shade700
                                                    : active ? Colors.blue.shade700
                                                    : Colors.grey,
                                              ),
                                            ),
                                          if (isMerging || isDone) ...[
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: LinearProgressIndicator(
                                                    value: b.percent,
                                                    minHeight: 4,
                                                    borderRadius: BorderRadius.circular(2),
                                                    backgroundColor: active ? Colors.blue.shade100 : Colors.green.shade100,
                                                    valueColor: AlwaysStoppedAnimation<Color>(
                                                      active ? Colors.blue : Colors.green,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${(b.percent * 100).toStringAsFixed(0)}%',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // 动作按钮
                                    // 显示已完成任务的操作按钮
                                    if (isDone && b.outputPath != null) ...[
                                      IconButton(
                                        icon: const Icon(Icons.folder_open, size: 20),
                                        tooltip: '打开目录',
                                        color: Colors.grey.shade700,
                                        onPressed: () => _openOutputDir(b.outputPath!),
                                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                        padding: const EdgeInsets.all(12),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.play_arrow, size: 20),
                                        tooltip: '播放视频',
                                        color: Colors.blue.shade700,
                                        onPressed: () => _playVideo(b.outputPath!),
                                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                        padding: const EdgeInsets.all(12),
                                      ),
                                    ] else if (isMerging) ...[
                                      // 合并中时显示进度和取消按钮
                                      IconButton(
                                        icon: const Icon(Icons.stop, size: 20),
                                        tooltip: '取消合并',
                                        color: Colors.red.shade700,
                                        onPressed: () async {
                                          final service = context.read<MergeService>();
                                          await service.cancelJob(b.id);
                                          if (!mounted) return;
                                          setState(() {
                                            b.state = 'error';
                                            b.message = '已取消';
                                            b.percent = 0.0;
                                          });
                                        },
                                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                        padding: const EdgeInsets.all(12),
                                      ),
                                    ] else if (b.state == 'pending') ...[
                                      // 待合并时显示开始按钮
                                      IconButton(
                                        icon: const Icon(Icons.play_circle_filled, size: 22),
                                        tooltip: '开始合并',
                                        color: Colors.green.shade700,
                                        onPressed: () => _startMerge(idx),
                                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                        padding: const EdgeInsets.all(12),
                                      ),
                                    ],
                                    // 删除（合并中不可删，需确认）
                                    if (!isMerging)
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        tooltip: '移除',
                                        color: Colors.grey.shade400,
                                        onPressed: () => _removeBatch(idx),
                                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                        padding: const EdgeInsets.all(12),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}