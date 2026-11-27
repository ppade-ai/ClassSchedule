/// 课程卡片：绝对定位渲染 + 内容组件（真实渲染测量用）
/// v0.7：移除 FittedBox —— 行高来自"真实渲染测量"（DynamicGrid），文字永远真实大小
library;

import 'package:flutter/material.dart';

import '../../core/model/week_course.dart';

/// 深色模式自动适配：降饱和 + 压亮度
Color adaptCardColor(String hex, Brightness brightness) {
  final c = hex.isNotEmpty ? _parseHex(hex) : null;
  final base = c ?? Colors.blueGrey.shade200;
  if (brightness == Brightness.dark) {
    final hsl = HSLColor.fromColor(base);
    final s = hsl.saturation < 0.45 ? hsl.saturation : 0.45;
    final l = hsl.lightness < 0.32 ? hsl.lightness : 0.32;
    return hsl.withSaturation(s).withLightness(l).toColor();
  }
  return base;
}

Color? _parseHex(String hex) {
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

/// 卡片内容组件（无定位）：供 CourseCard 与 真实测量层 共用
class CourseCardContent extends StatelessWidget {
  final WeekCourse course;
  final double fontScale;
  final bool planningMode;
  final bool isNow;
  final double? minHeight; // 测量时 0；渲染时 = 所跨行高度

  const CourseCardContent({
    super.key,
    required this.course,
    this.fontScale = 1.0,
    this.planningMode = true,
    this.isNow = false,
    this.minHeight,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = adaptCardColor(course.color, brightness);
    final onColor = _onColor(color);
    final inactive = course.inactive;
    final fs = fontScale;

    Color fill;
    Color border;
    if (!planningMode) {
      if (isNow) {
        fill = const Color(0xFF1B5E20).withValues(alpha: 0.22);
        border = const Color(0xFF4CAF50);
      } else {
        fill = brightness == Brightness.dark ? const Color(0xFF3A3A3A) : const Color(0xFFE8E8E8);
        border = Colors.grey.shade400;
      }
    } else {
      fill = inactive ? (brightness == Brightness.dark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0)) : color;
      border = inactive ? Colors.grey : color.withValues(alpha: 0.35);
    }
    final textColor = !planningMode && isNow
        ? Colors.white
        : (inactive || (!planningMode && !isNow) ? Colors.grey : onColor);

    return Container(
      constraints: minHeight != null ? BoxConstraints(minHeight: minHeight!) : null,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: border,
          width: isNow && !planningMode ? 1.6 : 0.8,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(3, 2, 3, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 课程名直接占满卡片宽度。
          // 原先前面有个课程类型符号（☆讲课 / ★实验 / ○上机 / ●实践）+ 2dp 间距，
          // 在 44dp 宽的列里白占约 8dp，导致课程名被挤成更多行 → 已按用户反馈移除。
          // 类型信息仍可在「详情弹窗」标题与编辑表单里看到。
          Text(
            course.name,
            style: TextStyle(
              fontSize: 10.5 * fs,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: textColor,
            ),
          ),
          // 教师在前，教室换行在后（用户反馈）
          if (course.teacher.isNotEmpty)
            Text(
              course.teacher,
              style: TextStyle(fontSize: 9 * fs, height: 1.25, color: textColor),
            ),
          if (course.room.isNotEmpty)
            Text(
              course.room,
              style: TextStyle(fontSize: 9 * fs, height: 1.25, color: textColor),
            ),
          if (inactive)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('非本周', style: TextStyle(fontSize: 8.5 * fs, color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Color _onColor(Color c) => c.computeLuminance() > 0.6 ? Colors.black87 : Colors.white;
}

class CourseCard extends StatelessWidget {
  final WeekCourse course;
  final double colWidth;
  final double rowHeight;
  final double? left; // 度量驱动定位；null=按 星期×行高 计算
  final double? top;
  final double? height;
  final bool planningMode;
  final bool isNow;
  final double fontScale;
  final bool highlight; // 长按拿起反馈：缩小10%+颜色鲜艳+滤镜（v0.11.4）
  final Offset dragOffset; // 拖动位移（Transform，不影响布局）
  final bool dragging; // 正在拖动（加投影，视觉上"提起"）
  final VoidCallback onTap;
  /// 长按拿起（带按下点全局坐标，供页面/网格换算拖动位移）
  final void Function(Offset globalPosition)? onLongPressStart;
  final void Function(Offset globalPosition)? onLongPressMoveUpdate; // 长按后跟手移动
  final void Function(Offset globalPosition)? onLongPressEnd; // 松手（决定落位）
  final VoidCallback? onLongPressCancel;

  const CourseCard({
    super.key,
    required this.course,
    required this.colWidth,
    required this.rowHeight,
    this.left,
    this.top,
    this.height,
    required this.planningMode,
    required this.isNow,
    this.fontScale = 1.0,
    this.highlight = false,
    this.dragOffset = Offset.zero,
    this.dragging = false,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onLongPressCancel,
  });

  /// 饱和度增强矩阵（1.35x）：按压时颜色更鲜艳（用户需求：显眼而非变灰）
  static const List<double> _vivid = [
    1.27545, -0.25025, -0.0252, 0, 0,
    -0.07455, 1.09975, -0.0252, 0, 0,
    -0.07455, -0.25025, 1.3248, 0, 0,
    0, 0, 0, 1, 0,
  ];

  /// 按压/拖动滤镜层：高亮描边 + 淡发光；[elevated] 时再加投影，视觉上"提起来"
  Widget _filtered(Widget child, {bool elevated = false}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.45),
            blurRadius: 10,
            spreadRadius: 1,
          ),
          if (elevated)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = CourseCardContent(
      course: course,
      fontScale: fontScale,
      planningMode: planningMode,
      isNow: isNow,
      minHeight: height == null
          ? rowHeight * (course.endPeriod - course.startPeriod + 1) - 4
          : null,
    );
    return Positioned(
      left: left ?? colWidth * (course.weekday - 1) + 2,
      top: top ?? rowHeight * (course.startPeriod - 1) + 2,
      width: colWidth - 4,
      height: height,
      // 拖动位移用 Transform（纯绘制变换，不改布局 → 不会触发重新测量）
      child: Transform.translate(
        offset: dragOffset,
        child: GestureDetector(
          onTap: onTap,
          onLongPressStart: onLongPressStart == null
              ? null
              : (d) => onLongPressStart!(d.globalPosition),
          onLongPressMoveUpdate: onLongPressMoveUpdate == null
              ? null
              : (d) => onLongPressMoveUpdate!(d.globalPosition),
          onLongPressEnd: onLongPressEnd == null
              ? null
              : (d) => onLongPressEnd!(d.globalPosition),
          onLongPressCancel: onLongPressCancel,
          child: AnimatedScale(
            scale: highlight ? 0.9 : 1.0, // 缩小 10%（保持可辨认）
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            child: highlight
                ? ColorFiltered(
                    colorFilter: const ColorFilter.matrix(_vivid),
                    child: _filtered(
                      card,
                      elevated: dragging,
                    ),
                  )
                : card,
          ),
        ),
      ),
    );
  }
}
