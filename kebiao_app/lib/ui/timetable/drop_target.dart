/// 拖动落点解算（纯几何，无 Widget 依赖，可独立单测）
///
/// 方案（用户确认）：**按重叠面积对比，面积最大者即落点**。
/// 为什么不用"手指所在格"：格子行高是动态的（30~90dp 不等），手指接触面远大于短行，
/// 按点判定极易放错节次；按面积判定则与"卡片视觉上盖住哪个格"完全一致（所见即所得）。
///
/// 关键性质：列与行相互独立 → 面积 = 横向重叠 × 纵向重叠 可分离，
/// 因此每次移动只需 7（列）+ N（行起点）次求交，是纯几何运算，
/// **不触碰任何布局/测量路径**（这点很重要：可结构性避免 v0.8 那类"重新测量导致闪烁"）。
library;

import 'grid_metrics.dart';

/// 一个落点槽位（星期 × 节次区间）
class DropTarget {
  final int weekday; // 1..7
  final int startPeriod;
  final int endPeriod;

  const DropTarget({
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
  });

  int get span => endPeriod - startPeriod + 1;

  bool get isValid =>
      weekday >= 1 &&
      weekday <= 7 &&
      startPeriod >= 1 &&
      endPeriod >= startPeriod &&
      endPeriod <= DropResolver.kMaxPeriod;

  @override
  bool operator ==(Object other) =>
      other is DropTarget &&
      other.weekday == weekday &&
      other.startPeriod == startPeriod &&
      other.endPeriod == endPeriod;

  @override
  int get hashCode => Object.hash(weekday, startPeriod, endPeriod);

  @override
  String toString() => 'DropTarget(周$weekday $startPeriod-$endPeriod节)';
}

class DropResolver {
  /// 节次上限（与网格固定 10 行一致）
  static const int kMaxPeriod = 10;

  /// 面积对比求落点。返回 null 表示"当前不构成有效落点"（离得太远 / 拖回原位 / 越界）。
  ///
  /// [card]     拖动中卡片的当前矩形（= 原位盒子 + 拖动位移）
  /// [span]     卡片跨几节（跨行数），由原课程决定，拖动不改变
  /// [cum]      GridMetrics.cumulativeOffsets()，长度 11
  /// [current]  当前已高亮的目标（用于滞回）
  /// [origin]   卡片原位（该位置视为"无变化"，不返回）
  /// [hysteresis] 滞回余量：新目标面积必须超过当前目标 (1+该值) 倍才切换。
  ///             ★ 必须 > 0，否则卡片停在两格边界上时高亮会来回抖。
  /// [minOverlap] 最小可接受重叠（dp），低于此认为"拖到网格外"
  static DropTarget? resolve({
    required CardBox card,
    required int span,
    required double colWidth,
    required List<double> cum,
    DropTarget? current,
    DropTarget? origin,
    double hysteresis = 0.10,
    double minOverlap = 1.0,
  }) {
    if (span < 1 || span > kMaxPeriod) return null;
    if (cum.length < kMaxPeriod + 1) return null;
    final maxStart = kMaxPeriod - span + 1;
    if (maxStart < 1) return null;

    final cardRight = card.left + card.width;
    final cardBottom = card.top + card.height;
    final cardCx = card.left + card.width / 2;

    // ---- 横向：7 列等宽，取重叠最大列；平局取更靠近卡片水平中心者 ----
    int? bc;
    double bh = -1;
    double bcCenter = 0;
    for (var w = 1; w <= 7; w++) {
      final l = colWidth * (w - 1) + 2;
      final r = l + colWidth - 4;
      final h = _overlap(card.left, cardRight, l, r);
      final c = l + (colWidth - 4) / 2;
      final better = bc == null ||
          h > bh + 0.5 ||
          ((h - bh).abs() <= 0.5 && (cardCx - c).abs() < (cardCx - bcCenter).abs());
      if (better) {
        bh = h;
        bc = w;
        bcCenter = c;
      }
    }

    // ---- 纵向：候选起点 1..maxStart，取重叠最大者；平局取离卡片顶部更近者 ----
    int? br;
    double bv = -1;
    double brTop = 0;
    for (var s = 1; s <= maxStart; s++) {
      final box = GridMetrics.boxFor(
        weekday: 1, // 纵向几何与星期无关
        startPeriod: s,
        endPeriod: s + span - 1,
        colWidth: colWidth,
        cum: cum,
      );
      final v = _overlap(card.top, cardBottom, box.top, box.top + box.height);
      final better = br == null ||
          v > bv + 0.5 ||
          ((v - bv).abs() <= 0.5 && (card.top - box.top).abs() < (card.top - brTop).abs());
      if (better) {
        bv = v;
        br = s;
        brTop = box.top;
      }
    }

    if (bc == null || br == null) return null;
    if (bh < minOverlap || bv < minOverlap) return null; // 拖到网格外

    final target = DropTarget(
      weekday: bc,
      startPeriod: br,
      endPeriod: br + span - 1,
    );
    if (!target.isValid) return null;

    // 拖回原位 = 无变化，不给落点（避免"松手却什么也没发生"的困惑）
    if (origin != null && target == origin) return null;

    // ---- 滞回：新目标必须明显优于当前目标才切换，消除边界抖动 ----
    if (current != null && current.isValid) {
      final curArea = _areaOf(current, card, colWidth, cum);
      final newArea = bh * bv;
      if (newArea <= curArea * (1 + hysteresis)) return current;
    }
    return target;
  }

  /// 某目标槽位与卡片矩形的重叠面积
  static double _areaOf(
    DropTarget t,
    CardBox card,
    double colWidth,
    List<double> cum,
  ) {
    if (!t.isValid) return 0;
    final b = GridMetrics.boxFor(
      weekday: t.weekday,
      startPeriod: t.startPeriod,
      endPeriod: t.endPeriod,
      colWidth: colWidth,
      cum: cum,
    );
    final h = _overlap(card.left, card.left + card.width, b.left, b.left + b.width);
    final v = _overlap(card.top, card.top + card.height, b.top, b.top + b.height);
    return h * v;
  }

  /// 一维区间重叠长度（不相交返回 0）
  static double _overlap(double a0, double a1, double b0, double b1) {
    final lo = a0 > b0 ? a0 : b0;
    final hi = a1 < b1 ? a1 : b1;
    return hi > lo ? hi - lo : 0.0;
  }
}
