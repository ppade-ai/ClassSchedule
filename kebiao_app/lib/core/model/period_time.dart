/// 一节课的起止时间（作息表）
///
/// 学校之间差异很大：有的 8:00 上课，有的 8:20；课间 5 分钟还是 10 分钟；
/// 上午两节连上还是四节连上。所以它必须是可编辑的数据，而不是代码里的常量。
library;

class PeriodTime {
  /// HH:mm
  final String start;
  final String end;

  const PeriodTime(this.start, this.end);

  /// 解析 `08:00-08:45`；非法返回 null（起止都必须合法，且结束晚于开始）
  static PeriodTime? tryParse(String s) {
    final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*[-~—]\s*(\d{1,2}):(\d{2})\s*$')
        .firstMatch(s);
    if (m == null) return null;
    final sh = int.parse(m.group(1)!);
    final sm = int.parse(m.group(2)!);
    final eh = int.parse(m.group(3)!);
    final em = int.parse(m.group(4)!);
    if (sh > 23 || eh > 23 || sm > 59 || em > 59) return null;
    final startMin = sh * 60 + sm;
    final endMin = eh * 60 + em;
    if (endMin <= startMin) return null;
    final start = '${_two(sh)}:${_two(sm)}';
    final end = '${_two(eh)}:${_two(em)}';
    return PeriodTime(start, end);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  int get startMinutes {
    final p = start.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  int get endMinutes {
    final p = end.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  String get text => '$start-$end';

  /// 课间（这一节结束到下一节开始）
  static int breakMinutes(PeriodTime a, PeriodTime b) =>
      b.startMinutes - a.endMinutes;

  PeriodTime copyWith({String? start, String? end}) =>
      PeriodTime(start ?? this.start, end ?? this.end);

  @override
  String toString() => text;
}
