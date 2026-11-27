/// 本地错误日志（不联网、不上传）
///
/// 为什么需要：release 包没有控制台，出了异常我这边什么也看不到，
/// 只能让用户"重装试试"。有本地日志，用户能复制一段文字过来。
///
/// 约束：记录本身**绝不能抛异常**（否则异常处理器里再抛就死循环）。
library;

import 'dart:io';

import '../store/app_paths.dart';

class ErrorLog {
  /// 保留最近多少条
  static const int keepEntries = 20;

  /// 超过这个大小就裁掉一半
  static const int maxBytes = 64 * 1024;

  static Future<File> _file() async {
    final dir = Directory('${await AppPaths.filesDir()}/logs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/errors.log');
  }

  /// 记一条（永不抛异常）
  static Future<void> record(
    String source,
    Object error,
    StackTrace? stack,
  ) async {
    try {
      final f = await _file();
      final ts = DateTime.now().toIso8601String();
      final head = '[$ts][$source] $error';
      final body = stack == null ? head : '$head\n$stack';
      final sep = List.filled(48, '-').join();
      final entry = '$body\n$sep\n';

      var old = '';
      if (await f.exists()) {
        old = await f.readAsString();
      }
      var text = '$entry$old';
      if (text.length > maxBytes) {
        text = text.substring(0, maxBytes ~/ 2);
      }
      await f.writeAsString(text, flush: true);
    } catch (_) {
      // 日志失败不影响用户
    }
  }

  /// 读出全部内容（供"复制诊断信息"）
  static Future<String> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return '';
      return await f.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
