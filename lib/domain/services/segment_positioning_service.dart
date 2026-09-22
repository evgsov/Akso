import 'dart:math' as math;
import '../models/piping_network.dart';
import '../enums/valve_type.dart';
import 'spool_calculator.dart';

/// Модель с детальной информацией о взаимном расположении элемента (стыка или арматуры)
/// на участке трубы, высотных отметках и длинах смежных катушек.
class SegmentPositionInfo {
  final String segmentId;
  final double ratio;
  final double segmentLengthMm;
  final double startDeductionMm;
  final double endDeductionMm;
  final double elementLengthMm;

  /// Отметка оси Z центра элемента (в метрах)
  final double elevationM;

  /// Можно ли редактировать отметку Z (для вертикальных и наклонных труб)
  final bool isElevationEditable;

  /// Отметка Z в начале и конце трубы (в метрах)
  final double startElevationM;
  final double endElevationM;

  /// Предыдущая граница (мм от осевого узла startNode)
  final double prevBoundaryMm;

  /// Следующая граница (мм от осевого узла startNode)
  final double nextBoundaryMm;

  /// Длина катушки до предыдущей границы (L1 в мм)
  final double lengthToPrevMm;

  /// Длина катушки до следующей границы (L2 в мм)
  final double lengthToNextMm;

  /// Расстояние от физического начала трубы до центра элемента (мм)
  final double distanceFromStartMm;

  /// Расстояние от центра элемента до физического конца трубы (мм)
  final double distanceToEndMm;

  /// Наименование предыдущего объекта (напр. "Отвод 90°", "Стык №1", "Начало трубы")
  final String prevItemLabel;

  /// Наименование следующего объекта (напр. "Тройник", "Стык №2", "Конец трубы")
  final String nextItemLabel;

  const SegmentPositionInfo({
    required this.segmentId,
    required this.ratio,
    required this.segmentLengthMm,
    required this.startDeductionMm,
    required this.endDeductionMm,
    required this.elementLengthMm,
    required this.elevationM,
    required this.isElevationEditable,
    required this.startElevationM,
    required this.endElevationM,
    required this.prevBoundaryMm,
    required this.nextBoundaryMm,
    required this.lengthToPrevMm,
    required this.lengthToNextMm,
    required this.distanceFromStartMm,
    required this.distanceToEndMm,
    required this.prevItemLabel,
    required this.nextItemLabel,
  });

  /// Форматированная строка отметки Z (например, "+2.800 м")
  String get elevationString {
    final sign = elevationM >= 0 ? '+' : '-';
    return '$sign${elevationM.abs().toStringAsFixed(3)} м';
  }
}

/// Элемент предварительного просмотра катушки при разбивке стояка
class RiserSectionPreview {
  final int spoolNumber;
  final double cutLengthMm;
  final double startElevationM;
  final double endElevationM;
  final String startLabel;
  final String endLabel;

  const RiserSectionPreview({
    required this.spoolNumber,
    required this.cutLengthMm,
    required this.startElevationM,
    required this.endElevationM,
    required this.startLabel,
    required this.endLabel,
  });

  String get startElevationString {
    final sign = startElevationM >= 0 ? '+' : '-';
    return '$sign${startElevationM.abs().toStringAsFixed(3)} м';
  }

  String get endElevationString {
    final sign = endElevationM >= 0 ? '+' : '-';
    return '$sign${endElevationM.abs().toStringAsFixed(3)} м';
  }
}

/// Сервис точного позиционирования элементов и нарезки стояков на катушки
class SegmentPositioningService {
  /// Получить информацию о взаимном расположении и высотах элемента на сегменте
  static SegmentPositionInfo getPositionInfo(
    PipingNetwork network,
    String segmentId,
    double ratio, {
    double elementLengthMm = 0.0,
    String? currentElementId,
  }) {
    final seg = network.segments[segmentId];
    if (seg == null) {
      return _emptyInfo(segmentId, ratio);
    }
    final startNode = network.nodes[seg.startNodeId];
    final endNode = network.nodes[seg.endNodeId];
    if (startNode == null || endNode == null) {
      return _emptyInfo(segmentId, ratio);
    }

    final totalLen = startNode.distanceTo(endNode);
    if (totalLen < 1.0) {
      return _emptyInfo(segmentId, ratio);
    }

    final startDeduction = SpoolCalculator.getFittingDeduction(network, startNode.id, segmentId: segmentId);
    final endDeduction = SpoolCalculator.getFittingDeduction(network, endNode.id, segmentId: segmentId);

    // Границы сегмента
    String prevLabel = network.getFittingLabelForNode(startNode.id, segmentId);
    double prevBoundary = startDeduction;

    String nextLabel = network.getFittingLabelForNode(endNode.id, segmentId);
    double nextBoundary = math.max(prevBoundary, totalLen - endDeduction);

    final currentCenterMm = ratio * totalLen;

    // Проверяем другие сварные стыки на сегменте (исключая собственные швы текущей арматуры)
    for (final w in network.weldJoints.values) {
      if (w.segmentId != segmentId ||
          w.id == currentElementId ||
          (currentElementId != null && w.sourceElementId != null && w.sourceElementId!.startsWith(currentElementId))) {
        continue;
      }
      final wCenterMm = w.ratio * totalLen;
      if (w.ratio < ratio - 0.0001) {
        if (wCenterMm > prevBoundary) {
          prevBoundary = wCenterMm;
          prevLabel = 'Стык №${w.number > 0 ? w.number : 1}';
        }
      } else if (w.ratio > ratio + 0.0001) {
        if (wCenterMm < nextBoundary) {
          nextBoundary = wCenterMm;
          nextLabel = 'Стык №${w.number > 0 ? w.number : 1}';
        }
      }
    }

    // Проверяем другую арматуру на сегменте (исключая родительскую арматуру текущего шва)
    for (final v in network.valves.values) {
      if (v.segmentId != segmentId ||
          v.id == currentElementId ||
          (currentElementId != null && currentElementId.startsWith(v.id))) {
        continue;
      }
      final vCenterMm = v.ratio * totalLen;
      final vUpstream = vCenterMm - v.effectiveHalfLengthMm;
      final vDownstream = vCenterMm + v.effectiveHalfLengthMm;
      final vName = v.name.trim().isNotEmpty ? v.name : v.valveType.displayName;

      if (v.ratio < ratio - 0.0001) {
        if (vDownstream > prevBoundary) {
          prevBoundary = vDownstream;
          prevLabel = vName;
        }
      } else if (v.ratio > ratio + 0.0001) {
        if (vUpstream < nextBoundary) {
          nextBoundary = vUpstream;
          nextLabel = vName;
        }
      }
    }

    final halfElem = elementLengthMm / 2.0;
    final lPrev = math.max(0.0, (currentCenterMm - halfElem) - prevBoundary);
    final lNext = math.max(0.0, nextBoundary - (currentCenterMm + halfElem));

    final distFromStart = math.max(0.0, currentCenterMm - startDeduction);
    final distToEnd = math.max(0.0, (totalLen - endDeduction) - currentCenterMm);

    final currentZ = startNode.z + (endNode.z - startNode.z) * ratio;
    final isElevEditable = (startNode.z - endNode.z).abs() > 1.0;

    return SegmentPositionInfo(
      segmentId: segmentId,
      ratio: ratio,
      segmentLengthMm: totalLen,
      startDeductionMm: startDeduction,
      endDeductionMm: endDeduction,
      elementLengthMm: elementLengthMm,
      elevationM: currentZ / 1000.0,
      isElevationEditable: isElevEditable,
      startElevationM: startNode.z / 1000.0,
      endElevationM: endNode.z / 1000.0,
      prevBoundaryMm: prevBoundary,
      nextBoundaryMm: nextBoundary,
      lengthToPrevMm: lPrev,
      lengthToNextMm: lNext,
      distanceFromStartMm: distFromStart,
      distanceToEndMm: distToEnd,
      prevItemLabel: prevLabel,
      nextItemLabel: nextLabel,
    );
  }

  /// Вычисление безопасных границ отношения ratio для элемента с учетом смежных элементов
  static (double minRatio, double maxRatio) getSafeRatioBounds(
    PipingNetwork network,
    String segmentId, {
    double elementLengthMm = 0.0,
    String? currentElementId,
    double currentRatio = 0.5,
  }) {
    final info = getPositionInfo(
      network,
      segmentId,
      currentRatio,
      elementLengthMm: elementLengthMm,
      currentElementId: currentElementId,
    );

    if (info.segmentLengthMm < 1.0) return (0.01, 0.99);

    final halfElem = elementLengthMm / 2.0;
    // Для элементов с ненулевой строительной длиной (арматура) разрешаем монтаж встык (минимальный зазор 0).
    // Для сварных стыков (длина 0) оставляем минимальный зазор 1 мм, чтобы предотвратить наложение стыков друг на друга.
    final minClearance = elementLengthMm > 0.0 ? 0.0 : 1.0;
    double minR = (info.prevBoundaryMm + halfElem + minClearance) / info.segmentLengthMm;
    double maxR = (info.nextBoundaryMm - halfElem - minClearance) / info.segmentLengthMm;

    minR = minR.clamp(0.000, 1.000);
    maxR = maxR.clamp(0.000, 1.000);

    if (minR > maxR) {
      final mid = (info.prevBoundaryMm + info.nextBoundaryMm) / (2.0 * info.segmentLengthMm);
      return (mid.clamp(0.001, 0.999), mid.clamp(0.001, 0.999));
    }
    return (minR, maxR);
  }

  /// Пересчет ratio по заданной высотной отметке Z (в метрах)
  static double calculateRatioFromElevation(
    PipingNetwork network,
    String segmentId,
    double targetElevationM, {
    double elementLengthMm = 0.0,
    String? currentElementId,
    double currentRatio = 0.5,
  }) {
    final seg = network.segments[segmentId];
    if (seg == null) return currentRatio;
    final startNode = network.nodes[seg.startNodeId];
    final endNode = network.nodes[seg.endNodeId];
    if (startNode == null || endNode == null) return currentRatio;

    final dz = endNode.z - startNode.z;
    if (dz.abs() < 1.0) return currentRatio; // Горизонтальная труба, высота фиксирована

    final targetZMm = targetElevationM * 1000.0;
    final unconstrainedR = (targetZMm - startNode.z) / dz;

    final (minR, maxR) = getSafeRatioBounds(
      network,
      segmentId,
      elementLengthMm: elementLengthMm,
      currentElementId: currentElementId,
      currentRatio: currentRatio,
    );

    return unconstrainedR.clamp(minR, maxR);
  }

  /// Пересчет ratio по желаемой длине предыдущей катушки L1 (мм)
  static double calculateRatioFromLengthToPrev(
    PipingNetwork network,
    String segmentId,
    double targetL1Mm, {
    double elementLengthMm = 0.0,
    String? currentElementId,
    double currentRatio = 0.5,
  }) {
    final info = getPositionInfo(
      network,
      segmentId,
      currentRatio,
      elementLengthMm: elementLengthMm,
      currentElementId: currentElementId,
    );
    if (info.segmentLengthMm < 1.0) return currentRatio;

    final halfElem = elementLengthMm / 2.0;
    final targetCenterMm = info.prevBoundaryMm + targetL1Mm + halfElem;
    final unconstrainedR = targetCenterMm / info.segmentLengthMm;

    final (minR, maxR) = getSafeRatioBounds(
      network,
      segmentId,
      elementLengthMm: elementLengthMm,
      currentElementId: currentElementId,
      currentRatio: currentRatio,
    );

    return unconstrainedR.clamp(minR, maxR);
  }

  /// Пересчет ratio по желаемой длине следующей катушки L2 (мм)
  static double calculateRatioFromLengthToNext(
    PipingNetwork network,
    String segmentId,
    double targetL2Mm, {
    double elementLengthMm = 0.0,
    String? currentElementId,
    double currentRatio = 0.5,
  }) {
    final info = getPositionInfo(
      network,
      segmentId,
      currentRatio,
      elementLengthMm: elementLengthMm,
      currentElementId: currentElementId,
    );
    if (info.segmentLengthMm < 1.0) return currentRatio;

    final halfElem = elementLengthMm / 2.0;
    final targetCenterMm = info.nextBoundaryMm - targetL2Mm - halfElem;
    final unconstrainedR = targetCenterMm / info.segmentLengthMm;

    final (minR, maxR) = getSafeRatioBounds(
      network,
      segmentId,
      elementLengthMm: elementLengthMm,
      currentElementId: currentElementId,
      currentRatio: currentRatio,
    );

    return unconstrainedR.clamp(minR, maxR);
  }

  /// Пересчет ratio по расстоянию от физического начала трубы (мм)
  static double calculateRatioFromDistanceFromStart(
    PipingNetwork network,
    String segmentId,
    double targetDistMm, {
    double elementLengthMm = 0.0,
    String? currentElementId,
    double currentRatio = 0.5,
  }) {
    final info = getPositionInfo(
      network,
      segmentId,
      currentRatio,
      elementLengthMm: elementLengthMm,
      currentElementId: currentElementId,
    );
    if (info.segmentLengthMm < 1.0) return currentRatio;

    final halfElem = elementLengthMm / 2.0;
    final targetCenterMm = info.startDeductionMm + targetDistMm + halfElem;
    final unconstrainedR = targetCenterMm / info.segmentLengthMm;

    final (minR, maxR) = getSafeRatioBounds(
      network,
      segmentId,
      elementLengthMm: elementLengthMm,
      currentElementId: currentElementId,
      currentRatio: currentRatio,
    );

    return unconstrainedR.clamp(minR, maxR);
  }

  // =========================================================================
  // Пакетная нарезка стояка на катушки (Batch Riser Sectioning)
  // =========================================================================

  /// Расчет позиций сварных стыков по равному шагу (макс. длине катушки stepMm)
  static List<double> calculateRiserWeldRatiosByStep(
    PipingNetwork network,
    String segmentId,
    double stepMm, {
    bool fromBottom = true,
  }) {
    if (stepMm <= 10.0) return [];
    final seg = network.segments[segmentId];
    if (seg == null) return [];
    final sNode = network.nodes[seg.startNodeId];
    final eNode = network.nodes[seg.endNodeId];
    if (sNode == null || eNode == null) return [];

    final totalLen = sNode.distanceTo(eNode);
    final startDeduction = SpoolCalculator.getFittingDeduction(network, sNode.id, segmentId: segmentId);
    final endDeduction = SpoolCalculator.getFittingDeduction(network, eNode.id, segmentId: segmentId);
    final pipeLen = totalLen - startDeduction - endDeduction;

    if (pipeLen <= stepMm + 10.0) {
      return []; // Труба короче шага, нарезка не требуется
    }

    final ratios = <double>[];
    if (fromBottom) {
      double d = stepMm;
      while (d < pipeLen - 10.0) {
        final r = (startDeduction + d) / totalLen;
        ratios.add(r);
        d += stepMm;
      }
    } else {
      double dFromEnd = stepMm;
      final dists = <double>[];
      while (dFromEnd < pipeLen - 10.0) {
        dists.add(pipeLen - dFromEnd);
        dFromEnd += stepMm;
      }
      dists.sort();
      for (final d in dists) {
        ratios.add((startDeduction + d) / totalLen);
      }
    }

    return ratios;
  }

  /// Расчет позиций сварных стыков по цепочке длин катушек (lengthsMm)
  static List<double> calculateRiserWeldRatiosByLengths(
    PipingNetwork network,
    String segmentId,
    List<double> lengthsMm, {
    bool fromBottom = true,
  }) {
    final validLengths = lengthsMm.where((l) => l > 10.0).toList();
    if (validLengths.isEmpty) return [];

    final seg = network.segments[segmentId];
    if (seg == null) return [];
    final sNode = network.nodes[seg.startNodeId];
    final eNode = network.nodes[seg.endNodeId];
    if (sNode == null || eNode == null) return [];

    final totalLen = sNode.distanceTo(eNode);
    final startDeduction = SpoolCalculator.getFittingDeduction(network, sNode.id, segmentId: segmentId);
    final endDeduction = SpoolCalculator.getFittingDeduction(network, eNode.id, segmentId: segmentId);
    final pipeLen = totalLen - startDeduction - endDeduction;

    if (pipeLen <= 10.0) return [];

    final ratios = <double>[];
    if (fromBottom) {
      double acc = 0.0;
      for (final len in validLengths) {
        acc += len;
        if (acc < pipeLen - 10.0) {
          ratios.add((startDeduction + acc) / totalLen);
        } else {
          break;
        }
      }
    } else {
      double acc = 0.0;
      final dists = <double>[];
      for (final len in validLengths) {
        acc += len;
        if (acc < pipeLen - 10.0) {
          dists.add(pipeLen - acc);
        } else {
          break;
        }
      }
      dists.sort();
      for (final d in dists) {
        ratios.add((startDeduction + d) / totalLen);
      }
    }

    return ratios;
  }

  /// Расчет позиций сварных стыков по списку высотных отметок этажей/перекрытий (elevationsMeters)
  static List<double> calculateRiserWeldRatiosByElevations(
    PipingNetwork network,
    String segmentId,
    List<double> elevationsMeters,
  ) {
    final seg = network.segments[segmentId];
    if (seg == null) return [];
    final sNode = network.nodes[seg.startNodeId];
    final eNode = network.nodes[seg.endNodeId];
    if (sNode == null || eNode == null) return [];

    final dz = eNode.z - sNode.z;
    if (dz.abs() < 1.0) return []; // Труба не вертикальная

    final totalLen = sNode.distanceTo(eNode);
    final startDeduction = SpoolCalculator.getFittingDeduction(network, sNode.id, segmentId: segmentId);
    final endDeduction = SpoolCalculator.getFittingDeduction(network, eNode.id, segmentId: segmentId);

    final ratios = <double>[];
    for (final elevM in elevationsMeters) {
      final zMm = elevM * 1000.0;
      final r = (zMm - sNode.z) / dz;
      final centerMm = r * totalLen;

      // Стык должен лежать строго на теле трубы (не залезая на фитинги)
      if (centerMm > startDeduction + 10.0 && centerMm < totalLen - endDeduction - 10.0) {
        ratios.add(r);
      }
    }

    ratios.sort();
    // Удаляем дубликаты, расположенные ближе 10 мм
    final unique = <double>[];
    for (final r in ratios) {
      if (unique.isEmpty || (r * totalLen - unique.last * totalLen).abs() > 10.0) {
        unique.add(r);
      }
    }
    return unique;
  }

  /// Генерация предварительного просмотра катушек для диалога нарезки стояка
  static List<RiserSectionPreview> previewSections(
    PipingNetwork network,
    String segmentId,
    List<double> weldRatios,
  ) {
    final seg = network.segments[segmentId];
    if (seg == null) return [];
    final sNode = network.nodes[seg.startNodeId];
    final eNode = network.nodes[seg.endNodeId];
    if (sNode == null || eNode == null) return [];

    final totalLen = sNode.distanceTo(eNode);
    final startDeduction = SpoolCalculator.getFittingDeduction(network, sNode.id, segmentId: segmentId);
    final endDeduction = SpoolCalculator.getFittingDeduction(network, eNode.id, segmentId: segmentId);

    final sortedRatios = List<double>.from(weldRatios)..sort();

    final boundaries = <double>[startDeduction];
    for (final r in sortedRatios) {
      final pos = r * totalLen;
      if (pos > startDeduction && pos < totalLen - endDeduction) {
        boundaries.add(pos);
      }
    }
    boundaries.add(totalLen - endDeduction);

    final startLabel = network.getFittingLabelForNode(sNode.id, segmentId);
    final endLabel = network.getFittingLabelForNode(eNode.id, segmentId);

    final result = <RiserSectionPreview>[];
    for (int i = 0; i < boundaries.length - 1; i++) {
      final bStart = boundaries[i];
      final bEnd = boundaries[i + 1];
      final cutLen = math.max(0.0, bEnd - bStart);

      final rStart = bStart / totalLen;
      final rEnd = bEnd / totalLen;
      final zStartM = (sNode.z + (eNode.z - sNode.z) * rStart) / 1000.0;
      final zEndM = (sNode.z + (eNode.z - sNode.z) * rEnd) / 1000.0;

      final sText = i == 0 ? startLabel : 'Стык №$i';
      final eText = i == boundaries.length - 2 ? endLabel : 'Стык №${i + 1}';

      result.add(RiserSectionPreview(
        spoolNumber: i + 1,
        cutLengthMm: cutLen,
        startElevationM: zStartM,
        endElevationM: zEndM,
        startLabel: sText,
        endLabel: eText,
      ));
    }

    return result;
  }

  static SegmentPositionInfo _emptyInfo(String segmentId, double ratio) {
    return SegmentPositionInfo(
      segmentId: segmentId,
      ratio: ratio,
      segmentLengthMm: 0.0,
      startDeductionMm: 0.0,
      endDeductionMm: 0.0,
      elementLengthMm: 0.0,
      elevationM: 0.0,
      isElevationEditable: false,
      startElevationM: 0.0,
      endElevationM: 0.0,
      prevBoundaryMm: 0.0,
      nextBoundaryMm: 0.0,
      lengthToPrevMm: 0.0,
      lengthToNextMm: 0.0,
      distanceFromStartMm: 0.0,
      distanceToEndMm: 0.0,
      prevItemLabel: '—',
      nextItemLabel: '—',
    );
  }
}
