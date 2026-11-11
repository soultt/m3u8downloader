import 'package:hive/hive.dart';
import '../models/download_task.dart';

/// Hive 适配器：DownloadStatus 枚举（含 label 字段，不能直接用 Hive 内置序列化）
class DownloadStatusAdapter extends TypeAdapter<DownloadStatus> {
  @override
  final int typeId = 10;

  @override
  DownloadStatus read(BinaryReader reader) =>
      DownloadStatus.values[reader.readByte()];

  @override
  void write(BinaryWriter writer, DownloadStatus obj) =>
      writer.writeByte(obj.index);

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
