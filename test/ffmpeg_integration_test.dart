import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8_down/app/models/merge_job.dart';
import 'package:m3u8_down/app/services/merger_service.dart';

/// FFmpeg 集成测试（需要实际设备/模拟器运行）
void main() {
  group('FFmpeg Integration Tests', () {
    late MergeService mergeService;

    setUp(() {
      mergeService = MergeService();
    });

    test('合并空文件列表应通过 onError 回调返回错误', () async {
      String? capturedError;
      bool onCompleteCalled = false;

      await mergeService.mergeTsFiles(
        tsFiles: [],
        outputPath: '${Directory.systemTemp.path}/empty_merged.mp4',
        job: _stubMergeJob(),
        onError: (error) => capturedError = error,
        onComplete: () => onCompleteCalled = true,
      );

      expect(capturedError, isNotNull);
      expect(onCompleteCalled, isFalse);
    });
  });
}

// 注：checkFfmpegAvailable 涉及原生 FFmpegKit 初始化，在 Flutter tests 环境中
// 会因平台绑定未完成而抛异常，建议在真机或模拟器上手动验证。

MergeJob _stubMergeJob() => MergeJob(
      id: 'test_stub_${DateTime.now().millisecondsSinceEpoch}',
      taskId: '',
      name: 'test',
      workDir: '',
      output: '',
      status: MergeStatus.running,
    );
