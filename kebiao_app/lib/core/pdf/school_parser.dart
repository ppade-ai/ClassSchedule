/// 学校 PDF 解析器：词块（带坐标）→ 基础课标准行
/// 示例大学教务 PDF（iText 导出）实测规则：
/// - 表头 星期一~星期日 定 7 列（课程词 x ≈ 表头 x - 29）
/// - 左侧节次数字 1~10 定行（块锚点 y 归属 = 最大节次号 ≤ y）
/// - 块结构：名称行（可能跨行）→ (X-Y节)A-B周/校区 行 → /场地:/教师: 等字段行
/// - 第 2 页同列词按列追加到该列最后一个课程块（y < 续页上限，防"其他课程"区混入）
/// - 规则参数化（16.3 3-2 规则编辑器的数据结构基础）
library;

import '../model/base_course.dart';
import '../model/enums.dart';
import '../parse/json_ext.dart';
import '../validate/issues.dart';
import 'pdf_word.dart';

/// 学校 PDF 解析规则（可配置、可分享）
class SchoolPdfRules {
  final List<String> dayHeaderLabels; // 星期一..星期日
  final double headerToContentOffset; // 课程词起点 = 表头 x - 该值
  final double columnTolerance; // 词归属列的最大水平距离
  final double lineTolerance; // 同行判定容差
  final int maxPeriodNumber; // 节次数字上限（1~10）
  final double periodNumberMaxX; // 节次数字最大 x（左栏，防数字混入列）
  final double page2ContinuationMaxY; // 第 2 页续行截止 y（"其他课程"区之上）

  const SchoolPdfRules({
    this.dayHeaderLabels = const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
    this.headerToContentOffset = 29,
    this.columnTolerance = 52,
    this.lineTolerance = 3,
    this.maxPeriodNumber = 10,
    this.periodNumberMaxX = 100,
    this.page2ContinuationMaxY = 110,
  });
}

class SchoolPdfParser {
  final SchoolPdfRules rules;

  SchoolPdfParser({this.rules = const SchoolPdfRules()});

  /// 解析：词块列表 → 基础课列表 + 问题
  ParseResult<List<BaseCourse>> parse(List<PdfWord> words) {
    final issues = <Issue>[];

    // 1. 表头 → 列 x
    final colX = <int, double>{};
    for (final w in words) {
      final idx = rules.dayHeaderLabels.indexOf(w.text);
      if (idx >= 0) colX[idx] = w.x;
    }
    if (colX.length != 7) {
      return ParseResult(null, [
        Issue('未识别全部 7 列表头（找到 ${colX.length} 列）'),
      ]);
    }

    // 2. 节次数字 → 行 y（按页分组）
    final rowY = <int, Map<int, double>>{}; // period -> page -> y
    for (final w in words) {
      final n = int.tryParse(w.text);
      if (n != null && n >= 1 && n <= rules.maxPeriodNumber && w.x < rules.periodNumberMaxX) {
        rowY.putIfAbsent(n, () => {})[w.page] = w.y;
      }
    }
    final firstRowYPerPage = <int, double>{};
    for (final e in rowY.entries) {
      for (final pe in e.value.entries) {
        final cur = firstRowYPerPage[pe.key];
        if (cur == null || pe.value < cur) firstRowYPerPage[pe.key] = pe.value;
      }
    }

    // 3. 词 → (页, 列) 分组（过滤：左栏数字/标签、表格上方标题）
    final groups = <(int, int), List<PdfWord>>{};
    for (final w in words) {
      if (w.x < rules.periodNumberMaxX) continue; // 节次数字、左栏标签
      final firstY = firstRowYPerPage[w.page];
      if (firstY != null && w.y < firstY) continue; // 标题区
      final col = _columnOf(w.x, colX);
      if (col == null) continue;
      groups.putIfAbsent((w.page, col), () => []).add(w);
    }

    // 4. 每列：页 1 建块（锚点定行），页 2 词追加到该列最后一块
    final blocks = <_Block>[];
    final colOrder = colX.keys.toList()..sort();
    for (final col in colOrder) {
      final p1 = groups[(0, col)] ?? [];
      if (p1.isEmpty) continue;
      blocks.addAll(_scanBlocks(p1, col, rowY));

      final p2 = groups[(1, col)] ?? [];
      if (p2.isEmpty) continue;
      final cont = p2.where((w) => w.y < rules.page2ContinuationMaxY).toList()
        ..sort((a, b) => a.y.compareTo(b.y));
      final last = blocks.lastWhere((b) => b.col == col);
      // 续页词按 y 序追加为字段续行（跨行值拼接在 _parseBlock 中完成）
      last.fieldLines.addAll(cont.map((w) => w.text));
    }

    // 5. 块 → 基础课
    final courses = <BaseCourse>[];
    for (final b in blocks) {
      final r = _parseBlock(b);
      if (r == null) continue;
      courses.add(r);
    }

    courses.sort((a, b) {
      final w = a.weekday.compareTo(b.weekday);
      if (w != 0) return w;
      return a.startPeriod.compareTo(b.startPeriod);
    });

    return ParseResult(courses, issues);
  }

  int? _columnOf(double x, Map<int, double> colX) {
    int? best;
    var bestD = double.infinity;
    for (final e in colX.entries) {
      final d = (x - (e.value - rules.headerToContentOffset)).abs();
      if (d < bestD) {
        bestD = d;
        best = e.key;
      }
    }
    return bestD <= rules.columnTolerance ? best : null;
  }

  List<_Block> _scanBlocks(List<PdfWord> words, int col, Map<int, Map<int, double>> rowY) {
    // 按 y 分组成行（行内按 x 排序）
    words.sort((a, b) => a.y.compareTo(b.y));
    final lines = <_Line>[];
    for (final w in words) {
      if (lines.isNotEmpty && (w.y - lines.last.y).abs() < rules.lineTolerance) {
        lines.last.words.add(w);
      } else {
        lines.add(_Line(w.y)..words.add(w));
      }
    }
    for (final l in lines) {
      l.words.sort((a, b) => a.x.compareTo(b.x));
    }

    final blocks = <_Block>[];
    _Block? cur;
    for (final line in lines) {
      final text = line.text; // 词按 x 序拼接
      final symbolMatch = RegExp(r'^(.*?)([☆★○●])$').firstMatch(text);
      if (symbolMatch != null) {
        // 名称行；当前块尚无表头时视为名称换行续接，否则开新块
        if (cur == null || cur.hasHeader) {
          cur = _Block(col: col, anchorY: line.y);
          blocks.add(cur);
        }
        cur.nameLines.add(symbolMatch.group(1)!);
        cur.type = courseTypeFromSymbol(symbolMatch.group(2)!);
      } else {
        // 字段续行必然含 '/' ':' ';'；纯文本裸行 = 新课程的名称（可能换行）
        final isFieldish =
            text.contains('/') || text.contains(':') || text.contains(';');
        if (cur == null || (cur.hasHeader && !isFieldish)) {
          cur = _Block(col: col, anchorY: line.y);
          blocks.add(cur);
          cur.nameLines.add(text);
          continue;
        }
        if (!cur.hasHeader) {
          if (cur.type == null) {
            cur.nameLines.add(text); // 名称续段
            continue;
          }
          if (text.startsWith('(')) {
            cur.headerLine = text; // (X-Y节)A-B周/校区:
            continue;
          }
          if (!isFieldish) {
            cur.nameLines.add(text);
            continue;
          }
          cur.headerLine = text; // 防御：类型已定但表头缺失
          continue;
        }
        cur.fieldLines.add(text); // 字段续行
      }
    }

    // 行归属：块锚点 y → 最大节次号 ≤ y
    for (final b in blocks) {
      var row = 0;
      for (var p = 1; p <= rules.maxPeriodNumber; p++) {
        final yp = rowY[p]?[0];
        if (yp != null && yp <= b.anchorY) row = p;
      }
      b.periodRow = row;
    }
    return blocks;
  }

  BaseCourse? _parseBlock(_Block b) {
    if (b.type == null || b.nameLines.isEmpty) return null;
    final name = b.nameLines.join();

    var startPeriod = 0, endPeriod = 0, startWeek = 0, endWeek = 0;
    var campus = '';

    // 表头行：(1-2节)1-9周/校区:校本部
    final h = b.headerLine;
    final pm = RegExp(r'\((\d+)-(\d+)节\)').firstMatch(h);
    if (pm != null) {
      startPeriod = int.tryParse(pm.group(1)!) ?? 0;
      endPeriod = int.tryParse(pm.group(2)!) ?? 0;
    }
    final wm = RegExp(r'(\d+)-(\d+)周').firstMatch(h);
    if (wm != null) {
      startWeek = int.tryParse(wm.group(1)!) ?? 0;
      endWeek = int.tryParse(wm.group(2)!) ?? 0;
    }
    final cm = RegExp(r'校区:([^/]+)').firstMatch(h);
    if (cm != null) campus = cm.group(1)!.trim();

    // 字段行拼接：'/场地:xxx/教师:yyy' + 续行（跨行值重建）
    final allFields = ([h] + b.fieldLines).join();
    final raw = <String, String>{};
    String? lastKey;
    for (final seg in allFields.split('/')) {
      if (seg.isEmpty) continue;
      final ci = seg.indexOf(':');
      if (ci > 0) {
        lastKey = seg.substring(0, ci).trim();
        raw[lastKey] = (raw[lastKey] ?? '') + seg.substring(ci + 1).trim();
      } else if (lastKey != null) {
        raw[lastKey] = (raw[lastKey] ?? '') + seg.trim();
      }
    }
    // 教师字段清洗：剥离尾部数字残片（PDF 行号噪声，如"李老师1"→"李老师"；
    // 实测同教师另一格为干净"李老师"，且中文人名不含尾部数字）
    final teacher =
        (raw['教师'] ?? '').replaceFirst(RegExp(r'\d+$'), '');
    var roomRaw = raw['场地'] ?? '';
    // 校区去重：场地含 (主) 等校区后缀时剥离
    if (roomRaw.isNotEmpty && campus.isNotEmpty) {
      final suffix = campus.replaceAll('校区', '');
      if (suffix.isNotEmpty && roomRaw.endsWith('($suffix)')) {
        roomRaw = roomRaw.substring(0, roomRaw.length - (suffix.length + 2));
      }
    }
    final room = campus.isEmpty ? roomRaw : '$campus$roomRaw';

    // 结构化扩展（教学班/学时/考核）→ 备注 {JSON}
    final ext = <String, dynamic>{};
    void put(String key, String k) {
      final v = raw[k];
      if (v != null && v.isNotEmpty) ext[key] = v;
    }

    put('教学班', '教学班');
    put('教学班组成', '教学班组成');
    put('考核方式', '考核方式');
    put('课程学时组成', '课程学时组成');
    put('周学时', '周学时');
    put('总学时', '总学时');
    put('学分', '学分');
    final plain = raw['选课备注'] ?? '';
    final remark = ext.isEmpty ? plain : buildRemark(plain, ext);

    return BaseCourse(
      name: name,
      type: b.type,
      teacher: teacher,
      room: room,
      weekday: b.col + 1,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      startWeek: startWeek,
      endWeek: endWeek,
      weekType: WeekType.every,
      color: '', // 导入时按调色板分配
      remark: remark,
      id: null,
    );
  }
}

class _Line {
  final double y;
  final List<PdfWord> words = [];
  _Line(this.y);

  String get text => words.map((w) => w.text).join();
}

class _Block {
  final int col;
  final double anchorY;
  final List<String> nameLines = [];
  CourseType? type;
  String headerLine = '';
  final List<String> fieldLines = [];
  int periodRow = 0;

  _Block({required this.col, required this.anchorY});

  bool get hasHeader => headerLine.isNotEmpty;
}
