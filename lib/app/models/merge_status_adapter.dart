import 'package:hive/hive.dart';
import '../models/merge_job.dart';

/// Hive 适配器：MergeStatus 枚举（含 label 字段，不能直接用 Hive 内置序列化）
class MergeStatusAdapter extends TypeAdapter<MergeStatus> {
  @override
  final int typeId = 11;

  @override
  MergeStatus read(BinaryReader reader) =>
      MergeStatus.values[reader.readByte()];

  @override
  void write(BinaryWriter writer, MergeStatus obj) =>
      writer.writeByte(obj.index);

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MergeStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
