import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import '../services/download_manager.dart';
import '../services/merger_service.dart';
import '../models/download_task.dart';
import '../models/merge_job.dart';
import '../widgets/download_card.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 服务已在 main.dart 中初始化
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _showAddTaskDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增下载任务'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'M3U8 链接',
                hintText: 'https://example.com/video.m3u8',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '任务名称 (可选)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => _addTask(context),
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Future<void> _addTask(BuildContext context) async {
    final url = _urlController.text.trim();
    final name = _nameController.text.trim();
    
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 M3U8 链接')),
      );
      return;
    }

    try {
      final downloadManager = Provider.of<DownloadManager>(context, listen: false);
      await downloadManager.addTask(url: url, name: name);
      
      if (!mounted) return;
      
      Navigator.pop(context);
      _urlController.clear();
      _nameController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('任务已添加')),
      );
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadManager = Provider.of<DownloadManager>(context);
    // 同时监听 MergeService，合并进度变化时自动刷新下载卡片
    final mergeService = context.watch<MergeService>();

    /// 按 taskId 查找关联的合并任务（最新的一条），未找到返回 null
    MergeJob? _findMergeJob(String taskId) {
      try {
        return mergeService.getAllJobs().firstWhere(
          (j) => j.taskId == taskId,
        );
      } catch (_) {
        return null;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('M3U8Down'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {},
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding = constraints.maxWidth > 600 ? 24.0 : 16.0;
                    return ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
                      itemCount: downloadManager.tasks.length,
                      itemBuilder: (context, index) {
                        final task = downloadManager.tasks[index];
                        final mergeJob = _findMergeJob(task.id);
                        return DownloadCard(
                          task: task,
                          onPause: () => downloadManager.pauseTask(task.id),
                          onResume: () => downloadManager.resumeTask(task.id),
                          onDelete: () => downloadManager.removeTask(task.id),
                          onOpenDir: () => _openDirectory(task.workDir),
                          onOpenSegs: () => _openDirectory(task.workDir),
                          onOpenMp4: task.mp4File != null && task.mp4File!.isNotEmpty
                              ? () => _openMp4(task)
                              : null,
                          mergeJob: mergeJob,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于 M3U8Down'),
        scrollable: true,
        content: const Text(
          'M3U8Down - 视频下载与合并工具\n\n'
          '功能：\n'
          '• M3U8 视频下载\n'
          '• TS 分片合并\n'
          '• 多线程并发\n'
          '• 断点续传',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 跨平台打开目录
  Future<void> _openDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('目录不存在: $path')),
      );
      return;
    }
    await _openPath(path);
  }

  Future<void> _openMp4(DownloadTask task) async {
    final mp4File = task.mp4File;
    if (mp4File == null || mp4File.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MP4 文件不存在')),
      );
      return;
    }
    final file = File(mp4File);
    if (await file.exists()) {
      await _openPath(mp4File);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件不存在: $mp4File')),
      );
    }
  }

  /// 跨平台打开文件/目录
  Future<void> _openPath(String path) async {
    try {
      if (Platform.isWindows) {
        // Windows: 使用 cmd start
        await Process.run('cmd', ['/c', 'start', '', path], runInShell: true);
      } else if (Platform.isMacOS) {
        // macOS: 使用 open
        await Process.run('open', [path]);
      } else if (Platform.isAndroid || Platform.isIOS) {
        // Android/iOS: 使用 open_filex 打开文件，或 url_launcher 打开目录
        final file = File(path);
        if (await file.exists()) {
          final result = await OpenFilex.open(path);
          if (result.type != ResultType.done) {
            // 尝试用 url_launcher 打开目录
            final uri = Uri.file(path);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            } else {
              throw Exception('无法打开文件: ${result.message}');
            }
          }
        } else {
          // 目录尝试用 url_launcher
          final uri = Uri.directory(path);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          } else {
            throw Exception('目录不存在或无法打开');
          }
        }
      } else {
        // Linux/其他: 使用 xdg-open
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
}