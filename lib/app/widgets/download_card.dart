import 'package:flutter/material.dart';
import 'package:m3u8_down/app/models/download_task.dart';
import 'package:m3u8_down/app/models/merge_job.dart';

class DownloadCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onDelete;
  final VoidCallback? onOpenDir;   // 打开工作目录（含分片+MP4）
  final VoidCallback? onOpenSegs;  // 仅打开分片 ts 子目录
  final VoidCallback? onOpenMp4;
  /// 关联的合并任务（可为 null，下载完成后由 DownloadPage 传入）
  final MergeJob? mergeJob;

  const DownloadCard({
    super.key,
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onDelete,
    this.onOpenDir,
    this.onOpenSegs,
    this.onOpenMp4,
    this.mergeJob,
  });

  @override
  Widget build(BuildContext context) {
    final canPause = task.status == DownloadStatus.downloading || task.status == DownloadStatus.parsing;
    final canResume = task.status == DownloadStatus.paused || task.status == DownloadStatus.error;
    final isCompleted = task.status == DownloadStatus.completed;
    final hasMp4 = task.mp4File != null && task.mp4File!.isNotEmpty;

    // 内嵌合并状态（无关联 job 时显示合并区）
    final isMerging = mergeJob != null && mergeJob!.status == MergeStatus.merging;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：名称、状态、操作按钮
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(status: task.status),
                const SizedBox(width: 8),
                if (hasMp4)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '已合并',
                      style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // URL 显示
            Text(
              task.url,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            
            const SizedBox(height: 8),
            
            // 工作目录
            Text(
              '分片目录: ${task.workDir}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            
            if (hasMp4) ...[
              const SizedBox(height: 4),
              Text(
                'MP4: ${task.mp4File}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            
            const SizedBox(height: 10),
            
            // 进度条
            LinearProgressIndicator(
              value: task.progress.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFEEF0F4),
              valueColor: AlwaysStoppedAnimation<Color>(
                task.status == DownloadStatus.error
                    ? Colors.red
                    : (task.status == DownloadStatus.completed ? Colors.green : const Color(0xFF3B82F6)),
              ),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            
            const SizedBox(height: 6),
            
            // 进度详情
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${task.done} / ${task.total} 分片  ·  ${(task.progress * 100).toStringAsFixed(1)}%'
                  '${task.speed > 0 ? '  ·  ${_formatSpeed(task.speed)}/s' : ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                if (task.autoMerge)
                  const Text(
                    '完成后自动合并',
                    style: TextStyle(fontSize: 11, color: Colors.blue),
                  )
                else if (isCompleted)
                  const Text(
                    '可手动合并生成 MP4',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
            
            if (task.message != null && task.message!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                task.message!,
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ],

            // ── 内嵌合并进度区（下载完成后自动显示）──
            if (isMerging || isCompleted) ...[
              const SizedBox(height: 10),
              _MergeSection(mergeJob: mergeJob, hasMp4: hasMp4),
            ],
            
            const SizedBox(height: 10),
            
            // 操作按钮
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 暂停
                if (canPause)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.pause, size: 18),
                    label: const Text('暂停'),
                    onPressed: onPause,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                  ),
                
                // 继续
                if (canResume)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('继续'),
                    onPressed: onResume,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green),
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                  ),
                
                // 重新校验并合并
                if (isCompleted && !hasMp4)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('校验并合并'),
                    onPressed: onResume,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                  ),
                
                // 打开 MP4
                if (hasMp4)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.video_file, size: 18),
                    label: const Text('打开 MP4'),
                    onPressed: onOpenMp4,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.purple,
                      side: const BorderSide(color: Colors.purple),
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                  ),
                
                // 打开目录（优先打开 segs 分片子目录）
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('目录'),
                  onPressed: onOpenSegs ?? onOpenDir,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    side: const BorderSide(color: Colors.grey),
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
                
                // 删除
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('删除'),
                  onPressed: onDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / 1024 / 1024).toStringAsFixed(2)} MB/s';
  }
}

/// 内嵌在 DownloadCard 中的合并进度区块
class _MergeSection extends StatelessWidget {
  final MergeJob? mergeJob;
  final bool hasMp4;

  const _MergeSection({this.mergeJob, required this.hasMp4});

  @override
  Widget build(BuildContext context) {
    if (mergeJob == null) return const SizedBox.shrink();

    final status = mergeJob!.status;
    final isMerging = status == MergeStatus.merging;
    final isError = status == MergeStatus.error;
    final isCanceled = status == MergeStatus.canceled;

    // 颜色语义：蓝色=进行中，绿色=成功，红色=失败，灰色=已取消
    final Color barColor = isMerging ? Colors.blue : (isError || isCanceled ? Colors.red : Colors.green);
    final String statusLabel = switch (status) {
      MergeStatus.merging  => '合并中',
      MergeStatus.completed => '合并完成',
      MergeStatus.error     => '合并失败',
      MergeStatus.canceled  => '已取消',
      MergeStatus.running   => '准备中',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(thickness: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.merge_type, size: 14, color: barColor),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: TextStyle(fontSize: 11, color: barColor, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${(mergeJob!.percent * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        LinearProgressIndicator(
          value: mergeJob!.percent.clamp(0.0, 1.0),
          backgroundColor: const Color(0xFFEEF0F4),
          valueColor: AlwaysStoppedAnimation<Color>(barColor),
          minHeight: 5,
          borderRadius: BorderRadius.circular(3),
        ),
        if (mergeJob!.message.isNotEmpty && !isMerging) ...[
          const SizedBox(height: 4),
          Text(
            mergeJob!.message,
            style: const TextStyle(fontSize: 10, color: Colors.red),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final DownloadStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case DownloadStatus.parsing:
        bgColor = const Color(0xFFEDE9FE);
        textColor = const Color(0xFF5B21B6);
        label = '解析中';
        break;
      case DownloadStatus.downloading:
        bgColor = const Color(0xFFDBEAFE);
        textColor = const Color(0xFF1E40AF);
        label = '下载中';
        break;
      case DownloadStatus.paused:
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF92400E);
        label = '已暂停';
        break;
      case DownloadStatus.completed:
        bgColor = const Color(0xFFDCFCE7);
        textColor = const Color(0xFF166534);
        label = '已完成';
        break;
      case DownloadStatus.error:
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF991B1B);
        label = '失败';
        break;
      case DownloadStatus.removed:
        bgColor = Colors.grey[200]!;
        textColor = Colors.grey[700]!;
        label = '已移除';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: textColor,
          
        ),
      ),
    );
  }
}