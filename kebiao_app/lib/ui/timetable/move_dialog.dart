/// 调课流程（M2.2）：源 → 目标格 → 范围(仅本次/整周/从第N周起/永久) → 对调 → 预览 → 执行
library;

import 'package:flutter/material.dart';

import '../../core/model/week_course.dart';
import 'timetable_controller.dart';

Future<void> showMoveFlow(
  BuildContext context, {
  required TimetableController controller,
  WeekCourse? sourceCourse,
}) async {
  // 未指定源 → 从当前周课程里选
  WeekCourse? source = sourceCourse;
  if (source == null) {
    final courses = controller.courses;
    if (courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前周没有课程可调')),
      );
      return;
    }
    source = await showDialog<WeekCourse>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择要调的课程'),
        children: [
          for (final c in courses)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: Text(
                '${c.name}（周${c.weekday} 第${c.startPeriod}-${c.endPeriod}节）',
                style: const TextStyle(fontSize: 14),
              ),
            ),
        ],
      ),
    );
    if (source == null) return;
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MoveSheet(controller: controller, source: source!),
  );
}

class _MoveSheet extends StatefulWidget {
  final TimetableController controller;
  final WeekCourse source;

  const _MoveSheet({required this.controller, required this.source});

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  int _targetWeekday = 1;
  int _targetStart = 1;
  int _targetEnd = 2;
  MoveScope _scope = MoveScope.week;
  bool _swap = false;
  final _dateCtrl = TextEditingController();
  final _fromWeekCtrl = TextEditingController();
  static const _weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  void dispose() {
    _dateCtrl.dispose();
    _fromWeekCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final c = widget.controller;
    final s = widget.source;
    await c.executeMove(
      source: s,
      targetWeekday: _targetWeekday,
      targetStart: _targetStart,
      targetEnd: _targetEnd,
      scope: _scope,
      exactDate: _scope == MoveScope.once
          ? (DateTime.tryParse(_dateCtrl.text.trim()) ?? DateTime.now())
          : null,
      fromWeek: _scope == MoveScope.longTerm
          ? (int.tryParse(_fromWeekCtrl.text.trim()) ?? c.week)
          : null,
      swap: _swap,
    );
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('调课完成')),
      );
    }
  }

  String _preview() {
    final c = widget.controller;
    final s = widget.source;
    final target = '周$_targetWeekday 第$_targetStart-$_targetEnd节';
    final sourceDesc = '${s.name}（周${s.weekday} 第${s.startPeriod}-${s.endPeriod}节）';
    switch (_scope) {
      case MoveScope.once:
        final d = _dateCtrl.text.trim().isEmpty ? '今天' : _dateCtrl.text.trim();
        return '$sourceDesc → $target（仅 $d）';
      case MoveScope.week:
        return '$sourceDesc → $target（第${c.week}周）';
      case MoveScope.longTerm:
        final n = _fromWeekCtrl.text.trim().isEmpty ? '${c.week}' : _fromWeekCtrl.text.trim();
        return '$sourceDesc → $target（从第$n周起每周）${s.source != 'base' ? '（源非基础课，退化为整周）' : ''}';
      case MoveScope.permanent:
        return '$sourceDesc → $target（永久，改基础课表）${s.source != 'base' ? '（源非基础课，退化为整周）' : ''}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = widget.source;
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('调课', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            Text('源：${s.name}（周${s.weekday} 第${s.startPeriod}-${s.endPeriod}节）',
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700)),
            const Divider(height: 20),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _targetWeekday,
                  isDense: true,
                  decoration: const InputDecoration(labelText: '目标星期', border: OutlineInputBorder()),
                  items: [
                    for (var i = 1; i <= 7; i++)
                      DropdownMenuItem(value: i, child: Text(_weekdayNames[i])),
                  ],
                  onChanged: (v) => setState(() => _targetWeekday = v ?? 1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _targetStart,
                  isDense: true,
                  decoration: const InputDecoration(labelText: '起始节', border: OutlineInputBorder()),
                  items: [for (var i = 1; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) => setState(() => _targetStart = v ?? 1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _targetEnd,
                  isDense: true,
                  decoration: const InputDecoration(labelText: '结束节', border: OutlineInputBorder()),
                  items: [for (var i = 1; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) => setState(() => _targetEnd = v ?? 2),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            const Text('范围', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            RadioGroup<MoveScope>(
              groupValue: _scope,
              onChanged: (v) => setState(() => _scope = v ?? MoveScope.week),
              child: Column(
                children: [
                  RadioListTile<MoveScope>(
                    dense: true,
                    title: const Text('仅本次（某一天）', style: TextStyle(fontSize: 13.5)),
                    value: MoveScope.once,
                  ),
                  if (_scope == MoveScope.once)
                    TextField(
                      controller: _dateCtrl,
                      decoration: const InputDecoration(
                        labelText: '日期（YYYY-MM-DD，留空=今天）',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  RadioListTile<MoveScope>(
                    dense: true,
                    title: Text('整周（第${c.week}周）', style: const TextStyle(fontSize: 13.5)),
                    value: MoveScope.week,
                  ),
                  RadioListTile<MoveScope>(
                    dense: true,
                    title: const Text('从第N周起（长期）', style: TextStyle(fontSize: 13.5)),
                    value: MoveScope.longTerm,
                  ),
                  if (_scope == MoveScope.longTerm)
                    TextField(
                      controller: _fromWeekCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '从第几周起（留空=第${c.week}周）',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  RadioListTile<MoveScope>(
                    dense: true,
                    title: const Text('永久（改基础课表）', style: TextStyle(fontSize: 13.5)),
                    value: MoveScope.permanent,
                  ),
                ],
              ),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('对调（目标格课程换到源格）', style: TextStyle(fontSize: 13.5)),
              value: _swap,
              onChanged: (v) => setState(() => _swap = v),
            ),
            const Divider(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('预览：${_preview()}', style: const TextStyle(fontSize: 12.5)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _confirm, child: const Text('确认调课')),
            ),
          ],
        ),
      ),
    );
  }
}
