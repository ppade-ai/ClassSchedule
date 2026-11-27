/// 批量文本编辑（M2.3 模式 B）
/// 大文本框粘贴标准行（基础课 13 字段 / 补丁 15 字段，| 分隔），
/// 300ms 节流实时逐行校验（错误行列表实时标红 + 原因），
/// 追加 / 覆盖两种写入模式，空模板一键插入，文本一键复制导出。
/// v0.15 新增：可直接粘贴「通用表格（CSV）」并一键转成标准行
/// （配合 assets/format/ 下的 AI Skill 与 CSV 模板使用）。
/// 设计依据：16.2-2-3（实时校验）/ 2-5（导入模式，此处先做追加/覆盖）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/model/base_course.dart';
import '../../core/model/patch.dart';
import '../../core/parse/base_parser.dart';
import '../../core/parse/csv_parser.dart';
import '../../core/parse/patch_parser.dart';
import '../../core/validate/issues.dart';
import '../../core/validate/validator.dart' show checkInputLimits;
import 'timetable_controller.dart';

enum _TargetKind { base, patch }

enum _WriteMode { append, overwrite }

class BatchTextPage extends StatefulWidget {
  final TimetableController controller;

  const BatchTextPage({super.key, required this.controller});

  @override
  State<BatchTextPage> createState() => _BatchTextPageState();
}

class _BatchTextPageState extends State<BatchTextPage> {
  final TextEditingController _text = TextEditingController();
  _TargetKind _target = _TargetKind.base;
  _WriteMode _mode = _WriteMode.append;
  Timer? _debounce;
  List<Issue> _issues = [];
  int _validCount = 0;
  bool _applying = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _validate);
  }

  void _validate() {
    final lines = _text.text.split('\n');
    final issues = <Issue>[];
    var valid = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      final r = _target == _TargetKind.base
          ? parseBaseLine(line, lineNumber: i + 1)
          : parsePatchLine(line, lineNumber: i + 1);
      if (r.issues.isEmpty) {
        valid++;
      } else {
        issues.addAll(r.issues);
      }
    }
    setState(() {
      _issues = issues;
      _validCount = valid;
    });
  }

  /// 错误行摘要：按行号合并原因（实时标红面板）
  List<String> _errorLines() {
    final byLine = <int, List<String>>{};
    for (final i in _issues) {
      byLine.putIfAbsent(i.line, () => []).add(i.message);
    }
    final keys = byLine.keys.toList()..sort();
    return [for (final k in keys) '第 $k 行：${byLine[k]!.join('；')}'];
  }

  String _templateFor(_TargetKind t) {
    if (t == _TargetKind.base) {
      return [
        '# 基础课表标准行（13 字段，| 分隔）',
        '# 名称|类型|教师|教室|星期|起始节|结束节|起始周|结束周|周类型|颜色|备注|id',
        '# 示例（id 留空自动分配）：',
        '高等数学|★|李老师|教3101|1|1|2|1|17||#8ecae6||',
      ].join('\n');
    }
    return [
      '# 补丁标准行（15 字段，| 分隔）',
      '# 定位类型|定位值|星期|起始节|结束节|周类型|操作|名称|类型|教师|教室|颜色|过期|备注|id',
      '# 定位类型：exactDate(公历日期) / weekOffset(周序号)；操作：add/replace/remove/modify',
      '# 示例（第 3 周周一 3-4 节加课，id 留空自动分配）：',
      'weekOffset|3|1|3|4||add|线性代数|★|孙老师|教3205|#f4a261|||',
    ].join('\n');
  }

  Future<void> _apply() async {
    if (_applying) return;

    // 大小/行数闸门：5MB、2 万行（以前写在 validator 里但没人调用）
    final limitIssues = checkInputLimits(_text.text, source: '粘贴内容');
    final fatal = limitIssues
            ?.where((i) => i.severity == IssueSeverity.error)
            .toList() ??
        const [];
    if (fatal.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('内容太大'),
          content: Text('${fatal.first.message}\n\n请拆成几批导入。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final errors = _errorLines();
    if (errors.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('存在错误行'),
          content: Text('仍有 ${errors.length} 行校验不通过，将被忽略。\n\n${errors.take(5).join('\n')}${errors.length > 5 ? '\n…' : ''}\n\n继续保存有效行？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('返回修改')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('忽略并保存')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => _applying = true);
    try {
      final valid = <dynamic>[];
      final lines = _text.text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
        final r = _target == _TargetKind.base
            ? parseBaseLine(line, lineNumber: i + 1)
            : parsePatchLine(line, lineNumber: i + 1);
        if (r.issues.isEmpty && r.value != null) valid.add(r.value);
      }
      if (_target == _TargetKind.base) {
        if (_mode == _WriteMode.overwrite) {
          await widget.controller.replaceAllBaseCourses(valid.cast<BaseCourse>());
        } else {
          await widget.controller.appendBaseCourses(valid.cast<BaseCourse>());
        }
      } else {
        if (_mode == _WriteMode.overwrite) {
          await widget.controller.replaceAllPatches(valid.cast<Patch>());
        } else {
          await widget.controller.appendPatches(valid.cast<Patch>());
        }
      }
      if (!mounted) return;
      final verb = _mode == _WriteMode.append ? '追加' : '覆盖写入';
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('已$verb ${valid.length} 行（${_target == _TargetKind.base ? '基础课' : '补丁'}）')),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// 「通用表格（CSV）→ 标准行」：把 AI Skill 生成的通用文件转成内核标准行。
  /// 转换后**复用同一套校验器**（下方实时校验会立刻核对），不新增第二套规则。
  Future<void> _convertCsv() async {
    final r = CsvConverter.convert(_text.text);
    if (!r.ok) {
      await _showCsvReport(r, title: '未能转换');
      return;
    }
    setState(() {
      _target = r.target == CsvTarget.patch ? _TargetKind.patch : _TargetKind.base;
      _text.text = r.standardText;
      _text.selection =
          TextSelection.collapsed(offset: _text.text.length);
      _validate();
    });
    if (r.skipped > 0) {
      await _showCsvReport(r, title: '已转换 ${r.converted} 行，跳过 ${r.skipped} 行');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通用表格：已转换 ${r.converted} 行，请检查后点「应用」')),
      );
    }
  }

  Future<void> _showCsvReport(CsvConversionResult r, {required String title}) async {
    final targetLabel = switch (r.target) {
      CsvTarget.base => '基础课表',
      CsvTarget.patch => '补丁表',
      CsvTarget.unknown => '未识别',
    };
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('识别为：$targetLabel', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              if (r.issues.isEmpty)
                const Text('无具体原因（内容为空或不是通用表格）。', style: TextStyle(fontSize: 13))
              else ...[
                const Text('以下行未转换（不会进入课表）：', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                for (final i in r.issues.take(20))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      i.line > 0 ? '第${i.line}行：${i.message}' : i.message,
                      style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
                    ),
                  ),
                if (r.issues.length > 20)
                  Text('（另有 ${r.issues.length - 20} 条未显示）',
                      style: const TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 12),
              const Text(
                '提示：请使用「更多 → Skill 下载」把模板与说明交给 AI，'
                '让它按模板表头生成通用文件。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final errors = _errorLines();
    return Scaffold(
      appBar: AppBar(
        title: const Text('批量文本编辑'),
        actions: [
          IconButton(
            tooltip: '复制全部文本',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _text.text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
            },
          ),
          TextButton(
            onPressed: _applying ? null : _apply,
            child: const Text('应用'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<_TargetKind>(
                      segments: const [
                        ButtonSegment(value: _TargetKind.base, label: Text('基础课表'), icon: Icon(Icons.event_note, size: 16)),
                        ButtonSegment(value: _TargetKind.patch, label: Text('补丁表'), icon: Icon(Icons.build, size: 16)),
                      ],
                      selected: {_target},
                      onSelectionChanged: (s) => setState(() {
                        _target = s.first;
                        _validate();
                      }),
                    ),
                    SegmentedButton<_WriteMode>(
                      segments: const [
                        ButtonSegment(value: _WriteMode.append, label: Text('追加')),
                        ButtonSegment(value: _WriteMode.overwrite, label: Text('覆盖')),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) => setState(() => _mode = s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 用 Wrap 而非 Row：360dp 屏放不下「状态 + 3 个按钮」时自动换行，不溢出
                Wrap(
                  spacing: 4,
                  runSpacing: 0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '有效 $_validCount 行 · 错误 ${errors.length} 行',
                        style: TextStyle(
                          fontSize: 12,
                          color: errors.isEmpty ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _text.text = _templateFor(_target);
                        _text.selection = TextSelection.collapsed(offset: _text.text.length);
                        _validate();
                      }),
                      icon: const Icon(Icons.article_outlined, size: 16),
                      label: const Text('空模板'),
                    ),
                    TextButton.icon(
                      onPressed: _convertCsv,
                      icon: const Icon(Icons.table_chart_outlined, size: 16),
                      label: const Tooltip(
                        message: '把 CSV 通用表格转成标准行（配合「更多 → Skill 下载」使用）',
                        child: Text('通用表格'),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _text.clear();
                        _validate();
                      }),
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('清空'),
                    ),
                  ],
                ),
                const Divider(height: 8),
              ],
            ),
          ),
          Expanded(
            child: TextField(
              controller: _text,
              onChanged: (_) => _onTextChanged(),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace', height: 1.4),
              decoration: const InputDecoration(
                hintText: '在此粘贴标准行，每行一条…\n支持 # 开头注释行与空行\n\n基础课：名称|类型|教师|教室|星期|起始节|结束节|起始周|结束周|周类型|颜色|备注|id\n补丁：定位类型|定位值|星期|起始节|结束节|周类型|操作|名称|类型|教师|教室|颜色|过期|备注|id',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          if (errors.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              width: double.infinity,
              color: Colors.red.withValues(alpha: 0.08),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                    child: Text(
                      '错误行（实时校验）',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      itemCount: errors.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          errors[i],
                          style: TextStyle(fontSize: 11.5, color: Colors.red.shade800),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
