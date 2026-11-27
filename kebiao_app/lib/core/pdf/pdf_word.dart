/// PDF 词块模型（pdfium/pdfx 运行时输出的通用形状）
library;

class PdfWord {
  final String text;
  final double x;
  final double y;
  final double width;
  final double height;
  final int page;

  const PdfWord({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.page,
  });

  factory PdfWord.fromJson(Map<String, dynamic> json) => PdfWord(
        text: json['t'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['w'] as num).toDouble(),
        height: (json['h'] as num).toDouble(),
        page: (json['p'] as num).toInt(),
      );
}
