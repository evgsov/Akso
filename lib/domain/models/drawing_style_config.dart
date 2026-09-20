/// Настройки графических стилей, весов линий и аннотативной типографики по ГОСТ 2.303 / 2.304
class DrawingStyleConfig {
  /// Толщина основных магистральных линий труб на листе (в мм бумаги, стандарт 0.8 мм)
  final double pipeLineWidthMm;

  /// Толщина тонких линий: выноски, размеры, засечки стыков (в мм бумаги, стандарт 0.25-0.35 мм)
  final double thinLineWidthMm;

  /// Толщина контуров арматуры и фитингов (в мм бумаги, стандарт 0.5 мм)
  final double fittingLineWidthMm;

  /// Толщина внутренней рамки листа (в мм бумаги, стандарт 0.8-1.0 мм)
  final double frameLineWidthMm;

  /// Толщина внешней рамки штампа (в мм бумаги, стандарт 0.8-1.0 мм)
  final double stampBorderWidthMm;

  /// Толщина внутренней сетки штампа и граф (в мм бумаги, стандарт 0.35 мм)
  final double stampGridWidthMm;

  /// Толщина осей трубопроводов и строительных осей (в мм бумаги, стандарт 0.25 мм)
  final double axisLineWidthMm;

  /// Аннотативная высота мелкого шрифта (2.5 мм — ячейки таблиц, подписи штампа)
  final double textHeightSmallMm;

  /// Аннотативная высота основного шрифта (3.5 мм — выноски диаметров, отметки Z, ТТ)
  final double textHeightRegularMm;

  /// Аннотативная высота среднего шрифта (5.0 мм — шифр в штампе, марки осей)
  final double textHeightMediumMm;

  /// Аннотативная высота крупного шрифта (7.0 мм — заголовки чертежей)
  final double textHeightLargeMm;

  /// Семейство шрифтов ('GOST Type B', 'GOST Type A', 'Roboto')
  final String fontFamily;

  const DrawingStyleConfig({
    this.pipeLineWidthMm = 0.8,
    this.thinLineWidthMm = 0.25,
    this.fittingLineWidthMm = 0.5,
    this.frameLineWidthMm = 0.8,
    this.stampBorderWidthMm = 0.8,
    this.stampGridWidthMm = 0.35,
    this.axisLineWidthMm = 0.25,
    this.textHeightSmallMm = 2.5,
    this.textHeightRegularMm = 3.5,
    this.textHeightMediumMm = 5.0,
    this.textHeightLargeMm = 7.0,
    this.fontFamily = 'GOST Type B',
  });

  Map<String, dynamic> toJson() => {
        'pipeLineWidthMm': pipeLineWidthMm,
        'thinLineWidthMm': thinLineWidthMm,
        'fittingLineWidthMm': fittingLineWidthMm,
        'frameLineWidthMm': frameLineWidthMm,
        'stampBorderWidthMm': stampBorderWidthMm,
        'stampGridWidthMm': stampGridWidthMm,
        'axisLineWidthMm': axisLineWidthMm,
        'textHeightSmallMm': textHeightSmallMm,
        'textHeightRegularMm': textHeightRegularMm,
        'textHeightMediumMm': textHeightMediumMm,
        'textHeightLargeMm': textHeightLargeMm,
        'fontFamily': fontFamily,
      };

  factory DrawingStyleConfig.fromJson(Map<String, dynamic> json) => DrawingStyleConfig(
        pipeLineWidthMm: (json['pipeLineWidthMm'] as num?)?.toDouble() ?? 0.8,
        thinLineWidthMm: (json['thinLineWidthMm'] as num?)?.toDouble() ?? 0.25,
        fittingLineWidthMm: (json['fittingLineWidthMm'] as num?)?.toDouble() ?? 0.5,
        frameLineWidthMm: (json['frameLineWidthMm'] as num?)?.toDouble() ?? 0.8,
        stampBorderWidthMm: (json['stampBorderWidthMm'] as num?)?.toDouble() ?? 0.8,
        stampGridWidthMm: (json['stampGridWidthMm'] as num?)?.toDouble() ?? 0.35,
        axisLineWidthMm: (json['axisLineWidthMm'] as num?)?.toDouble() ?? 0.25,
        textHeightSmallMm: (json['textHeightSmallMm'] as num?)?.toDouble() ?? 2.5,
        textHeightRegularMm: (json['textHeightRegularMm'] as num?)?.toDouble() ?? 3.5,
        textHeightMediumMm: (json['textHeightMediumMm'] as num?)?.toDouble() ?? 5.0,
        textHeightLargeMm: (json['textHeightLargeMm'] as num?)?.toDouble() ?? 7.0,
        fontFamily: json['fontFamily'] as String? ?? 'GOST Type B',
      );

  DrawingStyleConfig copyWith({
    double? pipeLineWidthMm,
    double? thinLineWidthMm,
    double? fittingLineWidthMm,
    double? frameLineWidthMm,
    double? stampBorderWidthMm,
    double? stampGridWidthMm,
    double? axisLineWidthMm,
    double? textHeightSmallMm,
    double? textHeightRegularMm,
    double? textHeightMediumMm,
    double? textHeightLargeMm,
    String? fontFamily,
  }) {
    return DrawingStyleConfig(
      pipeLineWidthMm: pipeLineWidthMm ?? this.pipeLineWidthMm,
      thinLineWidthMm: thinLineWidthMm ?? this.thinLineWidthMm,
      fittingLineWidthMm: fittingLineWidthMm ?? this.fittingLineWidthMm,
      frameLineWidthMm: frameLineWidthMm ?? this.frameLineWidthMm,
      stampBorderWidthMm: stampBorderWidthMm ?? this.stampBorderWidthMm,
      stampGridWidthMm: stampGridWidthMm ?? this.stampGridWidthMm,
      axisLineWidthMm: axisLineWidthMm ?? this.axisLineWidthMm,
      textHeightSmallMm: textHeightSmallMm ?? this.textHeightSmallMm,
      textHeightRegularMm: textHeightRegularMm ?? this.textHeightRegularMm,
      textHeightMediumMm: textHeightMediumMm ?? this.textHeightMediumMm,
      textHeightLargeMm: textHeightLargeMm ?? this.textHeightLargeMm,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}
