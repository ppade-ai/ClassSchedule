/// 「我的」：所有设置与数据入口集中在这里
///
/// 课表页右上角的「更多」只保留高频操作（编辑总入口 / 复制本周文本 / 颜色模式），
/// 偶尔才用的设置都收到这个页面，避免菜单越加越长。
library;

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../skill/skill_page.dart';
import '../timetable/backup_dialog.dart';
import '../timetable/period_dialog.dart';
import '../timetable/timetable_controller.dart';
import 'data_dialogs.dart';
import 'display_dialog.dart';
import 'term_dialog.dart';

class SettingsPage extends StatelessWidget {
  final TimetableController controller;

  const SettingsPage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final c = controller;
          final first = c.periodTimes.isEmpty
              ? '未设置'
              : c.periodTimes.first.text;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const _SectionTitle('课表设置'),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('作息时间'),
                subtitle: Text('第1节 $first · 共 ${c.periodCount} 节'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openPeriodTimesEditor(context, c),
              ),
              ListTile(
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('学期设置'),
                subtitle: Text(
                  '第1周 ${_fmt(c.baseMonday)} · 共 ${c.totalWeeks} 周',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showTermDialog(context, c),
              ),
              ListTile(
                leading: const Icon(Icons.format_size),
                title: const Text('字号与行高'),
                subtitle: Text(
                  '${fontLabel(c.fontScale)} · ${rowLabel(c.rowHeightBase)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDisplayDialog(context, c),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.palette_outlined),
                title: const Text('颜色模式'),
                subtitle: Text(
                  c.planningMode ? '展望：同课同色，看整学期分布' : '实时：全灰，只高亮当前这节课',
                ),
                value: c.planningMode,
                onChanged: (_) => c.toggleMode(),
              ),
              const Divider(height: 24),
              const _SectionTitle('数据管理'),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('备份与恢复'),
                subtitle: const Text('改坏了/误删了，回退到之前某一刻'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showBackupDialog(context, c),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('数据存储位置'),
                subtitle: const Text('看文件在哪、补丁内容长什么样'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showStorageInfo(context, c),
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('错误日志'),
                subtitle: const Text('出问题时复制一段文字给开发者（本地，不联网）'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showErrorLog(context),
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('学期归档'),
                subtitle: const Text('把当前学期存成只读历史，换学期时回看'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showArchiveManager(context, c),
              ),
              const Divider(height: 24),
              const _SectionTitle('其他'),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Skill 下载'),
                subtitle: const Text('交给 AI，让它生成通用课表文件'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SkillPage()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于'),
                subtitle: Text('v$kAppVersion ($kAppBuild) · 离线可用 · 无联网权限'),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
