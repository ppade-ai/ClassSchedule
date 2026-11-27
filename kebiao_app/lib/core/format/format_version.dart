/// 数据格式版本（不变量 I11：格式版本化）
///
/// 规则：
/// - 每个数据文件首行为 `#FORMAT vN`；**没有版本行的旧文件按 v1 处理**（向后兼容）
/// - 声明版本高于 App 支持版本 → **拒绝加载并说明原因**，绝不静默按 v1 解析
/// - 字段语义变更必须让版本号 +1 并补一个迁移器（见 migrator.dart）
///
/// 这里只做"读出与写回"，不做任何迁移；迁移由 Migrator 负责。
library;

/// 当前 App 支持的格式版本
const int kFormatVersion = 1;

/// 写入文件时使用的版本行
const String kFormatHeader = '#FORMAT v$kFormatVersion';

/// 版本行（允许 `# FORMAT v1` 这类宽松写法，避免手改文件后读不出来）
final RegExp _headerPattern =
    RegExp(r'^\s*#\s*FORMAT\s+v(\d+)\s*$', caseSensitive: false);

/// 版本行解析结果
class FormatHeader {
  const FormatHeader({required this.version, required this.hasHeader});

  /// 文件声明的版本。无版本行时按 [kFormatVersion] 处理（旧文件）
  final int version;

  /// 文件里是否真的有版本行
  final bool hasHeader;

  /// 是否为"未来版本"（本 App 不认识）
  bool get isFuture => version > kFormatVersion;

  /// 是否为本 App 能读的版本
  bool get isSupported => version <= kFormatVersion;

  @override
  String toString() => 'FormatHeader(v$version, hasHeader: $hasHeader)';
}

/// 读出文件声明的格式版本
///
/// 只看**第一个非空行**：正常文件版本行在第一行，空文件/全空白视为 v1。
FormatHeader parseFormatHeader(String text) {
  for (final raw in text.split('\n')) {
    final line = raw.replaceAll('\r', '');
    if (line.trim().isEmpty) continue;
    final m = _headerPattern.firstMatch(line);
    if (m != null) {
      return FormatHeader(version: int.parse(m.group(1)!), hasHeader: true);
    }
    break; // 第一个非空行不是版本行 → 旧文件
  }
  return const FormatHeader(version: kFormatVersion, hasHeader: false);
}

/// 是否为注释/版本行（解析器逐行处理时应跳过）
bool isFormatCommentLine(String line) => line.trimLeft().startsWith('#');

/// 给正文加上版本行；正文为空时只写版本行
String withFormatHeader(String body) {
  final trimmed = body.replaceAll(RegExp(r'\s+$'), '');
  return trimmed.isEmpty ? kFormatHeader : '$kFormatHeader\n$trimmed';
}

/// 去掉版本行，返回纯正文（迁移器与测试用）
String stripFormatHeader(String text) {
  final lines = text.split('\n');
  final out = <String>[];
  var dropped = false;
  for (final raw in lines) {
    final line = raw.replaceAll('\r', '');
    if (!dropped && line.trim().isEmpty) continue;
    if (!dropped && _headerPattern.hasMatch(line)) {
      dropped = true;
      continue;
    }
    out.add(line);
  }
  return out.join('\n');
}

/// 数据文件声明了本 App 不认识的更高版本
///
/// 用异常而不是"返回空列表"：空列表会被上层当成"没有课表"，
/// 用户看到的是空白而不是"你的文件比我新"，那等于静默丢数据。
class UnsupportedFormatVersion implements Exception {
  const UnsupportedFormatVersion({required this.found, this.supported = kFormatVersion});

  final int found;
  final int supported;

  /// 给用户看的一句话（不要用技术黑话）
  String get message => '课表文件格式是 v$found，这个版本只认到 v$supported。'
      '请先更新 App，不要用旧版打开，否则可能把数据改坏。';

  @override
  String toString() => message;
}
