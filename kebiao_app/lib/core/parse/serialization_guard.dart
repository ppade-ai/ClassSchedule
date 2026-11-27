/// 序列化守卫：模型 → 标准行时，保证这一行**一定能被读回来**
///
/// 起因（实测）：课程名里带一个 `|` → 写出 14 字段 → 解析器判定字段数不符 →
/// 读回 null → 下次保存这门课就永久消失。用户只输入了一个字符。
///
/// 两道检查：
/// 1. 字段级：明确拒绝 `|`、换行、NUL，并指出是哪个字段（给用户可执行的提示）
/// 2. 行级：序列化后用解析器自己读一遍，读不回就拒绝写入（以后加字段也自动生效）
library;

import '../model/base_course.dart';
import '../model/exam_note.dart';
import '../model/patch.dart';
import '../store/store_error.dart';
import 'base_parser.dart';
import 'exam_parser.dart';
import 'patch_parser.dart';

/// 会破坏 `|` 分隔结构的字符
const List<String> _forbidden = ['|', '\n', '\r', '\u0000'];

/// 基础课 → 标准行（带守卫）
String safeBaseLine(BaseCourse c) {
  _check('课程名称', c.name);
  _check('教师', c.teacher);
  _check('教室', c.room);
  _check('颜色', c.color);
  _check('备注', c.remark);

  final line = baseCourseToLine(c);
  if (parseBaseLine(line).value == null) {
    throw StoreException('课程「${c.name}」写成文本后读不回来，已拒绝保存（避免把这行写坏）');
  }
  return line;
}

/// 补丁 → 标准行（带守卫）
String safePatchLine(Patch p) {
  _check('课程名称', p.name);
  _check('教师', p.teacher);
  _check('教室', p.room);
  _check('颜色', p.color);
  _check('定位值', p.locationValue);
  _check('备注', p.remark);

  final line = patchToLine(p);
  if (parsePatchLine(line).value == null) {
    throw StoreException('补丁「${p.name}」写成文本后读不回来，已拒绝保存（避免把这行写坏）');
  }
  return line;
}

/// 考试便签 → 标准行（带守卫）
String safeExamLine(ExamNote e) {
  _check('科目', e.subject);
  _check('地点', e.place);
  _check('备注', e.remark);
  _check('开始时间', e.startTime);
  _check('结束时间', e.endTime);

  final line = examToLine(e);
  if (parseExamLine(line).value == null) {
    throw StoreException('便签「${e.subject}」写成文本后读不回来，已拒绝保存');
  }
  return line;
}

void _check(String label, String value) {
  for (final ch in _forbidden) {
    if (!value.contains(ch)) continue;
    final shown = switch (ch) {
      '\n' => '换行',
      '\r' => '回车',
      '\u0000' => '空字符',
      _ => ch,
    };
    throw StoreException('「$label」里有不能保存的字符「$shown」，请改用全角「｜」或删掉换行后再保存');
  }
}
