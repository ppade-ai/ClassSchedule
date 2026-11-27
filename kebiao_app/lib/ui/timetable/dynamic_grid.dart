/// 动态网格：真实渲染测量行高（v0.7）
/// 方案（用户确认）：测量卡片内容真实高度（GlobalKey + post-frame，真字体真布局）
/// → GridMetrics 反推行高 → 卡片永不重叠、字号真实大小、宽度固定。
/// 首次/换周/换字号时测量一帧（Offstage），之后稳定渲染。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/model/period_time.dart';
import '../../core/model/week_course.dart';
import '../demo/demo_data.dart';
import 'course_card.dart';
import 'drop_target.dart';
import 'grid_metrics.dart';

class DynamicGrid extends StatefulWidget {
  final int week;
  final List<WeekCourse> courses;
  final double fontScale;
  final bool planningMode;
  final double colWidth;
  final double leftColWidth;

  /// 行高下限（dp，默认 64）。实际行高 = max(该值, 该行卡片内容需求 ÷ 跨行数)。
  /// 调这个值**不需要重新测量**：测量缓存存的是与行高无关的内容自然高度，
  /// 所以切换行高不会出现"测量层闪一帧"（与改字号不同）。
  final double rowHeightBase;
  final ValueChanged<double> onTotalHeight; // 告知页面网格总高（纵向滚动范围）
  final void Function(WeekCourse) onCourseTap;
  final void Function(WeekCourse)? onCourseLongPressStart; // 长按拿起（按压反馈）
  final void Function(WeekCourse)? onCourseLongPressEnd; // 松手（清高亮）
  final void Function(WeekCourse)? onCourseLongPressCancel;
  final void Function(WeekCourse course, DropTarget target)?
  onCourseDropped; // 落位成功
  final WeekCourse? highlightedCourse; // 当前被拿起的课程
  final void Function(int weekday, int period)? onBlankLongPress; // 空白格长按

  /// 作息时间（第 1..N 节）。为空时退回内置模板。
  final List<PeriodTime> periodTimes;

  const DynamicGrid({
    super.key,
    required this.week,
    required this.courses,
    required this.fontScale,
    required this.planningMode,
    required this.colWidth,
    required this.leftColWidth,
    this.rowHeightBase = 64,
    required this.onTotalHeight,
    required this.onCourseTap,
    this.onCourseLongPressStart,
    this.onCourseLongPressEnd,
    this.onCourseLongPressCancel,
    this.onCourseDropped,
    this.highlightedCourse,
    this.onBlankLongPress,
    this.periodTimes = const [],
  });

  @override
  State<DynamicGrid> createState() => _DynamicGridState();

  /// 数据编辑后清空测量缓存（行高需重算）
  static void clearMeasureCache() => _DynamicGridState.clearMeasureCache();
}

class _DynamicGridState extends State<DynamicGrid> {
  /// 方案B（双保险）：按周测量缓存 周号 → (字号, 高度列表)
  /// 即使网格意外重建，直接出正确布局，测量层永不闪现。
  /// 字号变化时 key 不匹配自动失效；数据编辑时调用 clearMeasureCache()。
  /// 缓存条目数 ≠ 当前课程数时同样失效（防御跨周/跨测试错配）。
  static final Map<int, (double, List<double>)> _measureCache = {};

  static void clearMeasureCache() => _measureCache.clear();

  static bool _cacheValid(
    (double, List<double>)? cached,
    int count,
    double fontScale,
  ) => cached != null && cached.$1 == fontScale && cached.$2.length == count;

  List<double>? _intrinsic; // 每张卡片真实内容高度（测量结果）
  late List<GlobalKey> _keys;

  /// 最近一次 build 算出的度量（拖动落点计算需要 colWidth/cum，复用同一份，避免重算）
  GridMetrics? _metrics;

  // ---- 拖动状态（纯 UI 瞬态，不进 controller） ----
  WeekCourse? _dragCourse; // 正被拿起的课程
  Offset _pressStartGlobal = Offset.zero; // 长按按下点（全局坐标）
  Offset _dragOffset = Offset.zero; // 跟手位移（Transform，不改布局）
  DropTarget? _dropTarget; // 当前落点（null=无有效落点）

  /// 判定"算作拖动"的最小位移（dp）：低于此值视为原地松手（不产生改动）
  static const double kDragMinDistance = 6.0;

  /// 当前生效的作息时间（外部没传就用内置模板）
  late List<PeriodTime> _times;

  List<PeriodTime> _resolveTimes() {
    if (widget.periodTimes.isNotEmpty) return widget.periodTimes;
    return DemoData.periodTimes.map((t) => PeriodTime.tryParse(t)!).toList();
  }

  @override
  void initState() {
    super.initState();
    _times = _resolveTimes();
    _keys = List.generate(widget.courses.length, (_) => GlobalKey());
    if (_cacheValid(
      _measureCache[widget.week],
      widget.courses.length,
      widget.fontScale,
    )) {
      _intrinsic = _measureCache[widget.week]!.$2;
    } else {
      _scheduleMeasure();
    }
  }

  @override
  void didUpdateWidget(covariant DynamicGrid old) {
    super.didUpdateWidget(old);
    if (!identical(old.periodTimes, widget.periodTimes)) {
      _times = _resolveTimes();
    }
    if (old.week != widget.week ||
        old.fontScale != widget.fontScale ||
        old.courses.length != widget.courses.length) {
      _keys = List.generate(widget.courses.length, (_) => GlobalKey());
      if (_cacheValid(
        _measureCache[widget.week],
        widget.courses.length,
        widget.fontScale,
      )) {
        // 命中缓存：直接出结果，无测量层
        _intrinsic = _measureCache[widget.week]!.$2;
      } else {
        _intrinsic = null;
        _scheduleMeasure();
      }
    }
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hs = _keys
          .map((k) => k.currentContext?.size?.height ?? 0.0)
          .toList();
      if (hs.any((h) => h <= 0)) {
        // 防御：未布局完再排一帧（防测量层卡死导致"网格空白"）
        _scheduleMeasure();
        return;
      }
      _measureCache[widget.week] = (widget.fontScale, hs);
      setState(() => _intrinsic = hs);
    });
  }

  // ---------- 拖动：长按拿起 → 跟手 → 面积对比求落点 → 松手落位 ----------

  void _onLift(WeekCourse course, Offset globalPosition) {
    setState(() {
      _dragCourse = course;
      _pressStartGlobal = globalPosition;
      _dragOffset = Offset.zero;
      _dropTarget = null;
    });
    widget.onCourseLongPressStart?.call(course);
  }

  /// 跟手移动：按"与哪个槽位重叠面积最大"求落点并刷新预览
  void _onDragUpdate(WeekCourse course, Offset globalPosition) {
    final m = _metrics;
    if (m == null || !identical(_dragCourse, course)) return;
    // 显式身份查找（不用 indexOf：若将来 WeekCourse 重写了 ==，会静默匹配到错误的卡片）
    var idx = -1;
    for (var k = 0; k < widget.courses.length; k++) {
      if (identical(widget.courses[k], course)) {
        idx = k;
        break;
      }
    }
    if (idx < 0 || idx >= m.boxes.length) return;
    final translation = globalPosition - _pressStartGlobal;
    final base = m.boxes[idx];
    final card = CardBox(
      left: base.left + translation.dx,
      top: base.top + translation.dy,
      width: base.width,
      height: base.height,
    );
    final target = DropResolver.resolve(
      card: card,
      span: course.endPeriod - course.startPeriod + 1,
      colWidth: widget.colWidth,
      cum: m.cumulativeOffsets(),
      current: _dropTarget,
      origin: DropTarget(
        weekday: course.weekday,
        startPeriod: course.startPeriod,
        endPeriod: course.endPeriod,
      ),
    );
    if (target == _dropTarget && translation == _dragOffset) return; // 无变化不重建
    setState(() {
      _dragOffset = translation;
      _dropTarget = target;
    });
  }

  /// 松手：位移达到阈值且有有效落点 → 通知页面落位；否则视为"原地放下"（不产生改动）
  void _onDragEnd(WeekCourse course, Offset globalPosition) {
    final target = _dropTarget;
    final moved =
        (globalPosition - _pressStartGlobal).distance >= kDragMinDistance;
    setState(() {
      _dragCourse = null;
      _dragOffset = Offset.zero;
      _dropTarget = null;
    });
    widget.onCourseLongPressEnd?.call(course);
    if (moved && target != null) {
      widget.onCourseDropped?.call(course, target);
    }
  }

  void _onDragCancel(WeekCourse course) {
    setState(() {
      _dragCourse = null;
      _dragOffset = Offset.zero;
      _dropTarget = null;
    });
    widget.onCourseLongPressCancel?.call(course);
  }

  /// 落点是否已被其他课程占用（非本周不算占用，与冲突检测口径一致）
  bool _isOccupied(DropTarget t) {
    for (final c in widget.courses) {
      if (identical(c, _dragCourse) || c.inactive) continue;
      if (c.weekday != t.weekday) continue;
      if (!(c.endPeriod < t.startPeriod || t.endPeriod < c.startPeriod)) {
        return true;
      }
    }
    return false;
  }

  /// 落点预览：灰=可放 / 橙=目标格已有课（会叠加）
  /// 用虚线描边与"非本周灰化"区分（避免两种"灰"混淆）；IgnorePointer 不参与命中。
  Widget _buildDropPreview(GridMetrics m) {
    final t = _dropTarget!;
    final box = GridMetrics.boxFor(
      weekday: t.weekday,
      startPeriod: t.startPeriod,
      endPeriod: t.endPeriod,
      colWidth: widget.colWidth,
      cum: m.cumulativeOffsets(),
    );
    final color = _isOccupied(t) ? const Color(0xFFFF9800) : Colors.grey;
    return Positioned(
      key: const ValueKey('drop_preview'),
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DashedBorderPainter(color: color),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }

  /// 被拖动课程在 courses 中的下标（-1 = 当前无拖动）。显式身份查找，不用 indexOf。
  int get _dragIndex {
    final d = _dragCourse;
    if (d == null) return -1;
    for (var i = 0; i < widget.courses.length; i++) {
      if (identical(widget.courses[i], d)) return i;
    }
    return -1;
  }

  Widget _buildCard(int i, GridMetrics metrics, double colWidth) {
    final course = widget.courses[i];
    final isDrag = identical(course, _dragCourse);
    return CourseCard(
      // ★ 稳定 key 必需：拖动时被拖卡片会被移到 children 列表最后（为了让预览夹在中间），
      //   没有 key 的话 Flutter 会按位置复用同一位置的 RawGestureDetector State 却换上
      //   别的识别器 → 进行中的长按手势被丢弃（落点恒为 null）。有 key 则按 key 匹配、
      //   移动元素时保留手势状态。同 v0.9 修翻页闪烁的"兄弟级 key"手法。
      key: ValueKey('course_$i'),
      course: course,
      colWidth: colWidth,
      rowHeight: 64,
      left: metrics.boxes[i].left,
      top: metrics.boxes[i].top,
      height: metrics.boxes[i].height,
      planningMode: widget.planningMode,
      isNow: !widget.planningMode && _isNowOn(course),
      fontScale: widget.fontScale,
      highlight: identical(course, widget.highlightedCourse) || isDrag,
      dragging: isDrag,
      dragOffset: isDrag ? _dragOffset : Offset.zero,
      onTap: () => widget.onCourseTap(course),
      // 长按 = 拿起拖动（原"长按弹快捷菜单"已移除，功能移至详情弹窗）
      onLongPressStart: (g) => _onLift(course, g),
      onLongPressMoveUpdate: (g) => _onDragUpdate(course, g),
      onLongPressEnd: (g) => _onDragEnd(course, g),
      onLongPressCancel: () => _onDragCancel(course),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colWidth = widget.colWidth;
    final gridWidth = 7 * colWidth;
    if (_intrinsic == null) {
      // 测量层：真实布局（无高度约束 → 内容自然高度）
      return SizedBox(
        width: gridWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.courses.length; i++)
              SizedBox(
                width: colWidth - 4,
                child: KeyedSubtree(
                  key: _keys[i],
                  child: CourseCardContent(
                    course: widget.courses[i],
                    fontScale: widget.fontScale,
                    planningMode: widget.planningMode,
                    isNow: false,
                    minHeight: 0,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final metrics = GridMetrics.compute(
      courses: widget.courses,
      intrinsicHeights: _intrinsic!,
      colWidth: colWidth,
      rowMin: widget.rowHeightBase,
    );
    widget.onTotalHeight(metrics.totalHeight);
    final cum = metrics.cumulativeOffsets();
    _metrics = metrics; // 拖动落点计算复用同一份度量

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPeriodColumn(metrics),
        SizedBox(
          width: gridWidth,
          height: metrics.totalHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPressStart: widget.onBlankLongPress == null
                ? null
                : (d) {
                    // 空白格长按：由局部坐标反推 星期×节次（卡片上由卡片自身手势优先）
                    final col = (d.localPosition.dx / colWidth).floor();
                    final row = _periodAt(d.localPosition.dy, cum);
                    if (col >= 0 && col < 7 && row >= 1 && row <= 10) {
                      widget.onBlankLongPress!(col + 1, row);
                    }
                  },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 纵向格线（固定列宽，全高）
                for (var j = 0; j < 7; j++)
                  Positioned(
                    left: j * colWidth,
                    top: 0,
                    width: colWidth,
                    height: metrics.totalHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.15),
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 横向格线（动态行高）
                for (var i = 0; i < 10; i++)
                  Positioned(
                    left: 0,
                    top: cum[i],
                    width: gridWidth,
                    height: metrics.rowHeights[i],
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.15),
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 层次（Stack 后画的在上）：已有卡片 → 落点预览 → 被拖动卡片。
                // 为什么预览要夹在中间：① 若在卡片之下，目标格被占用时预览会被那张卡
                // 完全遮住（橙框永远看不见，等于白做）；② 若在最上层，会盖住用户
                // 正拿在手上的卡片。夹在两者之间同时满足"占用格可见"与"拖动卡在最上"。
                for (var i = 0; i < widget.courses.length; i++)
                  if (!identical(widget.courses[i], _dragCourse))
                    _buildCard(i, metrics, colWidth),
                if (_dropTarget != null) _buildDropPreview(metrics),
                if (_dragIndex >= 0) _buildCard(_dragIndex, metrics, colWidth),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 纵向坐标 → 节次（动态行高：找首个累计偏移 > y 的行）
  int _periodAt(double y, List<double> cum) {
    for (var i = 0; i < cum.length - 1; i++) {
      if (y < cum[i + 1]) return i + 1;
    }
    return 10;
  }

  bool _isNowOn(WeekCourse course) {
    final now = DateTime.now();
    if (course.inactive || now.weekday != course.weekday) return false;
    final nowMin = now.hour * 60 + now.minute;
    final p = currentPeriod(nowMin);
    return p != null && course.startPeriod <= p && p <= course.endPeriod;
  }

  int? currentPeriod(int nowMin) {
    for (var i = 0; i < _times.length; i++) {
      if (nowMin >= _times[i].startMinutes && nowMin < _times[i].endMinutes) {
        return i + 1;
      }
    }
    return null;
  }

  Widget _buildPeriodColumn(GridMetrics metrics) {
    return SizedBox(
      width: widget.leftColWidth,
      child: Column(
        children: [
          for (var i = 1; i <= 10; i++)
            Container(
              height: metrics.rowHeights[i - 1],
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
              ),
              child: _buildPeriodCell(i, metrics.rowHeights[i - 1]),
            ),
        ],
      ),
    );
  }

  /// 左列单格。**按行高自适应**少显示几行字，否则行高被调小时这里会溢出。
  ///
  /// 优先级：节次号 > 上课时间 > 分组名 > 下课时间（越靠后越先舍弃）。
  /// 默认行高 64 时仍显示全部 4 行，外观与之前完全一致。
  Widget _buildPeriodCell(int i, double rowHeight) {
    final showGroup =
        rowHeight >= 64 && DemoData.periodGroups.any((g) => g.$2 == i);
    final showEnd = rowHeight >= 64;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showGroup)
          Text(
            DemoData.periodGroups.firstWhere((g) => g.$2 == i).$1,
            style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
          ),
        Text(
          '$i',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        Text(
          i <= _times.length ? _times[i - 1].start : '',
          style: TextStyle(fontSize: 7.5, color: Colors.grey.shade600),
        ),
        if (showEnd)
          Text(
            i <= _times.length ? _times[i - 1].end : '',
            style: TextStyle(fontSize: 7.5, color: Colors.grey.shade600),
          ),
      ],
    );
  }
}

/// 圆角虚线描边（Flutter 无内置虚线边框）。
/// 用途：拖动落点预览。虚线是"占位框"的通用视觉语言，
/// 可与课程卡的实线边框、以及"非本周灰化"的实线灰卡区分开
/// （后者在实时模式下整屏皆灰，纯灰填充会看不出预览）。
class _DashedBorderPainter extends CustomPainter {
  final Color color;

  const _DashedBorderPainter({required this.color});

  static const double _radius = 6;
  static const double _dash = 5;
  static const double _gap = 3;
  static const double _strokeWidth = 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(_radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final next = math.min(d + _dash, metric.length);
        canvas.drawPath(metric.extractPath(d, next), paint);
        d = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color;
}
