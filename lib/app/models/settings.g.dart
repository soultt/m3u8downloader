// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 3;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return AppSettings(
      saveDir: fields[0] as String? ?? '',
      outputDir: fields[1] as String? ?? '',
      concurrency: fields[2] as int? ?? 8,
      autoMerge: fields[3] as bool? ?? true,
      ffmpegPath: fields[4] as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.saveDir)
      ..writeByte(1)
      ..write(obj.outputDir)
      ..writeByte(2)
      ..write(obj.concurrency)
      ..writeByte(3)
      ..write(obj.autoMerge)
      ..writeByte(4)
      ..write(obj.ffmpegPath);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
