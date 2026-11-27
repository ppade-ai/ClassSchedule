/// 课表控制器：文件存储 + 周切换 + 合并 + 编辑操作（M2）
/// 数据流：FileSchoolStore（schools/demo/）↔ 内存 ↔ 合并引擎
/// 首启初始化演示数据（17 课 + 3 补丁），之后全部编辑落盘
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/engine/conflict.dart';
import '../../core/engine/merge_engine.dart';
import '../../core/engine/week_engine.dart';
import '../../core/format/format_version.dart';
import '../../core/model/base_course.dart';
import '../../core/model/enums.dart';
import '../../core/model/exam_note.dart';
import '../../core/model/patch.dart';
import '../../core/model/period_time.dart';
import '../../core/model/week_course.dart';
import '../../core/pdf/pdf_word.dart';
import '../../core/pdf/school_parser.dart';
import '../../core/store/atomic_file.dart';
import '../../core/store/backup_entry.dart';
import '../../core/store/file_school_store.dart';
import '../../core/store/store_error.dart';
import '../../core/validate/issues.dart';
import '../demo/demo_data.dart';
import 'dynamic_grid.dart' show DynamicGrid;

/// 调课范围（M2.2）
enum MoveScope { once, week, longTerm, permanent }

class TimetableController extends ChangeNotifier {
  /// 学校存储（M2：真实文件；默认学校 demo，多学校 M3）
  final FileSchoolStore store = FileSchoolStore('demo');

  /// 编辑串行队列
  ///
  /// 编辑都是"读当前列表 → 改 → 写盘 → 换内存"，中间隔着 await。
  /// 两次编辑并发时会各自读到旧列表，后写者把前一个改动覆盖掉（丢更新）。
  /// 所以所有编辑操作都排进这一个队列，一次只跑一个。
  final WriteQueue _editQueue = WriteQueue();

  Future<void> _edit(Future<void> Function() body) => _editQueue.run(body);

  /// 学期配置（v0.8：第一周周一可变，持久化于 time_config.ini [term]）
  late DateTime baseMonday;
  late int totalWeeks;
  late WeekEngine weekEngine;

  List<BaseCourse> baseCourses = [];
  List<Patch> patches = [];

  /// 考试 / 便签：只有日期，不依赖学期与周次
  List<ExamNote> exams = [];

  int week = 1;
  bool loaded = false;

  /// 数据加载失败的原因（null = 正常）
  ///
  /// 阶段 1 起的约定：遇到未来版本**拒绝加载**并提示，绝不按旧格式解析后
  /// 再保存回去——那等于把用户更新的文件降级覆盖掉。
  /// v0.18.1 起：任何读取失败（版本/编码/IO）都走这里，并**同时锁只读**。
  String? loadError;

  /// 最近一次写入失败的原因（null = 无）
  ///
  /// 直写式保存的配套：写盘成功才改内存，失败则内存不动并在这里留原因，
  /// 由界面弹出提示。这样"界面显示成功"就等于"磁盘已写入"。
  String? storageError;

  /// 是否处于只读保护（读不懂的数据不写）
  bool get readOnly => store.isReadOnly;

  /// 只读原因（可直接展示）
  String? get readOnlyReason => store.readOnlyReason;

  /// 加载时无法识别的行（已隔离到 corrupt/，但还没从主文件移除）
  final List<Issue> loadIssues = [];

  /// 加载时需要告诉用户的话（坏行隔离等）
  final List<String> loadWarnings = [];

  /// 颜色模式：true=展望（同课同色），false=实时（全灰+当前课高亮）
  bool planningMode = true;

  /// 字号缩放（0.8/1.0/1.2/1.4，联动行高）
  double fontScale = 1.0;

  static const List<double> fontScaleOptions = [0.8, 1.0, 1.2, 1.4];

  /// 行高下限（dp），默认 64。持久化于 time_config.ini 的 [view] 段。
  ///
  /// ⚠️ 这只是**下限**：实际行高 = max(下限, 该行卡片内容需求 ÷ 跨行数)。
  /// 所以把下限调小**只会压掉富余空间，永远不会压到内容以下**（不会溢出/错位）——
  /// 这也是"调行高不会乱"的数学依据。内容本身需要的高度压不下去，此时下限不再起作用。
  double rowHeightBase = 64;

  /// 可选行高下限档位（dp）
  static const List<double> rowHeightOptions = [40, 64, 80, 96];

  /// 作息时间（第 1..N 节起止，可在「更多 → 作息时间」里改）
  ///
  /// 默认取内置模板；time_config.ini 的 [periods] 段优先。
  List<PeriodTime> periodTimes = DemoData.periodTimes
      .map((t) => PeriodTime.tryParse(t)!)
      .toList();

  int get periodCount => periodTimes.length;

  List<String> get periodStartTimes => periodTimes.map((p) => p.start).toList();

  List<String> get periodEndTimes => periodTimes.map((p) => p.end).toList();

  static const double kRowHeightMin = 32;
  static const double kRowHeightMax = 120;

  /// 单周缓存
  final Map<int, List<WeekCourse>> _cache = {};

  TimetableController() {
    _applyTerm(DemoData.baseMonday, DemoData.totalWeeks);
  }

  void _applyTerm(DateTime bm, int tw) {
    baseMonday = bm;
    totalWeeks = tw;
    weekEngine = WeekEngine(baseMonday: bm, totalWeeks: tw);
  }

  // ---------- 加载 ----------

  /// 首次启动：写入演示数据（17 课 + 3 补丁 + time_config）
  ///
  /// 演示数据来自可选的打包资产 `assets/demo/sample_pdf_words.json`。
  /// **资产不存在时返回空表**：纯净版（不含任何样例数据）删掉该资产即可，
  /// 首启自然落到空状态，`lib/` 无需分叉——这同时是路线图阶段 0.5 要的行为。
  ///
  /// 任何读取/写入失败 → 进入**只读保护**并把原因交给界面，绝不永远转圈。
  Future<void> loadDemo() async {
    await store.init();
    loadError = null;
    storageError = null;
    loadIssues.clear();
    loadWarnings.clear();

    var cfg = '';
    try {
      cfg = await store.loadTimeConfig();
      if (!await store.baseFile.exists()) {
        await _seedDemo();
      } else {
        final baseResult = await store.loadBaseCourses();
        final patchResult = await store.loadPatches();
        final examResult = await store.loadExams();
        baseCourses = baseResult.value;
        patches = patchResult.value;
        exams = examResult.value;
        if (!baseResult.ok) {
          loadWarnings.add('基础课${baseResult.summary}');
          loadIssues.addAll(baseResult.issues);
        }
        if (!patchResult.ok) {
          loadWarnings.add('补丁${patchResult.summary}');
          loadIssues.addAll(patchResult.issues);
        }
        if (!examResult.ok) {
          loadWarnings.add('考试便签${examResult.summary}');
          loadIssues.addAll(examResult.issues);
        }
      }
    } on UnsupportedFormatVersion catch (e) {
      // 文件比 App 新：**不读、不写、不覆盖**，只把原因交给界面提示升级。
      // 若这里静默按旧格式解析，下一步保存就会把用户的新字段抹掉。
      _enterSafeMode(e.message);
    } on StoreException catch (e) {
      _enterSafeMode(e.message);
    } catch (e) {
      // 兜底：任何未预期异常都不能让首屏永远转圈
      _enterSafeMode('读取数据时出错：$e');
    }

    // 学期配置恢复
    final term = _parseTerm(cfg.isEmpty ? _buildTimeConfig() : cfg);
    if (term != null) {
      _applyTerm(term.$1, term.$2);
    }

    // 视图配置恢复（行高）；缺省保持 64
    final rh = _parseRowHeight(cfg);
    if (rh != null) rowHeightBase = rh;

    // 作息时间恢复（学校之间不固定）；缺省用内置模板
    final pt = _parsePeriods(cfg);
    if (pt != null) periodTimes = pt;

    week = weekEngine.currentWeek(DateTime.now()) ?? 1;
    loaded = true;
    notifyListeners();
  }

  Future<List<BaseCourse>> _parseFixtureCourses() async {
    final String text;
    try {
      text = await rootBundle.loadString('assets/demo/sample_pdf_words.json');
    } catch (_) {
      // 未打包演示资产（纯净版）→ 首启空状态。注意这里必须 catch 住
      // FlutterError（不是 Exception），否则缺资产会直接崩在启动路径上。
      return const <BaseCourse>[];
    }
    final words = (jsonDecode(text) as List)
        .map((e) => PdfWord.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final r = SchoolPdfParser().parse(words);
    return (r.value ?? [])
        .map(
          (c) => c.color.isEmpty
              ? c.copyWith(color: DemoData.colorFor(c.name))
              : c,
        )
        .toList();
  }

  List<BaseCourse> _withIds(List<BaseCourse> list) {
    var id = 1;
    return list.map((c) => c.copyWith(id: id++)).toList();
  }

  /// 首启写入演示数据（三个文件各自原子写）
  Future<void> _seedDemo() async {
    final demo = _withIds(await _parseFixtureCourses());
    // 演示补丁是为演示课程写的；没有演示课程时一并留空，避免补丁凭空造课
    final demoPatches = demo.isEmpty ? const <Patch>[] : DemoData.demoPatches;
    await store.saveBaseCourses(demo);
    await store.savePatches(demoPatches);
    await store.saveTimeConfig(_buildTimeConfig());
    baseCourses = demo;
    patches = demoPatches;
  }

  /// 读不懂数据时的统一降级：清空内存 + 记下原因 + **锁只读**
  ///
  /// 只清空不锁写，就等于"读不懂就覆盖"——那正是我们要防止的事。
  void _enterSafeMode(String reason) {
    baseCourses = const <BaseCourse>[];
    patches = const <Patch>[];
    exams = const <ExamNote>[];
    loadError = reason;
    store.lockReadOnly(reason);
  }

  /// 统一写入管道（直写式）
  ///
  /// 先写盘，成功后才由调用方改内存；失败则内存保持原样，原因留给界面提示。
  /// 这样"界面显示保存成功"恒等于"磁盘已写入"。
  Future<bool> _commit(Future<void> Function() write) async {
    try {
      await write();
      if (storageError != null) storageError = null;
      return true;
    } on StoreException catch (e) {
      storageError = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      storageError = '保存失败：$e';
      notifyListeners();
      return false;
    }
  }

  /// 写前备份：备份失败不阻断保存（备份是兜底，不是前置条件）
  Future<void> _backup(String kind) async {
    try {
      await store.backup(kind: kind);
    } on StoreException {
      // 忽略：备份失败仍然让用户能编辑
    }
  }

  String _buildTimeConfig() {
    final buf = StringBuffer();
    buf.writeln('[term]');
    buf.writeln('baseMonday=${_fmtDate(baseMonday)}');
    buf.writeln('totalWeeks=$totalWeeks');
    buf.writeln('[periods]');
    for (var i = 0; i < periodTimes.length; i++) {
      buf.writeln('${i + 1}=${periodTimes[i].text}');
    }
    buf.writeln('[view]');
    buf.writeln('rowHeight=${_trimNum(rowHeightBase)}');
    return buf.toString();
  }

  /// 解析 [periods] 段（1=08:00-08:45 …）；编号必须从 1 连续
  List<PeriodTime>? _parsePeriods(String cfg) {
    final map = <int, PeriodTime>{};
    var inSection = false;
    for (final line in cfg.split('\n')) {
      final t = line.trim();
      if (t.startsWith('[') && t.endsWith(']')) {
        inSection = t == '[periods]';
        continue;
      }
      if (!inSection || t.isEmpty) continue;
      final m = RegExp(r'^(\d+)\s*=\s*(.+)$').firstMatch(t);
      if (m == null) continue;
      final idx = int.tryParse(m.group(1)!);
      final p = PeriodTime.tryParse(m.group(2)!);
      if (idx == null || idx < 1 || p == null) continue;
      map[idx] = p;
    }
    if (map.isEmpty) return null;
    final keys = map.keys.toList()..sort();
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] != i + 1) return null; // 编号断层 → 视为无效，回退默认
    }
    return [for (final k in keys) map[k]!];
  }

  (DateTime, int)? _parseTerm(String cfg) {
    DateTime? bm;
    int? tw;
    for (final line in cfg.split('\n')) {
      final t = line.trim();
      if (t.startsWith('baseMonday=')) {
        bm = DateTime.tryParse(t.substring(11).trim());
      } else if (t.startsWith('totalWeeks=')) {
        tw = int.tryParse(t.substring(11).trim());
      }
    }
    if (bm == null || tw == null) return null;
    return (bm, tw);
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 解析 [view] 段的 rowHeight（不存在或非法返回 null）
  double? _parseRowHeight(String cfg) {
    var inView = false;
    for (final line in cfg.split('\n')) {
      final t = line.trim();
      if (t.startsWith('[') && t.endsWith(']')) {
        inView = t == '[view]';
        continue;
      }
      if (!inView) continue;
      if (t.startsWith('rowHeight=')) {
        final v = double.tryParse(t.substring('rowHeight='.length).trim());
        if (v != null && v >= kRowHeightMin && v <= kRowHeightMax) return v;
      }
    }
    return null;
  }

  /// 只替换（或追加）[section] 段，**其余段落逐字节保留**。
  ///
  /// ★ 这是数据安全的关键：`[term]` 段存着用户设的第1周周一与总周数，
  ///   `[periods]` 可能被用户改过 —— 调行高时绝不能被顺手冲掉。
  ///   （对应项目总纲 §3.4 的「升级/设置不得触碰清单」）
  String _upsertSection(String cfg, String section, List<String> bodyLines) {
    final body = ['[$section]', ...bodyLines];
    final lines = cfg.isEmpty ? <String>[] : cfg.split('\n');

    var start = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim() == '[$section]') {
        start = i;
        break;
      }
    }

    if (start < 0) {
      // 该段不存在 → 追加到末尾（保持原有内容不动）
      final out = [...lines];
      while (out.isNotEmpty && out.last.trim().isEmpty) {
        out.removeLast();
      }
      if (out.isNotEmpty) out.add('');
      out.addAll(body);
      return '${out.join('\n')}\n';
    }

    // 该段存在 → 用它到下一个 [xxx] 之间的范围做替换
    var end = lines.length;
    for (var i = start + 1; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.startsWith('[') && t.endsWith(']')) {
        end = i;
        break;
      }
    }
    return <String>[
      ...lines.sublist(0, start),
      ...body,
      ...lines.sublist(end),
    ].join('\n');
  }

  /// 数字去掉多余的 .0（64.0 → 64，64.5 → 64.5）
  String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  // ---------- 查询 ----------

  List<WeekCourse> get courses => coursesOf(week);

  List<WeekCourse> coursesOf(int w) {
    final cached = _cache[w];
    if (cached != null) return cached;
    final r = MergeEngine().mergeWeek(
      baseCourses: baseCourses,
      patches: patches,
      week: w,
      weekMonday: weekEngine.mondayOf(w),
    );
    // 防御：空结果不缓存（防止瞬时空状态污染缓存导致"某周全灰"类问题）
    if (r.courses.isNotEmpty) {
      _cache[w] = r.courses;
    } else {
      debugPrint(
        '[kebiao] coursesOf($w) 合并结果为空 base=${baseCourses.length} patches=${patches.length}',
      );
    }
    return r.courses;
  }

  /// 模拟把 [patch] 加入后第 [w] 周的冲突（add 操作前检查用）
  List<ConflictPair> previewConflicts(Patch patch, {int? w}) {
    final target = w ?? week;
    final r = MergeEngine().mergeWeek(
      baseCourses: baseCourses,
      patches: [...patches, patch],
      week: target,
      weekMonday: weekEngine.mondayOf(target),
    );
    return findConflicts(r.courses);
  }

  // ---------- 编辑操作（M2） ----------

  /// 新建或更新补丁（自动备份 + 原子落盘 + 失效缓存）
  Future<void> savePatch(Patch p) => _edit(() async {
    await _backup('edit');
    final list = [...patches];
    final idx = p.id != null ? list.indexWhere((e) => e.id == p.id) : -1;
    if (idx >= 0) {
      list[idx] = p;
    } else {
      list.add(p.copyWith(id: nextId));
    }
    if (!await _commit(() => store.savePatches(list))) return;
    patches = list;
    invalidate();
  });

  /// 删除补丁（按 id）
  Future<void> deletePatch(int? id) => _edit(() async {
    if (id == null) return;
    await _backup('edit');
    final list = patches.where((p) => p.id != id).toList();
    if (!await _commit(() => store.savePatches(list))) return;
    patches = list;
    invalidate();
  });

  /// 当前周在指定格生成 remove 补丁（详情/长按"删除"入口）
  Future<void> removeCellForCurrentWeek({
    required int weekday,
    required int startPeriod,
    required int endPeriod,
  }) async {
    await savePatch(
      Patch(
        locationType: PatchLocationType.weekOffset,
        locationValue: '$week',
        weekday: weekday,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        action: PatchAction.remove,
        name: '',
        remark: '删除（第$week周）',
      ),
    );
  }

  /// 编辑基础课（学期修改入口：改字段后整学期生效）
  Future<void> saveBaseCourse(BaseCourse c) => _edit(() async {
    await _backup('edit');
    final list = [...baseCourses];
    final idx = c.id != null ? list.indexWhere((e) => e.id == c.id) : -1;
    if (idx >= 0) {
      list[idx] = c;
    } else {
      list.add(c.copyWith(id: nextId));
    }
    if (!await _commit(() => store.saveBaseCourses(list))) return;
    baseCourses = list;
    invalidate();
  });

  /// 删除基础课（整学期）
  Future<void> deleteBaseCourse(int? id) => _edit(() async {
    if (id == null) return;
    await _backup('edit');
    final list = baseCourses.where((c) => c.id != id).toList();
    if (!await _commit(() => store.saveBaseCourses(list))) return;
    baseCourses = list;
    invalidate();
  });

  int get nextId {
    var max = 0;
    for (final c in baseCourses) {
      final id = c.id;
      if (id != null && id > max) max = id;
    }
    for (final p in patches) {
      final id = p.id;
      if (id != null && id > max) max = id;
    }
    for (final e in exams) {
      final id = e.id;
      if (id != null && id > max) max = id;
    }
    return max + 1;
  }

  // ---------- 考试 / 便签（只有日期，不依赖周次） ----------

  /// 按日期（再看时间）排序
  List<ExamNote> get examsByDate {
    final list = [...exams];
    list.sort((a, b) {
      final d = a.date.compareTo(b.date);
      if (d != 0) return d;
      return a.startTime.compareTo(b.startTime);
    });
    return list;
  }

  /// 今天及以后的便签（过了的仍保留在文件里，只是不顶在日程最前面）
  List<ExamNote> get upcomingExams {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return examsByDate.where((e) => !e.date.isBefore(today)).toList();
  }

  /// 某个日期属于第几周（学期外返回 null）
  ///
  /// 考试只有日期，用户想知道"第几周"来安排复习——这个换算必须由 App 做。
  int? weekOf(DateTime date) => weekEngine.currentWeek(date);

  /// 某一天的便签
  List<ExamNote> examsOn(DateTime day) => exams
      .where(
        (e) =>
            e.date.year == day.year &&
            e.date.month == day.month &&
            e.date.day == day.day,
      )
      .toList();

  /// 第 [week] 周（周一~周日）内的便签，按日期时间排序
  List<ExamNote> examsInWeek(int week) {
    final range = weekEngine.rangeOf(week);
    final list = exams
        .where(
          (e) =>
              !e.date.isBefore(range.monday) && !e.date.isAfter(range.sunday),
        )
        .toList();
    list.sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.startTime.compareTo(b.startTime);
    });
    return list;
  }

  Future<void> saveExam(ExamNote e) => _edit(() async {
    await _backup('edit');
    final list = [...exams];
    final idx = e.id != null ? list.indexWhere((x) => x.id == e.id) : -1;
    if (idx >= 0) {
      list[idx] = e;
    } else {
      list.add(e.copyWith(id: nextId));
    }
    if (!await _commit(() => store.saveExams(list))) return;
    exams = list;
    invalidate();
  });

  Future<void> deleteExam(int? id) => _edit(() async {
    if (id == null) return;
    await _backup('edit');
    final list = exams.where((e) => e.id != id).toList();
    if (!await _commit(() => store.saveExams(list))) return;
    exams = list;
    invalidate();
  });

  /// 批量追加便签，返回成功写入条数
  Future<int> appendExams(List<ExamNote> list) async {
    var added = 0;
    await _edit(() async {
      if (list.isEmpty) return;
      await _backup('batch');
      var maxId = nextId - 1;
      for (final e in list) {
        final id = e.id;
        if (id != null && id > maxId) maxId = id;
      }
      final next = [
        ...exams,
        ...list.map((e) => e.id == null ? e.copyWith(id: ++maxId) : e),
      ];
      if (!await _commit(() => store.saveExams(next))) return;
      exams = next;
      added = list.length;
      invalidate();
    });
    return added;
  }

  // ---------- M2.2 调课 / 整周 / 学期 ----------

  /// 调课执行（三粒度）
  /// [source] 当前周视图中的源课程；[targetWeekday/start/end] 目标格
  /// once=仅本次(exactDate)；week=整周(weekOffset)；longTerm=从第N周起(基础课拆分)；
  /// permanent=永久(改基础课行)；[swap]=对调（两格互换）
  Future<void> executeMove({
    required WeekCourse source,
    required int targetWeekday,
    required int targetStart,
    required int targetEnd,
    required MoveScope scope,
    DateTime? exactDate,
    int? fromWeek,
    bool swap = false,
  }) => _edit(() async {
    await _backup('edit');
    final newPatches = [...patches];
    final newBase = [...baseCourses];

    String fmtD(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    Patch removePatch(int wd, int s, int e, String loc, String val) => Patch(
      locationType: loc == 'date'
          ? PatchLocationType.exactDate
          : PatchLocationType.weekOffset,
      locationValue: val,
      weekday: wd,
      startPeriod: s,
      endPeriod: e,
      action: PatchAction.remove,
      name: '',
      remark: '调课移除',
    );
    Patch addPatch(int wd, int s, int e, String loc, String val) => Patch(
      locationType: loc == 'date'
          ? PatchLocationType.exactDate
          : PatchLocationType.weekOffset,
      locationValue: val,
      weekday: wd,
      startPeriod: s,
      endPeriod: e,
      action: PatchAction.add,
      name: source.name,
      type: source.type,
      teacher: source.teacher,
      room: source.room,
      color: source.color,
      remark: source.remark,
    );

    // 目标格已有课程（对调用）
    WeekCourse? targetCourse;
    if (swap) {
      for (final c in coursesOf(week)) {
        if (c.weekday == targetWeekday &&
            !(c.endPeriod < targetStart || targetEnd < c.startPeriod) &&
            !c.inactive) {
          targetCourse = c;
          break;
        }
      }
    }

    switch (scope) {
      case MoveScope.once:
        final date = fmtD(exactDate ?? DateTime.now());
        newPatches.add(
          removePatch(
            source.weekday,
            source.startPeriod,
            source.endPeriod,
            'date',
            date,
          ),
        );
        newPatches.add(
          addPatch(targetWeekday, targetStart, targetEnd, 'date', date),
        );
        if (swap && targetCourse != null) {
          newPatches.add(
            removePatch(targetWeekday, targetStart, targetEnd, 'date', date),
          );
          newPatches.add(
            Patch(
              locationType: PatchLocationType.exactDate,
              locationValue: date,
              weekday: source.weekday,
              startPeriod: source.startPeriod,
              endPeriod: source.endPeriod,
              action: PatchAction.add,
              name: targetCourse.name,
              type: targetCourse.type,
              teacher: targetCourse.teacher,
              room: targetCourse.room,
              color: targetCourse.color,
              remark: targetCourse.remark,
            ),
          );
        }
      case MoveScope.week:
        newPatches.add(
          removePatch(
            source.weekday,
            source.startPeriod,
            source.endPeriod,
            'week',
            '$week',
          ),
        );
        newPatches.add(
          addPatch(targetWeekday, targetStart, targetEnd, 'week', '$week'),
        );
        if (swap && targetCourse != null) {
          newPatches.add(
            removePatch(targetWeekday, targetStart, targetEnd, 'week', '$week'),
          );
          newPatches.add(
            Patch(
              locationType: PatchLocationType.weekOffset,
              locationValue: '$week',
              weekday: source.weekday,
              startPeriod: source.startPeriod,
              endPeriod: source.endPeriod,
              action: PatchAction.add,
              name: targetCourse.name,
              type: targetCourse.type,
              teacher: targetCourse.teacher,
              room: targetCourse.room,
              color: targetCourse.color,
              remark: targetCourse.remark,
            ),
          );
        }
      case MoveScope.longTerm:
        final baseIdx = source.source == 'base'
            ? newBase.indexWhere((b) => b.id == source.id)
            : -1;
        if (baseIdx >= 0) {
          final b = newBase[baseIdx];
          final n = fromWeek ?? week;
          if (n > b.startWeek) {
            newBase[baseIdx] = b.copyWith(endWeek: n - 1); // 原格保留到 N-1 周
            newBase.add(
              b.copyWith(
                weekday: targetWeekday,
                startPeriod: targetStart,
                endPeriod: targetEnd,
                startWeek: n,
                id: null, // 保存时统一分配新 id
              ),
            );
          } else {
            newBase[baseIdx] = b.copyWith(
              weekday: targetWeekday,
              startPeriod: targetStart,
              endPeriod: targetEnd,
            );
          }
        } else {
          // 补丁源退化为整周
          newPatches.add(
            removePatch(
              source.weekday,
              source.startPeriod,
              source.endPeriod,
              'week',
              '$week',
            ),
          );
          newPatches.add(
            addPatch(targetWeekday, targetStart, targetEnd, 'week', '$week'),
          );
        }
      case MoveScope.permanent:
        final baseIdx = source.source == 'base'
            ? newBase.indexWhere((b) => b.id == source.id)
            : -1;
        if (baseIdx >= 0) {
          newBase[baseIdx] = newBase[baseIdx].copyWith(
            weekday: targetWeekday,
            startPeriod: targetStart,
            endPeriod: targetEnd,
          );
        } else {
          newPatches.add(
            removePatch(
              source.weekday,
              source.startPeriod,
              source.endPeriod,
              'week',
              '$week',
            ),
          );
          newPatches.add(
            addPatch(targetWeekday, targetStart, targetEnd, 'week', '$week'),
          );
        }
    }

    // 新基础课行/新补丁统一补 id（null id 会导致后续按 id 编辑时误判为新条目）
    var maxId = 0;
    for (final b in newBase) {
      final id = b.id;
      if (id != null && id > maxId) maxId = id;
    }
    for (final p in newPatches) {
      final id = p.id;
      if (id != null && id > maxId) maxId = id;
    }
    final nextBase = newBase
        .map((b) => b.id == null ? b.copyWith(id: ++maxId) : b)
        .toList();
    final nextPatches = newPatches
        .map((p) => p.id == null ? p.copyWith(id: ++maxId) : p)
        .toList();
    // 两个文件一起写：要么都成，要么都回滚（saveAll 内部保证）
    if (!await _commit(
      () => store.saveAll(base: nextBase, patches: nextPatches),
    )) {
      return;
    }
    baseCourses = nextBase;
    patches = nextPatches;
    invalidate();
  });

  /// 整周修改：清空指定周全部课程（为每个占用格生成 remove 补丁）
  /// 注意：exactDate 补丁优先级高于 weekOffset（最后应用）——
  /// 对 exactDate 来源的课程必须生成对应的 exactDate 移除，否则会"复活"
  Future<void> clearWeek(int targetWeek) => _edit(() async {
    await _backup('edit');
    final view = coursesOf(targetWeek);
    final cells = <(int, int, int)>{}; // (weekday, start, end)
    final exactCells = <(int, int, int, String)>{}; // (wd, s, e, date) 精确日期清
    for (final c in view) {
      if (c.inactive) continue;
      cells.add((c.weekday, c.startPeriod, c.endPeriod));
      // 若来自 exactDate 补丁：按精确日期移除
      final p = patches.where((p) => p.id != null && p.id == c.id).toList();
      if (p.isNotEmpty && p.first.locationType == PatchLocationType.exactDate) {
        exactCells.add((
          c.weekday,
          c.startPeriod,
          c.endPeriod,
          p.first.locationValue,
        ));
      }
    }
    final newPatches = [...patches];
    for (final (wd, s, e) in cells) {
      newPatches.add(
        Patch(
          locationType: PatchLocationType.weekOffset,
          locationValue: '$targetWeek',
          weekday: wd,
          startPeriod: s,
          endPeriod: e,
          action: PatchAction.remove,
          name: '',
          remark: '整周清空（第$targetWeek周）',
        ),
      );
    }
    for (final (wd, s, e, date) in exactCells) {
      newPatches.add(
        Patch(
          locationType: PatchLocationType.exactDate,
          locationValue: date,
          weekday: wd,
          startPeriod: s,
          endPeriod: e,
          action: PatchAction.remove,
          name: '',
          remark: '整周清空（$date）',
        ),
      );
    }
    // 补 id（防后续按 id 编辑误判）
    var maxId = 0;
    for (final p in patches) {
      final id = p.id;
      if (id != null && id > maxId) maxId = id;
    }
    final nextPatches = newPatches
        .map((p) => p.id == null ? p.copyWith(id: ++maxId) : p)
        .toList();
    if (!await _commit(() => store.savePatches(nextPatches))) return;
    patches = nextPatches;
    invalidate();
  });

  /// 学期修改：从周视图反查基础课
  BaseCourse? baseById(int? id) {
    if (id == null) return null;
    for (final b in baseCourses) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// 学期修改：新增基础课（长期表单保存）
  Future<void> addBaseCourse(BaseCourse c) =>
      saveBaseCourse(c.copyWith(id: nextId));

  // ---------- M2.3 批量文本 ----------

  /// 批量追加基础课（一次备份 + 一次落盘）
  Future<void> appendBaseCourses(List<BaseCourse> courses) => _edit(() async {
    if (courses.isEmpty) return;
    await _backup('batch');
    var maxId = nextId - 1;
    for (final c in courses) {
      final id = c.id;
      if (id != null && id > maxId) maxId = id;
    }
    final next = [
      ...baseCourses,
      ...courses.map((c) => c.id == null ? c.copyWith(id: ++maxId) : c),
    ];
    if (!await _commit(() => store.saveBaseCourses(next))) return;
    baseCourses = next;
    invalidate();
  });

  /// 批量追加补丁
  Future<void> appendPatches(List<Patch> list) => _edit(() async {
    if (list.isEmpty) return;
    await _backup('batch');
    var maxId = nextId - 1;
    for (final p in list) {
      final id = p.id;
      if (id != null && id > maxId) maxId = id;
    }
    final next = [
      ...patches,
      ...list.map((p) => p.id == null ? p.copyWith(id: ++maxId) : p),
    ];
    if (!await _commit(() => store.savePatches(next))) return;
    patches = next;
    invalidate();
  });

  /// 覆盖式写入基础课（清空后写入，行内 id 保留，空 id 自动分配）
  Future<void> replaceAllBaseCourses(List<BaseCourse> courses) =>
      _edit(() async {
        await _backup('batch');
        var maxId = 0;
        for (final c in courses) {
          final id = c.id;
          if (id != null && id > maxId) maxId = id;
        }
        final next = courses
            .map((c) => c.id == null ? c.copyWith(id: ++maxId) : c)
            .toList();
        if (!await _commit(() => store.saveBaseCourses(next))) return;
        baseCourses = next;
        invalidate();
      });

  /// 覆盖式写入补丁
  Future<void> replaceAllPatches(List<Patch> list) => _edit(() async {
    await _backup('batch');
    var maxId = 0;
    for (final p in list) {
      final id = p.id;
      if (id != null && id > maxId) maxId = id;
    }
    final next = list
        .map((p) => p.id == null ? p.copyWith(id: ++maxId) : p)
        .toList();
    if (!await _commit(() => store.savePatches(next))) return;
    patches = next;
    invalidate();
  });

  /// 学期归档：复制 base+patch+time_config 到 archive/<学期名>/
  /// 学期归档：返回实际使用的目录名（用户输入的名字会被消毒）
  Future<String> archiveSemester(String name) => store.archiveSemester(name);

  /// 列出备份（新的在前）
  Future<List<BackupEntry>> listBackups() => store.listBackups();

  /// 用一组备份覆盖当前数据（恢复前先备份当前状态，防手滑）
  ///
  /// 显式恢复是只读保护的**唯一出口**：当前文件读不懂时，
  /// 用户仍然能挑一份旧备份把数据救回来。
  Future<String?> restoreFromBackup(List<BackupEntry> entries) async {
    String? error;
    await _edit(() async {
      try {
        await store.backup(kind: 'restore');
        await store.restoreBackup(entries);
        store.unlock(); // 恢复成功后解除只读，重新按新内容判定
        await loadDemo();
      } on StoreException catch (e) {
        error = e.message;
        storageError = e.message;
        notifyListeners();
      }
    });
    return error;
  }

  // ---------- 设置 ----------

  void setFontScale(double s) {
    fontScale = s;
    notifyListeners();
  }

  /// 设置行高下限（dp）并持久化到 time_config.ini 的 [view] 段。
  /// 只改 [view] 段，`[term]` / `[periods]` 原样保留。
  Future<void> setRowHeight(double v) => _edit(() async {
    final clamped = v.clamp(kRowHeightMin, kRowHeightMax).toDouble();
    if (clamped == rowHeightBase) return;
    final cfg = await store.loadTimeConfig();
    final next = _upsertSection(cfg, 'view', [
      'rowHeight=${_trimNum(clamped)}',
    ]);
    if (!await _commit(() => store.saveTimeConfig(next))) return;
    rowHeightBase = clamped;
    notifyListeners();
  });

  /// 保存作息时间，只改 [periods] 段（[term] / [view] 原样保留）
  Future<void> savePeriodTimes(List<PeriodTime> times) => _edit(() async {
    if (times.isEmpty) return;
    final cfg = await store.loadTimeConfig();
    final body = [
      for (var i = 0; i < times.length; i++) '${i + 1}=${times[i].text}',
    ];
    final next = _upsertSection(cfg, 'periods', body);
    if (!await _commit(() => store.saveTimeConfig(next))) return;
    periodTimes = times;
    // 实时高亮依赖作息时间 → 清测量缓存并刷新
    DynamicGrid.clearMeasureCache();
    notifyListeners();
  });

  void toggleMode() {
    planningMode = !planningMode;
    notifyListeners();
  }

  String get modeLabel => planningMode ? '展望模式（同课同色）' : '实时模式（全灰+当前课高亮）';

  /// 设置学期并持久化到 time_config.ini [term]
  Future<void> saveTerm({
    required DateTime baseMonday,
    required int totalWeeks,
  }) => _edit(() async {
    // 只改 [term] 段：保留 [periods] / [view]，避免把用户的时段配置与行高冲掉
    final cfg = await store.loadTimeConfig();
    final next = _upsertSection(cfg, 'term', [
      'baseMonday=${_fmtDate(baseMonday)}',
      'totalWeeks=$totalWeeks',
    ]);
    if (!await _commit(() => store.saveTimeConfig(next))) return;
    _applyTerm(baseMonday, totalWeeks);
    _cache.clear();
    week = weekEngine.currentWeek(DateTime.now()) ?? 1;
    notifyListeners();
  });

  void backToCurrentWeek() {
    final w = weekEngine.currentWeek(DateTime.now());
    if (w != null) setWeek(w);
  }

  void setWeek(int w) {
    if (!weekEngine.isValidWeek(w)) return;
    week = w;
    notifyListeners();
  }

  /// 数据编辑后失效：清周缓存 + 清测量缓存（行高重算）
  void invalidate() {
    _cache.clear();
    DynamicGrid.clearMeasureCache();
    notifyListeners();
  }

  // ---------- 实时模式辅助 ----------

  bool isNowOn(WeekCourse course, DateTime now) {
    if (course.inactive) return false;
    if (now.weekday != course.weekday) return false;
    final current = weekEngine.currentWeek(now);
    if (current == null || current != week) return false;
    final p = currentPeriod(now);
    return p != null && course.startPeriod <= p && p <= course.endPeriod;
  }

  int? currentPeriod(DateTime now) {
    final nowMin = now.hour * 60 + now.minute;
    for (var i = 0; i < periodTimes.length; i++) {
      final start = periodTimes[i].startMinutes;
      final end = periodTimes[i].endMinutes;
      if (nowMin >= start && nowMin < end) return i + 1;
    }
    return null;
  }
}
