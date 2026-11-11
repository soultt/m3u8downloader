import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:file_picker/file_picker.dart';
import '../models/settings.dart';

const String settingsBoxName = 'app_settings';

class SettingsService extends ChangeNotifier {
  AppSettings _settings = const AppSettings();
  late Box<AppSettings> _box;
  bool _isInitialized = false;

  AppSettings get settings => _settings;
  bool get isInitialized => _isInitialized;

  /// 初始化设置服务
  Future<void> init() async {
    _box = await Hive.openBox<AppSettings>(settingsBoxName);
    final saved = _box.get('settings');
    if (saved != null) {
      _settings = saved;
    }
    _isInitialized = true;
    notifyListeners();
  }

  /// 更新保存目录
  Future<void> setSaveDir(String dir) async {
    _settings = _settings.copyWith(saveDir: dir);
    await _persist();
  }

  /// 更新输出目录
  Future<void> setOutputDir(String dir) async {
    _settings = _settings.copyWith(outputDir: dir);
    await _persist();
  }

  /// 更新并发数
  Future<void> setConcurrency(int concurrency) async {
    _settings = _settings.copyWith(concurrency: concurrency.clamp(1, 32));
    await _persist();
  }

  /// 更新自动合并
  Future<void> setAutoMerge(bool autoMerge) async {
    _settings = _settings.copyWith(autoMerge: autoMerge);
    await _persist();
  }

  /// 更新 FFmpeg 路径
  Future<void> setFFmpegPath(String path) async {
    _settings = _settings.copyWith(ffmpegPath: path);
    await _persist();
  }

  /// 清除 FFmpeg 自定义路径（使用内置）
  Future<void> clearFFmpegPath() async {
    _settings = _settings.copyWith(ffmpegPath: '');
    await _persist();
  }

  /// 持久化设置
  Future<void> _persist() async {
    await _box.put('settings', _settings);
    notifyListeners();
  }

  /// 选择保存目录
  Future<String?> pickSaveDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择下载保存目录',
      );
      
      if (selectedDirectory != null) {
        await setSaveDir(selectedDirectory);
        return selectedDirectory;
      }
    } catch (e) {
      debugPrint('选择目录失败: $e');
    }
    return null;
  }

  /// 选择输出目录
  Future<String?> pickOutputDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择合并输出目录',
      );
      
      if (selectedDirectory != null) {
        await setOutputDir(selectedDirectory);
        return selectedDirectory;
      }
    } catch (e) {
      debugPrint('选择目录失败: $e');
    }
    return null;
  }

  /// 选择 FFmpeg 可执行文件
  Future<String?> pickFFmpegPath() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择 FFmpeg 可执行文件',
        type: FileType.custom,
        allowedExtensions: ['exe', 'bin'],
      );
      
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null) {
          await setFFmpegPath(path);
          return path;
        }
      }
    } catch (e) {
      debugPrint('选择文件失败: $e');
    }
    return null;
  }

  /// 重置为默认设置
  Future<void> resetToDefaults() async {
    _settings = const AppSettings();
    await _persist();
  }
}