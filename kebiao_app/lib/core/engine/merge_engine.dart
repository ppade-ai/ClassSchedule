/// 合并引擎：基础课 + 补丁 → 当前周最终课程数组
/// 规则（16.4 已确认）：
/// - 周类型不匹配的基础课 → 仍渲染但标记 inactive（非本周灰化），不参与冲突检测
/// - 补丁优先级：exactDate 类 > weekOffset 类；同优先级按文件行序后者覆盖
/// - 过期判定按浏览周（补丁生效日期 > expireDate 即失效）
/// - replace=清空该格全部基础课再放新课；remove=清空该格全部课程（含补丁 add 的）
/// - modify=同格同课程名 → 仅改教师/教室，名称不变
library;

import '../model/base_course.dart';
import '../model/enums.dart';
import '../model/patch.dart';
import '../model/week_course.dart';
import '../parse/date_utils.dart';
import '../validate/issues.dart';
import 'week_engine.dart';

class MergeResult {
  final List<WeekCourse> courses;
  final List<Issue> issues; // 如 modify 目标不存在

  const MergeResult(this.courses, this.issues);
}

class MergeEngine {
  /// 合并第 [week] 周视图
  /// [weekMonday]：该周周一（由周引擎计算传入，避免重复计算）
  MergeResult mergeWeek({
    required List<BaseCourse> baseCourses,
    required List<Patch> patches,
    required int week,
    required DateTime weekMonday,
  }) {
    final issues = <Issue>[];
    final entries = <_SlotEntry>[];

    // ---- 1. 基础课过滤 + 周类型不匹配标记 ----
    for (final c in baseCourses) {
      if (c.startWeek > week || c.endWeek < week) continue;
      final inactive = !c.weekType.matches(week);
      entries.add(_SlotEntry(
        name: c.name,
        type: c.type,
        teacher: c.teacher,
        room: c.room,
        weekday: c.weekday,
        startPeriod: c.startPeriod,
        endPeriod: c.endPeriod,
        color: c.color,
        remark: c.remark,
        inactive: inactive,
        source: 'base',
        id: c.id,
      ));
    }

    // ---- 2. 补丁过滤（定位 + 周类型 + 过期） ----
    final applicable = <(int, Patch)>[]; // (原始序号, 补丁)
    for (var i = 0; i < patches.length; i++) {
      final p = patches[i];
      if (!_patchAppliesToWeek(p, week, weekMonday)) continue;
      applicable.add((i, p));
    }
    // 优先级：exactDate 类 > weekOffset 类（**最后应用者胜出**，故 exactDate 排后）
    // 同优先级保持文件行序（Dart sort 不稳定，必须带原始序号 tiebreaker）
    applicable.sort((a, b) {
      final pa = a.$2.locationType == PatchLocationType.exactDate ? 1 : 0;
      final pb = b.$2.locationType == PatchLocationType.exactDate ? 1 : 0;
      if (pa != pb) return pa.compareTo(pb);
      return a.$1.compareTo(b.$1);
    });

    // ---- 3. 按动作应用 ----
    for (final (_, p) in applicable) {
      switch (p.action) {
        case PatchAction.add:
          entries.add(_SlotEntry.fromPatch(p));
          break;
        case PatchAction.replace:
          entries.removeWhere((e) => e.overlapsCell(p.weekday, p.startPeriod, p.endPeriod));
          entries.add(_SlotEntry.fromPatch(p));
          break;
        case PatchAction.remove:
          entries.removeWhere((e) => e.overlapsCell(p.weekday, p.startPeriod, p.endPeriod));
          break;
        case PatchAction.modify:
          final target = entries
              .where((e) =>
                  e.overlapsCell(p.weekday, p.startPeriod, p.endPeriod) &&
                  e.name == p.name)
              .toList();
          if (target.isEmpty) {
            issues.add(Issue(
              'modify 未找到课程"${p.name}"（${p.weekday} 周${p.startPeriod}-${p.endPeriod}节）',
              severity: IssueSeverity.warning,
            ));
          } else {
            for (final e in target) {
              e.teacher = p.teacher;
              e.room = p.room;
            }
          }
          break;
      }
    }

    // ---- 4. 输出 ----
    final courses = entries
        .map((e) => WeekCourse(
              name: e.name,
              type: e.type,
              teacher: e.teacher,
              room: e.room,
              weekday: e.weekday,
              startPeriod: e.startPeriod,
              endPeriod: e.endPeriod,
              color: e.color,
              remark: e.remark,
              inactive: e.inactive,
              source: e.source,
              id: e.id,
            ))
        .toList();

    // 稳定排序：按星期 → 起始节次（渲染与测试友好）
    courses.sort((a, b) {
      final w = a.weekday.compareTo(b.weekday);
      if (w != 0) return w;
      return a.startPeriod.compareTo(b.startPeriod);
    });

    return MergeResult(courses, issues);
  }

  /// 补丁是否作用于第 [week] 周（周类型命中 + 未过期）
  bool _patchAppliesToWeek(Patch p, int week, DateTime weekMonday) {
    // 周类型
    if (!p.weekType.matches(week)) return false;

    // 定位
    switch (p.locationType) {
      case PatchLocationType.weekOffset:
        final w = int.tryParse(p.locationValue);
        if (w == null || w != week) return false;
        // 过期：该周周一 > 过期日期 → 失效
        if (p.expireDate.isNotEmpty) {
          final exp = parseFlexibleDate(p.expireDate);
          if (exp != null && weekMonday.isAfter(exp)) return false;
        }
        return true;
      case PatchLocationType.exactDate:
        final d = parseFlexibleDate(p.locationValue);
        if (d == null) return false;
        // 必须落在浏览周区间内
        final range = WeekRange(weekMonday, weekMonday.add(const Duration(days: 6)));
        if (!range.contains(d)) return false;
        // 过期：生效日期 > 过期日期 → 失效（按浏览周判定，历史回看完整）
        if (p.expireDate.isNotEmpty) {
          final exp = parseFlexibleDate(p.expireDate);
          if (exp != null && d.isAfter(exp)) return false;
        }
        return true;
    }
  }
}

/// 内部可变条目（渲染中间态）
class _SlotEntry {
  String name;
  CourseType? type;
  String teacher;
  String room;
  final int weekday;
  final int startPeriod;
  final int endPeriod;
  String color;
  String remark;
  bool inactive;
  String source;
  int? id;

  _SlotEntry({
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

  factory _SlotEntry.fromPatch(Patch p) => _SlotEntry(
        name: p.name,
        type: p.type,
        teacher: p.teacher,
        room: p.room,
        weekday: p.weekday,
        startPeriod: p.startPeriod,
        endPeriod: p.endPeriod,
        color: p.color,
        remark: p.remark,
        source: 'patch',
        id: p.id,
      );

  bool overlapsCell(int weekday2, int s, int e) {
    if (weekday != weekday2) return false;
    return !(endPeriod < s || e < startPeriod);
  }
}
