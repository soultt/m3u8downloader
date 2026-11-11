import 'package:hive/hive.dart';
part 'merge_job.g.dart';

enum MergeStatus {
  running('运行中'),
  merging('合并中'),
  completed('已完成'),
  canceled('已取消'),
  error('失败');

  final String label;
  const MergeStatus(this.label);
}

@HiveType(typeId: 2)
class MergeJob extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String taskId;

  @HiveField(2)
  String name;

  @HiveField(3)
  String workDir;

  @HiveField(4)
  String output;

  @HiveField(5)
  MergeStatus status;

  @HiveField(6)
  double percent;

  @HiveField(7)
  int total;

  @HiveField(8)
  int segIndex;

  @HiveField(9)
  int segTotal;

  @HiveField(10)
  String segName;

  @HiveField(11)
  String message;

  @HiveField(12)
  DateTime startedAt;

  MergeJob({
    required this.id,
    required this.taskId,
    required this.name,
    required this.workDir,
    required this.output,
    this.status = MergeStatus.running,
    this.percent = 0.0,
    this.total = 0,
    this.segIndex = 0,
    this.segTotal = 0,
    this.segName = '',
    this.message = '合并中',
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  factory MergeJob.fromJson(Map<String, dynamic> json) => MergeJob(
        id: json['id'] as String,
        taskId: json['taskId'] as String,
        name: json['name'] as String,
        workDir: json['workDir'] as String,
        output: json['output'] as String,
        status: MergeStatus.values[json['status'] as int],
        percent: json['percent'] as double,
        total: json['total'] as int,
        segIndex: json['segIndex'] as int,
        segTotal: json['segTotal'] as int,
        segName: json['segName'] as String,
        message: json['message'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'taskId': taskId,
        'name': name,
        'workDir': workDir,
        'output': output,
        'status': status.index,
        'percent': percent,
        'total': total,
        'segIndex': segIndex,
        'segTotal': segTotal,
        'segName': segName,
        'message': message,
        'startedAt': startedAt.millisecondsSinceEpoch,
      };
}