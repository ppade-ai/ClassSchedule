/// M1 演示数据：课时配置、调色板、演示补丁/单周课
/// 正式版由 time_config.ini + `schools/<学校ID>/` 文件提供（M2/M3 接上）
library;

import '../../core/model/enums.dart';
import '../../core/model/patch.dart';

class DemoData {
  /// 第 1 周周一（2026-08-31）
  /// 依据：教务导出文件页脚「本学期 2026-08-31 正式上课至 2027-01-17 结束，共 20 周」。
  /// 此前误用 2026-08-24（同一周几，但早了一整周）→ 所有周次显示整体偏移一周。
  static final DateTime baseMonday = DateTime(2026, 8, 31);

  /// 学期总周数
  static const int totalWeeks = 20;

  /// 课时时间（1~10 节，示例大学模板）
  static const List<String> periodTimes = [
    '08:00-08:45',
    '08:50-09:35',
    '09:50-10:35',
    '10:40-11:25',
    '14:00-14:45',
    '14:50-15:35',
    '16:00-16:45',
    '16:50-17:35',
    '19:00-19:45',
    '19:50-20:35',
  ];

  /// 每节开始时间（分钟，用于日程 Tab 的 已过/进行中/即将）
  static const List<int> periodStartMinutes = [
    8 * 60,
    8 * 60 + 50,
    9 * 60 + 50,
    10 * 60 + 40,
    14 * 60,
    14 * 60 + 50,
    16 * 60,
    16 * 60 + 50,
    19 * 60,
    19 * 60 + 50,
  ];

  /// 每节上课时间（左列第一行，如 08:00）
  static final List<String> periodStartTimes =
      periodTimes.map((t) => t.split('-')[0]).toList();

  /// 每节下课时间（左列第二行，如 08:45）
  static final List<String> periodEndTimes =
      periodTimes.map((t) => t.split('-')[1]).toList();

  /// 时段分组：名称 → 起止节次（PDF 实测：上午 1-4 / 下午 5-8 / 晚上 9-10）
  static const List<(String, int, int)> periodGroups = [
    ('上午', 1, 4),
    ('下午', 5, 8),
    ('晚上', 9, 10),
  ];

  /// 课程默认调色板（PDF 无颜色 → 按课程名哈希取色）
  static const List<String> palette = [
    '#ff9494', '#ffb86b', '#ffe066', '#a8e6cf', '#8ecae6', '#b8a9e9',
    '#f4a7b9', '#7fd8be', '#f6c177', '#6ab0de', '#b5e48c', '#e9a8c9',
  ];

  /// 按课程名稳定取色
  static String colorFor(String name) {
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }

  /// 第 [week] 周星期 [weekday]（1=周一…7=周日）的日期，格式 YYYY-MM-DD。
  /// 演示用的 exactDate 补丁一律由此推导 —— 不硬编码绝对日期，
  /// 否则一旦校准学期基准日，补丁会"悄悄跳到别的周"（2026-10 校准基准日时已真实发生过）。
  static String dateOf(int week, int weekday) {
    final d = baseMonday.add(Duration(days: (week - 1) * 7 + (weekday - 1)));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// 演示补丁：weekOffset add（第 4 周 周三 5-6 实验室安全讲座）
  static Patch get demoPatchAdd => const Patch(
        locationType: PatchLocationType.weekOffset,
        locationValue: '4',
        weekday: 3,
        startPeriod: 5,
        endPeriod: 6,
        action: PatchAction.add,
        name: '实验室安全讲座',
        type: CourseType.lab,
        teacher: '王教授',
        room: '实验楼',
        color: '#ff9800',
        remark: '带护目镜',
        id: 9001,
      );

  /// 演示补丁：exactDate replace（第 2 周 周二 1-2 节 概率论 → 高数答疑）
  static Patch get demoPatchReplace => Patch(
        locationType: PatchLocationType.exactDate,
        locationValue: dateOf(2, 2),
        weekday: 2,
        startPeriod: 1,
        endPeriod: 2,
        action: PatchAction.replace,
        name: '高等数学答疑',
        type: CourseType.lecture,
        teacher: '助教老师',
        room: '教学楼A101',
        color: '#4caf50',
        remark: '只此一次',
        id: 9002,
      );

  /// 演示补丁：exactDate remove（第 2 周 周四 3-4 停课）
  static Patch get demoPatchRemove => Patch(
        locationType: PatchLocationType.exactDate,
        locationValue: dateOf(2, 4),
        weekday: 4,
        startPeriod: 3,
        endPeriod: 4,
        action: PatchAction.remove,
        name: '',
        remark: '停课一次',
        id: 9003,
      );

  static List<Patch> get demoPatches => [
        demoPatchAdd,
        demoPatchReplace,
        demoPatchRemove,
      ];
}
