/// 文件存储实现：`schools/<学校ID>/` 真实文件读写（M2）
/// 纯文本哲学：base_course.txt / course_patch.txt / time_config.ini / backup/
/// 零插件：路径来自 AppPaths（MethodChannel），文件 IO 用 dart:io
///
/// v0.18.1 起的三条硬约束：
/// 1. **原子写**：任何写都走 stage→verify→rename→verify，主文件永不停留在半截状态
/// 2. **写队列**：同一 store 的写操作串行，两次快速保存不会互相覆盖
/// 3. **只读锁**：读不懂的文件（未来版本/编码坏/读失败）禁止写入，避免降级覆盖
library;

import 'dart:io';

import '../format/format_version.dart';
import '../model/base_course.dart';
import '../model/exam_note.dart';
import '../model/patch.dart';
import '../parse/base_parser.dart';
import '../parse/exam_parser.dart';
import '../parse/line_audit.dart';
import '../parse/patch_parser.dart';
import '../parse/serialization_guard.dart';
import '../validate/issues.dart' show IssueSeverity;
import '../validate/validator.dart' show checkInputLimits;
import 'app_paths.dart';
import 'atomic_file.dart';
import 'backup_entry.dart';
import 'load_result.dart';
import 'safe_path.dart';
import 'school_store.dart';
import 'store_error.dart';

class FileSchoolStore implements SchoolStore {
  @override
  final String schoolId;

  /// 数据根目录（`init()` 里赋值；恢复流程会重新 init，所以不能是 final）
  late String rootPath;

  final WriteQueue _queue = WriteQueue();

  bool _readOnly = false;
  String? _readOnlyReason;

  FileSchoolStore(this.schoolId);

  @override
  bool get isReadOnly => _readOnly;

  @override
  String? get readOnlyReason => _readOnlyReason;

  @override
  void lockReadOnly(String reason) {
    _readOnly = true;
    _readOnlyReason = reason;
  }

  /// 通过了一次完整读取后解除保护（测试与"重新加载"用）
  void unlock() {
    _readOnly = false;
    _readOnlyReason = null;
  }

  /// 初始化目录结构（`schools/<id>/` 及其子目录）
  ///
  /// [safeSegment]：学校 ID 将来会来自插件规则，不能直接当路径用。
  Future<void> init() async {
    rootPath = '${await AppPaths.filesDir()}/schools/${safeSegment(schoolId)}';
    for (final d in ['', 'backup', 'archive', 'corrupt']) {
      await Directory(d.isEmpty ? rootPath : '$rootPath/$d')
          .create(recursive: true);
    }
    // 清理上次崩溃残留的 *.tmp（它们没有 rename 成功，内容不可信）
    await sweepTempFiles(Directory(rootPath));
  }

  File get baseFile => File('$rootPath/base_course.txt');
  File get patchFile => File('$rootPath/course_patch.txt');
  File get examFile => File('$rootPath/exam_note.txt');
  File get timeConfigFile => File('$rootPath/time_config.ini');

  // ---------------- 读 ----------------

  /// 读文件；不存在返回 null
  ///
  /// 读失败（权限/编码）**一律锁只读**：读不懂的文件，写它就是把数据改坏。
  Future<String?> _readText(File f) async {
    if (!await f.exists()) return null;
    try {
      return await f.readAsString();
    } on FileSystemException catch (e) {
      lockReadOnly('无法读取 ${_name(f)}：${e.osError?.message ?? e.message}');
      throw StoreException('读取失败：${e.osError?.message ?? e.message}', cause: e);
    } on FormatException catch (e) {
      // 非 UTF-8 字节
      lockReadOnly('${_name(f)} 编码损坏（文件不是 UTF-8 文本）');
      throw StoreException('${_name(f)} 编码损坏，已进入保护模式（不会覆盖该文件）', cause: e);
    }
  }

  /// 读文件前的版本闸门：未来版本 → 锁只读 + 抛 [UnsupportedFormatVersion]
  ///
  /// **不静默按 v1 解析**（那会把新字段当垃圾读掉，等于改坏用户的文件）
  void _ensureReadable(String text, File f) {
    final h = parseFormatHeader(text);
    if (!h.isSupported) {
      lockReadOnly('${_name(f)} 格式为 v${h.version}，本 App 只支持到 v$kFormatVersion');
      throw UnsupportedFormatVersion(found: h.version);
    }
  }

  /// 大小闸门：超过 5MB / 2 万行 → 拒绝加载（防止卡死或内存爆掉）
  ///
  /// 这两条上限以前写在 validator.dart 里但**没人调用**，等于纸面防护。
  void _ensureSize(String text, File f) {
    final issues = checkInputLimits(text, source: _name(f));
    if (issues == null) return;
    final fatal = issues
        .where((i) => i.severity == IssueSeverity.error)
        .toList();
    if (fatal.isEmpty) return;
    lockReadOnly('${_name(f)} 超出可处理的大小');
    throw StoreException('${_name(f)} 太大，已拒绝加载：${fatal.first.message}');
  }

  @override
  Future<LoadResult<List<BaseCourse>>> loadBaseCourses() async {
    final text = await _readText(baseFile);
    if (text == null) return const LoadResult(<BaseCourse>[]);
    _ensureSize(text, baseFile);
    _ensureReadable(text, baseFile);

    final r = parseBaseLines(text);
    final audit = auditBaseLines(text);
    final quarantined = audit.isEmpty
        ? null
        : await _quarantine(audit.rawLines, 'base_course.txt');
    return LoadResult(
      r.value ?? const <BaseCourse>[],
      issues: audit.issues,
      quarantinedPath: quarantined,
    );
  }

  @override
  Future<LoadResult<List<Patch>>> loadPatches() async {
    final text = await _readText(patchFile);
    if (text == null) return const LoadResult(<Patch>[]);
    _ensureSize(text, patchFile);
    _ensureReadable(text, patchFile);

    final r = parsePatchLines(text);
    final audit = auditPatchLines(text);
    final quarantined = audit.isEmpty
        ? null
        : await _quarantine(audit.rawLines, 'course_patch.txt');
    return LoadResult(
      r.value ?? const <Patch>[],
      issues: audit.issues,
      quarantinedPath: quarantined,
    );
  }

  @override
  Future<String> loadTimeConfig() async {
    return await _readText(timeConfigFile) ?? '';
  }

  @override
  Future<LoadResult<List<ExamNote>>> loadExams() async {
    final text = await _readText(examFile);
    if (text == null) return const LoadResult(<ExamNote>[]);
    _ensureSize(text, examFile);
    _ensureReadable(text, examFile);

    final r = parseExamLines(text);
    final audit = auditExamLines(text);
    final quarantined =
        audit.isEmpty ? null : await _quarantine(audit.rawLines, 'exam_note.txt');
    return LoadResult(
      r.value ?? const <ExamNote>[],
      issues: audit.issues,
      quarantinedPath: quarantined,
    );
  }

  // ---------------- 写 ----------------

  /// 所有写操作的统一入口：排队 + 检查只读锁
  Future<T> _writable<T>(Future<T> Function() action) {
    return _queue.run(() async {
      if (_readOnly) {
        throw StoreReadOnlyException(_readOnlyReason ?? '数据处于保护状态，已禁止写入');
      }
      return action();
    });
  }

  @override
  Future<void> saveBaseCourses(List<BaseCourse> courses) {
    return _writable(() async {
      // 序列化守卫：含 | / 换行的字段会被拒绝，不会写出读不回来的行
      final body = courses.map(safeBaseLine).join('\n');
      await atomicWriteString(baseFile, withFormatHeader(body));
    });
  }

  @override
  Future<void> savePatches(List<Patch> patches) {
    return _writable(() async {
      final body = patches.map(safePatchLine).join('\n');
      await atomicWriteString(patchFile, withFormatHeader(body));
    });
  }

  @override
  Future<void> saveExams(List<ExamNote> exams) {
    return _writable(() async {
      final body = exams.map(safeExamLine).join('\n');
      await atomicWriteString(examFile, withFormatHeader(body));
    });
  }

  /// 两个文件一起写：先各自 stage（此时主文件都没动），再连续 commit；
  /// 第二个 commit 失败 → 用旧内容回滚第一个，避免"课表改了、补丁没改"的半套状态。
  @override
  Future<void> saveAll({List<BaseCourse>? base, List<Patch>? patches}) {
    return _writable(() async {
      final baseText = base == null
          ? null
          : withFormatHeader(base.map(safeBaseLine).join('\n'));
      final patchText = patches == null
          ? null
          : withFormatHeader(patches.map(safePatchLine).join('\n'));

      final oldBase = baseText == null ? null : await _readQuietly(baseFile);

      if (baseText != null) await stageString(baseFile, baseText);
      if (patchText != null) await stageString(patchFile, patchText);

      try {
        if (baseText != null) await commitStaged(baseFile);
        if (patchText != null) await commitStaged(patchFile);
      } catch (e) {
        // 回滚：把 base 恢复成改之前的样子
        if (baseText != null && oldBase != null) {
          try {
            await atomicWriteString(baseFile, oldBase);
          } on StoreException {
            // 回滚也失败：只能把错误往上抛，至少让用户知道
          }
        }
        rethrow;
      }

      // 终检：两份都读回来比对
      if (baseText != null) await _verify(baseFile, baseText);
      if (patchText != null) await _verify(patchFile, patchText);
    });
  }

  @override
  Future<void> saveTimeConfig(String content) {
    return _writable(() async {
      await atomicWriteString(timeConfigFile, content);
    });
  }

  // ---------------- 备份 / 归档 / 隔离 ----------------

  /// 编辑/导入前自动备份（每类文件保留最近 5 份，前缀区分类型）
  ///
  /// 备份**不受只读锁限制**：文件读不懂时更需要先把现场留一份。
  @override
  Future<void> backup({required String kind}) {
    return _queue.run(() async {
      final backupDir = Directory('$rootPath/backup');
      if (!await backupDir.exists()) await backupDir.create(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final seg = safeSegment(kind, fallback: 'manual');
      for (final (name, file) in [
        ('base_course.txt', baseFile),
        ('course_patch.txt', patchFile),
        ('time_config.ini', timeConfigFile),
      ]) {
        if (await file.exists()) {
          try {
            await file.copy('$rootPath/backup/${seg}_${ts}_$name');
          } on FileSystemException {
            // 单份备份失败不阻断保存
          }
        }
      }
      await _pruneBackups(backupDir, keep: 5);
    });
  }

  /// 按 (kind + 原文件名) 分组，各自保留最近 [keep] 份
  Future<void> _pruneBackups(Directory backupDir, {required int keep}) async {
    final entries = await backupDir.list().toList();
    final groups = <String, List<File>>{};
    for (final e in entries) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      final m = RegExp(r'^(\w+)_\d+_(.+)$').firstMatch(name);
      if (m == null) continue;
      groups.putIfAbsent('${m.group(1)}_${m.group(2)}', () => []).add(e);
    }
    for (final list in groups.values) {
      list.sort((a, b) => a.path.compareTo(b.path));
      while (list.length > keep) {
        try {
          await list.removeAt(0).delete();
        } on FileSystemException {
          list.clear();
        }
      }
    }
  }

  @override
  Future<List<BackupEntry>> listBackups() async {
    final dir = Directory('$rootPath/backup');
    if (!await dir.exists()) return const [];
    final out = <BackupEntry>[];
    for (final e in await dir.list().toList()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      final m = RegExp(r'^(\w+)_(\d+)_(.+)$').firstMatch(name);
      if (m == null) continue;
      out.add(
        BackupEntry(
          path: e.path,
          kind: m.group(1)!,
          fileName: m.group(3)!,
          time: DateTime.fromMillisecondsSinceEpoch(int.parse(m.group(2)!)),
          bytes: await e.length(),
        ),
      );
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  /// 显式恢复：**允许在只读保护下执行**——读不懂当前文件时，这正是出口
  @override
  Future<void> restoreBackup(List<BackupEntry> entries) {
    return _queue.run(() async {
      for (final entry in entries) {
        final target = _targetFor(entry.fileName);
        final src = File(entry.path);
        if (!await src.exists()) {
          throw StoreException('备份文件已不存在：${entry.fileName}');
        }
        await atomicWriteString(target, await src.readAsString());
      }
    });
  }

  File _targetFor(String fileName) => switch (fileName) {
    'base_course.txt' => baseFile,
    'course_patch.txt' => patchFile,
    'time_config.ini' => timeConfigFile,
    _ => throw StoreException('未知的备份文件：$fileName'),
  };

  @override
  Future<String> archiveSemester(String semesterName) async {
    // 学期名来自输入框：消毒后再当目录名，返回实际用到的名字给界面显示
    final seg = safeSegment(semesterName, fallback: 'archive');
    final d = Directory('$rootPath/archive/$seg');
    await d.create(recursive: true);
    if (await baseFile.exists()) {
      await baseFile.copy('${d.path}/base_course.txt');
    }
    if (await patchFile.exists()) {
      await patchFile.copy('${d.path}/course_patch.txt');
    }
    if (await examFile.exists()) {
      await examFile.copy('${d.path}/exam_note.txt');
    }
    if (await timeConfigFile.exists()) {
      await timeConfigFile.copy('${d.path}/time_config.ini');
    }
    return seg;
  }

  @override
  Future<void> archiveExpiredPatches(List<Patch> expired) async {
    if (expired.isEmpty) return;
    final d = Directory('$rootPath/archive/expired');
    await d.create(recursive: true);
    final f = File(
      '${d.path}/expired_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    await atomicWriteString(f, expired.map(patchToLine).join('\n'));
  }

  @override
  Future<void> isolateCorruptLines(
    String content, {
    required String sourceFile,
  }) async {
    await _quarantine(content.split('\n'), sourceFile);
  }

  /// 把读不回来的**原始行**另存到 `corrupt/`
  ///
  /// 返回副本路径（给界面提示用）。只写新文件，不动用户数据，
  /// 所以不受只读锁限制——读不懂的时候更需要先留现场。
  Future<String?> _quarantine(List<String> rawLines, String sourceFile) async {
    if (rawLines.isEmpty) return null;
    try {
      final d = Directory('$rootPath/corrupt');
      await d.create(recursive: true);
      final seg = safeSegment(sourceFile, fallback: 'unknown.txt');
      final f = File('${d.path}/${DateTime.now().millisecondsSinceEpoch}_$seg');
      await atomicWriteString(f, rawLines.join('\n'));
      return f.path;
    } on FileSystemException {
      // 隔离失败不能阻断加载：至少要能把课表打开
      return null;
    } on StoreException {
      return null;
    }
  }

  // ---------------- 内部工具 ----------------

  Future<String?> _readQuietly(File f) async {
    try {
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _verify(File f, String expected) async {
    final got = await f.readAsString();
    if (got != expected) {
      throw StoreException('落盘校验失败：${_name(f)} 内容与预期不一致');
    }
  }

  String _name(File f) =>
      f.uri.pathSegments.isEmpty ? f.path : f.uri.pathSegments.last;
}
