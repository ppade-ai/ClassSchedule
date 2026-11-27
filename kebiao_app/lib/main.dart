/// 课表 App 入口
///
/// v0.18.1 起装了全局错误边界：任何未捕获异常都落到本地 `logs/errors.log`
/// （不联网、不上传），用户可在「数据存储位置 → 错误日志」里复制出来。
/// 没有它，release 包出问题只能让用户"重装试试"。
library;

import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'core/diag/error_log.dart';
import 'ui/kebiao_app.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        ErrorLog.record('flutter', details.exception, details.stack);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        ErrorLog.record('async', error, stack);
        return true; // 已处理，不要让它把 App 打崩
      };

      runApp(const KebiaoApp());
    },
    (error, stack) {
      ErrorLog.record('zone', error, stack);
    },
  );
}
