/// 备注尾部 {JSON} 扩展块解析
/// 备注 = "纯文本说明 {json}"；无 JSON 块时退化纯文本（兼容旧数据）
library;

import 'dart:convert';

class RemarkParts {
  final String plain; // 去掉 JSON 块后的纯文本备注
  final Map<String, dynamic>? ext; // 解析出的结构化扩展（教学班/学时/考核等）

  const RemarkParts(this.plain, this.ext);

  bool get hasExt => ext != null;
}

/// 解析备注字段：尾部 {JSON} 扩展块
/// 规则：从最后一个 '{' 到字符串末尾的 '}' 视为候选 JSON；
/// 解析成功且为对象则拆分，否则整段当纯文本（不报错，兼容）
RemarkParts parseRemarkExt(String remark) {
  final r = remark.trim();
  final open = r.lastIndexOf('{');
  if (open < 0 || !r.endsWith('}')) {
    return RemarkParts(r, null);
  }
  final candidate = r.substring(open);
  try {
    final decoded = jsonDecode(candidate);
    if (decoded is Map<String, dynamic>) {
      final plain = r.substring(0, open).trim();
      return RemarkParts(plain, decoded);
    }
  } catch (_) {
    // 不是合法 JSON → 整段当纯文本
  }
  return RemarkParts(r, null);
}

/// 序列化：把结构化扩展写回备注尾部（plain + {json}）
String buildRemark(String plain, Map<String, dynamic>? ext) {
  final p = plain.trim();
  if (ext == null || ext.isEmpty) return p;
  return '$p ${jsonEncode(ext)}'.trim();
}
