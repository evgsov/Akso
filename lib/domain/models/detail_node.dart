import 'dart:math' as math;
import 'dart:ui';

import '../../core/math/axonometry_projector.dart';
import 'node_3d.dart';
import 'piping_network.dart';

/// Форма контура обводки выносного узла на основном чертеже (ГОСТ 2.305)
enum DetailBoundaryShape {
  /// Скругленный прямоугольник
  roundedRect,

  /// Овал (эллипс)
  oval,

  /// Круг
  circle,

  /// Свободный многоугольник с редактируемыми вершинами
  polygon;

  String get displayName {
    switch (this) {
      case DetailBoundaryShape.roundedRect:
        return 'Скругленный прямоугольник';
      case DetailBoundaryShape.oval:
        return 'Овал';
      case DetailBoundaryShape.circle:
        return 'Круг';
      case DetailBoundaryShape.polygon:
        return 'Свободный многоугольник';
    }
  }

  String get shortName {
    switch (this) {
      case DetailBoundaryShape.roundedRect:
        return 'Прямоуг.';
      case DetailBoundaryShape.oval:
        return 'Овал';
      case DetailBoundaryShape.circle:
        return 'Круг';
      case DetailBoundaryShape.polygon:
        return 'Многоугольник';
    }
  }
}

/// Укороченный контекстный отрезок («хвост») примыкающей магистрали
/// для отображения привязки на листе укрупненного узла (Вариант 1)
class DetailContextStub {
  final String segmentId;
  final String systemId;
  final int dn;

  /// Точка подключения к границе узла (3D координаты модели, мм)
  final double startX;
  final double startY;
  final double startZ;

  /// Точка обрыва контекстного участка (3D координаты модели, мм)
  final double endX;
  final double endY;
  final double endZ;

  const DetailContextStub({
    required this.segmentId,
    required this.systemId,
    required this.dn,
    required this.startX,
    required this.startY,
    required this.startZ,
    required this.endX,
    required this.endY,
    required this.endZ,
  });

  Node3D get boundaryNode => Node3D(id: '${segmentId}_start', x: startX, y: startY, z: startZ);
  Node3D get cutEndPoint => Node3D(id: '${segmentId}_end', x: endX, y: endY, z: endZ);
}

/// Выносной укрупненный узел (ГОСТ 2.305-2008 / ГОСТ 21.101-2020)
/// Позволяет выделить плотный участок схемы (ответвление, коллектор, обвязку),
/// скрыть его мелкие выноски на общем листе, обвести контуром со ссылкой на лист узла
/// и подробно показать на отдельном листе в крупном масштабе.
class DetailNode {
  final String id;

  /// Буквенное или цифровое обозначение узла (напр. "А", "Б", "1")
  final String mark;

  /// Заголовок узла над полкой выноски (по умолчанию "Узел А")
  final String title;

  /// Набор ID сегментов труб, входящих в состав узла
  final Set<String> segmentIds;

  /// Опциональный набор ID оборудования, входящего в состав узла
  final Set<String> equipmentIds;

  /// ID чертежного листа (DrawingSheet), на котором этот узел развернут подробно
  final String? targetSheetId;

  /// Номер целевого листа для подписи под полкой выноски (напр. "Лист 2")
  final int? targetSheetNumber;

  /// Форма контура обводки узла на основном чертеже
  final DetailBoundaryShape boundaryShape;

  /// Отступ контура обводки от габаритов элементов узла (в мм бумаги на листе)
  final double paddingMm;

  /// Вершины свободного многоугольника в сырых 2D-координатах проекции модели (rawModel2d).
  /// Хранение в координатах модели гарантирует синхронное масштабирование и сдвиг с видовым экраном.
  final List<Offset> polygonVerticesModel2d;

  /// Положение начала полки выноски узла в сырых 2D-координатах модели (rawModel2d).
  /// Если null — вычисляется автоматически сверху-справа от контура.
  final Offset? shelfPositionModel2d;

  /// Автоматически скрывать мелкие выноски и размеры элементов этого узла на общих листах
  final bool suppressCalloutsOnOverview;

  /// Показывать ли примыкающие участки основной трассы бледным пунктиром на листе узла
  final bool showContextStubs;

  /// Максимальная длина контекстного «хвоста» примыкающей трубы в 3D (мм)
  final double contextStubLengthMm;

  const DetailNode({
    required this.id,
    required this.mark,
    this.title = '',
    required this.segmentIds,
    this.equipmentIds = const {},
    this.targetSheetId,
    this.targetSheetNumber,
    this.boundaryShape = DetailBoundaryShape.roundedRect,
    this.paddingMm = 6.0,
    this.polygonVerticesModel2d = const [],
    this.shelfPositionModel2d,
    this.suppressCalloutsOnOverview = true,
    this.showContextStubs = true,
    this.contextStubLengthMm = 450.0,
  });

  /// Эффективный заголовок над полкой (например, "Узел А")
  String get effectiveTitle => title.trim().isNotEmpty ? title.trim() : 'Узел $mark';

  /// Эффективная ссылка на лист под полкой (например, "Лист 2")
  String get effectiveSheetLabel =>
      targetSheetNumber != null ? 'Лист $targetSheetNumber' : 'Лист узла';

  String get effectiveSheetReference => effectiveSheetLabel;
  String get shelfBottomText => effectiveSheetLabel;

  /// Вычисляет 2D габаритный прямоугольник (в rawModel2d координатах) всех элементов узла
  Rect? calculateModel2dBounds(PipingNetwork network, AxonometryProjector projector) {
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;
    bool hasPoints = false;

    void include3d(double x, double y, double z) {
      final raw = projector.projectRaw(x, y, z);
      if (raw.dx < minX) minX = raw.dx;
      if (raw.dx > maxX) maxX = raw.dx;
      if (raw.dy < minY) minY = raw.dy;
      if (raw.dy > maxY) maxY = raw.dy;
      hasPoints = true;
    }

    for (final segId in segmentIds) {
      final seg = network.segments[segId];
      if (seg == null) continue;
      final n1 = network.nodes[seg.startNodeId];
      final n2 = network.nodes[seg.endNodeId];
      if (n1 != null) include3d(n1.x, n1.y, n1.z);
      if (n2 != null) include3d(n2.x, n2.y, n2.z);
    }

    for (final eqId in equipmentIds) {
      final eq = network.equipments[eqId];
      if (eq == null) continue;
      include3d(eq.x - eq.width / 2, eq.y - eq.length / 2, eq.z);
      include3d(eq.x + eq.width / 2, eq.y + eq.length / 2, eq.z + eq.height);
    }

    if (!hasPoints) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Генерирует аккуратный выпуклый многоугольник с отступом вокруг всех узлов участка
  /// в координатах rawModel2d (для режима DetailBoundaryShape.polygon)
  List<Offset> computeDefaultPolygonModel2d(
    PipingNetwork network,
    AxonometryProjector projector, {
    double marginModelUnits = 160.0,
  }) {
    final rawPts = <Offset>[];
    for (final segId in segmentIds) {
      final seg = network.segments[segId];
      if (seg == null) continue;
      final n1 = network.nodes[seg.startNodeId];
      final n2 = network.nodes[seg.endNodeId];
      if (n1 != null) rawPts.add(projector.projectRaw(n1.x, n1.y, n1.z));
      if (n2 != null) rawPts.add(projector.projectRaw(n2.x, n2.y, n2.z));
    }
    for (final eqId in equipmentIds) {
      final eq = network.equipments[eqId];
      if (eq == null) continue;
      rawPts.add(projector.projectRaw(eq.x, eq.y, eq.z + eq.height / 2));
    }

    if (rawPts.isEmpty) {
      return const [
        Offset(-200, -150),
        Offset(200, -150),
        Offset(200, 150),
        Offset(-200, 150),
      ];
    }

    // Строим облако точек с радиальным расширением вокруг каждой узловой точки,
    // чтобы выпуклая оболочка имела аккуратный отступ вокруг труб
    final expanded = <Offset>[];
    const int dirs = 8;
    for (final pt in rawPts) {
      for (int i = 0; i < dirs; i++) {
        final angle = (2.0 * math.pi * i) / dirs;
        expanded.add(Offset(
          pt.dx + math.cos(angle) * marginModelUnits,
          pt.dy + math.sin(angle) * marginModelUnits,
        ));
      }
    }

    final hull = _convexHull(expanded);
    if (hull.length <= 8) return hull;

    // Упрощаем оболочку до 6..8 характерных вершин, чтобы пользователю было удобно двигать ручки
    return _simplifyPolygon(hull, targetMaxVertices: 8);
  }

  /// Возвращает актуальные вершины многоугольника в rawModel2d
  List<Offset> getEffectivePolygonModel2d(
    PipingNetwork network,
    AxonometryProjector projector, {
    double marginModelUnits = 160.0,
  }) {
    if (polygonVerticesModel2d.length >= 3) {
      return polygonVerticesModel2d;
    }
    return computeDefaultPolygonModel2d(
      network,
      projector,
      marginModelUnits: marginModelUnits,
    );
  }

  /// Алгоритм Эндрю (Monotone Chain) для построения выпуклой оболочки
  static List<Offset> _convexHull(List<Offset> pts) {
    if (pts.length <= 3) return List<Offset>.from(pts);
    final sorted = List<Offset>.from(pts)
      ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));

    double cross(Offset o, Offset a, Offset b) {
      return (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    }

    final lower = <Offset>[];
    for (final p in sorted) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <Offset>[];
    for (int i = sorted.length - 1; i >= 0; i--) {
      final p = sorted[i];
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  static List<Offset> _simplifyPolygon(List<Offset> hull, {int targetMaxVertices = 8}) {
    var current = List<Offset>.from(hull);
    while (current.length > targetMaxVertices && current.length > 4) {
      int minIdx = 0;
      double minArea = double.infinity;
      final n = current.length;
      for (int i = 0; i < n; i++) {
        final prev = current[(i - 1 + n) % n];
        final curr = current[i];
        final next = current[(i + 1) % n];
        final area = ((prev.dx * (curr.dy - next.dy) +
                    curr.dx * (next.dy - prev.dy) +
                    next.dx * (prev.dy - curr.dy))
                .abs()) *
            0.5;
        if (area < minArea) {
          minArea = area;
          minIdx = i;
        }
      }
      current.removeAt(minIdx);
    }
    return current;
  }

  /// Находит ближайшую точку на периметре замкнутого многоугольника [polygon] к точке [target]
  static Offset findClosestPointOnPolygon(Offset target, List<Offset> polygon) {
    if (polygon.isEmpty) return target;
    if (polygon.length == 1) return polygon.first;

    Offset bestPt = polygon.first;
    double bestDistSq = double.infinity;

    for (int i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      final dx = p2.dx - p1.dx;
      final dy = p2.dy - p1.dy;
      final lenSq = dx * dx + dy * dy;
      Offset proj;
      if (lenSq <= 1e-6) {
        proj = p1;
      } else {
        final t = (((target.dx - p1.dx) * dx + (target.dy - p1.dy) * dy) / lenSq).clamp(0.0, 1.0);
        proj = Offset(p1.dx + t * dx, p1.dy + t * dy);
      }
      final distSq = (target.dx - proj.dx) * (target.dx - proj.dx) +
          (target.dy - proj.dy) * (target.dy - proj.dy);
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        bestPt = proj;
      }
    }
    return bestPt;
  }

  /// Находит ближайшую точку на периметре прямоугольника [rect] к точке [target]
  static Offset findClosestPointOnRect(Offset target, Rect rect) {
    final corners = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];
    return findClosestPointOnPolygon(target, corners);
  }

  DetailNode copyWith({
    String? id,
    String? mark,
    String? title,
    Set<String>? segmentIds,
    Set<String>? equipmentIds,
    String? targetSheetId,
    bool clearTargetSheetId = false,
    bool clearTargetSheet = false,
    int? targetSheetNumber,
    bool clearTargetSheetNumber = false,
    DetailBoundaryShape? boundaryShape,
    double? paddingMm,
    List<Offset>? polygonVerticesModel2d,
    Offset? shelfPositionModel2d,
    bool clearShelfPosition = false,
    bool? suppressCalloutsOnOverview,
    bool? showContextStubs,
    double? contextStubLengthMm,
  }) {
    return DetailNode(
      id: id ?? this.id,
      mark: mark ?? this.mark,
      title: title ?? this.title,
      segmentIds: segmentIds ?? this.segmentIds,
      equipmentIds: equipmentIds ?? this.equipmentIds,
      targetSheetId: (clearTargetSheetId || clearTargetSheet) ? null : (targetSheetId ?? this.targetSheetId),
      targetSheetNumber: (clearTargetSheetNumber || clearTargetSheet)
          ? null
          : (targetSheetNumber ?? this.targetSheetNumber),
      boundaryShape: boundaryShape ?? this.boundaryShape,
      paddingMm: paddingMm ?? this.paddingMm,
      polygonVerticesModel2d: polygonVerticesModel2d ?? this.polygonVerticesModel2d,
      shelfPositionModel2d: clearShelfPosition ? null : (shelfPositionModel2d ?? this.shelfPositionModel2d),
      suppressCalloutsOnOverview: suppressCalloutsOnOverview ?? this.suppressCalloutsOnOverview,
      showContextStubs: showContextStubs ?? this.showContextStubs,
      contextStubLengthMm: contextStubLengthMm ?? this.contextStubLengthMm,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mark': mark,
        'title': title,
        'segmentIds': segmentIds.toList(),
        if (equipmentIds.isNotEmpty) 'equipmentIds': equipmentIds.toList(),
        if (targetSheetId != null) 'targetSheetId': targetSheetId,
        if (targetSheetNumber != null) 'targetSheetNumber': targetSheetNumber,
        'boundaryShape': boundaryShape.name,
        'paddingMm': paddingMm,
        if (polygonVerticesModel2d.isNotEmpty)
          'polygonVerticesModel2d': polygonVerticesModel2d
              .map((pt) => {'x': pt.dx, 'y': pt.dy})
              .toList(),
        if (shelfPositionModel2d != null)
          'shelfPositionModel2d': {
            'x': shelfPositionModel2d!.dx,
            'y': shelfPositionModel2d!.dy,
          },
        'suppressCalloutsOnOverview': suppressCalloutsOnOverview,
        'showContextStubs': showContextStubs,
        'contextStubLengthMm': contextStubLengthMm,
      };

  factory DetailNode.fromJson(Map<String, dynamic> json) {
    final segList = json['segmentIds'] is List
        ? (json['segmentIds'] as List).map((e) => e.toString()).toSet()
        : <String>{};
    final eqList = json['equipmentIds'] is List
        ? (json['equipmentIds'] as List).map((e) => e.toString()).toSet()
        : <String>{};
    final polyList = <Offset>[];
    if (json['polygonVerticesModel2d'] is List) {
      for (final item in json['polygonVerticesModel2d'] as List) {
        if (item is Map) {
          final x = (item['x'] as num?)?.toDouble() ?? 0.0;
          final y = (item['y'] as num?)?.toDouble() ?? 0.0;
          polyList.add(Offset(x, y));
        }
      }
    }
    Offset? shelfPos;
    if (json['shelfPositionModel2d'] is Map) {
      final m = json['shelfPositionModel2d'] as Map;
      shelfPos = Offset(
        (m['x'] as num?)?.toDouble() ?? 0.0,
        (m['y'] as num?)?.toDouble() ?? 0.0,
      );
    }

    return DetailNode(
      id: json['id'] as String,
      mark: json['mark'] as String? ?? 'А',
      title: json['title'] as String? ?? '',
      segmentIds: segList,
      equipmentIds: eqList,
      targetSheetId: json['targetSheetId'] as String?,
      targetSheetNumber: json['targetSheetNumber'] as int?,
      boundaryShape: DetailBoundaryShape.values.firstWhere(
        (e) => e.name == json['boundaryShape'],
        orElse: () => DetailBoundaryShape.roundedRect,
      ),
      paddingMm: (json['paddingMm'] as num?)?.toDouble() ?? 6.0,
      polygonVerticesModel2d: polyList,
      shelfPositionModel2d: shelfPos,
      suppressCalloutsOnOverview: json['suppressCalloutsOnOverview'] as bool? ?? true,
      showContextStubs: json['showContextStubs'] as bool? ?? true,
      contextStubLengthMm: (json['contextStubLengthMm'] as num?)?.toDouble() ?? 450.0,
    );
  }
}
