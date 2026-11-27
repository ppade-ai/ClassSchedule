/// App 根组件（主题 + 首页）
///
/// 单独一个文件是为了让测试能直接 pump 它，而不必引入 `main.dart` 里的 `main()`。
library;

import 'package:flutter/material.dart';

import 'home_shell.dart';

class KebiaoApp extends StatelessWidget {
  const KebiaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3F6FD8);
    return MaterialApp(
      title: '课表',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system, // 跟随系统（浅色/深色）
      home: const HomeShell(),
    );
  }
}
