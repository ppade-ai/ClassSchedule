/// 网格度量：基于"真实渲染测量高度"反推行高（v0.7）
/// 输入 intrinsicHeights = 每张卡片的真实内容高度（DynamicGrid 用 GlobalKey 实测，
/// 测试用真实渲染 + Ahem 字体实测）——不依赖 TextPainter 估算，100% 准确。
/// 行高 H[i] = max(64, max(跨该行的卡片需求 ÷ 跨行数)) → 数学保证卡片永不重叠。
/// 宽度固定不变。
library;

import 'dart:math' as math;

import '../../core/model/week_course.dart';

/// 卡片在网格中的位置与尺寸
class CardBox {
  final double left;
  final double top;
  final double width;
  final double height;

  const CardBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  bool overlapsWith(CardBox other) {
    final sameColumn = (left - other.left).abs() < 1;
    if (!sameColumn) return false;
    return !(top + height <= other.top + 0.5 || other.top + other.height <= top + 0.5);
  }
}

class GridMetrics {
  final List<double> rowHeights;
  final double totalHeight;
  final List<CardBox> boxes;

  GridMetrics._(this.rowHeights, this.totalHeight, this.boxes);

  List<double> cumulativeOffsets() {
    final cum = <double>[0];
    for (final h in rowHeights) {
      cum.add(cum.last + h);
    }
    return cum;
  }

  static const double kRowMin = 64;

  /// 任意 (星期, 起始节, 结束节) 的卡片盒几何。
  /// ★ 唯一几何来源：compute() 布局真实卡片、以及拖动落点预览，**都必须**走这里，
  ///   以保证"预览框的位置"与"松手后卡片实际落点"逐像素一致（否则会出现预览偏移）。
  static CardBox boxFor({
    required int weekday,
    required int startPeriod,
    required int endPeriod,
    required double colWidth,
    required List<double> cum,
  }) {
    final top = cum[startPeriod - 1] + 2;
    final bottom = cum[endPeriod];
    return CardBox(
      left: colWidth * (weekday - 1) + 2,
      top: top,
      width: colWidth - 4,
      // 高度 = 跨行和 - 4（top 已含 +2，再留 2dp 底间隙 → 上下各 2dp）
      height: math.max(1.0, (bottom - top) - 2),
    );
  }

  /// [intrinsicHeights]：每张卡片（与 courses 同序）的真实内容高度（不含格子最小高）
  static GridMetrics compute({
    required List<WeekCourse> courses,
    required List<double> intrinsicHeights,
    required double colWidth,
    double rowMin = kRowMin,
  }) {
    assert(courses.length == intrinsicHeights.length);
    final reqs = <double>[];
    for (var i = 0; i < courses.length; i++) {
      final c = courses[i];
      final span = c.endPeriod - c.startPeriod + 1;
      // 卡片需求 = max(真实内容高, 最小格子高×跨行数) + 4dp 缓冲
      // （盒子高度 = 跨行和 - 4，需求含缓冲 → 恒满足 盒子 ≥ 内容）
      reqs.add(math.max(intrinsicHeights[i], span * rowMin) + 4);
    }

    // 行高 = max(最小行高, max(跨该行的卡片需求 ÷ 跨行数))
    final H = List<double>.filled(10, rowMin);
    for (var i = 0; i < courses.length; i++) {
      final c = courses[i];
      final span = c.endPeriod - c.startPeriod + 1;
      for (var r = c.startPeriod - 1; r < c.endPeriod; r++) {
        H[r] = math.max(H[r], reqs[i] / span);
      }
    }
    // 向上取整到 0.5dp（防边界裁切）
    for (var i = 0; i < 10; i++) {
      H[i] = (H[i] / 0.5).ceil() * 0.5;
    }

    final cum = <double>[0];
    for (final h in H) {
      cum.add(cum.last + h);
    }

    final boxes = <CardBox>[];
    for (final c in courses) {
      boxes.add(boxFor(
        weekday: c.weekday,
        startPeriod: c.startPeriod,
        endPeriod: c.endPeriod,
        colWidth: colWidth,
        cum: cum,
      ));
    }

    return GridMetrics._(H, cum.last, boxes);
  }
}
