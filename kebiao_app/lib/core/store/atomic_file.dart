/// 原子写 + 写队列（地基一）
///
/// 为什么不用 `File.writeAsString` 直接覆盖：
/// 它是 `open(FileMode.write)` → 截断 → 写入。截断和写完之间有一个真实窗口，
/// 断电 / 杀进程 / 磁盘满 都会留下**半截文件**，而半截课表看起来像"少了几门课"。
///
/// 本文件的做法：
/// 1. 写 `<目标>.tmp`（flush 落盘）
/// 2. 把 tmp 读回来逐字节比对（防静默截断）
/// 3. `rename` 覆盖目标（同一文件系统内原子，Android/NTFS 均如此）
/// 4. 再把目标读回来比对（防 rename 后内容异常）
///
/// 任何一步失败 → 抛 [StoreException]，**主文件保持原样**。
library;

import 'dart:async';
import 'dart:io';

import 'store_error.dart';

/// 串行队列：让所有写操作排队，避免两次保存同时 rename 同一个文件
class WriteQueue {
  Future<void> _tail = Future<void>.value();

  /// 排到队尾执行；前一个任务的异常不会卡死队列
  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }
}

/// 目标文件对应的临时文件路径
File tempFileFor(File target) => File('${target.path}.tmp');

/// 第 1 步 + 第 2 步：把内容写进 tmp 并回读校验
///
/// 返回 tmp 文件，供 [commitStaged] 使用。失败时清掉 tmp 并抛错。
Future<File> stageString(File target, String content) async {
  final tmp = tempFileFor(target);
  try {
    await tmp.writeAsString(content, flush: true);
  } on FileSystemException catch (e) {
    await _tryDelete(tmp);
    throw StoreException('写入失败：${_reason(e)}', cause: e);
  }
  String back;
  try {
    back = await tmp.readAsString();
  } on FileSystemException catch (e) {
    await _tryDelete(tmp);
    throw StoreException('写入校验失败：${_reason(e)}', cause: e);
  }
  if (back != content) {
    await _tryDelete(tmp);
    throw const StoreException('写入校验失败：临时文件内容与预期不一致（通常是磁盘空间不足）');
  }
  return tmp;
}

/// 第 3 步：用 tmp 原子替换目标
Future<void> commitStaged(File target) async {
  final tmp = tempFileFor(target);
  if (!await tmp.exists()) {
    throw const StoreException('写入中断：临时文件已不存在');
  }
  try {
    await tmp.rename(target.path);
  } on FileSystemException catch (e) {
    await _tryDelete(tmp);
    throw StoreException('替换文件失败：${_reason(e)}', cause: e);
  }
}

/// 完整原子写：stage → commit → 终检
Future<void> atomicWriteString(File target, String content) async {
  await stageString(target, content);
  await commitStaged(target);
  // 第 4 步：终检（读不回原样说明落盘有问题，宁可报错也不装作成功）
  final String finalText;
  try {
    finalText = await target.readAsString();
  } on FileSystemException catch (e) {
    throw StoreException('落盘校验失败：${_reason(e)}', cause: e);
  }
  if (finalText != content) {
    throw const StoreException('落盘校验失败：文件内容与预期不一致');
  }
}

/// 崩溃残留清理：启动时删掉上次没 rename 成功的 `*.tmp`
Future<void> sweepTempFiles(Directory dir) async {
  if (!await dir.exists()) return;
  try {
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.tmp')) {
        await _tryDelete(e);
      }
    }
  } on FileSystemException {
    // 清理失败不影响主流程
  }
}

Future<void> _tryDelete(File f) async {
  try {
    if (await f.exists()) await f.delete();
  } on FileSystemException {
    // 忽略：删不掉也不该让主流程崩
  }
}

String _reason(FileSystemException e) => e.osError?.message ?? e.message;
