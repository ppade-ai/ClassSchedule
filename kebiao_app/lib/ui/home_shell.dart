/// 应用壳：底部 4 Tab（日程/课表/学习/我的），共享课表控制器
///
/// v0.18.1 起这里还负责两件事：
/// - 数据处于**只读保护**时，顶部常驻一条横幅（读不懂的文件不写）
/// - 保存失败时立刻弹提示（直写式保存失败 = 内存没变，界面不能装作成功）
library;

import 'package:flutter/material.dart';

import 'placeholder_tab.dart';
import 'schedule_tab.dart';
import 'settings/settings_page.dart';
import 'timetable/timetable_controller.dart';
import 'timetable/timetable_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final TimetableController _controller = TimetableController();
  int _index = 1; // 默认课表 Tab

  /// 已经提示过的保存错误（避免同一条反复弹）
  String? _shownStorageError;

  /// 上一次的只读状态（变化时才重建，避免每换一周都 setState）
  bool _lastReadOnly = false;

  @override
  void initState() {
    super.initState();
    _lastReadOnly = _controller.readOnly;
    _controller.addListener(_onControllerChanged);
    _controller.loadDemo().then((_) {
      if (!mounted) return;
      final err = _controller.loadError;
      if (err != null) {
        // 数据读不懂：明确告诉用户原因，而不是给一张空白课表让他以为是数据没了
        _showMessage(err, seconds: 12);
        return;
      }
      if (_controller.loadWarnings.isNotEmpty) {
        _showMessage(
          _controller.loadWarnings.join('\n'),
          seconds: 10,
          actionLabel: '查看',
          onAction: _showLoadIssues,
        );
      }
    });
  }

  void _onControllerChanged() {
    // 只读状态变化时重建（横幅在 IndexedStack 外层，不会跟着子页面刷新）
    if (_controller.readOnly != _lastReadOnly && mounted) {
      setState(() => _lastReadOnly = _controller.readOnly);
    }

    final err = _controller.storageError;
    if (err == null || err == _shownStorageError) return;
    _shownStorageError = err;
    _showMessage('保存失败：$err', seconds: 8);
  }

  void _showMessage(
    String text, {
    required int seconds,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(text),
            duration: Duration(seconds: seconds),
            action: SnackBarAction(
              label: actionLabel ?? '知道了',
              onPressed: onAction ?? () {},
            ),
          ),
        );
    });
  }

  /// 坏行明细：哪几行、为什么、副本在哪
  Future<void> _showLoadIssues() async {
    final issues = _controller.loadIssues;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('有 ${issues.length} 行无法识别'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '这些行的原文已另存到 corrupt/ 目录（没有删除）。'
                  '它们不会显示在课表里；下次保存时也不会再写回主文件。',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                for (final i in issues.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '第${i.line}行：${i.message}',
                      style: const TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                if (issues.length > 10)
                  Text(
                    '…另有 ${issues.length - 10} 行',
                    style: const TextStyle(fontSize: 12.5),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 只读保护横幅：常驻可见，说明"这次改动不会写入磁盘"
          if (_controller.readOnly)
            _ReadOnlyBanner(reason: _controller.readOnlyReason),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                ScheduleTab(controller: _controller),
                TimetablePage(controller: _controller),
                const PlaceholderTab(
                  icon: Icons.school,
                  title: '学习',
                  subtitle: '学习功能（插件预留）',
                ),
                SettingsPage(controller: _controller),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: '日程',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: '课表',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: '学习',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

/// 只读保护横幅
class _ReadOnlyBanner extends StatelessWidget {
  final String? reason;

  const _ReadOnlyBanner({this.reason});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        color: scheme.errorContainer,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '只读保护：${reason ?? '数据文件无法读取'}。为避免覆盖你的数据，本次不会写入任何改动。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
