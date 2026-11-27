/// 课表主页面：五层结构 + 三页横带拼页翻周 + 动态行高网格
/// v0.6 用户确认方案：
///   翻页：三页（上周|本周|下周）首尾相接成一条横带，整体平移"划出"相邻周，
///         物理不重叠 → 无重影；松手吸附并停住
///   网格：GridMetrics 内容反推行高（卡片永不重叠），宽度固定 44dp
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HapticFeedback;

import '../../core/model/base_course.dart';
import '../../core/model/enums.dart';
import '../../core/model/patch.dart';
import '../../core/model/week_course.dart';
import '../../core/parse/json_ext.dart';
import '../../core/parse/patch_parser.dart' show patchToLine;
import '../exam/exam_dialog.dart';
import 'batch_text_page.dart';
import 'drop_target.dart';
import 'dynamic_grid.dart';
import 'edit_dialog.dart';
import 'move_dialog.dart';
import 'timetable_controller.dart';

/// 布局常量（dp）
const double kLeftColWidth = 40;
const double kColWidth = 44; // 宽度固定不变（用户确定）
const double kRowHeightBase = 64; // 动态行高的最小基准（实际行高由 GridMetrics 决定）
const double kHeaderHeight = 38;
const int kPeriodCount = 10;

/// 翻页吸附阈值
const double _flipMinDist = 40;
const double _flipMinVelocity = 500;

class TimetablePage extends StatefulWidget {
  final TimetableController controller;

  const TimetablePage({super.key, required this.controller});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage>
    with TickerProviderStateMixin {
  double _dragX = 0; // 横带偏移：0=本周，-pageWidth=下周，+pageWidth=上周
  double _vOffset = 0; // 纵向偏移（各页共享，保证连续性）
  double _totalHeight = 640; // 当前周网格总高（DynamicGrid 测量后更新）
  WeekCourse? _longPressHighlight; // 长按按压反馈中的课程（缩小+变灰，v0.11.3）
  final ScrollController _stripCtrl = ScrollController(); // 横带滚动（v0.11.2）
  int? _lockAxis;
  double _totalDx = 0, _totalDy = 0;
  bool _flipping = false;
  AnimationController? _fling;
  double _pageWidth = 0, _viewportH = 0;

  TimetableController get c => widget.controller;

  @override
  void dispose() {
    _stripCtrl.dispose();
    _fling?.dispose();
    super.dispose();
  }

  /// 横带偏移同步：offset = 页宽 - dragX（0=上周页，W=本周页，2W=下周页）
  void _syncStripOffset() {
    if (!_stripCtrl.hasClients) return;
    final target = (_pageWidth - _dragX).clamp(0.0, _pageWidth * 2);
    if ((_stripCtrl.offset - target).abs() > 0.5) {
      _stripCtrl.jumpTo(target);
    }
  }

  // ---------- 手势 ----------

  void _onPanStart(DragStartDetails d) {
    if (_flipping) return;
    _lockAxis = null;
    _totalDx = 0;
    _totalDy = 0;
    _fling?.stop();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_flipping) return;
    _totalDx += d.delta.dx;
    _totalDy += d.delta.dy;
    if (_lockAxis == null) {
      if (_totalDx.abs() > 4 || _totalDy.abs() > 4) {
        _lockAxis = _totalDx.abs() > _totalDy.abs() ? 0 : 1;
      }
      return;
    }
    setState(() {
      if (_lockAxis == 0) {
        // 横带跟手（±整页），直接划出相邻周
        _dragX = _totalDx.clamp(-_pageWidth, _pageWidth);
      } else {
        _vOffset = (_vOffset + d.delta.dy).clamp(_maxV(), 0.0);
      }
    });
    if (_lockAxis == 0) _syncStripOffset();
  }

  void _onPanEnd(DragEndDetails d) {
    if (_flipping) return;
    if (_lockAxis == 0) {
      final v = d.velocity.pixelsPerSecond.dx;
      if (_dragX.abs() >= _flipMinDist || v.abs() >= _flipMinVelocity) {
        // 吸附到相邻页并停住（不继续惯性滑）
        _snapTo(_dragX < 0 ? 1 : -1);
      } else {
        _animateDragX(0); // 滑不够 → 退回
      }
    } else {
      final v = d.velocity.pixelsPerSecond.dy;
      if (v.abs() > 120) _startFling(v);
    }
    _lockAxis = null;
  }

  double _maxV() {
    return (_viewportH - _totalHeight).clamp(-100000.0, 0.0);
  }

  /// 吸附翻页：横带滑到目标页停住 → 换周 → 复位（视觉无跳变）
  void _snapTo(int dir) {
    final w = c.week + dir;
    if (!c.weekEngine.isValidWeek(w)) {
      _animateDragX(0); // 边界：退回
      return;
    }
    _flipping = true;
    final target = -dir * _pageWidth;
    _animateDragXTo(target).whenComplete(() {
      c.setWeek(w);
      setState(() {
        _dragX = 0;
        _flipping = false;
        // 方案C：翻周后保持纵向滚动位置（不强制回顶，消除滚动跳变感）
      });
      _syncStripOffset();
    });
  }

  Future<void> _animateDragXTo(double target) {
    final start = _dragX;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    final anim = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);
    ctrl.addListener(() {
      if (mounted) {
        setState(() => _dragX = start + (target - start) * anim.value);
        _syncStripOffset();
      }
    });
    final done = ctrl.forward().whenComplete(ctrl.dispose);
    return done;
  }

  void _animateDragX(double target) {
    if (_flipping) return;
    final start = _dragX;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    final anim = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);
    ctrl.addListener(() {
      if (mounted) {
        setState(() => _dragX = start + (target - start) * anim.value);
        _syncStripOffset();
      }
    });
    ctrl.forward().whenComplete(ctrl.dispose);
  }

  /// 顶栏箭头：直接吸附翻页
  void _arrowFlip(int dir) {
    if (_flipping) return;
    _snapTo(dir);
  }

  void _startFling(double v) {
    _fling?.dispose();
    _fling = AnimationController.unbounded(vsync: this);
    final sim = FrictionSimulation(0.135, _vOffset, v);
    _fling!.addListener(() {
      final t = _fling!.lastElapsedDuration?.inMicroseconds ?? 0;
      final x = sim.x(t / 1e6);
      setState(() => _vOffset = x.clamp(_maxV(), 0.0));
      if (sim.isDone(t / 1e6)) _fling!.stop();
    });
    _fling!.animateWith(sim);
  }

  // ---------- 学期归档（M2.3） ----------
  // ---------- 编辑流程（M2） ----------

  /// 单节编辑：抽屉表单 → add 冲突检查 → 保存
  Future<void> _showEditFlow({
    Patch? patch,
    BaseCourse? base,
    int? weekday,
    int? startPeriod,
    int? endPeriod,
    String? prefillName,
  }) async {
    final result = await showEditSheet(
      context,
      patchInitial: patch,
      baseInitial: base,
      currentWeek: c.week,
      prefillWeekday: weekday,
      prefillStartPeriod: startPeriod,
      prefillEndPeriod: endPeriod,
      prefillName: prefillName,
    );
    if (result == null || !mounted) return;

    if (result.isBase) {
      await c.saveBaseCourse(result.baseCourse!);
    } else {
      final p = result.patch!;
      // add 操作冲突检查
      if (p.action == PatchAction.add) {
        final conflicts = c.previewConflicts(p);
        if (conflicts.isNotEmpty) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('课程冲突'),
              content: Text(
                '「${p.name}」与以下课程在同一时段冲突：\n'
                '${conflicts.take(3).map((x) => '· ${x.a.name} / ${x.b.name}').join('\n')}'
                '\n\n仍要保存吗？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('仍要保存'),
                ),
              ],
            ),
          );
          if (ok != true) return;
        }
      }
      await c.savePatch(p);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  /// 编辑总入口：先选范围（单节/整周/学期/调课）—— M2.2
  Future<void> _showScopePicker() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '编辑',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('单节修改'),
              subtitle: const Text('新增 / 编辑某节课（临时或长期）'),
              onTap: () => Navigator.pop(ctx, 'single'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('调课'),
              subtitle: const Text('把课从一格移到另一格'),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep),
              title: const Text('整周修改'),
              subtitle: const Text('清空 / 替换某一整周'),
              onTap: () => Navigator.pop(ctx, 'week'),
            ),
            ListTile(
              leading: const Icon(Icons.event_repeat),
              title: const Text('学期修改'),
              subtitle: const Text('管理整个学期的基础课表'),
              onTap: () => Navigator.pop(ctx, 'term'),
            ),
            ListTile(
              leading: const Icon(Icons.notes),
              title: const Text('批量文本编辑'),
              subtitle: const Text('粘贴标准行批量增改（实时校验/追加/覆盖）'),
              onTap: () => Navigator.pop(ctx, 'batch'),
            ),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'single':
        await _showEditFlow();
      case 'move':
        await showMoveFlow(context, controller: c);
      case 'week':
        await _showWeekEditFlow();
      case 'term':
        await _showBaseEditFlow();
      case 'batch':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => BatchTextPage(controller: c)),
        );
    }
  }

  /// 整周修改：清空指定周（M2.2）
  Future<void> _showWeekEditFlow() async {
    final ctrl = TextEditingController(text: '${c.week}');
    final w = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('整周修改'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '周次（1-${c.weekEngine.totalWeeks}）',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '将清空该周全部课程（生成 remove 补丁），之后可用单节编辑重新添加。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
              final n = int.tryParse(ctrl.text.trim());
              if (n != null && c.weekEngine.isValidWeek(n)) {
                Navigator.pop(ctx, n);
              }
            },
            child: const Text('清空该周'),
          ),
        ],
      ),
    );
    if (w != null && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认清空'),
          content: Text('确定清空第$w周的全部课程吗？\n（其他周不受影响，可随时用删除/恢复补丁回退）'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认清空'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await c.clearWeek(w);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('第$w周已清空')));
        }
      }
    }
  }

  /// 学期修改：基础课列表管理（M2.2）
  Future<void> _showBaseEditFlow() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx2, scrollCtrl) => AnimatedBuilder(
          animation: c,
          builder: (context, _) => ListView(
            controller: scrollCtrl,
            children: [
              Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '学期修改（基础课表）',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx2),
                  ),
                ],
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('新增基础课'),
                onTap: () async {
                  Navigator.pop(ctx2);
                  await _showEditFlow(base: null);
                },
              ),
              const Divider(),
              for (final b in c.baseCourses)
                ListTile(
                  dense: true,
                  leading: Text(
                    b.type?.symbol ?? '',
                    style: const TextStyle(fontSize: 15),
                  ),
                  title: Text(b.name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '周${b.weekday} 第${b.startPeriod}-${b.endPeriod}节 · 第${b.startWeek}-${b.endWeek}周',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (dctx) => AlertDialog(
                          title: const Text('删除基础课'),
                          content: Text('整学期删除「${b.name}」？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await c.deleteBaseCourse(b.id);
                    },
                  ),
                  onTap: () async {
                    Navigator.pop(ctx2);
                    await _showEditFlow(base: b);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 删除：当前周 remove 补丁（二次确认）
  Future<void> _showDeleteFlow(WeekCourse course) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除课程'),
        content: Text(
          '将从第${c.week}周移除「${course.name}」\n（周${course.weekday} 第${course.startPeriod}-${course.endPeriod}节）\n\n仅影响当前周，不改变其他周。',
        ),
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
    if (ok != true) return;
    await c.removeCellForCurrentWeek(
      weekday: course.weekday,
      startPeriod: course.startPeriod,
      endPeriod: course.endPeriod,
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已删除（当前周）')));
    }
  }

  // ---------- 周操作 ----------

  Future<void> _showWeekPicker() async {
    final ctrl = TextEditingController(text: '${c.week}');
    final w = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转周次'),
        content: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () =>
                  ctrl.text = '${(int.tryParse(ctrl.text) ?? c.week) - 1}',
            ),
            Expanded(
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '第几周（1-${c.weekEngine.totalWeeks}）',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () =>
                  ctrl.text = '${(int.tryParse(ctrl.text) ?? c.week) + 1}',
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
              final n = int.tryParse(ctrl.text.trim());
              if (n != null && c.weekEngine.isValidWeek(n)) {
                Navigator.pop(ctx, n);
              }
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (w != null && w != c.week) setState(() => c.setWeek(w));
  }

  Future<void> _showDetail(WeekCourse course) async {
    final ext = parseRemarkExt(course.remark).ext;
    final weekdayName = [
      '',
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ][course.weekday];
    final act = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            if (course.type != null)
              Text(course.type!.symbol, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(course.name, style: const TextStyle(fontSize: 17)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _kv(
                '时间',
                '$weekdayName 第${course.startPeriod}-${course.endPeriod}节',
              ),
              if (course.teacher.isNotEmpty) _kv('教师', course.teacher),
              if (course.room.isNotEmpty) _kv('教室', course.room),
              if (course.inactive) _kv('状态', '非本周（单/双周不匹配，不上课）'),
              _kv('来源', course.source == 'base' ? '基础课表' : '临时补丁'),
              if (ext != null && ext.isNotEmpty) ...[
                const Divider(),
                ...ext.entries.map(
                  (e) => _kv(e.key.toString(), e.value.toString()),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'edit'),
            child: const Text('编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'move'),
            child: const Text('调课'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'copy'),
            child: const Text('复制补丁'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (act == null || !mounted) return;
    if (act == 'edit') {
      final base = course.source == 'base' ? c.baseById(course.id) : null;
      final patch = course.source == 'patch' ? _patchById(course.id) : null;
      await _showEditFlow(
        patch: patch,
        base: base,
        weekday: course.weekday,
        startPeriod: course.startPeriod,
        endPeriod: course.endPeriod,
        prefillName: course.name,
      );
    } else if (act == 'delete') {
      await _showDeleteFlow(course);
    } else if (act == 'move') {
      // 由「长按菜单」迁入详情弹窗（长按已改为拖动，能力不丢）
      await showMoveFlow(context, controller: c, sourceCourse: course);
    } else if (act == 'copy') {
      await _copyPatchText(course);
    }
  }

  /// 复制该格对应的补丁标准行到剪贴板
  /// （由「长按菜单」迁入详情弹窗，v0.14）
  Future<void> _copyPatchText(WeekCourse course) async {
    final patch = Patch(
      locationType: PatchLocationType.weekOffset,
      locationValue: '${c.week}',
      weekday: course.weekday,
      startPeriod: course.startPeriod,
      endPeriod: course.endPeriod,
      action: PatchAction.replace,
      name: course.name,
      type: course.type,
      teacher: course.teacher,
      room: course.room,
      color: course.color,
      remark: course.remark,
    );
    await Clipboard.setData(ClipboardData(text: patchToLine(patch)));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('补丁文本已复制到剪贴板')));
    }
  }

  /// 复制当前浏览周的全部课程为标准补丁文本
  /// （需求 7-4「当前周全部补丁文本一键复制」；也是本项目的"带走数据"手段之一）
  Future<void> _copyCurrentWeekText() async {
    final list = c.coursesOf(c.week).where((x) => !x.inactive).toList();
    if (list.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('第${c.week}周没有课程可复制')));
      return;
    }
    final buf = StringBuffer();
    buf.writeln('# 课表 · 第${c.week}周 补丁文本（共 ${list.length} 条）');
    buf.writeln('# 定位类型|定位值|星期|起始节|结束节|周类型|操作|课程名称|类型|教师|教室|颜色|过期日期|备注|id');
    for (final x in list) {
      buf.writeln(
        patchToLine(
          Patch(
            locationType: PatchLocationType.weekOffset,
            locationValue: '${c.week}',
            weekday: x.weekday,
            startPeriod: x.startPeriod,
            endPeriod: x.endPeriod,
            action: PatchAction.replace,
            name: x.name,
            type: x.type,
            teacher: x.teacher,
            room: x.room,
            color: x.color,
            remark: x.remark,
          ),
        ),
      );
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制第${c.week}周 ${list.length} 条补丁文本')),
    );
  }

  Patch? _patchById(int? id) {
    if (id == null) return null;
    for (final p in c.patches) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 拖动落位：只写"未固定的信息"（补丁），**绝不修改基础课表**。
  /// 默认粒度「仅本次」(exactDate) —— 改动最小、回退最简单（删掉补丁即还原）；
  /// 需要「整周 / 从第N周起 / 永久 / 对调」时走详情弹窗的「调课」（四种粒度齐全）。
  Future<void> _onCourseDropped(WeekCourse course, DropTarget target) async {
    if (course.weekday == target.weekday &&
        course.startPeriod == target.startPeriod &&
        course.endPeriod == target.endPeriod) {
      return; // 原位，无改动
    }

    // 落位前快照已有补丁 id，供「撤销」精确删除本次新增（不用猜）
    final beforeIds = c.patches.map((p) => p.id).whereType<int>().toSet();

    await c.executeMove(
      source: course,
      targetWeekday: target.weekday,
      targetStart: target.startPeriod,
      targetEnd: target.endPeriod,
      scope: MoveScope.once,
      // ★ 必须显式传"正在浏览那一周"的日期：
      //   executeMove 的 once 分支默认用 DateTime.now()，
      //   若用户翻到第 3 周而当天属第 6 周，补丁会落到错误的周。
      exactDate: c.weekEngine.mondayOf(c.week),
    );
    if (!mounted) return;

    final newIds = c.patches
        .map((p) => p.id)
        .whereType<int>()
        .where((id) => !beforeIds.contains(id))
        .toList();

    String wd(int w) => ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'][w];
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '已调课：${course.name}\n'
            '${wd(course.weekday)} ${course.startPeriod}-${course.endPeriod}节 → '
            '${wd(target.weekday)} ${target.startPeriod}-${target.endPeriod}节（仅本次）\n'
            '要改整周/永久，请点该课程 → 详情 → 调课',
          ),
          duration: const Duration(seconds: 6),
          action: newIds.isEmpty
              ? null
              : SnackBarAction(
                  label: '撤销',
                  onPressed: () async {
                    for (final id in newIds) {
                      await c.deletePatch(id);
                    }
                  },
                ),
        ),
      );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            '$k：',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13.5))),
      ],
    ),
  );

  // ---------- 构建 ----------
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        if (!c.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return SafeArea(
          child: Column(
            children: [
              _buildTopBar(context),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, cons) {
                    _pageWidth = cons.maxWidth;
                    _viewportH = cons.maxHeight - kHeaderHeight;
                    final bg = Theme.of(context).colorScheme.surface;
                    // 同步横带滚动偏移（offset = 页宽 - dragX；0=上周页，W=本周页，2W=下周页）
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _syncStripOffset(),
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      child: ClipRect(
                        // 三页横带：上周|本周|下周 首尾相接
                        // v0.11.2 修复：Transform.translate 命中测试缺陷（网格手势全失效）
                        // → 改用标准横向 ScrollView（命中测试可靠），jumpTo 驱动
                        child: SingleChildScrollView(
                          controller: _stripCtrl,
                          physics: const NeverScrollableScrollPhysics(),
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              // 方案A：key 加在"兄弟级整页"上——翻周时 Flutter 按 key
                              // 连根移动整页（保留网格测量状态），零重建零重测 → 无闪烁
                              KeyedSubtree(
                                key: ValueKey(c.week - 1),
                                child: SizedBox(
                                  width: _pageWidth,
                                  child: Container(
                                    color: bg,
                                    child: c.weekEngine.isValidWeek(c.week - 1)
                                        ? _pageView(c.week - 1)
                                        : null,
                                  ),
                                ),
                              ),
                              KeyedSubtree(
                                key: ValueKey(c.week),
                                child: SizedBox(
                                  width: _pageWidth,
                                  child: Container(
                                    color: bg,
                                    child: _pageView(c.week),
                                  ),
                                ),
                              ),
                              KeyedSubtree(
                                key: ValueKey(c.week + 1),
                                child: SizedBox(
                                  width: _pageWidth,
                                  child: Container(
                                    color: bg,
                                    child: c.weekEngine.isValidWeek(c.week + 1)
                                        ? _pageView(c.week + 1)
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 一页 = 表头 + 考试条 + 网格（纵向滚动在网格内部，_vOffset 各页共享）
  Widget _pageView(int week) {
    return Column(
      children: [
        _buildHeaderRow(week),
        _buildExamStrip(week),
        Expanded(child: _buildGridArea(week)),
      ],
    );
  }

  /// 本周有考试时，在表头下挂一条：周几 + 科目 + 时间，点开可编辑
  Widget _buildExamStrip(int week) {
    final list = c.examsInWeek(week);
    if (list.isEmpty) return const SizedBox.shrink();
    const examColor = Color(0xFFD84315);
    return Container(
      width: double.infinity,
      color: examColor.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
      child: Row(
        children: [
          const Icon(Icons.assignment_outlined, size: 15, color: examColor),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in list)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(
                          '${_weekdayName(e.date.weekday)} ${e.subject}'
                          '${e.timeText.isEmpty ? '' : ' ${e.timeText}'}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        onPressed: () =>
                            showExamEditDialog(context, c, note: e),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _weekdayName(int w) =>
      const ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'][w];

  Widget _buildTopBar(BuildContext context) {
    final range = c.weekEngine.rangeOf(c.week);
    final current = c.weekEngine.currentWeek(DateTime.now());
    final isCurrent = current == c.week;
    String fmt(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一周',
            onPressed: c.week > 1 && !_flipping ? () => _arrowFlip(-1) : null,
          ),
          InkWell(
            onTap: _showWeekPicker,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第${c.week}周',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${fmt(range.monday)} ~ ${fmt(range.sunday)}',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一周',
            onPressed: c.week < c.weekEngine.totalWeeks && !_flipping
                ? () => _arrowFlip(1)
                : null,
          ),
          const Spacer(),
          if (!isCurrent)
            IconButton(
              icon: const Icon(Icons.today, size: 20),
              tooltip: '回到本周',
              onPressed: () => setState(c.backToCurrentWeek),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增',
            onPressed: () => _showEditFlow(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            tooltip: '更多',
            // ★ 菜单从按钮「下方」展开，而不是盖在按钮上（默认是 over）。
            //   盖住时点不到按钮、点图标位置也关不掉菜单（那一下落在菜单里），
            //   用户只能点菜单之外的空白处。
            position: PopupMenuPosition.under,
            onSelected: (v) async {
              if (v == '编辑总入口') {
                _showScopePicker();
              } else if (v == '复制本周文本') {
                await _copyCurrentWeekText();
              } else if (v == 'mode-toggle') {
                c.toggleMode();
                // 模式切换明确反馈，防"变灰"误判为 bug
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(c.modeLabel),
                    duration: const Duration(milliseconds: 1200),
                  ),
                );
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: '编辑总入口', child: Text('编辑总入口')),
              const PopupMenuItem(value: '复制本周文本', child: Text('复制本周课程文本')),
              CheckedPopupMenuItem(
                value: 'mode-toggle',
                checked: c.planningMode,
                child: Text(
                  c.planningMode ? '颜色模式：展望（同课同色）' : '颜色模式：实时（全灰+当前课高亮）',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(int week) {
    final range = c.weekEngine.rangeOf(week);
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final m1 = range.monday.month;
    final m2 = range.sunday.month;
    final monthLabel = m1 == m2 ? '$m1月' : '$m1/$m2月';
    // 本周哪几天有考试 → 日期下面点一个小红点
    final examDays = c.examsInWeek(week).map((e) => e.date.weekday).toSet();
    return SizedBox(
      height: kHeaderHeight,
      child: Row(
        children: [
          SizedBox(
            width: kLeftColWidth,
            child: Center(
              child: Text(
                monthLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ),
          for (var i = 0; i < 7; i++)
            SizedBox(
              width: kColWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    names[i],
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${range.monday.add(Duration(days: i)).day}',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                  if (examDays.contains(i + 1))
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: const BoxDecoration(
                        color: Color(0xFFD84315),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGridArea(int week) {
    return LayoutBuilder(
      builder: (context, cons) {
        _viewportH = cons.maxHeight;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(0, _vOffset),
              child: DynamicGrid(
                // 按周作 Key：翻页换周时 Flutter 按 key 保留各周网格状态，
                // 已测量周不重新测量 → 消除换周闪烁（v0.8 修复）
                key: ValueKey(week),
                week: week,
                courses: c.coursesOf(week),
                fontScale: c.fontScale,
                planningMode: c.planningMode,
                rowHeightBase: c.rowHeightBase,
                colWidth: kColWidth,
                leftColWidth: kLeftColWidth,
                periodTimes: c.periodTimes,
                onTotalHeight: (h) => _totalHeight = h,
                onCourseTap: (course) => _showDetail(course),
                // 长按 = 拿起拖动（v0.14）。原"长按弹快捷菜单"已移除，
                // 其「调课 / 复制补丁」已迁入详情弹窗（能力不丢）
                onCourseLongPressStart: (course) {
                  HapticFeedback.mediumImpact(); // 震动与拿起反馈同步
                  if (_longPressHighlight == null) {
                    setState(() => _longPressHighlight = course);
                  }
                },
                onCourseLongPressEnd: (_) {
                  if (_longPressHighlight != null) {
                    setState(() => _longPressHighlight = null);
                  }
                },
                onCourseLongPressCancel: (_) {
                  if (_longPressHighlight != null) {
                    setState(() => _longPressHighlight = null);
                  }
                },
                onCourseDropped: _onCourseDropped,
                highlightedCourse: _longPressHighlight,
                onBlankLongPress: (weekday, period) => _showEditFlow(
                  weekday: weekday,
                  startPeriod: period,
                  endPeriod: period,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
