/// 作息时间编辑（学校之间不固定：8:00 还是 8:20、课间 5 分还是 15 分）
///
/// 交互（v0.19.4）：
/// - 整页编辑，不再挤在窄弹窗里
/// - 每节的上课/下课时间是大按钮，点开**表盘式时间选择器**（不用敲键盘）
/// - **课间并进每一节的卡片**：不需要在"按节次/按课间"之间切换。
///   每张卡底下就是"这一节到下一节之间的课间"，改它 → 后面各节整段顺延、时长不变。
library;

import 'package:flutter/material.dart';

import '../../core/model/period_time.dart';
import '../demo/demo_data.dart';
import 'timetable_controller.dart';

Future<void> openPeriodTimesEditor(
  BuildContext context,
  TimetableController c,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => _PeriodTimesPage(controller: c)),
  );
}

class _PeriodTimesPage extends StatefulWidget {
  final TimetableController controller;

  const _PeriodTimesPage({required this.controller});

  @override
  State<_PeriodTimesPage> createState() => _PeriodTimesPageState();
}

class _PeriodTimesPageState extends State<_PeriodTimesPage> {
  late List<PeriodTime> _times = [...widget.controller.periodTimes];

  String? _error;

  TimetableController get c => widget.controller;

  // ---------------- 编辑逻辑 ----------------

  void _setStart(int i, TimeOfDay t) {
    final duration = _times[i].endMinutes - _times[i].startMinutes;
    final start = t.hour * 60 + t.minute;
    final p = _make(start, start + duration);
    if (p == null) {
      setState(() => _error = '第${i + 1}节改完会跨过零点，请改小一点的时长');
      return;
    }
    setState(() {
      _times[i] = p;
      _error = null;
    });
  }

  void _setEnd(int i, TimeOfDay t) {
    final end = t.hour * 60 + t.minute;
    final p = _make(_times[i].startMinutes, end);
    if (p == null) {
      setState(() => _error = '下课时间必须晚于上课时间');
      return;
    }
    setState(() {
      _times[i] = p;
      _error = null;
    });
  }

  /// 改第 [i] 节与第 [i+1] 节之间的课间：后面各节整段顺延，时长不变
  void _setBreak(int i, int minutes) {
    final current = PeriodTime.breakMinutes(_times[i], _times[i + 1]);
    final delta = minutes - current;
    if (delta == 0) return;

    final next = <PeriodTime>[];
    for (var j = 0; j < _times.length; j++) {
      if (j <= i) {
        next.add(_times[j]);
        continue;
      }
      final p = _make(
        _times[j].startMinutes + delta,
        _times[j].endMinutes + delta,
      );
      if (p == null) {
        setState(() => _error = '顺延后超出当天范围，请把课间改小');
        return;
      }
      next.add(p);
    }
    setState(() {
      _times = next;
      _error = null;
    });
  }

  PeriodTime? _make(int startMin, int endMin) {
    if (startMin < 0 || endMin > 24 * 60 || endMin <= startMin) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    return PeriodTime(
      '${two(startMin ~/ 60)}:${two(startMin % 60)}',
      '${two(endMin ~/ 60)}:${two(endMin % 60)}',
    );
  }

  Future<void> _pick(int i, {required bool isStart}) async {
    final p = _times[i];
    final initial = _toTimeOfDay(isStart ? p.start : p.end);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: '第${i + 1}节 · 选择${isStart ? '上课' : '下课'}时间',
      // 把选择器放大一点：小屏上更好点
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: const TextScaler.linear(1.15)),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    if (isStart) {
      _setStart(i, picked);
    } else {
      _setEnd(i, picked);
    }
  }

  Future<void> _pickBreak(int i) async {
    final current = PeriodTime.breakMinutes(_times[i], _times[i + 1]);
    final ctrl = TextEditingController(text: '$current');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('第${i + 1}节与第${i + 2}节之间的课间'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final m in [0, 5, 10, 15, 20, 30])
                  ChoiceChip(
                    label: Text('$m 分钟'),
                    selected: current == m,
                    onSelected: (_) => Navigator.pop(ctx, m),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '自定义分钟数',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '修改后，第${i + 2}节及以后各节整段顺延，每节时长不变。',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, v == null || v < 0 || v > 240 ? current : v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    _setBreak(i, result);
  }

  void _restoreDefaults() {
    setState(() {
      _times = [
        for (final p in DemoData.periodTimes)
          if (PeriodTime.tryParse(p) != null) PeriodTime.tryParse(p)!,
      ];
      _error = null;
    });
  }

  Future<void> _save() async {
    for (var i = 1; i < _times.length; i++) {
      if (_times[i].startMinutes < _times[i - 1].endMinutes) {
        setState(() => _error = '第${i + 1}节与第$i节时间重叠，请调整');
        return;
      }
    }
    await c.savePeriodTimes(_times);
    if (!mounted) return;
    if (c.storageError != null) {
      setState(() => _error = c.storageError);
      return;
    }
    Navigator.pop(context);
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('作息时间'),
        actions: [
          TextButton(onPressed: _restoreDefaults, child: const Text('恢复默认')),
          const SizedBox(width: 4),
          FilledButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '点时间按钮选上课/下课时间。每节下面的「课间」是这一节到下一节之间；'
                    '改课间时，后面各节整段顺延、每节时长不变。',
                    style: TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          for (var i = 0; i < _times.length; i++) _periodCard(i),
        ],
      ),
    );
  }

  Widget _periodCard(int i) {
    final p = _times[i];
    final duration = p.endMinutes - p.startMinutes;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '第${i + 1}节',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$duration 分钟',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    label: '上课',
                    time: p.start,
                    onTap: () => _pick(i, isStart: true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                Expanded(
                  child: _TimeButton(
                    label: '下课',
                    time: p.end,
                    onTap: () => _pick(i, isStart: false),
                  ),
                ),
              ],
            ),
            // 课间和这一节放在同一张卡里：改它，后面的节次整体跟着走
            if (i < _times.length - 1) _breakSection(i),
          ],
        ),
      ),
    );
  }

  /// 本卡内的课间：− / 当前分钟 / ＋ / 自定义
  Widget _breakSection(int i) {
    final gap = PeriodTime.breakMinutes(_times[i], _times[i + 1]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 18),
        Row(
          children: [
            Text(
              '课间',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            IconButton(
              tooltip: '减少课间',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: gap <= 0 ? null : () => _setBreak(i, gap - 5),
            ),
            TextButton(
              onPressed: () => _pickBreak(i),
              style: TextButton.styleFrom(
                minimumSize: const Size(72, 36),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: Text(
                '$gap 分钟',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: '增加课间',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: () => _setBreak(i, gap + 5),
            ),
            Expanded(
              child: Text(
                '后面顺延',
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 60),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            time,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

TimeOfDay _toTimeOfDay(String hhmm) {
  final parts = hhmm.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}
