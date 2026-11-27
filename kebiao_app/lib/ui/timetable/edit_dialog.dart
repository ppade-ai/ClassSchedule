/// 单节编辑（模式 A）：底部抽屉表单，双表单（补丁/长期）
/// v0.11 UX 优化：showModalBottomSheet 全屏滚动表单，错误走 SnackBar 可见；
/// 补丁表单默认（临时调课最多），可切换长期表单（基础课编辑）
library;

import 'package:flutter/material.dart';

import '../../core/model/base_course.dart';
import '../../core/model/enums.dart';
import '../../core/model/patch.dart';
import '../../core/parse/base_parser.dart';
import '../../core/parse/patch_parser.dart';

/// 返回编辑结果：null=取消；非 null 含补丁或基础课
class EditResult {
  final Patch? patch;
  final BaseCourse? baseCourse;
  final bool isBase;

  const EditResult.patch(Patch p)
      : patch = p,
        baseCourse = null,
        isBase = false;
  const EditResult.base(BaseCourse c)
      : patch = null,
        baseCourse = c,
        isBase = true;
}

/// 弹出编辑抽屉；[baseInitial] 非空 = 长期表单（学期修改），否则补丁表单
Future<EditResult?> showEditSheet(
  BuildContext context, {
  Patch? patchInitial,
  BaseCourse? baseInitial,
  int currentWeek = 1,
  int? prefillWeekday,
  int? prefillStartPeriod,
  int? prefillEndPeriod,
  String? prefillName,
}) {
  return showModalBottomSheet<EditResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EditSheet(
      patchInitial: patchInitial,
      baseInitial: baseInitial,
      currentWeek: currentWeek,
      prefillWeekday: prefillWeekday,
      prefillStartPeriod: prefillStartPeriod,
      prefillEndPeriod: prefillEndPeriod,
      prefillName: prefillName,
    ),
  );
}

class _EditSheet extends StatefulWidget {
  final Patch? patchInitial;
  final BaseCourse? baseInitial;
  final int currentWeek;
  final int? prefillWeekday;
  final int? prefillStartPeriod;
  final int? prefillEndPeriod;
  final String? prefillName;

  const _EditSheet({
    required this.patchInitial,
    required this.baseInitial,
    required this.currentWeek,
    this.prefillWeekday,
    this.prefillStartPeriod,
    this.prefillEndPeriod,
    this.prefillName,
  });

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late bool _isBase; // 长期表单（基础课） / 补丁表单
  late bool _isExactDate;
  late TextEditingController _locValue;
  late int _weekday;
  late int _startPeriod;
  late int _endPeriod;
  late PatchAction _action;
  late TextEditingController _name;
  late CourseType _type;
  late TextEditingController _teacher;
  late TextEditingController _room;
  late TextEditingController _color;
  late TextEditingController _expire;
  late TextEditingController _remark;
  late int _startWeek;
  late int _endWeek;
  late WeekType _weekType;

  static const _weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  void initState() {
    super.initState();
    final p = widget.patchInitial;
    final b = widget.baseInitial;
    _isBase = b != null;
    _isExactDate = p?.locationType == PatchLocationType.exactDate;
    _locValue = TextEditingController(
      text: p?.locationValue ?? '${widget.currentWeek}',
    );
    _weekday = b?.weekday ?? p?.weekday ?? widget.prefillWeekday ?? 1;
    _startPeriod = b?.startPeriod ?? p?.startPeriod ?? widget.prefillStartPeriod ?? 1;
    _endPeriod = b?.endPeriod ?? p?.endPeriod ?? widget.prefillEndPeriod ?? 2;
    _action = p?.action ?? PatchAction.add;
    _name = TextEditingController(text: b?.name ?? p?.name ?? widget.prefillName ?? '');
    _type = b?.type ?? p?.type ?? CourseType.lecture;
    _teacher = TextEditingController(text: b?.teacher ?? p?.teacher ?? '');
    _room = TextEditingController(text: b?.room ?? p?.room ?? '');
    _color = TextEditingController(text: b?.color ?? p?.color ?? '');
    _expire = TextEditingController(text: p?.expireDate ?? '');
    _remark = TextEditingController(text: b?.remark ?? p?.remark ?? '');
    _startWeek = b?.startWeek ?? 1;
    _endWeek = b?.endWeek ?? widget.currentWeek;
    _weekType = b?.weekType ?? WeekType.every;
  }

  @override
  void dispose() {
    _locValue.dispose();
    _name.dispose();
    _teacher.dispose();
    _room.dispose();
    _color.dispose();
    _expire.dispose();
    _remark.dispose();
    super.dispose();
  }

  void _submit() {
    if (_isBase) {
      final c = BaseCourse(
        name: _name.text.trim(),
        type: _type,
        teacher: _teacher.text.trim(),
        room: _room.text.trim(),
        weekday: _weekday,
        startPeriod: _startPeriod,
        endPeriod: _endPeriod,
        startWeek: _startWeek,
        endWeek: _endWeek,
        weekType: _weekType,
        color: _color.text.trim(),
        remark: _remark.text.trim(),
        id: widget.baseInitial?.id,
      );
      final r = parseBaseLine(baseCourseToLine(c));
      if (!r.ok) {
        _showError(r.issues.first.message);
        return;
      }
      Navigator.pop(context, EditResult.base(r.value!));
      return;
    }

    final patch = Patch(
      locationType: _isExactDate ? PatchLocationType.exactDate : PatchLocationType.weekOffset,
      locationValue: _locValue.text.trim(),
      weekday: _weekday,
      startPeriod: _startPeriod,
      endPeriod: _endPeriod,
      weekType: WeekType.every,
      action: _action,
      name: _name.text.trim(),
      type: _type,
      teacher: _teacher.text.trim(),
      room: _room.text.trim(),
      color: _color.text.trim(),
      expireDate: _expire.text.trim(),
      remark: _remark.text.trim(),
      id: widget.patchInitial?.id,
    );
    final r = parsePatchLine(patchToLine(patch));
    if (!r.ok) {
      _showError(r.issues.first.message);
      return;
    }
    Navigator.pop(context, EditResult.patch(r.value!));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.baseInitial != null
                        ? '编辑基础课（整学期生效）'
                        : (widget.patchInitial != null ? '编辑补丁' : '新增 / 临时调整'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              if (!_isBase) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('按周序号')),
                    ButtonSegment(value: true, label: Text('精确日期')),
                  ],
                  selected: {_isExactDate},
                  onSelectionChanged: (s) => setState(() {
                    _isExactDate = s.first;
                    _locValue.text = _isExactDate ? _fmtToday() : '${widget.currentWeek}';
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _locValue,
                  keyboardType: _isExactDate ? TextInputType.datetime : TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _isExactDate ? '日期（如 2026-08-20）' : '周序号',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<PatchAction>(
                  initialValue: _action,
                  isDense: true,
                  decoration: const InputDecoration(labelText: '操作', border: OutlineInputBorder()),
                  items: [
                    for (final a in PatchAction.values)
                      DropdownMenuItem(value: a, child: Text(a.label)),
                  ],
                  onChanged: (v) => setState(() => _action = v ?? PatchAction.add),
                ),
                const SizedBox(height: 8),
              ],
              if (_isBase) ...[
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: '$_startWeek'),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '起始周', isDense: true, border: OutlineInputBorder()),
                      onChanged: (v) => _startWeek = int.tryParse(v) ?? 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: '$_endWeek'),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '结束周', isDense: true, border: OutlineInputBorder()),
                      onChanged: (v) => _endWeek = int.tryParse(v) ?? 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<WeekType>(
                      initialValue: _weekType,
                      isDense: true,
                      decoration: const InputDecoration(labelText: '周类型', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: WeekType.every, child: Text('每周')),
                        DropdownMenuItem(value: WeekType.odd, child: Text('单周')),
                        DropdownMenuItem(value: WeekType.even, child: Text('双周')),
                      ],
                      onChanged: (v) => setState(() => _weekType = v ?? WeekType.every),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _weekday,
                    isDense: true,
                    decoration: const InputDecoration(labelText: '星期', border: OutlineInputBorder()),
                    items: [
                      for (var i = 1; i <= 7; i++)
                        DropdownMenuItem(value: i, child: Text(_weekdayNames[i])),
                    ],
                    onChanged: (v) => setState(() => _weekday = v ?? 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _startPeriod,
                    isDense: true,
                    decoration: const InputDecoration(labelText: '起始节', border: OutlineInputBorder()),
                    items: [for (var i = 1; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                    onChanged: (v) => setState(() => _startPeriod = v ?? 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _endPeriod,
                    isDense: true,
                    decoration: const InputDecoration(labelText: '结束节', border: OutlineInputBorder()),
                    items: [for (var i = 1; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                    onChanged: (v) => setState(() => _endPeriod = v ?? 2),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (_action != PatchAction.remove || _isBase) ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: '课程名称', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<CourseType>(
                  initialValue: _type,
                  isDense: true,
                  decoration: const InputDecoration(labelText: '类型', border: OutlineInputBorder()),
                  items: [
                    for (final t in CourseType.values)
                      DropdownMenuItem(value: t, child: Text('${t.symbol} ${t.label}')),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? CourseType.lecture),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _teacher,
                  decoration: const InputDecoration(labelText: '教师', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _room,
                  decoration: const InputDecoration(labelText: '教室', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _color,
                  decoration: const InputDecoration(
                    labelText: '颜色（#RRGGBB，留空自动分配）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (!_isBase) ...[
                TextField(
                  controller: _expire,
                  decoration: const InputDecoration(
                    labelText: '过期日期（可空 = 不过期）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _remark,
                decoration: const InputDecoration(labelText: '备注', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtToday() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }
}
