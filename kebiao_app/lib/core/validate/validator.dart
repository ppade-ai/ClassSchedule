/// 文件级输入防护（17.2 B7 已确认）
/// 上限：单文件 ≤5MB、单次解析 ≤2 万行、行长 ≤2000、名称 ≤100 字符
/// 防止恶意/异常文本引发解析死循环或内存溢出
library;

import 'dart:convert';

import 'issues.dart';

/// 文件级防护常量
const int kMaxFileBytes = 5 * 1024 * 1024; // 5MB
const int kMaxLines = 20000;
const int kMaxLineLength = 2000;
const int kMaxNameLength = 100;

/// 对整份文本做输入防护检查；通过返回 null，违规返回 Issue 列表
List<Issue>? checkInputLimits(String text, {String source = '输入'}) {
  final issues = <Issue>[];

  // 文件大小（UTF-8 实际字节数，中文按 3 字节计）
  final bytes = utf8.encode(text).length;
  if (bytes > kMaxFileBytes) {
    issues.add(Issue('$source超过大小上限（5MB）', severity: IssueSeverity.error));
  }

  // 行数
  final lines = text.split('\n');
  if (lines.length > kMaxLines) {
    issues.add(Issue('$source行数(${lines.length})超过上限（$kMaxLines 行）', severity: IssueSeverity.error));
    return issues; // 行数超限直接拒绝，不再逐行解析
  }

  // 行长
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].length > kMaxLineLength) {
      issues.add(Issue('第${i + 1}行超长（${lines[i].length} > $kMaxLineLength）', line: i + 1));
      // 只报前 20 个，避免海量 issue
      if (issues.length >= 20) break;
    }
  }

  return issues.isEmpty ? null : issues;
}

/// 字段长度校验（名称等）
bool isValidNameLength(String name) => name.length <= kMaxNameLength;
