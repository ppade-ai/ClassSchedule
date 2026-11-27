/// 校验问题模型（供 UI 标红 / 悬浮提示 / 预览列表）
library;

enum IssueSeverity { error, warning }

class Issue {
  final int line; // 行号（从 1 开始；0 = 非行级问题）
  final String message;
  final IssueSeverity severity;

  const Issue(this.message, {this.line = 0, this.severity = IssueSeverity.error});

  @override
  String toString() =>
      line > 0 ? '第$line行: $message' : message;
}

/// 解析结果：值 + 问题列表
class ParseResult<T> {
  final T? value;
  final List<Issue> issues;

  const ParseResult(this.value, this.issues);

  bool get ok => issues.isEmpty;
}
