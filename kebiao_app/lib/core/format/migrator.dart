/// 格式迁移器骨架（不变量 I11 / P0 12-4）
///
/// 现在只有 v1，所以**迁移表是空的**——这不代表它没用：
/// 结构先就位，将来字段一变就直接往 [steps] 里加一条 `vN → vN+1`，
/// 调用点不用改。没有这张表，第一次改格式时就会被迫写一堆散落的 if。
library;

import 'format_version.dart';

/// 一步迁移：把 vN 的文本变成 v(N+1) 的文本
typedef FormatStep = String Function(String text);

class Migrator {
  /// 已实现的迁移步骤：键是"源版本"，值是 source → source+1 的转换
  ///
  /// 例：将来加 `#FORMAT v2` 时写 `2: _v1ToV2`（若从 1 升 2 则是 `1: _v1ToV2`）
  static const Map<int, FormatStep> steps = <int, FormatStep>{};

  /// 目标版本
  static int get target => kFormatVersion;

  /// 能否直接读懂该版本（不需要迁移）
  static bool isCurrent(int version) => version == kFormatVersion;

  /// 是否有从 [from] 一路升到当前版本的完整迁移链
  static bool canMigrate(int from) {
    if (from > kFormatVersion) return false;
    for (var v = from; v < kFormatVersion; v++) {
      if (!steps.containsKey(v)) return false;
    }
    return true;
  }

  /// 把 [text] 从 [from] 升到 [to]（默认当前版本）
  ///
  /// - [from] 高于当前版本 → 抛 [UnsupportedFormatVersion]（不猜、不降级）
  /// - 缺少某一步 → 抛 [StateError]，别假装迁移成功
  static String migrate(String text, {required int from, int? to}) {
    final targetVersion = to ?? kFormatVersion;
    if (from > kFormatVersion) {
      throw UnsupportedFormatVersion(found: from, supported: kFormatVersion);
    }
    if (from == targetVersion) return text;

    var current = text;
    var v = from;
    while (v < targetVersion) {
      final step = steps[v];
      if (step == null) {
        throw StateError('缺少 v$v → v${v + 1} 的迁移步骤（Migrator.steps 里没有 $v）');
      }
      current = step(current);
      v++;
    }
    return current;
  }
}
