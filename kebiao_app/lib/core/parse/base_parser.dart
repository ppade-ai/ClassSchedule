/// 基础课解析器：13 字段 | 分隔 ↔ 模型
/// 课程名称|类型|教师|校区教室|星期|起始节次|结束节次|生效起始周|生效结束周|周类型|颜色|备注|id
library;

import '../model/base_course.dart';
import '../model/enums.dart';
import '../validate/issues.dart';
import '../validate/validator.dart' show kMaxNameLength;

const int baseFieldCount = 13;

/// 单行解析 → 模型 + 问题
/// 结构错误（字段数不符）返回 value=null；字段级错误保留模型并附问题
ParseResult<BaseCourse> parseBaseLine(String line, {int lineNumber = 0}) {
  final issues = <Issue>[];

  if (line.trim().isEmpty) return const ParseResult(null, []);

  // 版本行 / 注释行不参与字段计数（数据文件首行是 `#FORMAT vN`，见 core/format）
  if (line.trimLeft().startsWith('#')) return const ParseResult(null, []);

  final parts = line.split('|');
  if (parts.length != baseFieldCount) {
    return ParseResult(
      null,
      [Issue('基础课字段数应为 $baseFieldCount，实际 ${parts.length}', line: lineNumber)],
    );
  }

  // 1 名称
  final name = parts[0].trim();
  if (name.isEmpty) {
    issues.add(Issue('课程名称不能为空', line: lineNumber));
  } else if (name.length > kMaxNameLength) {
    issues.add(Issue('课程名称超长（${name.length} > $kMaxNameLength 字符）', line: lineNumber));
  }

  // 2 类型
  final type = courseTypeFromSymbol(parts[1]);
  if (type == null) {
    issues.add(Issue('课程类型"${parts[1].trim()}"无效（应为 ☆/★/○/●）', line: lineNumber));
  }

  // 3 教师 / 4 教室
  final teacher = parts[2].trim();
  final room = parts[3].trim();
  if (teacher.isEmpty && room.isEmpty) {
    issues.add(Issue('教师与教室至少填写一项', line: lineNumber));
  }

  // 5-7 星期/节次
  final weekday = int.tryParse(parts[4].trim());
  final startPeriod = int.tryParse(parts[5].trim());
  final endPeriod = int.tryParse(parts[6].trim());
  if (weekday == null || weekday < 1 || weekday > 7) {
    issues.add(Issue('星期"${parts[4].trim()}"无效（应为 1-7）', line: lineNumber));
  }
  if (startPeriod == null || startPeriod < 1) {
    issues.add(Issue('起始节次"${parts[5].trim()}"无效', line: lineNumber));
  }
  if (endPeriod == null || endPeriod < 1) {
    issues.add(Issue('结束节次"${parts[6].trim()}"无效', line: lineNumber));
  }
  if (startPeriod != null && endPeriod != null && endPeriod < startPeriod) {
    issues.add(Issue('结束节次($endPeriod) 不能小于起始节次($startPeriod)', line: lineNumber));
  }

  // 8-9 周范围
  final startWeek = int.tryParse(parts[7].trim());
  final endWeek = int.tryParse(parts[8].trim());
  if (startWeek == null || startWeek < 1 || startWeek > 60) {
    issues.add(Issue('生效起始周"${parts[7].trim()}"无效（应为 1-60）', line: lineNumber));
  }
  if (endWeek == null || endWeek < 1 || endWeek > 60) {
    issues.add(Issue('生效结束周"${parts[8].trim()}"无效（应为 1-60）', line: lineNumber));
  }
  if (startWeek != null && endWeek != null && endWeek < startWeek) {
    issues.add(Issue('生效结束周($endWeek) 不能小于起始周($startWeek)', line: lineNumber));
  }

  // 10 周类型
  final weekType = weekTypeFromCode(parts[9]);
  if (weekType == null) {
    issues.add(Issue('周类型"${parts[9].trim()}"无效（应为 空/单/双）', line: lineNumber));
  }

  // 11 颜色
  final color = parts[10].trim();
  if (color.isNotEmpty && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
    issues.add(Issue('颜色"$color"无效（应为 #RRGGBB）', line: lineNumber));
  }

  // 12 备注（可带 {JSON}）
  final remark = parts[11].trim();

  // 13 id
  final id = int.tryParse(parts[12].trim());

  final course = BaseCourse(
    name: name,
    type: type,
    teacher: teacher,
    room: room,
    weekday: weekday ?? 0,
    startPeriod: startPeriod ?? 0,
    endPeriod: endPeriod ?? 0,
    startWeek: startWeek ?? 0,
    endWeek: endWeek ?? 0,
    weekType: weekType ?? WeekType.every,
    color: color,
    remark: remark,
    id: id,
  );

  return ParseResult(course, issues);
}

/// 序列化为标准行
String baseCourseToLine(BaseCourse c) {
  final type = c.type?.symbol ?? '';
  return [
    c.name,
    type,
    c.teacher,
    c.room,
    c.weekday.toString(),
    c.startPeriod.toString(),
    c.endPeriod.toString(),
    c.startWeek.toString(),
    c.endWeek.toString(),
    c.weekType.code,
    c.color,
    c.remark,
    c.id?.toString() ?? '',
  ].join('|');
}

/// 批量解析（空行跳过）
ParseResult<List<BaseCourse>> parseBaseLines(String text) {
  final courses = <BaseCourse>[];
  final issues = <Issue>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final r = parseBaseLine(lines[i], lineNumber: i + 1);
    if (r.value != null) courses.add(r.value!);
    issues.addAll(r.issues);
  }
  return ParseResult(courses, issues);
}
