/// 表格 → 考试便签（批量导入）
///
/// 典型输入（从教务/Excel/聊天记录里直接复制）：
/// ```
/// 日期,科目,时间,地点
/// 2026-11-25,高等数学,14:00-16:00,教3101
/// 11月27日 大学物理 09:00-11:00 教2205
/// ```
/// 支持：逗号 / 制表符 / 全角逗号 / 连续空格；带表头按列名取，不带表头按位置取。
/// 缺年份的日期（11月25日）按学期起始日推断年份。
library;

import '../model/exam_note.dart';
import '../validate/issues.dart';
import 'date_utils.dart';
import 'exam_parser.dart' show normalizeHhmm, isValidHhmm;

class ExamImportResult {
  final List<ExamNote> notes;
  final List<Issue> issues;

  const ExamImportResult(this.notes, this.issues);

  int get skipped => issues.length;
  bool get ok => notes.isNotEmpty;
}

const Map<String, List<String>> _aliases = {
  'date': ['日期', '考试日期', 'date', '时间日期'],
  'subject': ['科目', '课程', '考试科目', '课程名称', '名称', 'subject'],
  'time': ['时间', '考试时间', '时段', 'time'],
  'start': ['开始', '开始时间', 'start'],
  'end': ['结束', '结束时间', 'end'],
  'place': ['地点', '考场', '教室', '位置', 'place', 'room'],
  'remark': ['备注', '说明', 'remark', 'note'],
};

/// [reference]：学期第一周周一（用于给"11月25日"补年份）
ExamImportResult parseExamTable(String input, {required DateTime reference}) {
  final issues = <Issue>[];
  final notes = <ExamNote>[];

  final raw = input
      .replaceFirst('\uFEFF', '')
      .split('\n')
      .map((l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l)
      .toList();

  final lines = <(int, String)>[]; // (原始行号, 内容)
  for (var i = 0; i < raw.length; i++) {
    final t = raw[i].trim();
    if (t.isEmpty) continue;
    if (t.startsWith('#')) continue;
    lines.add((i + 1, t));
  }
  if (lines.isEmpty) return const ExamImportResult([], []);

  final delimiter = _detectDelimiter(lines.first.$2);
  final header = _splitLine(lines.first.$2, delimiter);
  final mapping = _mapHeader(header);

  var start = 0;
  if (mapping != null) start = 1; // 有表头 → 从第二行开始

  for (var i = start; i < lines.length; i++) {
    final (lineNo, text) = lines[i];
    final cells = _splitLine(text, delimiter);
    final note = _buildNote(cells, mapping, reference, lineNo, issues);
    if (note != null) notes.add(note);
  }

  return ExamImportResult(notes, issues);
}

/// 表头映射（null = 没有表头，按位置取）
Map<String, int>? _mapHeader(List<String> cells) {
  final map = <String, int>{};
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i].trim();
    for (final entry in _aliases.entries) {
      if (entry.value.any((a) => cell.toLowerCase() == a.toLowerCase())) {
        map.putIfAbsent(entry.key, () => i);
      }
    }
  }
  // 至少要有日期列才算表头
  return map.containsKey('date') ? map : null;
}

String _detectDelimiter(String line) {
  if (line.contains('\t')) return '\t';
  if (line.contains(',')) return ',';
  if (line.contains('，')) return '，';
  return '  '; // 连续空格（下面按多空格切）
}

List<String> _splitLine(String line, String delimiter) {
  if (delimiter == '  ') {
    return line.split(RegExp(r'\s{2,}')).map((e) => e.trim()).toList();
  }
  return line.split(delimiter).map((e) => e.trim()).toList();
}

ExamNote? _buildNote(
  List<String> cells,
  Map<String, int>? mapping,
  DateTime reference,
  int lineNo,
  List<Issue> issues,
) {
  String cell(String key, {int fallbackIndex = -1}) {
    final idx = mapping != null ? (mapping[key] ?? -1) : fallbackIndex;
    if (idx < 0 || idx >= cells.length) return '';
    return cells[idx].trim();
  }

  final dateRaw = cell('date', fallbackIndex: 0);
  final subject = cell('subject', fallbackIndex: 1);
  if (dateRaw.isEmpty) {
    issues.add(Issue('没有日期', line: lineNo));
    return null;
  }
  if (subject.isEmpty) {
    issues.add(Issue('没有科目', line: lineNo));
    return null;
  }

  final date = _parseDateLoose(dateRaw, reference);
  if (date == null) {
    issues.add(
      Issue('日期无法识别："$dateRaw"（支持 2026-11-25 / 11/25 / 11月25日）', line: lineNo),
    );
    return null;
  }

  var startTime = '';
  var endTime = '';
  final timeRaw = cell('time', fallbackIndex: 2);
  if (timeRaw.isNotEmpty && timeRaw.contains('-')) {
    final seg = timeRaw.split('-');
    startTime = _cleanTime(seg.first);
    endTime = _cleanTime(seg.length > 1 ? seg[1] : '');
  } else if (timeRaw.isNotEmpty) {
    startTime = _cleanTime(timeRaw);
  } else {
    startTime = _cleanTime(cell('start'));
    endTime = _cleanTime(cell('end'));
  }

  if (startTime.isNotEmpty && !isValidHhmm(startTime)) {
    issues.add(Issue('时间无法识别："$timeRaw"', line: lineNo));
    startTime = '';
    endTime = '';
  }

  return ExamNote(
    date: date,
    subject: subject,
    startTime: startTime,
    endTime: endTime,
    place: cell('place', fallbackIndex: 3),
    remark: cell('remark', fallbackIndex: 4),
  );
}

String _cleanTime(String s) {
  var t = s.trim();
  // "14:00-16:00" 里可能带 星期/空格
  t = t.replaceAll(RegExp(r'[（(].*?[)）]'), '').trim();
  if (t.isEmpty) return '';
  return normalizeHhmm(t);
}

/// 宽松日期：完整日期 / 11月25日 / 11-25 / 11/25（后可跟星期）
DateTime? _parseDateLoose(String input, DateTime reference) {
  var s = input.trim();
  // 去掉"星期一"/"周一"
  s = s.replaceAll(RegExp(r'(星期|周)[一二三四五六日天]'), '').trim();
  s = s.replaceAll(RegExp(r'\s+'), '');

  final full = parseFlexibleDate(s);
  if (full != null) return full;

  final md = RegExp(r'^(\d{1,2})[月/.-](\d{1,2})[日]?$').firstMatch(s);
  if (md != null) {
    final month = int.parse(md.group(1)!);
    final day = int.parse(md.group(2)!);
    final year = month < reference.month ? reference.year + 1 : reference.year;
    if (isRealDate(year, month, day)) return DateTime(year, month, day);
  }
  return null;
}
