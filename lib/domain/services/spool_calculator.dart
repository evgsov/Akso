import 'dart:math' as math;
import '../models/piping_network.dart';
import '../models/pipe_spool.dart';
import '../enums/fitting_type.dart';
import '../enums/valve_type.dart';

class SpoolCalculator {
  static void recalculateSpools(PipingNetwork network) {
    network.autoDetectAllFittings();
    network.spools.clear();
    int spoolCounter = 1;

    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final totalLen = start.distanceTo(end);

      // Сварные стыки на этом сегменте
      final segWelds = network.weldJoints.values
          .where((w) => w.segmentId == seg.id)
          .toList()
        ..sort((a, b) => a.ratio.compareTo(b.ratio));

      // Проходная арматура на этом сегменте
      final segValves = network.valves.values
          .where((v) => v.segmentId == seg.id && v.valveType.isInline)
          .toList()
        ..sort((a, b) => a.ratio.compareTo(b.ratio));

      // Вычеты фитингов на концах
      double startDeduction = 0.0;
      final startFit = network.fittings[seg.startNodeId];
      if (startFit != null) {
        if (startFit.fittingType == FittingType.directBranch) {
          // Для прямой врезки вычет из магистрали = 0!
          startDeduction = 0.0;
        } else if (startFit.buildingLengthMm != null && startFit.buildingLengthMm! > 0) {
          startDeduction = startFit.buildingLengthMm! / 2.0;
        } else {
          startDeduction = startFit.effectiveRadiusMm;
        }
      }

      double endDeduction = 0.0;
      final endFit = network.fittings[seg.endNodeId];
      if (endFit != null) {
        if (endFit.fittingType == FittingType.directBranch) {
          endDeduction = 0.0;
        } else if (endFit.buildingLengthMm != null && endFit.buildingLengthMm! > 0) {
          endDeduction = endFit.buildingLengthMm! / 2.0;
        } else {
          endDeduction = endFit.effectiveRadiusMm;
        }
      }

      if (segWelds.isEmpty && segValves.isEmpty) {
        // Одиночная катушка на весь участок
        final cutLen = math.max(0.0, totalLen - startDeduction - endDeduction);
        final spoolId = 'spool_${seg.id}_1';
        network.spools[spoolId] = PipeSpool(
          id: spoolId,
          segmentId: seg.id,
          number: 'К-$spoolCounter',
          cutLengthMm: cutLen,
          dn: seg.dn,
          wallThickness: seg.wallThicknessMm,
          material: seg.material,
        );
        spoolCounter++;
      } else {
        // Разбиение на подкатушки между швами и арматурой
        final points = <double>[0.0];
        for (final w in segWelds) {
          points.add(w.ratio);
        }
        for (final v in segValves) {
          final halfRatio = (v.lengthMm / 2.0) / math.max(totalLen, 1.0);
          points.add((v.ratio - halfRatio).clamp(0.0, 1.0));
          points.add((v.ratio + halfRatio).clamp(0.0, 1.0));
        }
        points.add(1.0);
        points.sort();

        // Удаляем дубликаты
        final uniquePoints = <double>[];
        for (final p in points) {
          if (uniquePoints.isEmpty || (p - uniquePoints.last).abs() > 0.001) {
            uniquePoints.add(p);
          }
        }

        for (int i = 0; i < uniquePoints.length - 1; i++) {
          final p1 = uniquePoints[i];
          final p2 = uniquePoints[i + 1];
          final rawSegmentLen = (p2 - p1) * totalLen;

          // Проверяем, не попадает ли интервал внутрь корпуса арматуры
          bool insideValve = false;
          for (final v in segValves) {
            final halfRatio = (v.lengthMm / 2.0) / math.max(totalLen, 1.0);
            if (p1 >= v.ratio - halfRatio - 0.001 && p2 <= v.ratio + halfRatio + 0.001) {
              insideValve = true;
              break;
            }
          }
          if (insideValve) continue;

          double deduction = 0.0;
          if (i == 0) deduction += startDeduction;
          if (i == uniquePoints.length - 2) deduction += endDeduction;

          final cutLen = math.max(0.0, rawSegmentLen - deduction);
          if (cutLen > 1.0) {
            final spoolId = 'spool_${seg.id}_${i + 1}';
            network.spools[spoolId] = PipeSpool(
              id: spoolId,
              segmentId: seg.id,
              number: 'К-$spoolCounter',
              cutLengthMm: cutLen,
              dn: seg.dn,
              wallThickness: seg.wallThicknessMm,
              material: seg.material,
            );
            spoolCounter++;
          }
        }
      }
    }
  }
}
