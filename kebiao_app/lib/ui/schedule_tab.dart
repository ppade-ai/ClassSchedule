/// 日程 Tab：考试便签（按日期）+ 今日课程（按作息时间分段）
///
/// 考试只认日期，不依赖"第几周"——用户手上通常只有"11月25日 14:00"这种信息。
library;

import 'package:flutter/material.dart';

import '../core/model/exam_note.dart';
import '../core/model/week_course.dart';
import 'exam/exam_dialog.dart';
import 'timetable/timetable_controller.dart';

class ScheduleTab extends StatelessWidget {
  final TimetableController controller;

  const ScheduleTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (!controller.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final now = DateTime.now();
          final todayWeekday = now.weekday; // 1=周一，与数据同口径
          final todayCourses = controller.courses
              .where((c) => c.weekday == todayWeekday && !c.inactive)
              .toList();

          final nowMin = now.hour * 60 + now.minute;
          String section(WeekCourse c) {
            final times = controller.periodTimes;
            final start = c.startPeriod <= times.length
                ? times[c.startPeriod - 1].startMinutes
                : 0;
            final end = c.endPeriod <= times.length
                ? times[c.endPeriod - 1].endMinutes
                : start;
            if (nowMin >= end) return '已过';
            if (nowMin >= start) return '进行中';
            return '即将';
          }

          final groups = <String, List<WeekCourse>>{
            '进行中': [],
            '即将': [],
            '已过': [],
          };
          for (final c in todayCourses) {
            groups[section(c)]!.add(c);
          }
          const order = ['进行中', '即将', '已过'];
          final exams = controller.examsByDate;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _examHeader(context),
              if (exams.isEmpty)
                Card(
                  margin: const EdgeInsets.only(top: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '还没有考试信息。点右上「粘贴表格」把教务的表粘进来，'
                      '或点「＋」单条添加——只需要日期，不用算周次。',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              for (final e in exams) _examTile(context, e),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              Text(
                '今日课程 ${now.month}月${now.day}日',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (todayCourses.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: Text('今天没有课 🎉')),
                ),
              for (final key in order)
                if (groups[key]!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 6),
                    child: Text(
                      key,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: key == '进行中'
                            ? Colors.green
                            : Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final c in groups[key]!) _courseTile(context, c),
                ],
            ],
          );
        },
      ),
    );
  }

  Widget _examHeader(BuildContext context) {
    return Row(
      children: [
        const Text(
          '考试 / 便签',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        IconButton(
          tooltip: '添加考试',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => showExamEditDialog(context, controller),
        ),
        IconButton(
          tooltip: '粘贴表格',
          icon: const Icon(Icons.table_chart_outlined),
          onPressed: () => showExamImportDialog(context, controller),
        ),
      ],
    );
  }

  Widget _examTile(BuildContext context, ExamNote e) {
    final days = e.daysFrom(DateTime.now());
    final week = controller.weekOf(e.date);
    final weekText = week == null ? '学期外' : '第$week周';
    final (label, color) = switch (days) {
      < 0 => ('已过', Colors.grey),
      0 => ('今天', Colors.red),
      1 => ('明天', Colors.orange.shade800),
      < 7 => ('$days 天后', Colors.orange.shade700),
      _ => ('$days 天后', Colors.grey.shade600),
    };
    final passed = days < 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${e.date.month}/${e.date.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: passed ? Colors.grey : null,
              ),
            ),
            Text(
              e.weekdayText,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
            ),
          ],
        ),
        title: Text(
          e.subject,
          style: TextStyle(fontSize: 14.5, color: passed ? Colors.grey : null),
        ),
        subtitle: Text(
          [
            weekText,
            if (e.timeText.isNotEmpty) e.timeText,
            if (e.place.isNotEmpty) e.place,
            if (e.remark.isNotEmpty) e.remark,
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        onTap: () => showExamEditDialog(context, controller, note: e),
        onLongPress: () => _confirmDeleteExam(context, e),
      ),
    );
  }

  Future<void> _confirmDeleteExam(BuildContext context, ExamNote e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条便签？'),
        content: Text('${e.dateText} ${e.weekdayText} ${e.subject}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.deleteExam(e.id);
  }

  Widget _courseTile(BuildContext context, WeekCourse c) {
    final times = controller.periodTimes;
    final time = c.startPeriod <= times.length
        ? times[c.startPeriod - 1].start
        : '';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        leading: Text(
          time,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        title: Text(c.name, style: const TextStyle(fontSize: 14.5)),
        subtitle: Text(
          [
            if (c.room.isNotEmpty) c.room,
            if (c.teacher.isNotEmpty) c.teacher,
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text(
          '第${c.startPeriod}-${c.endPeriod}节',
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}
