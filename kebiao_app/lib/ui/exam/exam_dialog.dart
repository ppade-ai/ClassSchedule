/// 考试 / 便签的录入：单条表单 + 表格批量导入
///
/// 特点：只认日期，不问周次。用户手上只有"11月25日 14:00-16:00 教3101"
/// 这种信息，不该先让他换算成第几周。
library;

import 'package:flutter/material.dart';

import '../../core/model/exam_note.dart';
import '../../core/parse/exam_parser.dart' show isValidHhmm, normalizeHhmm;
import '../../core/parse/exam_table.dart';
import '../../core/validate/issues.dart';
import '../timetable/timetable_controller.dart';

const String _template =
    '日期,科目,时间,地点\n'
    '2026-11-25,高等数学,14:00-16:00,教3101\n'
    '11月27日,大学物理,09:00-11:00,教2205\n';

/// 单条新增 / 编辑
Future<void> showExamEditDialog(
  BuildContext context,
  TimetableController c, {
  ExamNote? note,
}) async {
  DateTime date = note?.date ?? _today();
  final subject = TextEditingController(text: note?.subject ?? '');
  final start = TextEditingController(text: note?.startTime ?? '');
  final end = TextEditingController(text: note?.endTime ?? '');
  final place = TextEditingController(text: note?.place ?? '');
  final remark = TextEditingController(text: note?.remark ?? '');
  String? error;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(note == null ? '添加考试 / 便签' : '编辑考试 / 便签'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => date = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '日期',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    child: Text('${_fmt(date)} ${_weekday(date)}'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: subject,
                  decoration: const InputDecoration(
                    labelText: '科目 / 标题（必填）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: start,
                        decoration: const InputDecoration(
                          labelText: '开始 HH:mm',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: end,
                        decoration: const InputDecoration(
                          labelText: '结束 HH:mm',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: place,
                  decoration: const InputDecoration(
                    labelText: '地点 / 考场',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: remark,
                  decoration: const InputDecoration(
                    labelText: '备注（座位号、准考证号…）',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final s = subject.text.trim();
              if (s.isEmpty) {
                setState(() => error = '科目不能为空');
                return;
              }
              final st = start.text.trim();
              final et = end.text.trim();
              if (st.isNotEmpty && !isValidHhmm(st)) {
                setState(() => error = '开始时间格式应为 HH:mm，如 14:00');
                return;
              }
              if (et.isNotEmpty && !isValidHhmm(et)) {
                setState(() => error = '结束时间格式应为 HH:mm，如 16:00');
                return;
              }
              final note2 = ExamNote(
                date: date,
                subject: s,
                startTime: st.isEmpty ? '' : normalizeHhmm(st),
                endTime: et.isEmpty ? '' : normalizeHhmm(et),
                place: place.text.trim(),
                remark: remark.text.trim(),
                id: note?.id,
              );
              Navigator.pop(ctx);
              c.saveExam(note2);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

/// 批量粘贴表格
Future<void> showExamImportDialog(
  BuildContext context,
  TimetableController c,
) async {
  final text = TextEditingController();
  ExamImportResult? result;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void reparse() {
          final input = text.text.trim();
          if (input.isEmpty) {
            setState(() {
              result = null;
              error = null;
            });
            return;
          }
          final r = parseExamTable(input, reference: c.baseMonday);
          setState(() {
            result = r;
            error = r.notes.isEmpty ? '没有解析出任何一行，检查一下分隔符与日期格式' : null;
          });
        }

        final notes = result?.notes ?? const <ExamNote>[];
        final issues = result?.issues ?? const <Issue>[];

        return AlertDialog(
          title: const Text('粘贴考试表格'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '从 Excel / 教务系统直接复制粘贴。支持逗号、制表符、全角逗号、'
                    '连续空格分隔；日期可以是 2026-11-25、11/25 或 11月25日（缺年份按学期推断）。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.description_outlined, size: 16),
                        label: const Text('插入模板'),
                        onPressed: () {
                          text.text = _template;
                          reparse();
                        },
                      ),
                      const Spacer(),
                      Text(
                        '${notes.length} 条 · ${issues.length} 行有问题',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  TextField(
                    controller: text,
                    minLines: 6,
                    maxLines: 12,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '日期,科目,时间,地点',
                    ),
                    onChanged: (_) => reparse(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12.5),
                    ),
                  ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '将写入：',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final e in notes.take(6))
                      Text(
                        '${e.dateText} ${e.weekdayText}  ${e.subject}  ${e.timeText}  ${e.place}',
                        style: const TextStyle(fontSize: 12, height: 1.5),
                      ),
                    if (notes.length > 6)
                      Text(
                        '…共 ${notes.length} 条',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                  if (issues.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '有 ${issues.length} 行没解析出来：',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                    for (final i in issues.take(4))
                      Text(
                        '第${i.line}行：${i.message}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.orange,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: notes.isEmpty
                  ? null
                  : () async {
                      final n = await c.appendExams(notes);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('已添加 $n 条考试便签')));
                    },
              child: Text('写入 ${notes.length} 条'),
            ),
          ],
        );
      },
    ),
  );
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _weekday(DateTime d) => '周${ExamNote.weekdayNames[d.weekday - 1]}';
