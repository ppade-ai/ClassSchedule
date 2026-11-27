/// 存储层异常（地基一/四：写入失败绝不能静默）
///
/// 设计约束：
/// - 所有异常都带**给用户看的中文话术**，不需要 UI 再翻译一遍
/// - [StoreReadOnlyException] 继承 [StoreException]，上层一个 catch 就能兜住
/// - 不吞原始错误（[cause]），排查时还能拿到 OS 的原因
library;

/// 一次存储操作失败（读或写）
class StoreException implements Exception {
  const StoreException(this.message, {this.cause});

  /// 可直接展示给用户的一句话
  final String message;

  /// 原始异常（FileSystemException / FormatException 等）
  final Object? cause;

  @override
  String toString() => message;
}

/// 数据处于保护状态：读不懂的文件（未来版本 / 编码损坏 / 读失败）**禁止写入**
///
/// 这是"本地信息不可动"在代码里的落点：读不懂就别碰，
/// 宁可这一轮改不了，也不要把用户的新数据降级覆盖掉。
class StoreReadOnlyException extends StoreException {
  const StoreReadOnlyException(super.message, {super.cause});
}
