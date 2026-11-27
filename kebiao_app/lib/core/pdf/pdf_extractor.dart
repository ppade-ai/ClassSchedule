/// PDF 文本提取接口（M0 技术攻关点）
/// 示例大学 PDF 为 CID 字体 + ToUnicode 映射（pypdf 可解码、pdfplumber 乱码）
/// 实现方案（M0.5 验证）：
///   首选 pdfx（pdfium 内核）→ 用真实课表 PDF 样本（本地留存，未入库）实测
///   失败备选：Android 原生 PdfRenderer / 自研 CID ToUnicode 解码
library;

abstract class PdfTextExtractor {
  /// 提取 PDF 全部文本（保留换行与大致布局），失败抛异常
  Future<String> extractText(String filePath);
}
