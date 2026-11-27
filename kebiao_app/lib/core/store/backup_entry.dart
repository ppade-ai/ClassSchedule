/// 备份条目：`backup/<kind>_<时间戳>_<原文件名>`
///
/// 文件名里已经带着类型与时间，所以列表不需要再读文件内容。
library;

class BackupEntry {
  /// 备份文件绝对路径
  final String path;

  /// edit / batch / manual / restore
  final String kind;

  /// 原文件名：base_course.txt / course_patch.txt / time_config.ini
  final String fileName;

  /// 备份时间（取自文件名时间戳）
  final DateTime time;

  /// 字节数
  final int bytes;

  const BackupEntry({
    required this.path,
    required this.kind,
    required this.fileName,
    required this.time,
    required this.bytes,
  });

  /// 同一次备份产生的多个文件共享这个键
  String get groupKey => '${kind}_${time.millisecondsSinceEpoch}';

  String get timeText {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  String get sizeText =>
      bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB';

  /// 类型的中文名
  String get kindText => switch (kind) {
    'edit' => '编辑前',
    'batch' => '批量前',
    'restore' => '恢复前',
    'manual' => '手动',
    _ => kind,
  };

  /// 文件的中文名
  String get fileText => switch (fileName) {
    'base_course.txt' => '基础课',
    'course_patch.txt' => '补丁',
    'time_config.ini' => '课时配置',
    _ => fileName,
  };

  @override
  String toString() => '$timeText $kindText $fileText';
}
