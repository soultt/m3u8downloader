import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../services/settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _concurrencyController = TextEditingController();
  String? _savedSaveDir;
  String? _savedOutputDir;
  String? _savedFfmpegPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsService>().settings;
      _concurrencyController.text = settings.concurrency.toString();
      _savedSaveDir = settings.saveDir;
      _savedOutputDir = settings.outputDir;
      _savedFfmpegPath = settings.ffmpegPath;
    });
  }

  @override
  void dispose() {
    _concurrencyController.dispose();
    super.dispose();
  }

  Future<void> _pickSaveDirectory() async {
    final path = await context.read<SettingsService>().pickSaveDirectory();
    if (path != null && mounted) {
      setState(() => _savedSaveDir = path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存目录已设置: $path')),
      );
    }
  }

  Future<void> _pickOutputDirectory() async {
    final path = await context.read<SettingsService>().pickOutputDirectory();
    if (path != null && mounted) {
      setState(() => _savedOutputDir = path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('输出目录已设置: $path')),
      );
    }
  }

  Future<void> _pickFFmpegPath() async {
    final path = await context.read<SettingsService>().pickFFmpegPath();
    if (path != null && mounted) {
      setState(() => _savedFfmpegPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('FFmpeg 路径已设置: $path')),
      );
    }
  }

  Future<void> _saveConcurrency() async {
    final value = int.tryParse(_concurrencyController.text.trim());
    if (value != null && value >= 1 && value <= 32) {
      await context.read<SettingsService>().setConcurrency(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('并发数已更新')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入 1-32 之间的数字')),
        );
      }
    }
  }

  Future<void> _resetSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置设置'),
        scrollable: true,
        content: const Text('确定要重置所有设置为默认值吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<SettingsService>().resetToDefaults();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final settings = context.read<SettingsService>().settings;
          _concurrencyController.text = settings.concurrency.toString();
          _savedSaveDir = settings.saveDir;
          _savedOutputDir = settings.outputDir;
          _savedFfmpegPath = settings.ffmpegPath;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('设置已重置为默认值')),
          );
        }
      });
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于 M3U8Down'),
        scrollable: true,
        content: const Text(
          'M3U8Down - 视频下载与合并工具\n\n'
          '版本: v1.0.0\n\n'
          '功能：\n'
          '• M3U8 视频下载\n'
          '• TS 分片合并 (FFmpeg)\n'
          '• 多线程并发下载\n'
          '• 断点续传\n'
          '• AES-128 解密支持\n\n'
          '技术栈: Flutter + Dio + FFmpegKit + Hive',
          style: const TextStyle(),
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

  @override
  Widget build(BuildContext context) {
    final settingsService = context.watch<SettingsService>();
    final settings = settingsService.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth > 600 ? 24.0 : 16.0;
            return ListView(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
              children: [
                // 下载目录设置
                _buildSectionHeader('下载设置'),
                _buildDirectoryTile(
                  title: '下载保存目录',
                  subtitle: (_savedSaveDir ?? settings.saveDir).isEmpty
                      ? '使用默认目录 (应用数据目录/downloads)'
                      : (_savedSaveDir ?? settings.saveDir),
                  icon: Icons.folder_outlined,
                  onTap: _pickSaveDirectory,
                ),

                // 输出目录设置
                _buildDirectoryTile(
                  title: '合并输出目录',
                  subtitle: (_savedOutputDir ?? settings.outputDir).isEmpty
                      ? '与下载目录相同'
                      : (_savedOutputDir ?? settings.outputDir),
                  icon: Icons.save_outlined,
                  onTap: _pickOutputDirectory,
                ),

                // 并发数设置
                _buildConcurrencyTile(settings),

                const SizedBox(height: 24),

                // 合并设置
                _buildSectionHeader('合并设置'),
                _buildSwitchTile(
                  title: '下载完成后自动合并',
                  subtitle: '下载完成后自动使用 FFmpeg 合并 TS 文件',
                  value: settings.autoMerge,
                  onChanged: (value) => context.read<SettingsService>().setAutoMerge(value),
                ),

                // FFmpeg 路径设置
                Consumer<SettingsService>(
                  builder: (context, settingsService, child) {
                    final ffmpegPath = _savedFfmpegPath ?? settingsService.settings.ffmpegPath;
                    return _buildDirectoryTile(
                      title: 'FFmpeg 可执行文件路径',
                      subtitle: ffmpegPath.isEmpty
                          ? '使用内置 FFmpeg (ffmpeg_kit_flutter)'
                          : ffmpegPath,
                      icon: Icons.code_outlined,
                      onTap: _pickFFmpegPath,
                      onClear: ffmpegPath.isNotEmpty
                          ? () async {
                              await settingsService.clearFFmpegPath();
                              if (mounted) {
                                setState(() => _savedFfmpegPath = null);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已恢复使用内置 FFmpeg')),
                                );
                              }
                            }
                          : null,
                    );
                  },
                ),

                const SizedBox(height: 24),

                // 高级设置
                _buildSectionHeader('高级设置'),
                _buildActionTile(
                  title: '重置所有设置',
                  subtitle: '恢复为默认配置',
                  icon: Icons.restore_outlined,
                  onTap: _resetSettings,
                  isDestructive: true,
                ),

                const SizedBox(height: 24),

                // 关于
                _buildSectionHeader('关于'),
                _buildActionTile(
                  title: '版本信息',
                  subtitle: 'M3U8Down v1.0.0',
                  icon: Icons.info_outline,
                  onTap: () => _showAboutDialog(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }

  Widget _buildDirectoryTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(title),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onClear != null)
              IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: onClear,
                tooltip: '清除路径',
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Widget _buildConcurrencyTile(AppSettings settings) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.speed_outlined, color: Theme.of(context).primaryColor),
        title: const Text('下载并发数'),
        subtitle: Text('当前: ${settings.concurrency} (范围: 1-32)'),
        trailing: SizedBox(
          width: 120,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: TextField(
                  controller: _concurrencyController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.end,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.check, size: 20),
                onPressed: _saveConcurrency,
                tooltip: '保存',
              ),
            ],
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      child: SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        value: value,
        onChanged: onChanged,
        activeThumbColor: Theme.of(context).primaryColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: isDestructive ? Colors.red : Theme.of(context).primaryColor),
        title: Text(
          title,
          style: TextStyle(color: isDestructive ? Colors.red : null),
        ),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}