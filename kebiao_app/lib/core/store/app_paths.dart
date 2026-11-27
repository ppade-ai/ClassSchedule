/// App 私有文件目录（零插件方案）
/// 真机：Kotlin MethodChannel 返回 filesDir（App 沙箱，无需任何权限）
/// 测试/桌面：systemTemp 兜底
library;

import 'dart:io';

import 'package:flutter/services.dart';

class AppPaths {
  static String? _filesDir;

  /// 测试专用覆写（优先于 MethodChannel）
  static String? overrideForTest;

  /// 测试重置（清缓存）
  static void resetForTest() {
    _filesDir = null;
  }

  static Future<String> filesDir() async {
    if (_filesDir != null) return _filesDir!;
    if (overrideForTest != null) {
      _filesDir = overrideForTest;
      return _filesDir!;
    }
    try {
      const ch = MethodChannel('kebiao/storage');
      final p = await ch.invokeMethod<String>('filesDir');
      if (p != null && p.isNotEmpty) {
        _filesDir = p;
        return p;
      }
    } catch (_) {
      // 非 Android 环境（测试/桌面）：走 systemTemp
    }
    final tmp = Directory.systemTemp.createTempSync('kebiao_app');
    _filesDir = tmp.path;
    return _filesDir!;
  }
}
