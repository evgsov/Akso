import 'dart:math' as math;
import 'dart:ui';
import '../../core/math/axonometry_projector.dart';
import '../enums/projection_type.dart';
import '../models/drawing_sheet.dart';
import '../models/piping_network.dart';

/// Результат автоматического расчета масштаба и центра видового экрана
class AutoFitResult {
  final double scale;
  final double centerX;
  final double centerY;

  const AutoFitResult({
    required this.scale,
    required this.centerX,
    required this.centerY,
  });
}

/// Математический сервис для преобразования координат между 3D-моделью,
/// 2D-аксонометрией, пространством листа (мм бумаги) и экранными пикселями
class ViewportTransformService {
  /// Стандартный ряд строительных и машиностроительных масштабов по ГОСТ 2.302-68
  static const List<double> standardScales = [
    1.0 / 10.0,  // 1:10
    1.0 / 20.0,  // 1:20
    1.0 / 25.0,  // 1:25
    1.0 / 50.0,  // 1:50
    1.0 / 100.0, // 1:100
    1.0 / 200.0, // 1:200
    1.0 / 500.0, // 1:500
    1.0 / 1000.0,// 1:1000
  ];

  /// Преобразование сырой 2D-координаты модели в миллиметры листа бумаги
  static Offset model2dToSheetMm(Offset rawModel2d, SheetViewport viewport) {
    final vpCenterX = viewport.xMm + (viewport.widthMm / 2.0);
    final vpCenterY = viewport.yMm + (viewport.heightMm / 2.0);

    final sheetX = vpCenterX + (rawModel2d.dx - viewport.modelCenterX) * viewport.viewScale;
    // Во Flutter/на листе ось Y направлена вниз, а в CAD 2D сырой Y направлен вверх
    final sheetY = vpCenterY - (rawModel2d.dy - viewport.modelCenterY) * viewport.viewScale;

    return Offset(sheetX, sheetY);
  }

  /// Преобразование координаты с листа бумаги (мм) обратно в сырую 2D-координату модели
  static Offset sheetMmToModel2d(Offset sheetMm, SheetViewport viewport) {
    final vpCenterX = viewport.xMm + (viewport.widthMm / 2.0);
    final vpCenterY = viewport.yMm + (viewport.heightMm / 2.0);

    final rawX = viewport.modelCenterX + (sheetMm.dx - vpCenterX) / viewport.viewScale;
    final rawY = viewport.modelCenterY - (sheetMm.dy - vpCenterY) / viewport.viewScale;

    return Offset(rawX, rawY);
  }

  /// Преобразование миллиметров листа в экранные пиксели Flutter
  static Offset sheetMmToScreen(Offset sheetMm, Offset sheetPanPx, double sheetZoomPxPerMm) {
    return Offset(
      sheetPanPx.dx + (sheetMm.dx * sheetZoomPxPerMm),
      sheetPanPx.dy + (sheetMm.dy * sheetZoomPxPerMm),
    );
  }

  /// Создает проектор AxonometryProjector, настроенный для прямого рендеринга модели
  /// и ее аннотаций (выносок, отметок) на экранные пиксели видового экрана листа
  static AxonometryProjector createViewportProjector({
    required SheetViewport viewport,
    required Offset sheetPanPx,
    required double sheetZoom,
    required ProjectionType projectionType,
  }) {
    final vpCenterX = viewport.xMm + (viewport.widthMm / 2.0);
    final vpCenterY = viewport.yMm + (viewport.heightMm / 2.0);

    final totalScale = viewport.viewScale * sheetZoom;
    final panX = sheetPanPx.dx + (vpCenterX - (viewport.modelCenterX * viewport.viewScale)) * sheetZoom;
    final panY = sheetPanPx.dy + (vpCenterY + (viewport.modelCenterY * viewport.viewScale)) * sheetZoom;

    return AxonometryProjector(
      projectionType: projectionType,
      scale: totalScale,
      panOffset: Offset(panX, panY),
    );
  }

  /// Преобразование экранных пикселей Flutter в миллиметры листа бумаги
  static Offset screenToSheetMm(Offset screenPx, Offset sheetPanPx, double sheetZoomPxPerMm) {
    if (sheetZoomPxPerMm <= 0) return Offset.zero;
    return Offset(
      (screenPx.dx - sheetPanPx.dx) / sheetZoomPxPerMm,
      (screenPx.dy - sheetPanPx.dy) / sheetZoomPxPerMm,
    );
  }

  /// Вычисление коэффициента масштабирования аннотаций (выносок, отметок)
  /// для сохранения постоянной высоты текста на листе бумаги независимо от viewScale
  static double calculateAnnotationScale(double viewScale) {
    if (viewScale <= 0) return 1.0;
    return 1.0 / viewScale;
  }

  /// Форматирование текстового обозначения масштаба (например, "М 1:50")
  static String formatScaleText(double viewScale) {
    if (viewScale <= 0) return '—';
    final ratio = (1.0 / viewScale).round();
    return 'М 1:$ratio';
  }

  /// Расчет 2D габаритного прямоугольника (Bounding Box) спроецированной сети
  static Rect calculateModel2dBounds(
    PipingNetwork network,
    ProjectionType projectionType, {
    Set<String>? visibleSystemIds,
  }) {
    final projector = AxonometryProjector(projectionType: projectionType);
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    void includePoint(double x, double y, double z) {
      final raw = projector.projectRaw(x, y, z);
      if (raw.dx < minX) minX = raw.dx;
      if (raw.dx > maxX) maxX = raw.dx;
      if (raw.dy < minY) minY = raw.dy;
      if (raw.dy > maxY) maxY = raw.dy;
    }

    bool hasPoints = false;

    // Сканируем сегменты труб
    for (final seg in network.segments.values) {
      if (visibleSystemIds != null && !visibleSystemIds.contains(seg.systemId)) {
        continue;
      }
      final n1 = network.nodes[seg.startNodeId];
      final n2 = network.nodes[seg.endNodeId];
      if (n1 != null) {
        includePoint(n1.x, n1.y, n1.z);
        hasPoints = true;
      }
      if (n2 != null) {
        includePoint(n2.x, n2.y, n2.z);
        hasPoints = true;
      }
    }

    // Если нет видимых сегментов, проверяем все узлы
    if (!hasPoints) {
      for (final n in network.nodes.values) {
        includePoint(n.x, n.y, n.z);
        hasPoints = true;
      }
    }

    if (!hasPoints || minX.isInfinite) {
      return const Rect.fromLTWH(-500, -500, 1000, 1000);
    }

    // Добавляем минимальный запас, чтобы не было нулевой ширины/высоты у строго вертикальных/горизонтальных труб
    final width = math.max(100.0, maxX - minX);
    final height = math.max(100.0, maxY - minY);
    final centerX = (minX + maxX) / 2.0;
    final centerY = (minY + maxY) / 2.0;

    return Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: width,
      height: height,
    );
  }

  /// Автоматический расчет оптимального центра и масштаба для вписывания модели в видовой экран
  static AutoFitResult calculateAutoFit({
    required PipingNetwork network,
    required ProjectionType projectionType,
    required SheetViewport viewport,
    double marginMm = 15.0,
    Set<String>? visibleSystemIds,
    bool snapToStandardScale = false,
  }) {
    final effectiveSystems = visibleSystemIds ?? viewport.visibleSystemIds;
    final bounds = calculateModel2dBounds(
      network,
      projectionType,
      visibleSystemIds: effectiveSystems,
    );

    final availW = math.max(10.0, viewport.widthMm - (marginMm * 2.0));
    final availH = math.max(10.0, viewport.heightMm - (marginMm * 2.0));

    final rawScaleX = availW / bounds.width;
    final rawScaleY = availH / bounds.height;
    var fitScale = math.min(rawScaleX, rawScaleY);

    if (snapToStandardScale) {
      // Ищем наибольший стандартный масштаб, который меньше или равен fitScale
      double bestScale = standardScales.last;
      for (final s in standardScales) {
        if (s <= fitScale) {
          bestScale = s;
          break;
        }
      }
      fitScale = bestScale;
    }

    // Ограничиваем масштаб разумными пределами
    fitScale = fitScale.clamp(0.0005, 1.0);

    return AutoFitResult(
      scale: fitScale,
      centerX: bounds.center.dx,
      centerY: bounds.center.dy,
    );
  }
}
