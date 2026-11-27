/// 读取结果：值 + 坏行清单 + 隔离副本位置
///
/// 以前 `loadBaseCourses` 只回一个 List，解析问题在那一层就蒸发了：
/// 坏行既不报错也不留副本，用户下次保存时它们就永久没了。
library;

import '../validate/issues.dart';

class LoadResult<T> {
  final T value;

  /// 无法识别的行（行号 + 原因）；空 = 全部读成功
  final List<Issue> issues;

  /// 隔离副本的路径（null = 没有坏行）
  final String? quarantinedPath;

  const LoadResult(
    this.value, {
    this.issues = const <Issue>[],
    this.quarantinedPath,
  });

  bool get ok => issues.isEmpty;
  int get badLineCount => issues.length;

  /// 给用户看的一句话
  String get summary =>
      ok ? '' : '有 $badLineCount 行无法识别，原文已另存到 corrupt/（下次保存会从主文件移除）';

  /// 诊断用：前 [limit] 条明细
  List<Issue> firstIssues([int limit = 5]) =>
      issues.length <= limit ? issues : issues.sublist(0, limit);
}
