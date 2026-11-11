// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_task.dart';

class DownloadTaskAdapter extends TypeAdapter<DownloadTask> {
  @override
  final int typeId = 1;

  @override
  DownloadTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      final f = reader.readByte();
      switch (f) {
        case 0: case 1: case 2: case 7: case 12: case 13: case 14:
          try { fields[f] = reader.readString(); } catch (_) { break; }
          break;
        case 3:
          // Enum stored as int index
          try { fields[f] = reader.readInt(); } catch (_) { break; }
          break;
        case 4: case 5: case 10: case 15:
          try { fields[f] = reader.readInt(); } catch (_) { break; }
          break;
        case 6: case 11:
          try { fields[f] = reader.readDouble(); } catch (_) { break; }
          break;
        case 8:
          try { fields[f] = reader.readString(); } catch (_) { fields[f] = null; }
          break;
        case 9:
          try { fields[f] = reader.readBool(); } catch (_) { break; }
          break;
        case 16:
          // DateTime stored as two consecutive writeInt() calls (int64 millis)
          try {
            final lo = reader.readInt();
            final hi = reader.readInt();
            final ms = ((hi.toUnsigned(32)) << 32) | lo.toUnsigned(32);
            fields[f] = DateTime.fromMillisecondsSinceEpoch(ms.toSigned(64));
          } catch (_) { break; }
          break;
        default:
          reader.read();
      }
    }
    return DownloadTask(
      id:        fields[0] as String? ?? '',
      name:      fields[1] as String? ?? '',
      url:       fields[2] as String? ?? '',
      status:    DownloadStatus.values[(fields[3] as int?) ?? 2],
      total:     fields[4] as int? ?? 0,
      done:      fields[5] as int? ?? 0,
      progress:  fields[6] as double? ?? 0.0,
      workDir:   fields[7] as String? ?? '',
      mp4File:   fields[8] as String?,
      autoMerge: fields[9] as bool? ?? false,
      concurrency: fields[10] as int? ?? 8,
      speed:     fields[11] as double? ?? 0.0,
      outputDir: fields[12] as String?,
      outputName: fields[13] as String?,
      message:   fields[14] as String?,
      failed:    fields[15] as int? ?? 0,
      createdAt: _readCreated(fields[16]),
    );
  }

  static DateTime? _readCreated(dynamic v) {
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  @override
  void write(BinaryWriter writer, DownloadTask obj) {
    // Field count: indices 0..16 = 17 fields
    writer.writeByte(17);
    writer.writeByte(0);  writer.writeString(obj.id);
    writer.writeByte(1);  writer.writeString(obj.name);
    writer.writeByte(2);  writer.writeString(obj.url);
    writer.writeByte(3);  writer.writeInt(obj.status.index);
    writer.writeByte(4);  writer.writeInt(obj.total);
    writer.writeByte(5);  writer.writeInt(obj.done);
    writer.writeByte(6);  writer.writeDouble(obj.progress);
    writer.writeByte(7);  writer.writeString(obj.workDir);
    writer.writeByte(8);  writer.writeString(obj.mp4File ?? '');
    writer.writeByte(9);  writer.writeBool(obj.autoMerge);
    writer.writeByte(10); writer.writeInt(obj.concurrency);
    writer.writeByte(11); writer.writeDouble(obj.speed);
    writer.writeByte(12); writer.writeString(obj.outputDir ?? '');
    writer.writeByte(13); writer.writeString(obj.outputName ?? '');
    writer.writeByte(14); writer.writeString(obj.message ?? '');
    writer.writeByte(15); writer.writeInt(obj.failed);
    // Write DateTime as int64 millis – reader must match this format
    writer.writeByte(16);
    final ms = obj.createdAt.millisecondsSinceEpoch;
    writer.writeInt(ms & 0xFFFFFFFF);           // low 32 bits
    writer.writeInt(ms >> 32);                   // high 32 bits (signed)
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadTaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
