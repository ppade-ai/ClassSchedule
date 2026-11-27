/// 备份与恢复（地基六：让 backup/ 真正能被拿回来）
///
/// 以前只在存储弹窗里写一句"备份在 backup/ 目录"，可 App 私有目录
/// 普通用户根本进不去——等于有保险箱没配钥匙。
library;

import 'package:flutter/material.dart';

import '../../core/store/backup_entry.dart';
import 'timetable_controller.dart';

/// 打开备份列表（同一次备份产生的 base/patch/config 合成一组）
Future<void> showBackupDialog(
  BuildContext context,
  TimetableController c,
) async {
  List<BackupEntry> entries;
  try {
    entries = await c.listBackups();
  } catch (_) {
    entries = const [];
  }
  if (!context.mounted) return;

  // 按「类型 + 时间戳」分组，恢复时整组一起回去
  final groups = <String, List<BackupEntry>>{};
  for (final e in entries) {
    groups.putIfAbsent(e.groupKey, () => []).add(e);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) => groups[b]!.first.time.compareTo(groups[a]!.first.time));

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('备份与恢复'),
      content: SizedBox(
        width: 460,
        child: keys.isEmpty
            ? const Text(
                '暂无备份。每次编辑/批量导入前会自动备份一份（每类保留最近 5 份）。',
                style: TextStyle(fontSize: 13, height: 1.4),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '点「恢复」用旧备份覆盖当前数据。恢复前会自动把当前状态再备份一份。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final k in keys)
                          _BackupTile(
                            group: groups[k]!,
                            onRestore: (g) =>
                                _confirmRestore(context, ctx, c, g),
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
      ],
    ),
  );
}

class _BackupTile extends StatelessWidget {
  final List<BackupEntry> group;
  final void Function(List<BackupEntry>) onRestore;

  const _BackupTile({required this.group, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final head = group.first;
    final detail = group.map((e) => '${e.fileText} ${e.sizeText}').join(' / ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history, size: 20),
      title: Text(
        '${head.timeText} · ${head.kindText}',
        style: const TextStyle(fontSize: 13.5),
      ),
      subtitle: Text(detail, style: const TextStyle(fontSize: 11.5)),
      trailing: TextButton(
        onPressed: () => onRestore(group),
        child: const Text('恢复'),
      ),
    );
  }
}

Future<void> _confirmRestore(
  BuildContext pageContext,
  BuildContext listContext,
  TimetableController c,
  List<BackupEntry> group,
) async {
  final ok = await showDialog<bool>(
    context: listContext,
    builder: (ctx) => AlertDialog(
      title: const Text('恢复这份备份？'),
      content: Text(
        '将用 ${group.first.timeText} 的备份覆盖当前 ${group.length} 个文件。\n\n'
        '恢复前会先把当前状态备份一份（类型：恢复前），所以这一步可以反悔。',
        style: const TextStyle(fontSize: 13, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('恢复'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  final error = await c.restoreFromBackup(group);

  if (listContext.mounted) Navigator.pop(listContext);
  if (!pageContext.mounted) return;
  ScaffoldMessenger.of(pageContext).showSnackBar(
    SnackBar(
      content: Text(
        error == null ? '已恢复到 ${group.first.timeText} 的备份' : '恢复失败：$error',
      ),
      duration: const Duration(seconds: 6),
    ),
  );
}
