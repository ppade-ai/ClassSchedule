/// 通用表格（CSV）→ 标准文本行
///
/// 用途：把「AI Skill 生成的通用文件」或用户手工填写的 CSV 表格，转成内核唯一认识的标准行，
/// 之后复用**同一套**校验器与写入管道（不新增第二条真相、不新增第二写入路径）。
///
/// 设计要点
/// - **表头驱动**：按列名取字段，因此列顺序任意（AI 输出顺序不同也能用）
/// - 纯 Dart、零依赖：自己解析 CSV（支持双引号包裹与 `""` 转义），不引入任何包
/// - `#` 开头整行视为注释（模板文件顶部就是注释），空行跳过；兼容 UTF-8 BOM 与 CRLF
/// - 语法错误落在**这一行**上并给出原因，不抛异常、不中断其余行
library;

import '../model/base_course.dart';
import '../model/enums.dart';
import '../model/patch.dart';
import '../validate/issues.dart';
import 'base_parser.dart' show baseCourseToLine;
import 'patch_parser.dart' show patchToLine;

/// 通用表格的目标类型（由表头推断）
enum CsvTarget { base, patch, unknown }

class CsvConversionResult {
  final CsvTarget target;

  /// 转换出的标准行文本（每行一条，`|` 分隔）
  final String standardText;

  /// 转换失败的行（带原始行号与原因），这些行**不会**进入 standardText
  final List<Issue> issues;

  final int converted; // 成功转换条数
  final int skipped; // 跳过条数

  const CsvConversionResult({
    required this.target,
    required this.standardText,
    required this.issues,
    required this.converted,
    required this.skipped,
  });

  bool get ok => target != CsvTarget.unknown && converted > 0;
}

class CsvConverter {
  /// 基础课表模板的表头（顺序即模板默认顺序，但解析时按列名匹配）
  static const List<String> baseHeaders = [
    '课程名称', '类型', '教师', '教室', '星期', '起始节', '结束节',
    '起始周', '结束周', '周类型', '颜色', '备注',
  ];

  /// 调课/临时课模板的表头
  static const List<String> patchHeaders = [
    '定位类型', '定位值', '星期', '起始节', '结束节', '周类型', '操作',
    '课程名称', '类型', '教师', '教室', '颜色', '过期日期', '备注',
  ];

  /// 把 CSV 文本转成标准行
  static CsvConversionResult convert(String input) {
    final issues = <Issue>[];
    final outLines = <String>[];

    final rawLines = input
        .replaceFirst('\uFEFF', '') // UTF-8 BOM（Excel 另存为 CSV 常见）
        .split('\n')
        .map((l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l)
        .toList();

    // 收集有效行（跳过注释与空行），并保留原始行号
    final kept = <(int, String)>[];
    for (var i = 0; i < rawLines.length; i++) {
      final t = rawLines[i].trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      kept.add((i + 1, rawLines[i]));
    }
    if (kept.isEmpty) {
      return const CsvConversionResult(
        target: CsvTarget.unknown,
        standardText: '',
        issues: [],
        converted: 0,
        skipped: 0,
      );
    }

    // 表头
    final headerCells =
        _splitCsvLine(kept.first.$2).map((c) => c.trim()).toList();
    final idx = <String, int>{};
    for (var i = 0; i < headerCells.length; i++) {
      if (headerCells[i].isNotEmpty) idx[headerCells[i]] = i;
    }

    final target = _detectTarget(idx);

    var converted = 0;
    var skipped = 0;
    for (final (lineNo, raw) in kept.skip(1)) {
      final cells = _splitCsvLine(raw);
      String cell(String col) {
        final i = idx[col];
        if (i == null || i >= cells.length) return '';
        return cells[i].trim();
      }

      final rowIssues = <Issue>[];
      final line = switch (target) {
        CsvTarget.base => _baseLine(cell, lineNo, rowIssues),
        CsvTarget.patch => _patchLine(cell, lineNo, rowIssues),
        CsvTarget.unknown => null,
      };

      if (line == null) {
        skipped++;
        if (rowIssues.isEmpty) {
          rowIssues.add(Issue('无法识别的表头，请使用模板中的列名', line: lineNo));
        }
        issues.addAll(rowIssues);
      } else {
        converted++;
        outLines.add(line);
      }
    }

    if (target == CsvTarget.unknown) {
      issues.insert(
        0,
        Issue(
          '表头无法识别：请使用模板列名（基础课需含「课程名称/星期/起始节」；'
          '调课需含「定位类型/操作」）',
          line: kept.first.$1,
        ),
      );
    }

    return CsvConversionResult(
      target: target,
      standardText: outLines.join('\n'),
      issues: issues,
      converted: converted,
      skipped: skipped,
    );
  }

  static CsvTarget _detectTarget(Map<String, int> idx) {
    if (idx.containsKey('定位类型') || idx.containsKey('操作')) {
      return CsvTarget.patch;
    }
    if (idx.containsKey('课程名称') && idx.containsKey('星期')) {
      return CsvTarget.base;
    }
    return CsvTarget.unknown;
  }

  // ---------------- 基础课 ----------------

  static String? _baseLine(
    String Function(String) cell,
    int lineNo,
    List<Issue> issues,
  ) {
    final name = cell('课程名称');
    if (name.isEmpty) {
      issues.add(Issue('课程名称不能为空', line: lineNo));
      return null;
    }

    final type = courseTypeFromSymbol(cell('类型'));
    if (type == null) {
      issues.add(Issue('类型「${cell('类型')}」无效（应为 ☆/★/○/●）', line: lineNo));
      return null;
    }

    final weekday = int.tryParse(cell('星期'));
    final startPeriod = int.tryParse(cell('起始节'));
    final endPeriod = int.tryParse(cell('结束节'));
    if (weekday == null || weekday < 1 || weekday > 7) {
      issues.add(Issue('星期「${cell('星期')}」无效（应为 1-7）', line: lineNo));
      return null;
    }
    if (startPeriod == null || startPeriod < 1) {
      issues.add(Issue('起始节「${cell('起始节')}」无效', line: lineNo));
      return null;
    }
    if (endPeriod == null || endPeriod < startPeriod) {
      issues.add(Issue('结束节「${cell('结束节')}」无效（应 ≥ 起始节）', line: lineNo));
      return null;
    }

    final startWeek = int.tryParse(cell('起始周'));
    final endWeek = int.tryParse(cell('结束周'));
    if (startWeek == null || startWeek < 1 || startWeek > 60) {
      issues.add(Issue('起始周「${cell('起始周')}」无效（应为 1-60）', line: lineNo));
      return null;
    }
    if (endWeek == null || endWeek < startWeek || endWeek > 60) {
      issues.add(Issue('结束周「${cell('结束周')}」无效（应 ≥ 起始周且 ≤ 60）', line: lineNo));
      return null;
    }

    final weekType = weekTypeFromCode(cell('周类型'));
    if (weekType == null) {
      issues.add(Issue('周类型「${cell('周类型')}」无效（应为 空/单/双）', line: lineNo));
      return null;
    }

    final color = cell('颜色');
    if (color.isNotEmpty && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      issues.add(Issue('颜色「$color」无效（应为 #RRGGBB）', line: lineNo));
      return null;
    }

    // ★ 用现有序列化器产出标准行，不手工拼字段（避免第二套格式真相）
    return baseCourseToLine(BaseCourse(
      name: name,
      type: type,
      teacher: cell('教师'),
      room: cell('教室'),
      weekday: weekday,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      startWeek: startWeek,
      endWeek: endWeek,
      weekType: weekType,
      color: color,
      remark: cell('备注'),
    ));
  }

  // ---------------- 补丁 ----------------

  static String? _patchLine(
    String Function(String) cell,
    int lineNo,
    List<Issue> issues,
  ) {
    final locationType = patchLocationTypeFromCode(cell('定位类型'));
    if (locationType == null) {
      issues.add(Issue(
        '定位类型「${cell('定位类型')}」无效（应为 weekOffset 或 exactDate）',
        line: lineNo,
      ));
      return null;
    }

    final locationValue = cell('定位值');
    if (locationValue.isEmpty) {
      issues.add(Issue('定位值不能为空（周号或日期）', line: lineNo));
      return null;
    }

    final action = patchActionFromCode(cell('操作'));
    if (action == null) {
      issues.add(Issue(
        '操作「${cell('操作')}」无效（应为 add/replace/remove/modify）',
        line: lineNo,
      ));
      return null;
    }

    final weekday = int.tryParse(cell('星期'));
    final startPeriod = int.tryParse(cell('起始节'));
    final endPeriod = int.tryParse(cell('结束节'));
    if (weekday == null || weekday < 1 || weekday > 7) {
      issues.add(Issue('星期「${cell('星期')}」无效（应为 1-7）', line: lineNo));
      return null;
    }
    if (startPeriod == null || startPeriod < 1 || endPeriod == null || endPeriod < startPeriod) {
      issues.add(Issue('节次区间无效（结束节应 ≥ 起始节）', line: lineNo));
      return null;
    }

    final weekType = weekTypeFromCode(cell('周类型'));
    if (weekType == null) {
      issues.add(Issue('周类型「${cell('周类型')}」无效（应为 空/单/双）', line: lineNo));
      return null;
    }

    final symbol = cell('类型');
    final type = symbol.isEmpty ? null : courseTypeFromSymbol(symbol);
    if (symbol.isNotEmpty && type == null) {
      issues.add(Issue('类型「$symbol」无效（应为 ☆/★/○/●）', line: lineNo));
      return null;
    }

    final color = cell('颜色');
    if (color.isNotEmpty && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      issues.add(Issue('颜色「$color」无效（应为 #RRGGBB）', line: lineNo));
      return null;
    }

    // remove 允许课程名为空（与标准格式一致）
    return patchToLine(Patch(
      locationType: locationType,
      locationValue: locationValue,
      weekday: weekday,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      weekType: weekType,
      action: action,
      name: cell('课程名称'),
      type: type,
      teacher: cell('教师'),
      room: cell('教室'),
      color: color,
      expireDate: cell('过期日期'),
      remark: cell('备注'),
    ));
  }

  // ---------------- CSV 行拆分 ----------------

  /// 拆一行 CSV：支持字段用双引号包裹、内部 `""` 表示一个双引号。
  /// 说明：不支持字段内含换行（模板与 Skill 均要求 AI 不要产生换行）。
  static List<String> _splitCsvLine(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == ',') {
          out.add(buf.toString());
          buf.clear();
        } else {
          buf.write(ch);
        }
      }
    }
    out.add(buf.toString());
    return out;
  }
}
