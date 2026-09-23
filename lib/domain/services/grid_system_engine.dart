import 'dart:math' as math;
import 'dart:ui';
import '../models/construction_axis.dart';
import '../models/node_3d.dart';

/// Группа связанных выровненных концов параллельных осей (Alignment Chain)
class AlignmentChain {
  final bool isStart;
  final List<String> axisIds;
  final double alignmentCoordinate;

  const AlignmentChain({
    required this.isStart,
    required this.axisIds,
    required this.alignmentCoordinate,
  });
}

/// Временный размер между соседними параллельными осями (Revit-style Temporary Dimension)
class TemporaryGridDimension {
  final String targetAxisId;
  final String referenceAxisId;
  final double distanceMm;
  final Node3D dimStart;
  final Node3D dimEnd;

  const TemporaryGridDimension({
    required this.targetAxisId,
    required this.referenceAxisId,
    required this.distanceMm,
    required this.dimStart,
    required this.dimEnd,
  });
}

/// Сервис координатной сетки и строительных осей здания по ГОСТ 21.101 и Revit
class GridSystemEngine {
  /// Алфавит русских букв по ГОСТ Р 21.101-2020 (п. 5.3.3)
  /// Исключены: Ё, З, Й, О, Х, Ц, Ч, Щ, Ъ, Ы, Ь
  static const List<String> gostRussianLetters = [
    'А', 'Б', 'В', 'Г', 'Д', 'Е', 'Ж', 'И', 'К', 'Л', 'М',
    'Н', 'П', 'Р', 'С', 'Т', 'У', 'Ф', 'Ш', 'Э', 'Ю', 'Я'
  ];

  /// Алфавит латинских букв (исключены I, O)
  static const List<String> latinLetters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L',
    'M', 'N', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
  ];

  /// Генерация следующей марки оси с автоинкрементом по ГОСТ
  static String generateNextLabel(String currentLabel) {
    final trimmed = currentLabel.trim();
    if (trimmed.isEmpty) return '1';

    // 1. Только цифры (1 -> 2, 9 -> 10)
    final intVal = int.tryParse(trimmed);
    if (intVal != null) {
      return (intVal + 1).toString();
    }

    // 2. Строка с цифровым суффиксом (Grid-1 -> Grid-2, А1 -> А2)
    final match = RegExp(r'^(.*?)(\d+)$').firstMatch(trimmed);
    if (match != null) {
      final prefix = match.group(1)!;
      final numVal = int.parse(match.group(2)!);
      return '$prefix${numVal + 1}';
    }

    // 3. Русские буквы по ГОСТ 21.101
    final upper = trimmed.toUpperCase();
    final ruIdx = gostRussianLetters.indexOf(upper);
    if (ruIdx != -1) {
      if (ruIdx + 1 < gostRussianLetters.length) {
        return gostRussianLetters[ruIdx + 1];
      } else {
        return '${gostRussianLetters.first}1';
      }
    }

    // 4. Латинские буквы
    final latIdx = latinLetters.indexOf(upper);
    if (latIdx != -1) {
      if (latIdx + 1 < latinLetters.length) {
        return latinLetters[latIdx + 1];
      } else {
        return '${latinLetters.first}1';
      }
    }

    // 5. Fallback
    return '${trimmed}1';
  }

  /// Поиск цепочек выравнивания концов параллельных осей
  static List<AlignmentChain> findAlignmentChains(
    Map<String, ConstructionAxis> axes, {
    double toleranceMm = 50.0,
  }) {
    final chains = <AlignmentChain>[];
    if (axes.length < 2) return chains;

    final axisList = axes.values.toList();

    // Проверяем выравнивание начала (isStart = true) и конца (isStart = false)
    for (final isStart in [true, false]) {
      final processed = <String>{};

      for (int i = 0; i < axisList.length; i++) {
        final a1 = axisList[i];
        if (processed.contains(a1.id)) continue;

        final dir1 = _get2dDirection(a1);
        if (dir1 == null) continue;

        final p1 = isStart ? a1.startPoint : a1.endPoint;
        final coord1 = p1.x * dir1.dx + p1.y * dir1.dy;

        final groupIds = <String>[a1.id];

        for (int j = i + 1; j < axisList.length; j++) {
          final a2 = axisList[j];
          if (processed.contains(a2.id)) continue;

          final dir2 = _get2dDirection(a2);
          if (dir2 == null) continue;

          // Проверка параллельности
          final dot = dir1.dx * dir2.dx + dir1.dy * dir2.dy;
          if (dot.abs() < 0.99) continue;

          // Проекция точки вдоль оси
          final p2 = isStart ? a2.startPoint : a2.endPoint;
          final coord2 = p2.x * dir1.dx + p2.y * dir1.dy;

          if ((coord1 - coord2).abs() <= toleranceMm) {
            groupIds.add(a2.id);
          }
        }

        if (groupIds.length >= 2) {
          processed.addAll(groupIds);
          chains.add(AlignmentChain(
            isStart: isStart,
            axisIds: groupIds,
            alignmentCoordinate: coord1,
          ));
        }
      }
    }

    return chains;
  }

  /// Совместное растяжение цепочки выровненных осей при заблокированном замочке
  static Map<String, ConstructionAxis> stretchChainedEndpoints({
    required String draggedAxisId,
    required bool isStart,
    required Node3D newPoint,
    required Map<String, ConstructionAxis> axes,
    double toleranceMm = 50.0,
  }) {
    final draggedAxis = axes[draggedAxisId];
    if (draggedAxis == null) return axes;

    final oldPoint = isStart ? draggedAxis.startPoint : draggedAxis.endPoint;
    final deltaX = newPoint.x - oldPoint.x;
    final deltaY = newPoint.y - oldPoint.y;
    final deltaZ = newPoint.z - oldPoint.z;

    final chains = findAlignmentChains(axes, toleranceMm: toleranceMm);
    final activeChain = chains.where((c) => c.isStart == isStart && c.axisIds.contains(draggedAxisId)).firstOrNull;

    final isDraggedLocked = isStart ? draggedAxis.isStartLocked : draggedAxis.isEndLocked;
    final updated = Map<String, ConstructionAxis>.from(axes);

    if (activeChain != null && isDraggedLocked) {
      for (final id in activeChain.axisIds) {
        final ax = axes[id];
        if (ax == null) continue;

        final isLocked = isStart ? ax.isStartLocked : ax.isEndLocked;
        if (id == draggedAxisId || isLocked) {
          if (isStart) {
            updated[id] = ax.copyWith(
              startPoint: Node3D(
                id: ax.startPoint.id,
                x: ax.startPoint.x + deltaX,
                y: ax.startPoint.y + deltaY,
                z: ax.startPoint.z + deltaZ,
              ),
            );
          } else {
            updated[id] = ax.copyWith(
              endPoint: Node3D(
                id: ax.endPoint.id,
                x: ax.endPoint.x + deltaX,
                y: ax.endPoint.y + deltaY,
                z: ax.endPoint.z + deltaZ,
              ),
            );
          }
        }
      }
    } else {
      // Одиночное растяжение
      if (isStart) {
        updated[draggedAxisId] = draggedAxis.copyWith(startPoint: newPoint);
      } else {
        updated[draggedAxisId] = draggedAxis.copyWith(endPoint: newPoint);
      }
    }

    return updated;
  }

  /// Расчет временных цепочек расстояний (Temporary Dimensions) до соседних параллельных осей
  static List<TemporaryGridDimension> calculateTemporaryDimensions(
    String selectedAxisId,
    Map<String, ConstructionAxis> axes,
  ) {
    final selected = axes[selectedAxisId];
    if (selected == null) return const [];

    final dir = _get2dDirection(selected);
    if (dir == null) return const [];

    final normal = Offset(-dir.dy, dir.dx); // 2D нормаль к оси
    final selMid = Offset(
      (selected.startPoint.x + selected.endPoint.x) / 2,
      (selected.startPoint.y + selected.endPoint.y) / 2,
    );

    ConstructionAxis? bestPrev;
    double minNegDist = -double.infinity;

    ConstructionAxis? bestNext;
    double minPosDist = double.infinity;

    for (final entry in axes.entries) {
      if (entry.key == selectedAxisId) continue;
      final other = entry.value;

      final otherDir = _get2dDirection(other);
      if (otherDir == null) continue;

      // Проверка параллельности
      final dot = dir.dx * otherDir.dx + dir.dy * otherDir.dy;
      if (dot.abs() < 0.99) continue;

      final otherMid = Offset(
        (other.startPoint.x + other.endPoint.x) / 2,
        (other.startPoint.y + other.endPoint.y) / 2,
      );

      final diff = otherMid - selMid;
      final distAlongNormal = diff.dx * normal.dx + diff.dy * normal.dy;

      if (distAlongNormal < -1.0) {
        if (distAlongNormal > minNegDist) {
          minNegDist = distAlongNormal;
          bestPrev = other;
        }
      } else if (distAlongNormal > 1.0) {
        if (distAlongNormal < minPosDist) {
          minPosDist = distAlongNormal;
          bestNext = other;
        }
      }
    }

    final result = <TemporaryGridDimension>[];

    if (bestPrev != null) {
      final dist = minNegDist.abs();
      final p1 = Node3D(id: 't1_s', x: selMid.dx, y: selMid.dy, z: selected.elevationZ);
      final p2 = Node3D(id: 't1_e', x: selMid.dx + normal.dx * minNegDist, y: selMid.dy + normal.dy * minNegDist, z: selected.elevationZ);
      result.add(TemporaryGridDimension(
        targetAxisId: selectedAxisId,
        referenceAxisId: bestPrev.id,
        distanceMm: dist,
        dimStart: p1,
        dimEnd: p2,
      ));
    }

    if (bestNext != null) {
      final dist = minPosDist.abs();
      final p1 = Node3D(id: 't2_s', x: selMid.dx, y: selMid.dy, z: selected.elevationZ);
      final p2 = Node3D(id: 't2_e', x: selMid.dx + normal.dx * minPosDist, y: selMid.dy + normal.dy * minPosDist, z: selected.elevationZ);
      result.add(TemporaryGridDimension(
        targetAxisId: selectedAxisId,
        referenceAxisId: bestNext.id,
        distanceMm: dist,
        dimStart: p1,
        dimEnd: p2,
      ));
    }

    return result;
  }

  /// Смещение оси на заданное точное расстояние от опорной параллельной оси
  static ConstructionAxis moveAxisByDistance({
    required ConstructionAxis axisToMove,
    required ConstructionAxis referenceAxis,
    required double targetDistanceMm,
  }) {
    final rDir = _get2dDirection(referenceAxis);
    if (rDir == null) return axisToMove;

    final normal = Offset(-rDir.dy, rDir.dx);

    final rMid = Offset(
      (referenceAxis.startPoint.x + referenceAxis.endPoint.x) / 2,
      (referenceAxis.startPoint.y + referenceAxis.endPoint.y) / 2,
    );
    final mMid = Offset(
      (axisToMove.startPoint.x + axisToMove.endPoint.x) / 2,
      (axisToMove.startPoint.y + axisToMove.endPoint.y) / 2,
    );

    final diff = mMid - rMid;
    final currentDist = diff.dx * normal.dx + diff.dy * normal.dy;
    final sign = currentDist >= 0 ? 1.0 : -1.0;

    final targetDist = sign * targetDistanceMm;
    final shiftMm = targetDist - currentDist;

    final shift = Offset(normal.dx * shiftMm, normal.dy * shiftMm);

    return axisToMove.copyWith(
      startPoint: Node3D(
        id: axisToMove.startPoint.id,
        x: axisToMove.startPoint.x + shift.dx,
        y: axisToMove.startPoint.y + shift.dy,
        z: axisToMove.startPoint.z,
      ),
      endPoint: Node3D(
        id: axisToMove.endPoint.id,
        x: axisToMove.endPoint.x + shift.dx,
        y: axisToMove.endPoint.y + shift.dy,
        z: axisToMove.endPoint.z,
      ),
    );
  }

  /// Создание параллельной копии оси со смещением (Revit Offset)
  static ConstructionAxis createOffsetAxis({
    required ConstructionAxis sourceAxis,
    required double offsetDistanceMm,
    bool positiveSide = true,
  }) {
    final dir = _get2dDirection(sourceAxis) ?? const Offset(1, 0);
    final Offset normal;
    if (dir.dy.abs() > dir.dx.abs()) {
      // Преимущественно вертикальная ось: положительное смещение вправо (+X)
      normal = dir.dy >= 0 ? Offset(dir.dy, -dir.dx) : Offset(-dir.dy, dir.dx);
    } else {
      // Преимущественно горизонтальная ось: положительное смещение вверх (+Y)
      normal = dir.dx >= 0 ? Offset(-dir.dy, dir.dx) : Offset(dir.dy, -dir.dx);
    }
    final sign = positiveSide ? 1.0 : -1.0;
    final shift = Offset(normal.dx * offsetDistanceMm * sign, normal.dy * offsetDistanceMm * sign);

    final nextLabel = generateNextLabel(sourceAxis.label);
    final nextId = 'axis_${DateTime.now().microsecondsSinceEpoch}';

    return sourceAxis.copyWith(
      id: nextId,
      label: nextLabel,
      startPoint: Node3D(
        id: '${nextId}_start',
        x: sourceAxis.startPoint.x + shift.dx,
        y: sourceAxis.startPoint.y + shift.dy,
        z: sourceAxis.startPoint.z,
      ),
      endPoint: Node3D(
        id: '${nextId}_end',
        x: sourceAxis.endPoint.x + shift.dx,
        y: sourceAxis.endPoint.y + shift.dy,
        z: sourceAxis.endPoint.z,
      ),
      clearStartElbow: true,
      clearEndElbow: true,
    );
  }

  static Offset? _get2dDirection(ConstructionAxis axis) {
    final dx = axis.endPoint.x - axis.startPoint.x;
    final dy = axis.endPoint.y - axis.startPoint.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-4) return null;
    return Offset(dx / len, dy / len);
  }
}
