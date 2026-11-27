/// 增量补丁模型（格式 v2.0：15 字段）
/// 定位类型|公历日期/周序号|星期|起始节次|结束节次|周类型|操作类型|课程名称|类型|教师|教室|颜色|过期日期|备注|id
library;

import 'enums.dart';

class Patch {
  final PatchLocationType locationType; // exactDate / weekOffset
  final String locationValue; // 日期 YYYY-MM-DD 或 周序号数字
  final int weekday; // 1-7
  final int startPeriod;
  final int endPeriod;
  final WeekType weekType; // v2.0 新增：空/单/双
  final PatchAction action; // add/replace/remove/modify
  final String name; // remove 时可空
  final CourseType? type;
  final String teacher;
  final String room;
  final String color;
  final String expireDate; // YYYY-MM-DD，空 = 不过期
  final String remark;
  final int? id;

  const Patch({
    required this.locationType,
    required this.locationValue,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    this.weekType = WeekType.every,
    required this.action,
    this.name = '',
    this.type,
    this.teacher = '',
    this.room = '',
    this.color = '',
    this.expireDate = '',
    this.remark = '',
    this.id,
  });

  Patch copyWith({
    PatchLocationType? locationType,
    String? locationValue,
    int? weekday,
    int? startPeriod,
    int? endPeriod,
    WeekType? weekType,
    PatchAction? action,
    String? name,
    CourseType? type,
    String? teacher,
    String? room,
    String? color,
    String? expireDate,
    String? remark,
    int? id,
  }) {
    return Patch(
      locationType: locationType ?? this.locationType,
      locationValue: locationValue ?? this.locationValue,
      weekday: weekday ?? this.weekday,
      startPeriod: startPeriod ?? this.startPeriod,
      endPeriod: endPeriod ?? this.endPeriod,
      weekType: weekType ?? this.weekType,
      action: action ?? this.action,
      name: name ?? this.name,
      type: type ?? this.type,
      teacher: teacher ?? this.teacher,
      room: room ?? this.room,
      color: color ?? this.color,
      expireDate: expireDate ?? this.expireDate,
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
      'Patch(${locationType.code}:$locationValue w$weekday [$startPeriod-$endPeriod] ${action.code})';
}
