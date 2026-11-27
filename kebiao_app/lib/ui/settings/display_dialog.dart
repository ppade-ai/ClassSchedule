/// 字号与行高（合并成一个弹窗）
///
/// 为什么合并：这两组共 8 个档位，平铺进菜单会让菜单高达 ~800dp，
/// 展开时盖住右上角按钮且难以关闭。
library;

import 'package:flutter/material.dart';

import '../timetable/timetable_controller.dart';

Future<void> showDisplayDialog(
  BuildContext context,
  TimetableController c,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: const Text('字号与行高'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '字号（影响文字大小）',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final s in TimetableController.fontScaleOptions)
                    ChoiceChip(
                      label: Text(fontLabel(s)),
                      selected: c.fontScale == s,
                      onSelected: (_) => setDlg(() => c.setFontScale(s)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                '行高（影响一屏能看几节）',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final h in TimetableController.rowHeightOptions)
                    ChoiceChip(
                      label: Text(rowLabel(h)),
                      selected: c.rowHeightBase == h,
                      onSelected: (_) async {
                        await c.setRowHeight(h);
                        setDlg(() {});
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '行高只是下限：内容需要多高，格子就多高。'
                '调小只会压掉富余空间，不会把文字压出界。'
                '调行高不会触发重新测量，所以切换时不会闪。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade600,
                  height: 1.35,
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
    ),
  );
}

String fontLabel(double s) => switch (s) {
  0.8 => '小',
  1.0 => '中',
  1.2 => '大',
  1.4 => '特大',
  _ => '${s}x',
};

String rowLabel(double h) => switch (h) {
  40 => '紧凑 40',
  64 => '标准 64',
  80 => '宽松 80',
  96 => '很宽 96',
  _ => h.toInt().toString(),
};
