/// 周引擎：基准周一 + 周日期换算 + 回到本周
/// 第1周周一为基准（time_config.ini [term] 段配置）
library;

class WeekRange {
  final DateTime monday;
  final DateTime sunday;

  const WeekRange(this.monday, this.sunday);

  bool contains(DateTime d) {
    final date = DateTime(d.year, d.month, d.day);
    return !date.isBefore(monday) && !date.isAfter(sunday);
  }
}

class WeekEngine {
  final DateTime baseMonday; // 第 1 周周一（自动归一化到当天 0 点）
  final int totalWeeks; // 学期总周数（上限 60）

  WeekEngine({required DateTime baseMonday, this.totalWeeks = 20})
      : assert(totalWeeks >= 1 && totalWeeks <= 60),
        baseMonday = DateTime(baseMonday.year, baseMonday.month, baseMonday.day);

  /// 第 [week] 周周一
  DateTime mondayOf(int week) =>
      baseMonday.add(Duration(days: (week - 1) * 7));

  /// 第 [week] 周周日
  DateTime sundayOf(int week) => mondayOf(week).add(const Duration(days: 6));

  /// 第 [week] 周区间（周一~周日）
  WeekRange rangeOf(int week) => WeekRange(mondayOf(week), sundayOf(week));

  /// 现实日期 → 当前周序号；学期外（早于基准周一）返回 null
  int? currentWeek(DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    final diff = t.difference(baseMonday).inDays;
    if (diff < 0) return null;
    final w = diff ~/ 7 + 1;
    return w > totalWeeks ? null : w;
  }

  /// 周序号是否合法
  bool isValidWeek(int week) => week >= 1 && week <= totalWeeks;
}
