/// 逐行体检：找出"写进去却读不回来"的行
///
/// 用途：加载时把这些行原文隔离到 `corrupt/`，并在界面上明说有几行、
/// 为什么读不出来。以前这类行是**静默丢弃**的——下一保存就永久消失。
library;

import '../validate/issues.dart';
import 'base_parser.dart';
import 'exam_parser.dart';
import 'patch_parser.dart';

/// 一次体检结果
class LineAudit {
  /// 无法识别的行（行号 + 原因）
  final List<Issue> issues;

  /// 与 [issues] 一一对应的原始行（用于隔离，可原样找回）
  final List<String> rawLines;

  const LineAudit(this.issues, this.rawLines);

  bool get isEmpty => issues.isEmpty;
  int get count => issues.length;

  /// 给用户看的一句话（不含技术细节）
  String get summary => isEmpty ? '' : '有 $count 行无法识别，已另存到 corrupt/（原文件未删）';
}

/// 基础课文件体检
LineAudit auditBaseLines(String text) =>
    _audit(text, (line, n) => parseBaseLine(line, lineNumber: n));

/// 补丁文件体检
LineAudit auditPatchLines(String text) =>
    _audit(text, (line, n) => parsePatchLine(line, lineNumber: n));

/// 考试便签文件体检
LineAudit auditExamLines(String text) =>
    _audit(text, (line, n) => parseExamLine(line, lineNumber: n));

LineAudit _audit(
  String text,
  ParseResult<dynamic> Function(String line, int lineNumber) parse,
) {
  final issues = <Issue>[];
  final raw = <String>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    // 空行与注释/版本行本来就不算数据
    if (line.trim().isEmpty) continue;
    if (line.trimLeft().startsWith('#')) continue;

    final r = parse(line, i + 1);
    if (r.value != null) continue;

    final reason = r.issues.isEmpty ? '字段格式不符' : r.issues.first.message;
    issues.add(Issue(reason, line: i + 1));
    raw.add(line);
  }
  return LineAudit(issues, raw);
}
