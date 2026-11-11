import 'package:hive/hive.dart';
part 'download_task.g.dart';

enum DownloadStatus {
  parsing('解析中'),
  downloading('下载中'),
  paused('已暂停'),
  completed('已完成'),
  error('失败'),
  removed('已移除');

  final String label;
  const DownloadStatus(this.label);
}

@HiveType(typeId: 1)
class DownloadTask extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String url;

  @HiveField(3)
  DownloadStatus status;

  @HiveField(4)
  int total;

  @HiveField(5)
  int done;

  @HiveField(6)
  double progress;

  @HiveField(7)
  String workDir;

  @HiveField(8)
  String? mp4File;

  @HiveField(9)
  bool autoMerge;

  @HiveField(10)
  int concurrency;

  @HiveField(11)
  double speed;

  @HiveField(12)
  String? outputDir;

  @HiveField(13)
  String? outputName;

  @HiveField(14)
  String? message;

  @HiveField(15)
  int failed;

  @HiveField(16)
  DateTime createdAt;

  DownloadTask({
    required this.id,
    required this.name,
    required this.url,
    this.status = DownloadStatus.parsing,
    this.total = 0,
    this.done = 0,
    this.progress = 0.0,
    required this.workDir,
    this.mp4File,
    this.autoMerge = true,
    this.concurrency = 8,
    this.speed = 0.0,
    this.outputDir,
    this.outputName,
    this.message,
    this.failed = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        status: DownloadStatus.values[json['status'] as int],
        total: json['total'] as int,
        done: json['done'] as int,
        progress: json['progress'] as double,
        workDir: json['workDir'] as String,
        mp4File: json['mp4File'] as String?,
        autoMerge: json['autoMerge'] as bool? ?? true,
        concurrency: json['concurrency'] as int? ?? 8,
        speed: json['speed'] as double? ?? 0.0,
        outputDir: json['outputDir'] as String?,
        outputName: json['outputName'] as String?,
        message: json['message'] as String?,
        failed: json['failed'] as int? ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'url': url,
        'status': status.index,
        'total': total,
        'done': done,
        'progress': progress,
        'workDir': workDir,
        'mp4File': mp4File,
        'autoMerge': autoMerge,
        'concurrency': concurrency,
        'speed': speed,
        'outputDir': outputDir,
        'outputName': outputName,
        'message': message,
        'failed': failed,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };
}