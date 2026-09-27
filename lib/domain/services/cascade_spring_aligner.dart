import 'dart:math' as math;
import 'dart:ui';
import '../models/callout_candidate_slot.dart';

/// Сервис 1D-пружинного каскадного выравнивания (Cascade Spring Aligner)
/// Выравнивает близкие по X выноски в строгие вертикальные каскады («друг под другом») с идеальным шагом
class CascadeSpringAligner {
  /// Выравнивает полочки, оказавшиеся на близких X-координатах, в строгий каскад
  static Map<String, CalloutCandidateSlot> align(
    Map<String, CalloutCandidateSlot> solution, {
    double? pitchMm,
    double maxXClusterDistance = 3.5,
    double maxYClusterDistance = 50.0,
  }) {
    if (solution.length <= 1) return solution;

    final result = Map<String, CalloutCandidateSlot>.from(solution);
    final entries = solution.entries.toList();

    // Построение графа смежности для кластеризации в каскадные группы
    final visited = <int>{};
    final clusters = <List<int>>[];

    for (int i = 0; i < entries.length; i++) {
      if (visited.contains(i)) continue;
      final cluster = [i];
      visited.add(i);

      for (int j = i + 1; j < entries.length; j++) {
        if (visited.contains(j)) continue;
        final slotA = entries[i].value;
        final slotB = entries[j].value;

        // Одно направление (обе вправо или обе влево)
        if (slotA.isRight != slotB.isRight) continue;

        // Близкие по X
        if ((slotA.entryShelf.dx - slotB.entryShelf.dx).abs() > maxXClusterDistance) continue;

        // Близкие по Y
        if ((slotA.entryShelf.dy - slotB.entryShelf.dy).abs() > maxYClusterDistance) continue;

        cluster.add(j);
        visited.add(j);
      }

      if (cluster.length >= 2) {
        clusters.add(cluster);
      }
    }

    // Выравнивание для каждого найденного каскадного кластера
    for (final clusterIndices in clusters) {
      final clusterSlots = clusterIndices.map((idx) => entries[idx].value).toList();

      // Находим медианную координату X
      final xValues = clusterSlots.map((s) => s.entryShelf.dx).toList()..sort();
      final targetX = xValues[xValues.length ~/ 2];

      // Сортируем элементы кластера по вертикали (сверху вниз)
      final sortedClusterIndices = List<int>.from(clusterIndices)
        ..sort((a, b) => entries[a].value.entryShelf.dy.compareTo(entries[b].value.entryShelf.dy));

      final firstSlot = entries[sortedClusterIndices.first].value;
      final defaultPitch = pitchMm ?? (firstSlot.boundingBox.height + 2.0);

      double currentY = firstSlot.entryShelf.dy;

      for (int k = 0; k < sortedClusterIndices.length; k++) {
        final idx = sortedClusterIndices[k];
        final id = entries[idx].key;
        final oldSlot = entries[idx].value;

        final targetY = k == 0 ? oldSlot.entryShelf.dy : math.max(oldSlot.entryShelf.dy, currentY + defaultPitch);
        currentY = targetY;

        final textW = oldSlot.boundingBox.width - 1.6;
        final halfH = oldSlot.boundingBox.height / 2.0;

        final newEntryShelf = Offset(targetX, targetY);
        final newShelfEnd = Offset(
          oldSlot.isRight ? targetX + textW : targetX - textW,
          targetY,
        );

        final rectLeft = oldSlot.isRight ? targetX : targetX - textW;
        final rectRight = oldSlot.isRight ? targetX + textW : targetX;
        final newBox = Rect.fromLTRB(
          rectLeft - 0.8,
          targetY - halfH,
          rectRight + 0.8,
          targetY + halfH,
        );

        final newRadius = (newEntryShelf - oldSlot.anchor).distance;
        final newAngle = math.atan2(newEntryShelf.dy - oldSlot.anchor.dy, newEntryShelf.dx - oldSlot.anchor.dx);

        result[id] = CalloutCandidateSlot(
          anchor: oldSlot.anchor,
          entryShelf: newEntryShelf,
          shelfEnd: newShelfEnd,
          isRight: oldSlot.isRight,
          boundingBox: newBox,
          radius: newRadius,
          angleRad: newAngle,
          localStaticCost: oldSlot.localStaticCost,
        );
      }
    }

    return result;
  }
}
