/// 日期工具：多格式容错解析 + 真实日期校验 + 中文数字转换
/// 覆盖：YYYY-M-D / YYYY/M/D / YYYY.M.D / YY-M-D / YYYY年M月D日 / 中文数字年月日
library;

/// 中文数字 → 数字（0-9 逐位、十位组合）
const Map<String, int?> _cnDigits = {
  '零': 0, '〇': 0, '○': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
  '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
};

/// 中文数字串 → 整数（支持 一~九十九）；无法识别返回 null
int? chineseToInt(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  // 纯数字
  final n = int.tryParse(t);
  if (n != null) return n;
  // 含中文数字
  int? result;
  if (t.contains('十')) {
    final parts = t.split('十');
    final tens = parts[0].isEmpty ? 1 : _cnDigits[parts[0]];
    final ones = parts.length > 1 && parts[1].isNotEmpty ? _cnDigits[parts[1]] : 0;
    if (tens == null || ones == null) return null;
    result = tens * 10 + ones;
  } else {
    // 逐位（用于年份：二零二六）
    int? acc;
    for (final ch in t.split('')) {
      final d = _cnDigits[ch];
      if (d == null) return null;
      acc = (acc ?? 0) * 10 + d;
    }
    result = acc;
  }
  return result;
}

/// 校验真实日期（月天数 + 闰年，拒绝 2 月 30 日等非法日期）
bool isRealDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1) return false;
  final daysInMonth = <int>[31, _leapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= daysInMonth[month - 1];
}

bool _leapYear(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

/// 格式化日期为 YYYY-MM-DD（系统标准格式）
String formatDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// 多格式日期解析 → DateTime（标准化为 YYYY-MM-DD 语义）；无法解析返回 null
DateTime? parseFlexibleDate(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;

  DateTime? tryParse(int? Function(String) numFn, String year, String month, String day) {
    final y = numFn(year);
    final m = numFn(month);
    final d = numFn(day);
    if (y == null || m == null || d == null) return null;
    // 两位年份 → 2000 后
    final fullYear = y < 100 ? y + 2000 : y;
    if (!isRealDate(fullYear, m, d)) return null;
    return DateTime(fullYear, m, d);
  }

  // 1) 分隔符格式：YYYY-M-D / YYYY/M/D / YYYY.M.D / YY-M-D
  final sep = RegExp(r'^(\d{2,4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(s);
  if (sep != null) {
    final r = tryParse(
      (x) => int.tryParse(x) ?? (chineseToInt(x) ?? -1),
      sep.group(1)!,
      sep.group(2)!,
      sep.group(3)!,
    );
    if (r != null) return r;
  }

  // 2) 中文年月日：YYYY年M月D日 / 二〇二六年八月十六日（可混合）
  final cn = RegExp(r'^(\S+?)[年](.+?)[月](.+?)[日]$').firstMatch(s);
  if (cn != null) {
    final r = tryParse(chineseToInt, cn.group(1)!, cn.group(2)!, cn.group(3)!);
    if (r != null) return r;
  }

  // 3) 纯标准格式兜底（严格正则：防 DateTime.tryParse 把 2月30日 自动进位成 3月2日）
  final std = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
  if (std != null) {
    final y = int.tryParse(std.group(1)!);
    final m = int.tryParse(std.group(2)!);
    final d = int.tryParse(std.group(3)!);
    if (y != null && m != null && d != null && isRealDate(y, m, d)) {
      return DateTime(y, m, d);
    }
  }

  return null;
}
