/// 核心枚举：类型 / 操作 / 定位 / 周类型
/// 对应格式 v2.0 与 16.12 枚举配置化设计（当前为代码枚举，后续可迁移为配置表）
library;

/// 课程类型：☆讲课 ★实验 ○上机 ●实践（实测 PDF 图例 4 种）
enum CourseType { lecture, lab, computer, practice }

extension CourseTypeX on CourseType {
  String get symbol {
    switch (this) {
      case CourseType.lecture:
        return '☆';
      case CourseType.lab:
        return '★';
      case CourseType.computer:
        return '○';
      case CourseType.practice:
        return '●';
    }
  }

  String get label {
    switch (this) {
      case CourseType.lecture:
        return '讲课';
      case CourseType.lab:
        return '实验';
      case CourseType.computer:
        return '上机';
      case CourseType.practice:
        return '实践';
    }
  }
}

/// 从符号解析类型；不识别返回 null（由调用方产生校验问题）
CourseType? courseTypeFromSymbol(String s) {
  final t = s.trim();
  for (final c in CourseType.values) {
    if (c.symbol == t) return c;
  }
  return null;
}

/// 周类型：空=每周 / 单=仅奇数周 / 双=仅偶数周
enum WeekType { every, odd, even }

extension WeekTypeX on WeekType {
  /// 文本编码：空字符串 / 单 / 双
  String get code {
    switch (this) {
      case WeekType.every:
        return '';
      case WeekType.odd:
        return '单';
      case WeekType.even:
        return '双';
    }
  }

  /// 该周类型在指定周序号是否上课
  bool matches(int week) {
    switch (this) {
      case WeekType.every:
        return true;
      case WeekType.odd:
        return week.isOdd;
      case WeekType.even:
        return week.isEven;
    }
  }
}

WeekType? weekTypeFromCode(String s) {
  final t = s.trim();
  if (t.isEmpty || t == '空') return WeekType.every;
  if (t == '单') return WeekType.odd;
  if (t == '双') return WeekType.even;
  return null;
}

/// 补丁操作类型
enum PatchAction { add, replace, remove, modify }

extension PatchActionX on PatchAction {
  String get code {
    switch (this) {
      case PatchAction.add:
        return 'add';
      case PatchAction.replace:
        return 'replace';
      case PatchAction.remove:
        return 'remove';
      case PatchAction.modify:
        return 'modify';
    }
  }

  String get label {
    switch (this) {
      case PatchAction.add:
        return '新增叠加';
      case PatchAction.replace:
        return '覆盖';
      case PatchAction.remove:
        return '清空';
      case PatchAction.modify:
        return '仅改教师教室';
    }
  }
}

PatchAction? patchActionFromCode(String s) {
  final t = s.trim().toLowerCase();
  for (final a in PatchAction.values) {
    if (a.code == t) return a;
  }
  return null;
}

/// 补丁定位类型：精确日期 / 周序号
enum PatchLocationType { exactDate, weekOffset }

extension PatchLocationTypeX on PatchLocationType {
  String get code {
    switch (this) {
      case PatchLocationType.exactDate:
        return 'exactDate';
      case PatchLocationType.weekOffset:
        return 'weekOffset';
    }
  }
}

PatchLocationType? patchLocationTypeFromCode(String s) {
  final t = s.trim().toLowerCase();
  for (final l in PatchLocationType.values) {
    // code 为 camelCase（exactDate/weekOffset），两侧都小写再比较
    if (l.code.toLowerCase() == t) return l;
  }
  return null;
}
