/// 数据相关的弹窗：存储位置 / 错误日志 / 学期归档
///
/// 从课表页的「更多」菜单搬到「我的」页后独立出来的：
/// 这些是"偶尔看一眼"的信息，不该挤在课表操作菜单里。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/diag/error_log.dart';
import '../timetable/backup_dialog.dart';
import '../timetable/timetable_controller.dart';

/// 数据存储位置（含补丁前 24 行预览、备份/日志/归档入口）
Future<void> showStorageInfo(
  BuildContext context,
  TimetableController c,
) async {
  String patchPreview = '';
  try {
    final lines = (await c.store.patchFile.readAsString()).split('\n');
    patchPreview = lines.take(24).join('\n');
    if (lines.length > 24) patchPreview += '\n…（共 ${lines.length} 行）';
  } catch (_) {
    patchPreview = '（读取失败）';
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('数据存储位置'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.store.rootPath}\n\n'
              'base_course.txt / course_patch.txt / exam_note.txt / time_config.ini\n'
              '备份在 backup/ 目录（每类保留 5 份）',
              style: const TextStyle(fontSize: 13),
            ),
            const Divider(),
            const Text(
              'course_patch.txt 内容：',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              patchPreview,
              style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            showBackupDialog(context, c);
          },
          child: const Text('备份与恢复'),
        ),
      ],
    ),
  );
}

/// 本地错误日志（不联网）：出问题时用户能复制一段文字过来
Future<void> showErrorLog(BuildContext context) async {
  final text = await ErrorLog.read();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('错误日志'),
      content: SizedBox(
        width: 460,
        height: 320,
        child: SingleChildScrollView(
          child: SelectableText(
            text.isEmpty ? '没有记录。' : text,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ErrorLog.clear();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('清空'),
        ),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
          },
          child: const Text('复制'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 学期归档：列出 archive/ 下归档（只读回看）+ 新建归档
Future<void> showArchiveManager(
  BuildContext context,
  TimetableController c,
) async {
  var names = <String>[];
  try {
    final dir = Directory('${c.store.rootPath}/archive');
    if (await dir.exists()) {
      names = await dir
          .list()
          .where((e) => e is Directory)
          .map((e) => e.uri.pathSegments.last)
          .toList();
      names.sort((a, b) => b.compareTo(a)); // 最新在前
    }
  } catch (_) {}
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('学期归档'),
      content: SizedBox(
        width: 420,
        child: names.isEmpty
            ? const Text(
                '暂无归档。可将当前课表归档保存为历史学期（只读）。',
                style: TextStyle(fontSize: 13),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '点击归档可只读回看：',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final n in names)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.folder),
                            title: Text(n),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () {
                              Navigator.pop(ctx);
                              _viewArchive(context, c, n);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.archive_outlined, size: 18),
          label: const Text('新建归档'),
          onPressed: () {
            Navigator.pop(ctx);
            _createArchive(context, c);
          },
        ),
      ],
    ),
  );
}

/// 新建归档：输入学期名 → 复制 base+patch+time_config 到 archive/<名>/
Future<void> _createArchive(BuildContext context, TimetableController c) async {
  final bm = c.baseMonday;
  final defaultName = '${bm.year}-${bm.year + 1}-${bm.month >= 8 ? 1 : 2}';
  final ctrl = TextEditingController(text: defaultName);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新建学期归档'),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(
          labelText: '学期名（如 2026-2027-1）',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('归档'),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty || !context.mounted) return;
  final saved = await c.archiveSemester(name);
  if (!context.mounted) return;
  final note = saved == name ? '' : '（名字已改为 "$saved"：只允许安全字符）';
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('已归档到 archive/$saved/$note')));
}

/// 只读回看归档内容（base + patch 文本）
Future<void> _viewArchive(
  BuildContext context,
  TimetableController c,
  String name,
) async {
  var b = '';
  var p = '';
  try {
    b = await File('${c.store.rootPath}/archive/$name/base_course.txt')
        .readAsString();
  } catch (_) {}
  try {
    p = await File('${c.store.rootPath}/archive/$name/course_patch.txt')
        .readAsString();
  } catch (_) {}
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('归档：$name'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'base_course.txt：',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              Text(
                b.isEmpty ? '（空）' : b,
                style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              const Text(
                'course_patch.txt：',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              Text(
                p.isEmpty ? '（空）' : p,
                style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
