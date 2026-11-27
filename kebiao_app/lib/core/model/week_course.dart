/// 合并后的周课程（渲染层输入）
/// 由合并引擎生成：基础课 + 补丁 → 当前周最终课程数组
library;

import 'enums.dart';

class WeekCourse {
  final String name;
  final CourseType? type;
  final String teacher;
  final String room;
  final int weekday; // 1-7
  final int startPeriod;
  final int endPeriod;
  final String color;
  final String remark;
  final bool inactive; // true = 非本周（单/双周不匹配，灰化显示）
  final String source; // 'base' | 'patch'
  final int? id; // 数据行 id（用于精准定位编辑）

  const WeekCourse({
    required this.name,
    this.type,
    this.teacher = '',
    this.room = '',
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    this.color = '',
    this.remark = '',
    this.inactive = false,
    this.source = 'base',
    this.id,
  });

  /// 时段是否与 [weekday2]/[s]/[e] 格重叠
  bool overlapsCell(int weekday2, int s, int e) {
    if (weekday != weekday2) return false;
    return !(endPeriod < s || e < startPeriod);
  }

  @override
  String toString() =>
      'WeekCourse($name w$weekday [$startPeriod-$endPeriod]${inactive ? " 非本周" : ""})';
}
