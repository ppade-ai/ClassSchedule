/// 考试 / 便签的标准文本解析：7 字段
/// 日期|科目|开始|结束|地点|备注|id
///
/// 日期必须是完整的 YYYY-MM-DD（写入前已归一化）；只有"11月25日"这种
/// 缺年份的输入由批量导入补年份，补完再落到这里。
library;

import '../model/exam_note.dart';
import '../validate/issues.dart';
import 'date_utils.dart';

const int examFieldCount = 7;

bool isValidHhmm(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return false;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  return h >= 0 && h <= 23 && min >= 0 && min <= 59;
}

/// 统一成 HH:mm（8:00 → 08:00）
String normalizeHhmm(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return s.trim();
  return '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
}

ParseResult<ExamNote> parseExamLine(String line, {int lineNumber = 0}) {
  final issues = <Issue>[];

  if (line.trim().isEmpty) return const ParseResult(null, []);
  if (line.trimLeft().startsWith('#')) return const ParseResult(null, []);

  final parts = line.split('|');
  if (parts.length != examFieldCount) {
    return ParseResult(null, [
      Issue('便签字段数应为 $examFieldCount，实际 ${parts.length}', line: lineNumber),
    ]);
  }

  final date = parseFlexibleDate(parts[0]);
  if (date == null) {
    issues.add(
      Issue('日期"${parts[0].trim()}"无效（应为 YYYY-MM-DD）', line: lineNumber),
    );
  }

  final subject = parts[1].trim();
  if (subject.isEmpty) {
    issues.add(Issue('科目不能为空', line: lineNumber));
  }

  final start = parts[2].trim();
  final end = parts[3].trim();
  if (start.isNotEmpty && !isValidHhmm(start)) {
    issues.add(Issue('开始时间"$start"无效（应为 HH:mm）', line: lineNumber));
  }
  if (end.isNotEmpty && !isValidHhmm(end)) {
    issues.add(Issue('结束时间"$end"无效（应为 HH:mm）', line: lineNumber));
  }

  final note = ExamNote(
    date: date ?? DateTime(2000, 1, 1),
    subject: subject,
    startTime: normalizeHhmm(start),
    endTime: normalizeHhmm(end),
    place: parts[4].trim(),
    remark: parts[5].trim(),
    id: int.tryParse(parts[6].trim()),
  );

  // 日期坏掉的行不能进模型（否则会在 2000 年冒出一条）
  return ParseResult(date == null ? null : note, issues);
}

String examToLine(ExamNote e) => [
  e.dateText,
  e.subject,
  e.startTime,
  e.endTime,
  e.place,
  e.remark,
  e.id?.toString() ?? '',
].join('|');

ParseResult<List<ExamNote>> parseExamLines(String text) {
  final notes = <ExamNote>[];
  final issues = <Issue>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final r = parseExamLine(lines[i], lineNumber: i + 1);
    if (r.value != null) notes.add(r.value!);
    issues.addAll(r.issues);
  }
  return ParseResult(notes, issues);
}
