import 'package:hive/hive.dart';

part 'settings.g.dart';

@HiveType(typeId: 3)
class AppSettings {
  @HiveField(0)
  final String saveDir;

  @HiveField(1)
  final String outputDir;

  @HiveField(2)
  final int concurrency;

  @HiveField(3)
  final bool autoMerge;

  @HiveField(4)
  final String ffmpegPath;

  const AppSettings({
    this.saveDir = '',
    this.outputDir = '',
    this.concurrency = 8,
    this.autoMerge = true,
    this.ffmpegPath = '',
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        saveDir: json['saveDir'] as String? ?? '',
        outputDir: json['outputDir'] as String? ?? '',
        concurrency: json['concurrency'] as int? ?? 8,
        autoMerge: json['autoMerge'] as bool? ?? true,
        ffmpegPath: json['ffmpegPath'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'saveDir': saveDir,
        'outputDir': outputDir,
        'concurrency': concurrency,
        'autoMerge': autoMerge,
        'ffmpegPath': ffmpegPath,
      };

  AppSettings copyWith({
    String? saveDir,
    String? outputDir,
    int? concurrency,
    bool? autoMerge,
    String? ffmpegPath,
  }) {
    return AppSettings(
      saveDir: saveDir ?? this.saveDir,
      outputDir: outputDir ?? this.outputDir,
      concurrency: concurrency ?? this.concurrency,
      autoMerge: autoMerge ?? this.autoMerge,
      ffmpegPath: ffmpegPath ?? this.ffmpegPath,
    );
  }
}
