/// 考试 / 便签：只有日期，不依赖学期与周次
///
/// 为什么单独一个模型：考试是"某天几点在哪"，跟课表的"第 N 周星期几第几节"
/// 是两套坐标。硬塞进补丁表会让用户先算周次，正是这次要避免的事。
library;

class ExamNote {
  /// 考试日期（时分为零，仅用于排序/倒计时）
  final DateTime date;

  /// 科目 / 标题
  final String subject;

  /// 开始时间 HH:mm（可空）
  final String startTime;

  /// 结束时间 HH:mm（可空）
  final String endTime;

  /// 地点 / 考场
  final String place;

  /// 备注
  final String remark;

  final int? id;

  const ExamNote({
    required this.date,
    required this.subject,
    this.startTime = '',
    this.endTime = '',
    this.place = '',
    this.remark = '',
    this.id,
  });

  ExamNote copyWith({
    DateTime? date,
    String? subject,
    String? startTime,
    String? endTime,
    String? place,
    String? remark,
    int? id,
  }) {
    return ExamNote(
      date: date ?? this.date,
      subject: subject ?? this.subject,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      place: place ?? this.place,
      remark: remark ?? this.remark,
      id: id ?? this.id,
    );
  }

  /// 时间区间文本（14:00-16:00 / 14:00 / 空）
  String get timeText {
    if (startTime.isEmpty) return '';
    if (endTime.isEmpty) return startTime;
    return '$startTime-$endTime';
  }

  /// 与今天相差的天数（0=今天，1=明天，负=已过）
  int daysFrom(DateTime today) {
    final a = DateTime(date.year, date.month, date.day);
    final b = DateTime(today.year, today.month, today.day);
    return a.difference(b).inDays;
  }

  String get dateText =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static const List<String> weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  String get weekdayText => '周${weekdayNames[date.weekday - 1]}';

  @override
  String toString() => '$dateText $subject $timeText $place';
}
