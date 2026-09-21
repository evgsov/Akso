import 'dart:math' as math;
import 'dart:ui';
import '../../domain/enums/projection_type.dart';
import '../../domain/models/node_3d.dart';

/// Математический проектор 3D-координат сети в 2D-плоскость экрана и чертежа
class AxonometryProjector {
  final ProjectionType projectionType;

  /// Углы вращения для 3D-орбиты (в радианах)
  final double orbitAzimuth; // Горизонтальный угол
  final double orbitElevation; // Вертикальный угол (наклон)

  /// Масштаб отображения (пикселей на миллиметр)
  final double scale;

  /// Смещение центра холста (панорамирование)
  final Offset panOffset;

  /// Центр вращения сцены
  final Node3D targetCenter;

  const AxonometryProjector({
    this.projectionType = ProjectionType.gostFrontal45,
    this.orbitAzimuth = -math.pi / 4,
    this.orbitElevation = math.pi / 6,
    this.scale = 0.2, // 1 метр = 200 пикселей
    this.panOffset = Offset.zero,
    this.targetCenter = const Node3D(id: 'center', x: 0, y: 0, z: 0),
  });

  /// Проекция точки (X, Y, Z в мм) в экранные координаты (Offset в пикселях)
  Offset project(Node3D point) {
    return projectCoordinates(point.x, point.y, point.z);
  }

  /// Проекция точки (X, Y, Z в мм) в сырые 2D-координаты аксонометрии
  Offset projectNodeRaw(Node3D point) => projectRaw(point.x, point.y, point.z);

  /// Проекция координат (X, Y, Z в мм) в сырые 2D-координаты аксонометрии
  /// (без учета экранного масштаба scale и панорамирования panOffset)
  Offset projectRaw(double x, double y, double z) {
    double rawX2d = 0.0;
    double rawY2d = 0.0;

    switch (projectionType) {
      case ProjectionType.gostFrontal45:
        // ГОСТ 21.602: Y горизонтально (1:1), X под 45° (0.5), Z вертикально (1:1)
        const cos45 = 0.70710678118;
        const sin45 = 0.70710678118;
        rawX2d = y - (x * 0.5 * cos45);
        rawY2d = z - (x * 0.5 * sin45);
        break;

      case ProjectionType.gostMirrored45:
        // Зеркальный разворот для трасс, где стояки загораживают видимость
        const cos45 = 0.70710678118;
        const sin45 = 0.70710678118;
        rawX2d = -y + (x * 0.5 * cos45);
        rawY2d = z - (x * 0.5 * sin45);
        break;

      case ProjectionType.iso30:
        // ISO прямоугольная изометрия 30° / 30°
        const cos30 = 0.86602540378;
        const sin30 = 0.5;
        rawX2d = (y - x) * cos30;
        rawY2d = z + (x + y) * sin30;
        break;

      case ProjectionType.topPlan2d:
        // План сверху (X вправо, Y вверх)
        rawX2d = x;
        rawY2d = y;
        break;

      case ProjectionType.orbit3d:
        // 3D вращение относительно центра сцены
        final dx = x - targetCenter.x;
        final dy = y - targetCenter.y;
        final dz = z - targetCenter.z;

        // Поворот вокруг Z (азимут)
        final cosA = math.cos(orbitAzimuth);
        final sinA = math.sin(orbitAzimuth);
        final x1 = dx * cosA - dy * sinA;
        final y1 = dx * sinA + dy * cosA;
        final z1 = dz;

        // Поворот вокруг X (элевация)
        final cosE = math.cos(orbitElevation);
        final sinE = math.sin(orbitElevation);
        final z2 = y1 * sinE + z1 * cosE;

        rawX2d = x1;
        rawY2d = z2;
        break;
    }

    return Offset(rawX2d, rawY2d);
  }

  /// Проекция координат (X, Y, Z) в экранные координаты
  Offset projectCoordinates(double x, double y, double z) {
    final raw = projectRaw(x, y, z);
    // Во Flutter ось Y направлена вниз, в то время как Z в CAD направлена вверх
    final screenX = panOffset.dx + (raw.dx * scale);
    final screenY = panOffset.dy - (raw.dy * scale);

    return Offset(screenX, screenY);
  }

  /// Вычисление глубины точки (Z-depth) вдоль луча взгляда камеры.
  /// Чем больше значение depth, тем глубже (дальше) точка находится от наблюдателя.
  /// Используется для Painter's algorithm (Z-сортировки) в 3D.
  double computeDepth(double x, double y, double z) {
    switch (projectionType) {
      case ProjectionType.orbit3d:
        final dx = x - targetCenter.x;
        final dy = y - targetCenter.y;
        final dz = z - targetCenter.z;

        final cosA = math.cos(orbitAzimuth);
        final sinA = math.sin(orbitAzimuth);
        final y1 = dx * sinA + dy * cosA;

        final cosE = math.cos(orbitElevation);
        final sinE = math.sin(orbitElevation);
        return y1 * cosE - dz * sinE;

      case ProjectionType.gostFrontal45:
      case ProjectionType.gostMirrored45:
        return x;

      case ProjectionType.iso30:
        return (x + y) * 0.70710678118;

      case ProjectionType.topPlan2d:
        return -z;
    }
  }

  /// Вычисление глубины узла Node3D
  double computeNodeDepth(Node3D node) => computeDepth(node.x, node.y, node.z);

  /// Вычисление охватывающего 2D-прямоугольника (в raw 2D-координатах) для набора 3D-узлов
  Rect? computeRawBoundingBox(Iterable<Node3D> nodes) {
    if (nodes.isEmpty) return null;
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final n in nodes) {
      final raw = projectRaw(n.x, n.y, n.z);
      if (raw.dx < minX) minX = raw.dx;
      if (raw.dx > maxX) maxX = raw.dx;
      if (raw.dy < minY) minY = raw.dy;
      if (raw.dy > maxY) maxY = raw.dy;
    }

    if (minX.isInfinite || maxX.isInfinite) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Обратное преобразование: вычисление высотной отметки Z (мм) по координатам экрана
  /// для фиксированных мировых координат (X, Y).
  /// Используется при вертикальном перетаскивании стояков (risers) и опусков.
  double unprojectElevation(Offset screenPoint, double fixedWorldX, double fixedWorldY) {
    final rawY2d = -(screenPoint.dy - panOffset.dy) / scale;

    switch (projectionType) {
      case ProjectionType.gostFrontal45:
        const sin45 = 0.70710678118;
        return rawY2d + (fixedWorldX * 0.5 * sin45);

      case ProjectionType.gostMirrored45:
        const sin45 = 0.70710678118;
        return rawY2d + (fixedWorldX * 0.5 * sin45);

      case ProjectionType.iso30:
        const sin30 = 0.5;
        return rawY2d - (fixedWorldX + fixedWorldY) * sin30;

      case ProjectionType.topPlan2d:
        return 0.0;

      case ProjectionType.orbit3d:
        final dx = fixedWorldX - targetCenter.x;
        final dy = fixedWorldY - targetCenter.y;
        final cosA = math.cos(orbitAzimuth);
        final sinA = math.sin(orbitAzimuth);
        final y1 = dx * sinA + dy * cosA;

        final cosE = math.cos(orbitElevation);
        final sinE = math.sin(orbitElevation);
        final safeCosE = cosE.abs() < 1e-4 ? (cosE >= 0 ? 1e-4 : -1e-4) : cosE;
        return targetCenter.z + (rawY2d - y1 * sinE) / safeCosE;
    }
  }

  /// Обратное преобразование: из координат экрана планшета в 3D координаты (X, Y)
  /// на заданной высотной отметке Z (мм)
  Node3D unproject(Offset screenPoint, double currentElevationZ) {
    final rawX2d = (screenPoint.dx - panOffset.dx) / scale;
    final rawY2d = -(screenPoint.dy - panOffset.dy) / scale;

    double worldX = 0.0;
    double worldY = 0.0;

    switch (projectionType) {
      case ProjectionType.gostFrontal45:
        const cos45 = 0.70710678118;
        const sin45 = 0.70710678118;
        // rawY2d = currentElevationZ - (worldX * 0.5 * sin45)
        // worldX = (currentElevationZ - rawY2d) / (0.5 * sin45)
        worldX = (currentElevationZ - rawY2d) / (0.5 * sin45);
        worldY = rawX2d + (worldX * 0.5 * cos45);
        break;

      case ProjectionType.gostMirrored45:
        const cos45 = 0.70710678118;
        const sin45 = 0.70710678118;
        worldX = (currentElevationZ - rawY2d) / (0.5 * sin45);
        worldY = -(rawX2d - (worldX * 0.5 * cos45));
        break;

      case ProjectionType.iso30:
        const cos30 = 0.86602540378;
        const sin30 = 0.5;
        // rawY2d = currentElevationZ + (worldX + worldY) * sin30
        // (worldX + worldY) = (rawY2d - currentElevationZ) / sin30
        // (worldY - worldX) = rawX2d / cos30
        final sum = (rawY2d - currentElevationZ) / sin30;
        final diff = rawX2d / cos30;
        worldY = (sum + diff) / 2.0;
        worldX = (sum - diff) / 2.0;
        break;

      case ProjectionType.topPlan2d:
        worldX = rawX2d;
        worldY = rawY2d;
        break;

      case ProjectionType.orbit3d:
        // Точная обратная 3D-матрица вращения камеры (элевация и азимут)
        final dz = currentElevationZ - targetCenter.z;
        final cosE = math.cos(orbitElevation);
        final sinE = math.sin(orbitElevation);

        // Защита от деления на 0 при виде строго в горизонт
        final safeSinE = sinE.abs() < 1e-4 ? (sinE >= 0 ? 1e-4 : -1e-4) : sinE;
        final y1 = (rawY2d - dz * cosE) / safeSinE;
        final x1 = rawX2d;

        final cosA = math.cos(orbitAzimuth);
        final sinA = math.sin(orbitAzimuth);

        // Обратный поворот вокруг Z (транспонированная ортогональная матрица)
        final dx = x1 * cosA + y1 * sinA;
        final dy = -x1 * sinA + y1 * cosA;

        worldX = targetCenter.x + dx;
        worldY = targetCenter.y + dy;
        break;
    }

    return Node3D(
      id: 'unprojected',
      x: worldX,
      y: worldY,
      z: currentElevationZ,
    );
  }

  AxonometryProjector copyWith({
    ProjectionType? projectionType,
    double? orbitAzimuth,
    double? orbitElevation,
    double? scale,
    Offset? panOffset,
    Node3D? targetCenter,
  }) {
    return AxonometryProjector(
      projectionType: projectionType ?? this.projectionType,
      orbitAzimuth: orbitAzimuth ?? this.orbitAzimuth,
      orbitElevation: orbitElevation ?? this.orbitElevation,
      scale: scale ?? this.scale,
      panOffset: panOffset ?? this.panOffset,
      targetCenter: targetCenter ?? this.targetCenter,
    );
  }
}
