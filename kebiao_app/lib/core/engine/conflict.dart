/// 冲突检测：同星期同节次重叠课程
/// 非本周（inactive）课程不参与冲突检测（16.4 已确认）
library;

import '../model/week_course.dart';

class ConflictPair {
  final WeekCourse a;
  final WeekCourse b;

  const ConflictPair(this.a, this.b);

  @override
  String toString() => '冲突：${a.name} 与 ${b.name}（周${a.weekday} ${a.startPeriod}-${a.endPeriod}节）';
}

/// 找出全部冲突对（同一星期且节次区间重叠的两门有效课程）
List<ConflictPair> findConflicts(List<WeekCourse> courses) {
  final result = <ConflictPair>[];
  final active = courses.where((c) => !c.inactive).toList();
  for (var i = 0; i < active.length; i++) {
    for (var j = i + 1; j < active.length; j++) {
      final a = active[i];
      final b = active[j];
      if (a.weekday == b.weekday &&
          !(a.endPeriod < b.startPeriod || b.endPeriod < a.startPeriod)) {
        result.add(ConflictPair(a, b));
      }
    }
  }
  return result;
}
