/// 学校存储接口：schools/<学校ID>/ 目录的数据读写契约
/// 具体文件 IO 由 M1 实现（path_provider 定位目录），本接口保证核心逻辑可单测（用内存实现）
///
/// 地基约定（v0.18.1 起）：
/// - 读不懂的文件（未来格式版本 / 编码损坏 / 读失败）→ [lockReadOnly]，之后所有写入抛
///   [StoreReadOnlyException]。宁可这一轮改不了，也不降级覆盖用户数据。
/// - 写操作要么整体成功，要么主文件保持原样（原子写，见 atomic_file.dart）。
library;

import '../model/base_course.dart';
import '../model/exam_note.dart';
import '../model/patch.dart';
import '../parse/base_parser.dart';
import '../parse/exam_parser.dart';
import '../parse/patch_parser.dart';
import 'backup_entry.dart';
import 'load_result.dart';
import 'safe_path.dart';
import 'store_error.dart';

/// 单文件读取/写入结果
class FileContent {
  final String text;
  const FileContent(this.text);
}

abstract class SchoolStore {
  String get schoolId;

  /// 是否处于只读保护（读不懂的用户数据不写）
  bool get isReadOnly;

  /// 只读原因（可直接展示给用户）
  String? get readOnlyReason;

  /// 进入只读保护
  void lockReadOnly(String reason);

  /// 读取基础课表（不存在返回空结果）
  Future<LoadResult<List<BaseCourse>>> loadBaseCourses();

  /// 保存基础课表（整文件覆盖）
  Future<void> saveBaseCourses(List<BaseCourse> courses);

  /// 读取补丁（不存在返回空结果）
  Future<LoadResult<List<Patch>>> loadPatches();

  /// 保存补丁（整文件覆盖）
  Future<void> savePatches(List<Patch> patches);

  /// 两个文件一起写：任一份失败则回滚另一份（调课/整周清空用）
  Future<void> saveAll({List<BaseCourse>? base, List<Patch>? patches});

  /// 读取考试便签（不存在返回空结果）
  Future<LoadResult<List<ExamNote>>> loadExams();

  /// 保存考试便签（整文件覆盖）
  Future<void> saveExams(List<ExamNote> exams);

  /// 读取课时配置（time_config.ini）
  Future<String> loadTimeConfig();

  /// 保存课时配置
  Future<void> saveTimeConfig(String content);

  /// 编辑/导入前自动备份（保留最近 [keep] 份，文件名前缀区分类型）
  Future<void> backup({required String kind}); // kind: 'edit'|'import'|'manual'

  /// 列出备份（新的在前）
  Future<List<BackupEntry>> listBackups();

  /// 用备份覆盖主文件（显式恢复；允许在只读保护下执行）
  Future<void> restoreBackup(List<BackupEntry> entries);

  /// 学期归档（复制到 archive/<名>/）；返回实际使用的目录名（已消毒）
  Future<String> archiveSemester(String semesterName);

  /// 过期补丁移入 archive/expired/
  Future<void> archiveExpiredPatches(List<Patch> expired);

  /// 损坏行隔离（写入 corrupt/ 目录）
  Future<void> isolateCorruptLines(
    String content, {
    required String sourceFile,
  });
}

/// 内存实现：供单元测试与预览使用
class MemorySchoolStore implements SchoolStore {
  @override
  final String schoolId;
  String _base = '';
  String _patch = '';
  String _exams = '';
  String _timeConfig = '';
  bool _readOnly = false;
  String? _readOnlyReason;

  MemorySchoolStore(this.schoolId);

  @override
  bool get isReadOnly => _readOnly;

  @override
  String? get readOnlyReason => _readOnlyReason;

  @override
  void lockReadOnly(String reason) {
    _readOnly = true;
    _readOnlyReason = reason;
  }

  void _assertWritable() {
    if (_readOnly) {
      throw StoreReadOnlyException(_readOnlyReason ?? '数据处于保护状态');
    }
  }

  @override
  Future<LoadResult<List<BaseCourse>>> loadBaseCourses() async {
    final r = parseBaseLines(_base);
    return LoadResult(r.value ?? const []);
  }

  @override
  Future<void> saveBaseCourses(List<BaseCourse> courses) async {
    _assertWritable();
    _base = courses.map(baseCourseToLine).join('\n');
  }

  @override
  Future<LoadResult<List<Patch>>> loadPatches() async {
    final r = parsePatchLines(_patch);
    return LoadResult(r.value ?? const []);
  }

  @override
  Future<void> savePatches(List<Patch> patches) async {
    _assertWritable();
    _patch = patches.map(patchToLine).join('\n');
  }

  @override
  Future<void> saveAll({List<BaseCourse>? base, List<Patch>? patches}) async {
    _assertWritable();
    if (base != null) _base = base.map(baseCourseToLine).join('\n');
    if (patches != null) _patch = patches.map(patchToLine).join('\n');
  }

  @override
  Future<LoadResult<List<ExamNote>>> loadExams() async {
    final r = parseExamLines(_exams);
    return LoadResult(r.value ?? const []);
  }

  @override
  Future<void> saveExams(List<ExamNote> exams) async {
    _assertWritable();
    _exams = exams.map(examToLine).join('\n');
  }

  @override
  Future<String> loadTimeConfig() async => _timeConfig;

  @override
  Future<void> saveTimeConfig(String content) async {
    _assertWritable();
    _timeConfig = content;
  }

  @override
  Future<void> backup({required String kind}) async {}

  @override
  Future<List<BackupEntry>> listBackups() async => const [];

  @override
  Future<void> restoreBackup(List<BackupEntry> entries) async {}

  @override
  Future<String> archiveSemester(String semesterName) async =>
      safeSegment(semesterName, fallback: 'archive');

  @override
  Future<void> archiveExpiredPatches(List<Patch> expired) async {}

  @override
  Future<void> isolateCorruptLines(
    String content, {
    required String sourceFile,
  }) async {}
}
