/// Skill 下载页：把「给 AI 的说明（Skill）」与「通用文件 CSV 模板」交给用户。
///
/// 为什么用「复制」而不是「下载文件」：
///   本 App 刻意保持**零第三方依赖、零网络权限**。写文件到手机共享目录需要引入
///   SAF/file_picker 依赖，而「复制到剪贴板 → 粘贴到微信/备忘录/电脑」对用户是等价可达的。
///   若后续确实需要真·文件下载/分享，再单独引入 share_plus 并在此页加按钮即可。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;

class SkillPage extends StatefulWidget {
  const SkillPage({super.key});

  @override
  State<SkillPage> createState() => _SkillPageState();
}

class _SkillPageState extends State<SkillPage> {
  static const _pathSkill = 'assets/format/ai_skill.md';
  static const _pathBase = 'assets/format/base_template.csv';
  static const _pathPatch = 'assets/format/patch_template.csv';

  String? _skill;
  String? _base;
  String? _patch;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await rootBundle.loadString(_pathSkill);
      final b = await rootBundle.loadString(_pathBase);
      final p = await rootBundle.loadString(_pathPatch);
      if (!mounted) return;
      setState(() {
        _skill = s;
        _base = b;
        _patch = p;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label 已复制到剪贴板')));
  }

  String get _allText =>
      '===== ① 给 AI 的说明（Skill）=====\n${_skill ?? ''}\n\n'
      '===== ② 通用文件模板·基础课 =====\n${_base ?? ''}\n\n'
      '===== ③ 通用文件模板·调课 =====\n${_patch ?? ''}\n';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skill 下载'),
        actions: [
          IconButton(
            tooltip: '一次复制全部（Skill + 两个模板）',
            icon: const Icon(Icons.copy_all),
            onPressed: (_skill == null) ? null : () => _copy(_allText, '全部内容'),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('读取失败：$_error')))
          : _skill == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    _buildHowTo(),
                    const SizedBox(height: 14),
                    _buildBlock(
                      index: '①',
                      title: 'Skill（给 AI 的说明）',
                      subtitle: '连同你的教务课表一起发给任意 AI，让它按规范输出通用文件',
                      body: _skill!,
                      copyLabel: 'Skill',
                    ),
                    const SizedBox(height: 12),
                    _buildBlock(
                      index: '②',
                      title: '通用文件模板 · 基础课',
                      subtitle: 'CSV：一行一条课程，可直接在 Excel/WPS 里填',
                      body: _base!,
                      copyLabel: '基础课模板',
                    ),
                    const SizedBox(height: 12),
                    _buildBlock(
                      index: '③',
                      title: '通用文件模板 · 调课 / 临时课',
                      subtitle: 'CSV：只影响指定周或指定日期的变动',
                      body: _patch!,
                      copyLabel: '调课模板',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '说明：本 App 不联网、不申请任何权限，所以这里用「复制」代替「下载文件」——\n'
                      '复制后粘贴到微信、备忘录或电脑上的 .csv 文件即可。',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
    );
  }

  Widget _buildHowTo() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('怎么用（4 步）',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _step('1', '复制 ① Skill 与 ② 模板，连同你的教务课表（PDF / Excel / 截图）一起发给 AI'),
            _step('2', 'AI 按规范输出 CSV —— 这就是「通用文件」'),
            _step('3', '回到「编辑总入口 → 批量文本」，粘贴 CSV，点「通用表格」转成标准行'),
            _step('4', '检查「有效 N 行 · 错误 M 行」，点「应用」（追加或覆盖）'),
            const SizedBox(height: 6),
            Text(
              'AI 出错也不会污染课表：每一行都会过 App 的校验器，错误行会被拒绝并给出原因。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1, right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(n,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildBlock({
    required String index,
    required String title,
    required String subtitle,
    required String body,
    required String copyLabel,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('$index $title',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  onPressed: () => _copy(body, copyLabel),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制'),
                ),
              ],
            ),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                child: Text(
                  body,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
