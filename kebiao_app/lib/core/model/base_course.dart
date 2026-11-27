/// 基础课模型（格式 v2.0：13 字段）
/// 课程名称|类型|教师|校区教室|星期|起始节次|结束节次|生效起始周|生效结束周|周类型|颜色|备注|id
library;

import 'enums.dart';

class BaseCourse {
  final String name;
  final CourseType? type; // null = 解析失败/未知，渲染时降级
  final String teacher;
  final String room; // 校区教室
  final int weekday; // 1-7
  final int startPeriod;
  final int endPeriod;
  final int startWeek;
  final int endWeek;
  final WeekType weekType;
  final String color; // #RRGGBB
  final String remark; // 备注，尾部可带 {JSON} 扩展块
  final int? id; // 自增唯一编号

  const BaseCourse({
    required this.name,
    this.type,
    this.teacher = '',
    this.room = '',
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.startWeek,
    required this.endWeek,
    this.weekType = WeekType.every,
    this.color = '',
    this.remark = '',
    this.id,
  });

  BaseCourse copyWith({
    String? name,
    CourseType? type,
    String? teacher,
    String? room,
    int? weekday,
    int? startPeriod,
    int? endPeriod,
    int? startWeek,
    int? endWeek,
    WeekType? weekType,
    String? color,
    String? remark,
    int? id,
    bool clearType = false,
  }) {
    return BaseCourse(
      name: name ?? this.name,
      type: clearType ? null : (type ?? this.type),
      teacher: teacher ?? this.teacher,
      room: room ?? this.room,
      weekday: weekday ?? this.weekday,
      startPeriod: startPeriod ?? this.startPeriod,
      endPeriod: endPeriod ?? this.endPeriod,
      startWeek: startWeek ?? this.startWeek,
      endWeek: endWeek ?? this.endWeek,
      weekType: weekType ?? this.weekType,
      color: color ?? this.color,
      remark: remark ?? this.remark,
      id: id ?? this.id,
    );
  }

  /// 时段是否与 [weekday2]/[s]/[e] 格重叠
  bool overlapsCell(int weekday2, int s, int e) {
    if (weekday != weekday2) return false;
    return !(endPeriod < s || e < startPeriod);
  }

  @override
  String toString() =>
      'BaseCourse($name w$weekday [$startPeriod-$endPeriod] 周$startWeek-$endWeek $weekType)';
}
