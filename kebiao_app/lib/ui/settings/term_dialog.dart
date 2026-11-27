/// 学期设置：第 1 周周一 + 总周数
library;

import 'package:flutter/material.dart';

import '../timetable/timetable_controller.dart';

Future<void> showTermDialog(BuildContext context, TimetableController c) async {
  var monday = c.baseMonday;
  final weeksCtrl = TextEditingController(text: '${c.totalWeeks}');

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('学期设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('第1周周一（基准日期）：', style: TextStyle(fontSize: 13.5)),
            const SizedBox(height: 6),
            FilledButton.tonalIcon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: monday,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (d != null) setDialogState(() => monday = d);
              },
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text(
                '${monday.year}-${monday.month.toString().padLeft(2, '0')}'
                '-${monday.day.toString().padLeft(2, '0')}',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weeksCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '总周数（1-60）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '提示：导入课表前请先确认第1周周一日期，否则周次与公历日期会错位。',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final tw = int.tryParse(weeksCtrl.text.trim());
              if (tw != null && tw >= 1 && tw <= 60) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text('总周数无效（应为 1-60）')));
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );

  if (ok == true) {
    await c.saveTerm(
      baseMonday: monday,
      totalWeeks: int.parse(weeksCtrl.text.trim()),
    );
  }
}
