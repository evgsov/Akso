import '../enums/sheet_format_type.dart';

/// Геометрические параметры и рамка листа по ГОСТ 2.301-68 / ГОСТ 21.101-2020
class SheetFormat {
  final SheetFormatType type;
  final SheetOrientation orientation;
  final double? customWidthMm;
  final double? customHeightMm;

  const SheetFormat({
    this.type = SheetFormatType.a3,
    this.orientation = SheetOrientation.landscape,
    this.customWidthMm,
    this.customHeightMm,
  });

  /// Физическая ширина листа бумаги в миллиметрах
  double get widthMm {
    if (type == SheetFormatType.custom) {
      return customWidthMm ?? 420.0;
    }
    final (shortSide, longSide) = _getStandardDimensions(type);
    return orientation == SheetOrientation.landscape ? longSide : shortSide;
  }

  /// Физическая высота листа бумаги в миллиметрах
  double get heightMm {
    if (type == SheetFormatType.custom) {
      return customHeightMm ?? 297.0;
    }
    final (shortSide, longSide) = _getStandardDimensions(type);
    return orientation == SheetOrientation.landscape ? shortSide : longSide;
  }

  /// Поле подшивки слева по ГОСТ 21.101: 20 мм
  double get frameLeftMm => 20.0;

  /// Поле сверху: 5 мм
  double get frameTopMm => 5.0;

  /// Поле справа: 5 мм
  double get frameRightMm => 5.0;

  /// Поле снизу: 5 мм
  double get frameBottomMm => 5.0;

  /// Полезная ширина внутри рамки чертежа (мм)
  double get printableWidthMm => widthMm - (frameLeftMm + frameRightMm);

  /// Полезная высота внутри рамки чертежа (мм)
  double get printableHeightMm => heightMm - (frameTopMm + frameBottomMm);

  static (double shortSide, double longSide) _getStandardDimensions(SheetFormatType type) {
    switch (type) {
      case SheetFormatType.a4:
        return (210.0, 297.0);
      case SheetFormatType.a3:
        return (297.0, 420.0);
      case SheetFormatType.a2:
        return (420.0, 594.0);
      case SheetFormatType.a1:
        return (594.0, 841.0);
      case SheetFormatType.a0:
        return (841.0, 1189.0);
      case SheetFormatType.custom:
        return (297.0, 420.0);
    }
  }

  String get label {
    final typeStr = type.name.toUpperCase();
    final orientStr = orientation == SheetOrientation.landscape ? 'Альбомная' : 'Книжная';
    return '$typeStr ($orientStr, ${widthMm.toInt()}×${heightMm.toInt()} мм)';
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'orientation': orientation.name,
        if (customWidthMm != null) 'customWidthMm': customWidthMm,
        if (customHeightMm != null) 'customHeightMm': customHeightMm,
      };

  factory SheetFormat.fromJson(Map<String, dynamic> json) => SheetFormat(
        type: SheetFormatType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => SheetFormatType.a3,
        ),
        orientation: SheetOrientation.values.firstWhere(
          (e) => e.name == json['orientation'],
          orElse: () => SheetOrientation.landscape,
        ),
        customWidthMm: (json['customWidthMm'] as num?)?.toDouble(),
        customHeightMm: (json['customHeightMm'] as num?)?.toDouble(),
      );

  SheetFormat copyWith({
    SheetFormatType? type,
    SheetOrientation? orientation,
    double? customWidthMm,
    double? customHeightMm,
  }) {
    return SheetFormat(
      type: type ?? this.type,
      orientation: orientation ?? this.orientation,
      customWidthMm: customWidthMm ?? this.customWidthMm,
      customHeightMm: customHeightMm ?? this.customHeightMm,
    );
  }
}
