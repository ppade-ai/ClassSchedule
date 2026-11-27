/// 路径片段消毒
///
/// 名字会来自用户输入（学期名）或未来的插件规则（学校 ID、文件名）。
/// 直接拼进路径时，`../` 能跳出归档目录、`/` 能造出意料之外的层级。
/// 这里把任意字符串压成**单级、安全、可读**的片段。
///
/// 规则（宁可改名，不许越界）：
/// - 路径分隔符、Windows 保留字符、控制字符 → `_`
/// - 连续的 `..` → `_`（`../..` 去掉分隔符后仍不能留下穿透语义）
/// - `.` / `..` / 空 / 全是符号 → 回退到 fallback
/// - 去掉首尾的点与空白（以点开头会被当成隐藏文件）
/// - 最长 60 字符，避免超过文件系统上限
library;

/// 保留字符（路径分隔、通配符、Windows 不允许的字符）
final RegExp _illegal = RegExp(r'[\x00-\x1f\\/:*?"<>|]');

/// 连续空白
final RegExp _spaces = RegExp(r'\s+');

/// 两个以上连续的点
final RegExp _dots = RegExp(r'\.{2,}');

/// 首尾的点与空白
final RegExp _edgeDots = RegExp(r'^[.\s]+|[.\s]+$');

/// 是否含有真正的内容（不只是点、下划线、空白）
final RegExp _hasContent = RegExp(r'[^_.\s]');

String safeSegment(String raw, {String fallback = 'unnamed'}) {
  var s = raw.trim();
  if (s.isEmpty) return fallback;
  if (s == '.' || s == '..') return fallback;

  s = s.replaceAll(_illegal, '_');
  s = s.replaceAll(_spaces, ' ');
  s = s.replaceAll(_dots, '_');
  s = s.replaceAll(_edgeDots, '');

  if (s.isEmpty || !_hasContent.hasMatch(s)) return fallback;

  if (s.length > 60) s = s.substring(0, 60).trim();
  if (s.isEmpty) return fallback;
  return s;
}

/// 名字是否已经安全（用于测试与断言）
bool isSafeSegment(String s) =>
    s.isNotEmpty &&
    !s.contains('/') &&
    !s.contains('\\') &&
    s != '.' &&
    s != '..' &&
    !_illegal.hasMatch(s);
