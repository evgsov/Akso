import 'dart:ui';

/// Слои векторной сцены чертежа для упорядоченной отрисовки
enum VectorSceneLayer {
  axes,
  equipment,
  pipes,
  fittings,
  valves,
  welds,
  supports,
  dimensions,
  callouts,
  annotations,
  frameAndStamp,
}

/// Базовый класс векторного примитива листа чертежа (в миллиметрах листа)
abstract class VectorPrimitive {
  const VectorPrimitive();
}

/// Полилиния или одиночный отрезок
class VectorPolyline extends VectorPrimitive {
  final List<Offset> points;
  final double strokeWidthMm;
  final int colorValue;
  final bool isClosed;
  final bool smoothJoin;
  final List<double>? dashPattern;

  const VectorPolyline({
    required this.points,
    required this.strokeWidthMm,
    required this.colorValue,
    this.isClosed = false,
    this.smoothJoin = true,
    this.dashPattern,
  });

  VectorPolyline copyWith({
    List<Offset>? points,
    double? strokeWidthMm,
    int? colorValue,
    bool? isClosed,
    bool? smoothJoin,
    List<double>? dashPattern,
  }) {
    return VectorPolyline(
      points: points ?? this.points,
      strokeWidthMm: strokeWidthMm ?? this.strokeWidthMm,
      colorValue: colorValue ?? this.colorValue,
      isClosed: isClosed ?? this.isClosed,
      smoothJoin: smoothJoin ?? this.smoothJoin,
      dashPattern: dashPattern ?? this.dashPattern,
    );
  }
}

/// Команда векторного пути
abstract class VectorPathCommand {
  const VectorPathCommand();
}

class VectorPathMoveTo extends VectorPathCommand {
  final Offset point;
  const VectorPathMoveTo(this.point);
}

class VectorPathLineTo extends VectorPathCommand {
  final Offset point;
  const VectorPathLineTo(this.point);
}

class VectorPathCubicTo extends VectorPathCommand {
  final Offset control1;
  final Offset control2;
  final Offset endPoint;
  const VectorPathCubicTo(this.control1, this.control2, this.endPoint);
}

class VectorPathClose extends VectorPathCommand {
  const VectorPathClose();
}

/// Составной путь (Path) для сложных контуров, штриховок и заливок
class VectorPath extends VectorPrimitive {
  final List<VectorPathCommand> commands;
  final double? strokeWidthMm;
  final int? strokeColorValue;
  final int? fillColorValue;
  final bool smoothJoin;

  const VectorPath({
    required this.commands,
    this.strokeWidthMm,
    this.strokeColorValue,
    this.fillColorValue,
    this.smoothJoin = true,
  });
}

/// Окружность
class VectorCircle extends VectorPrimitive {
  final Offset center;
  final double radiusMm;
  final bool isFilled;
  final int strokeColorValue;
  final int? fillColorValue;
  final double strokeWidthMm;

  const VectorCircle({
    required this.center,
    required this.radiusMm,
    this.isFilled = false,
    required this.strokeColorValue,
    this.fillColorValue,
    this.strokeWidthMm = 0.25,
  });
}

/// Эллипс
class VectorEllipse extends VectorPrimitive {
  final Offset center;
  final double radiusXMm;
  final double radiusYMm;
  final bool isFilled;
  final int strokeColorValue;
  final int? fillColorValue;
  final double strokeWidthMm;

  const VectorEllipse({
    required this.center,
    required this.radiusXMm,
    required this.radiusYMm,
    this.isFilled = false,
    required this.strokeColorValue,
    this.fillColorValue,
    this.strokeWidthMm = 0.25,
  });
}

/// Прямоугольник (рамки, ячейки штампа, подложки)
class VectorRect extends VectorPrimitive {
  final Rect rect;
  final double? strokeWidthMm;
  final int? strokeColorValue;
  final int? fillColorValue;

  const VectorRect({
    required this.rect,
    this.strokeWidthMm,
    this.strokeColorValue,
    this.fillColorValue,
  });
}

/// Текстовая аннотация
class VectorText extends VectorPrimitive {
  final String text;
  final Offset position;
  final double fontSizePt;
  final bool isBold;
  final bool isLeftAligned;
  final double rotationAngleRad;
  final int colorValue;
  final double? maskPaddingMm;
  final int? maskFillColorValue;

  const VectorText({
    required this.text,
    required this.position,
    required this.fontSizePt,
    this.isBold = false,
    this.isLeftAligned = false,
    this.rotationAngleRad = 0.0,
    required this.colorValue,
    this.maskPaddingMm,
    this.maskFillColorValue,
  });
}

/// Элемент векторной сцены с привязкой к слою
class VectorSceneItem {
  final VectorSceneLayer layer;
  final VectorPrimitive primitive;
  final int zIndex;

  const VectorSceneItem({
    required this.layer,
    required this.primitive,
    this.zIndex = 0,
  });
}

/// Векторная сцена всего чертежного листа
class VectorScene {
  final double widthMm;
  final double heightMm;
  final List<VectorSceneItem> _items = [];

  VectorScene({
    required this.widthMm,
    required this.heightMm,
  });

  List<VectorSceneItem> get items => List.unmodifiable(_items);

  void addItem(VectorSceneLayer layer, VectorPrimitive primitive, {int zIndex = 0}) {
    _items.add(VectorSceneItem(layer: layer, primitive: primitive, zIndex: zIndex));
  }

  void addPolyline({
    required VectorSceneLayer layer,
    required List<Offset> points,
    required double strokeWidthMm,
    required int colorValue,
    bool isClosed = false,
    bool smoothJoin = true,
    List<double>? dashPattern,
    int zIndex = 0,
  }) {
    if (points.length < 2) return;
    addItem(
      layer,
      VectorPolyline(
        points: points,
        strokeWidthMm: strokeWidthMm,
        colorValue: colorValue,
        isClosed: isClosed,
        smoothJoin: smoothJoin,
        dashPattern: dashPattern,
      ),
      zIndex: zIndex,
    );
  }

  void addLine({
    required VectorSceneLayer layer,
    required Offset start,
    required Offset end,
    required double strokeWidthMm,
    required int colorValue,
    bool smoothJoin = true,
    List<double>? dashPattern,
    int zIndex = 0,
  }) {
    addPolyline(
      layer: layer,
      points: [start, end],
      strokeWidthMm: strokeWidthMm,
      colorValue: colorValue,
      smoothJoin: smoothJoin,
      dashPattern: dashPattern,
      zIndex: zIndex,
    );
  }

  void addRect({
    required VectorSceneLayer layer,
    required Rect rect,
    double? strokeWidthMm,
    int? strokeColorValue,
    int? fillColorValue,
    int zIndex = 0,
  }) {
    addItem(
      layer,
      VectorRect(
        rect: rect,
        strokeWidthMm: strokeWidthMm,
        strokeColorValue: strokeColorValue,
        fillColorValue: fillColorValue,
      ),
      zIndex: zIndex,
    );
  }

  void addCircle({
    required VectorSceneLayer layer,
    required Offset center,
    required double radiusMm,
    bool isFilled = false,
    required int strokeColorValue,
    int? fillColorValue,
    double strokeWidthMm = 0.25,
    int zIndex = 0,
  }) {
    addItem(
      layer,
      VectorCircle(
        center: center,
        radiusMm: radiusMm,
        isFilled: isFilled,
        strokeColorValue: strokeColorValue,
        fillColorValue: fillColorValue,
        strokeWidthMm: strokeWidthMm,
      ),
      zIndex: zIndex,
    );
  }

  void addText({
    required VectorSceneLayer layer,
    required String text,
    required Offset position,
    required double fontSizePt,
    bool isBold = false,
    bool isLeftAligned = false,
    double rotationAngleRad = 0.0,
    required int colorValue,
    double? maskPaddingMm,
    int? maskFillColorValue,
    int zIndex = 0,
  }) {
    if (text.isEmpty) return;
    addItem(
      layer,
      VectorText(
        text: text,
        position: position,
        fontSizePt: fontSizePt,
        isBold: isBold,
        isLeftAligned: isLeftAligned,
        rotationAngleRad: rotationAngleRad,
        colorValue: colorValue,
        maskPaddingMm: maskPaddingMm,
        maskFillColorValue: maskFillColorValue,
      ),
      zIndex: zIndex,
    );
  }

  /// Возвращает элементы, отсортированные по порядку слоев и zIndex
  List<VectorSceneItem> getOrderedItems() {
    final sorted = List<VectorSceneItem>.from(_items);
    sorted.sort((a, b) {
      final layerCmp = a.layer.index.compareTo(b.layer.index);
      if (layerCmp != 0) return layerCmp;
      return a.zIndex.compareTo(b.zIndex);
    });
    return sorted;
  }
}
