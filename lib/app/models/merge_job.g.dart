// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'merge_job.dart';

class MergeJobAdapter extends TypeAdapter<MergeJob> {
  @override
  final int typeId = 2;

  @override
  MergeJob read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      final f = reader.readByte();
      switch (f) {
        case 0: case 1: case 2: case 3: case 4: case 10: case 11:
          try { fields[f] = reader.readString(); } catch (_) { break; }
          break;
        case 5:
          // Enum stored as int index
          try { fields[f] = reader.readInt(); } catch (_) { break; }
          break;
        case 6:
          try { fields[f] = reader.readDouble(); } catch (_) { break; }
          break;
        case 7: case 8: case 9:
          try { fields[f] = reader.readInt(); } catch (_) { break; }
          break;
        case 12:
          // DateTime stored as two consecutive writeInt() calls (int64 millis)
          try {
            final lo = reader.readInt();
            final hi = reader.readInt();
            final ms = ((hi.toUnsigned(32)) << 32) | lo.toUnsigned(32);
            fields[f] = DateTime.fromMillisecondsSinceEpoch(ms.toSigned(64));
          } catch (_) { fields[f] = DateTime.now(); }
          break;
        default:
          reader.read();
      }
    }
    return MergeJob(
      id:        fields[0] as String? ?? '',
      taskId:    fields[1] as String? ?? '',
      name:      fields[2] as String? ?? '',
      workDir:   fields[3] as String? ?? '',
      output:    fields[4] as String? ?? '',
      status:    MergeStatus.values[(fields[5] as int?) ?? 0],
      percent:   fields[6] as double? ?? 0.0,
      total:     fields[7] as int? ?? 0,
      segIndex:  fields[8] as int? ?? 0,
      segTotal:  fields[9] as int? ?? 0,
      segName:   fields[10] as String? ?? '',
      message:   fields[11] as String? ?? '',
      startedAt: fields[12] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, MergeJob obj) {
    // Field count: indices 0..12 = 13 fields
    writer.writeByte(13);
    writer.writeByte(0);  writer.writeString(obj.id);
    writer.writeByte(1);  writer.writeString(obj.taskId);
    writer.writeByte(2);  writer.writeString(obj.name);
    writer.writeByte(3);  writer.writeString(obj.workDir);
    writer.writeByte(4);  writer.writeString(obj.output);
    writer.writeByte(5);  writer.writeInt(obj.status.index);
    writer.writeByte(6);  writer.writeDouble(obj.percent);
    writer.writeByte(7);  writer.writeInt(obj.total);
    writer.writeByte(8);  writer.writeInt(obj.segIndex);
    writer.writeByte(9);  writer.writeInt(obj.segTotal);
    writer.writeByte(10); writer.writeString(obj.segName);
    writer.writeByte(11); writer.writeString(obj.message);
    // Write DateTime as int64 millis (two consecutive writeInt calls)
    writer.writeByte(12);
    final ms = obj.startedAt.millisecondsSinceEpoch;
    writer.writeInt(ms & 0xFFFFFFFF);
    writer.writeInt(ms >> 32);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MergeJobAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
