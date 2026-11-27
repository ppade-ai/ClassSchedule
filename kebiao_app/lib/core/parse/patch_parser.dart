/// 补丁解析器：15 字段 | 分隔 ↔ 模型
/// 定位类型|公历日期/周序号|星期|起始节次|结束节次|周类型|操作类型|课程名称|类型|教师|教室|颜色|过期日期|备注|id
library;

import '../model/enums.dart';
import '../model/patch.dart';
import '../validate/issues.dart';
import '../validate/validator.dart' show kMaxNameLength;
import 'date_utils.dart';

const int patchFieldCount = 15;

/// 单行解析 → 模型 + 问题
ParseResult<Patch> parsePatchLine(String line, {int lineNumber = 0}) {
  final issues = <Issue>[];

  if (line.trim().isEmpty) return const ParseResult(null, []);

  // 版本行 / 注释行不参与字段计数（数据文件首行是 `#FORMAT vN`，见 core/format）
  if (line.trimLeft().startsWith('#')) return const ParseResult(null, []);

  final parts = line.split('|');
  if (parts.length != patchFieldCount) {
    return ParseResult(
      null,
      [Issue('补丁字段数应为 $patchFieldCount，实际 ${parts.length}', line: lineNumber)],
    );
  }

  // 1 定位类型
  final locationType = patchLocationTypeFromCode(parts[0]);
  if (locationType == null) {
    issues.add(Issue('定位类型"${parts[0].trim()}"无效（应为 exactDate/weekOffset）', line: lineNumber));
  }

  // 2 定位值
  final locationValue = parts[1].trim();
  if (locationValue.isEmpty) {
    issues.add(Issue('定位值不能为空', line: lineNumber));
  }
  if (locationType == PatchLocationType.exactDate) {
    if (parseFlexibleDate(locationValue) == null) {
      issues.add(Issue('精确日期"$locationValue"无效或非法（如 2月30日）', line: lineNumber));
    }
  } else if (locationType == PatchLocationType.weekOffset) {
    final w = int.tryParse(locationValue);
    if (w == null || w < 1 || w > 60) {
      issues.add(Issue('周序号"$locationValue"无效（应为 1-60）', line: lineNumber));
    }
  }

  // 3-5 星期/节次
  final weekday = int.tryParse(parts[2].trim());
  final startPeriod = int.tryParse(parts[3].trim());
  final endPeriod = int.tryParse(parts[4].trim());
  if (weekday == null || weekday < 1 || weekday > 7) {
    issues.add(Issue('星期"${parts[2].trim()}"无效（应为 1-7）', line: lineNumber));
  }
  if (startPeriod == null || startPeriod < 1) {
    issues.add(Issue('起始节次"${parts[3].trim()}"无效', line: lineNumber));
  }
  if (endPeriod == null || endPeriod < 1) {
    issues.add(Issue('结束节次"${parts[4].trim()}"无效', line: lineNumber));
  }
  if (startPeriod != null && endPeriod != null && endPeriod < startPeriod) {
    issues.add(Issue('结束节次($endPeriod) 不能小于起始节次($startPeriod)', line: lineNumber));
  }

  // 6 周类型
  final weekType = weekTypeFromCode(parts[5]);
  if (weekType == null) {
    issues.add(Issue('周类型"${parts[5].trim()}"无效（应为 空/单/双）', line: lineNumber));
  }

  // 7 操作类型
  final action = patchActionFromCode(parts[6]);
  if (action == null) {
    issues.add(Issue('操作类型"${parts[6].trim()}"无效（应为 add/replace/remove/modify）', line: lineNumber));
  }

  // 8 课程名称（remove 可空）
  final name = parts[7].trim();
  if (action != PatchAction.remove && name.isEmpty) {
    issues.add(Issue('课程名称不能为空（remove 除外）', line: lineNumber));
  } else if (name.length > kMaxNameLength) {
    issues.add(Issue('课程名称超长（${name.length} > $kMaxNameLength 字符）', line: lineNumber));
  }

  // 9 类型
  final type = courseTypeFromSymbol(parts[8]);
  if (type == null && parts[8].trim().isNotEmpty) {
    issues.add(Issue('课程类型"${parts[8].trim()}"无效（应为 ☆/★/○/●）', line: lineNumber));
  }

  // 10 教师 / 11 教室
  final teacher = parts[9].trim();
  final room = parts[10].trim();
  if (teacher.isEmpty && room.isEmpty && action != PatchAction.remove) {
    issues.add(Issue('教师与教室至少填写一项', line: lineNumber));
  }

  // 12 颜色
  final color = parts[11].trim();
  if (color.isNotEmpty && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
    issues.add(Issue('颜色"$color"无效（应为 #RRGGBB）', line: lineNumber));
  }

  // 13 过期日期
  final expireDate = parts[12].trim();
  if (expireDate.isNotEmpty && parseFlexibleDate(expireDate) == null) {
    issues.add(Issue('过期日期"$expireDate"无效或非法', line: lineNumber));
  }

  // 14 备注
  final remark = parts[13].trim();

  // 15 id
  final id = int.tryParse(parts[14].trim());

  final patch = Patch(
    locationType: locationType ?? PatchLocationType.weekOffset,
    locationValue: locationValue,
    weekday: weekday ?? 0,
    startPeriod: startPeriod ?? 0,
    endPeriod: endPeriod ?? 0,
    weekType: weekType ?? WeekType.every,
    action: action ?? PatchAction.add,
    name: name,
    type: type,
    teacher: teacher,
    room: room,
    color: color,
    expireDate: expireDate,
    remark: remark,
    id: id,
  );

  return ParseResult(patch, issues);
}

/// 序列化为标准行
String patchToLine(Patch p) {
  return [
    p.locationType.code,
    p.locationValue,
    p.weekday.toString(),
    p.startPeriod.toString(),
    p.endPeriod.toString(),
    p.weekType.code,
    p.action.code,
    p.name,
    p.type?.symbol ?? '',
    p.teacher,
    p.room,
    p.color,
    p.expireDate,
    p.remark,
    p.id?.toString() ?? '',
  ].join('|');
}

/// 批量解析（空行跳过）
ParseResult<List<Patch>> parsePatchLines(String text) {
  final patches = <Patch>[];
  final issues = <Issue>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final r = parsePatchLine(lines[i], lineNumber: i + 1);
    if (r.value != null) patches.add(r.value!);
    issues.addAll(r.issues);
  }
  return ParseResult(patches, issues);
}
