import 'dart:math' as math;
import 'dart:ui';
import '../../core/math/axonometry_projector.dart';
import '../models/callout.dart';
import '../models/callout_candidate_slot.dart';
import '../models/drawing_sheet.dart';
import '../models/piping_network.dart';
import 'callout_layout_engine.dart';
import 'viewport_transform_service.dart';

/// Генератор богатого пула слотов-кандидатов (колонки и веерные углы) для глобальной оптимизации выносок
class CalloutCandidateGenerator {
  /// Генерирует веер направлений (вправо и влево под чертежными углами)
  static List<double> generateCandidateAngles() {
    final angles = <double>[];
    const degToRad = math.pi / 180.0;

    // Вправо (от -60° до +60°)
    for (int deg = -60; deg <= 60; deg += 10) {
      angles.add(deg * degToRad);
    }
    angles.add(-45.0 * degToRad);
    angles.add(45.0 * degToRad);

    // Влево (от 120° до 240°)
    for (int deg = 120; deg <= 240; deg += 10) {
      angles.add(deg * degToRad);
    }
    angles.add(135.0 * degToRad);
    angles.add(225.0 * degToRad);

    // Крутые направления для обхода препятствий (но без чисто вертикальных 90° и 270°)
    angles.add(75.0 * degToRad);
    angles.add(105.0 * degToRad);
    angles.add(255.0 * degToRad);
    angles.add(285.0 * degToRad);

    return angles.toSet().toList()..sort();
  }

  /// Набор радиальных расстояний для выносок (от компактных 10 мм до глубоких 68 мм)
  static const List<double> defaultRadii = [
    10.0,
    14.0,
    18.0,
    24.0,
    32.0,
    42.0,
    54.0,
    68.0,
  ];

  /// Дистанции отступа для колоночных (карманных) кандидатов
  static const List<double> columnClearances = [
    16.0,
    24.0,
    34.0,
    48.0,
    64.0,
  ];

  /// Вертикальные смещения полочек в колонке
  static const List<double> columnVerticalShifts = [
    -50.0,
    -42.0,
    -34.0,
    -26.0,
    -18.0,
    -12.0,
    -6.0,
    0.0,
    6.0,
    12.0,
    18.0,
    26.0,
    34.0,
    42.0,
    50.0,
  ];

  /// Формирует пул разносторонних кандидатов для каждой видимой выноски листа
  static Map<String, List<CalloutCandidateSlot>> generateCandidatePools({
    required DrawingSheet sheet,
    required PipingNetwork network,
    required AxonometryProjector projector,
    required CalloutObstacleMap obstacleMap,
    Map<String, String>? calloutTemplates,
    int maxCandidatesPerCallout = 44,
  }) {
    final pools = <String, List<CalloutCandidateSlot>>{};
    final vp = sheet.viewport;
    final fmt = sheet.format;

    // Границы рабочей зоны листа (с 2 мм отступом безопасности)
    final frameLeft = fmt.frameLeftMm + 2.0;
    final frameTop = fmt.frameTopMm + 2.0;
    final frameRight = fmt.widthMm - fmt.frameRightMm - 2.0;
    final frameBottom = fmt.heightMm - fmt.frameBottomMm - 2.0;

    // Штамп
    final stampRect = Rect.fromLTWH(
      fmt.widthMm - fmt.frameRightMm - 185.0 - 2.0,
      fmt.heightMm - fmt.frameBottomMm - 55.0 - 2.0,
      185.0 + 4.0,
      55.0 + 4.0,
    );

    final angles = generateCandidateAngles();

    // Вычисляем охватывающие координаты анкеров для формирования общих внешних направляющих колонок
    double minAnchorX = double.infinity;
    double maxAnchorX = -double.infinity;
    for (final callout in network.callouts.values) {
      if (!sheet.isCalloutVisible(callout, network)) continue;
      final anchor3D = CalloutLayoutEngine.computeAnchorNode(callout, network);
      if (anchor3D == null) continue;
      final raw2D = projector.projectRaw(anchor3D.x, anchor3D.y, anchor3D.z);
      final pt = ViewportTransformService.model2dToSheetMm(raw2D, vp);
      if (pt.dx < minAnchorX) minAnchorX = pt.dx;
      if (pt.dx > maxAnchorX) maxAnchorX = pt.dx;
    }
    final hasGlobalColumns = minAnchorX <= maxAnchorX;
    final globalLeftColumns = hasGlobalColumns
        ? [minAnchorX - 18.0, minAnchorX - 32.0, minAnchorX - 48.0]
        : <double>[];
    final globalRightColumns = hasGlobalColumns
        ? [maxAnchorX + 18.0, maxAnchorX + 32.0, maxAnchorX + 48.0]
        : <double>[];

    for (final callout in network.callouts.values) {
      if (!sheet.isCalloutVisible(callout, network)) continue;

      final anchor3D = CalloutLayoutEngine.computeAnchorNode(callout, network);
      if (anchor3D == null) continue;

      final raw2D = projector.projectRaw(anchor3D.x, anchor3D.y, anchor3D.z);
      final anchorMm = ViewportTransformService.model2dToSheetMm(raw2D, vp);

      // Расчет габаритов текста выноски
      final charWidthMm = callout.textHeight * 0.65;
      final topText = network.generateCalloutText(callout, calloutTemplates ?? defaultCalloutTemplates);
      final bottomText = network.generateCalloutBottomText(callout, calloutTemplates ?? defaultCalloutTemplates);
      final maxLen = math.max(
        topText.length,
        (bottomText != null && bottomText.trim().isNotEmpty) ? bottomText.length : 0,
      );
      final textWidthMm = math.max(12.0, maxLen * charWidthMm + 3.0);
      final hasBottom = bottomText != null && bottomText.trim().isNotEmpty;
      final topH = callout.textHeight;
      final bottomH = hasBottom ? (callout.textHeight * 0.85 + 1.5) : 0.0;

      // Определение направления трубы для штрафа/бонуса за угол
      Offset? pipeDir2D;
      final targetSegId = network.getTargetSegmentId(callout.targetType, callout.targetId);
      if (targetSegId != null) {
        final seg = network.segments[targetSegId];
        if (seg != null) {
          final sNode = network.nodes[seg.startNodeId];
          final eNode = network.nodes[seg.endNodeId];
          if (sNode != null && eNode != null) {
            final p1 = ViewportTransformService.model2dToSheetMm(
              projector.projectRaw(sNode.x, sNode.y, sNode.z),
              vp,
            );
            final p2 = ViewportTransformService.model2dToSheetMm(
              projector.projectRaw(eNode.x, eNode.y, eNode.z),
              vp,
            );
            final v = p2 - p1;
            if (v.distance > 1e-4) {
              pipeDir2D = Offset(v.dx / v.distance, v.dy / v.distance);
            }
          }
        }
      }

      // Список связанных сегментов трубы для исключения самопересечений у анкера
      final connectedSegIds = <String>{};
      if (callout.targetType == CalloutTargetType.segment) {
        connectedSegIds.add(callout.targetId);
      } else if (callout.targetType == CalloutTargetType.valve) {
        final v = network.valves[callout.targetId];
        if (v != null) connectedSegIds.add(v.segmentId);
      } else if (callout.targetType == CalloutTargetType.fitting) {
        final fit = network.fittings[callout.targetId];
        final nId = fit?.nodeId ?? callout.targetId;
        for (final s in network.getConnectedSegments(nId)) {
          connectedSegIds.add(s.id);
        }
      } else if (callout.targetType == CalloutTargetType.node) {
        for (final s in network.getConnectedSegments(callout.targetId)) {
          connectedSegIds.add(s.id);
        }
      }

      final allRawCandidates = <CalloutCandidateSlot>[];

      // Вспомогательная функция валидации и оценки стоимости кандидата
      void tryAddCandidate({
        required Offset entryShelf,
        required bool isRight,
        required double radius,
        required double angleRad,
        bool isColumnSlot = false,
      }) {
        final shelfEnd = Offset(
          isRight ? entryShelf.dx + textWidthMm : entryShelf.dx - textWidthMm,
          entryShelf.dy,
        );

        final rectLeft = isRight ? entryShelf.dx : entryShelf.dx - textWidthMm;
        final rectRight = isRight ? entryShelf.dx + textWidthMm : entryShelf.dx;
        final rectTop = entryShelf.dy - topH - 1.0;
        final rectBottom = entryShelf.dy + bottomH + 1.0;

        final boundingBox = Rect.fromLTRB(
          rectLeft - 0.8,
          rectTop - 0.8,
          rectRight + 0.8,
          rectBottom + 0.8,
        );

        // 1. Выход за пределы листа — строгий отсев
        if (boundingBox.left < frameLeft ||
            boundingBox.right > frameRight ||
            boundingBox.top < frameTop ||
            boundingBox.bottom > frameBottom) {
          return;
        }

        // 2. Наложение на штамп или таблицы — строгий отсев
        if (boundingBox.overlaps(stampRect)) return;
        if (CalloutObstacleMap.rectCollidesWithSegment(stampRect, anchorMm, entryShelf, 0.5)) return;

        for (final obs in obstacleMap.rects) {
          if (obs.id != null && (obs.id == 'stamp' || obs.id!.startsWith('table_') || obs.id == 'tech_reqs')) {
            if (boundingBox.overlaps(obs.rect)) return;
            if (CalloutObstacleMap.rectCollidesWithSegment(obs.rect, anchorMm, entryShelf, 0.5)) return;
          }
        }

        // 3. Расчет статической стоимости
        double cost = radius * 1.5;

        // Поощрение чистых колоночных позиций
        if (isColumnSlot) {
          cost -= 25.0;
        }

        // Эстетический бонус за классические углы 45°, 30°, 60°
        final deg = ((angleRad * 180.0 / math.pi) % 90.0).abs();
        if ((deg - 45.0).abs() <= 3.0) {
          cost -= 15.0;
        } else if ((deg - 30.0).abs() <= 3.0 || (deg - 60.0).abs() <= 3.0) {
          cost -= 8.0;
        }

        // Оценка направления относительно оси трубы
        if (pipeDir2D != null) {
          final dx = entryShelf.dx - anchorMm.dx;
          final dy = entryShelf.dy - anchorMm.dy;
          final leaderDist = math.sqrt(dx * dx + dy * dy);
          if (leaderDist > 1e-4) {
            final leaderDir = Offset(dx / leaderDist, dy / leaderDist);
            final cosTheta = (leaderDir.dx * pipeDir2D.dx + leaderDir.dy * pipeDir2D.dy).abs();
            if (cosTheta > 0.6) {
              cost += 80.0; // соосно с трубой
            } else if (cosTheta < 0.3) {
              cost -= 20.0; // перпендикулярно трубе
            }
          }
        }

        // Строжайший штраф за наложение полки на трубы (+50 000 000)
        if (obstacleMap.testShelfPipeCollision(boundingBox, maxRadius: 1.0)) {
          cost += 50000000.0;
        }

        // Штраф за наложение полки на компактные элементы сети (+30 000 000)
        for (final obs in obstacleMap.rects) {
          if (obs.id != null && (obs.id == 'stamp' || obs.id!.startsWith('table_') || obs.id == 'tech_reqs' || obs.id!.startsWith('callout_'))) {
            continue;
          }
          if (obs.id != null && callout.targetId == obs.id) continue;
          final compactElem = Rect.fromCenter(center: obs.rect.center, width: 2.5, height: 2.5);
          if (boundingBox.overlaps(compactElem)) {
            cost += 30000000.0;
          }
        }

        // Строжайший штраф за пересечение стрелки с чужими трубами (+30 000 000)
        for (final pipe in obstacleMap.pipes) {
          if (pipe.id != null && connectedSegIds.contains(pipe.id)) continue;
          if ((anchorMm - pipe.p1).distance < 0.8 || (anchorMm - pipe.p2).distance < 0.8) continue;
          if (CalloutObstacleMap.segmentsIntersect(anchorMm, entryShelf, pipe.p1, pipe.p2, tolerance: 0.05)) {
            cost += 30000000.0;
          }
        }

        allRawCandidates.add(CalloutCandidateSlot(
          anchor: anchorMm,
          entryShelf: entryShelf,
          shelfEnd: shelfEnd,
          isRight: isRight,
          boundingBox: boundingBox,
          radius: radius,
          angleRad: angleRad,
          localStaticCost: cost,
        ));
      }

      // А. Генерация колоночных (карманных) кандидатов
      // 1. Общие направляющие колонки листа (строго вертикальные каскады с единым X)
      if (hasGlobalColumns) {
        for (final colX in globalLeftColumns) {
          for (final shiftY in columnVerticalShifts) {
            final leftEntry = Offset(colX, anchorMm.dy + shiftY);
            final dx = leftEntry.dx - anchorMm.dx;
            final dy = shiftY;
            final dist = math.sqrt(dx * dx + dy * dy);
            if (dist < 8.0 || dist > 120.0) continue;
            tryAddCandidate(
              entryShelf: leftEntry,
              isRight: false,
              radius: dist,
              angleRad: math.atan2(dy, dx),
              isColumnSlot: true,
            );
          }
        }
        for (final colX in globalRightColumns) {
          for (final shiftY in columnVerticalShifts) {
            final rightEntry = Offset(colX, anchorMm.dy + shiftY);
            final dx = rightEntry.dx - anchorMm.dx;
            final dy = shiftY;
            final dist = math.sqrt(dx * dx + dy * dy);
            if (dist < 8.0 || dist > 120.0) continue;
            tryAddCandidate(
              entryShelf: rightEntry,
              isRight: true,
              radius: dist,
              angleRad: math.atan2(dy, dx),
              isColumnSlot: true,
            );
          }
        }
      }

      // 2. Локальные относительные колонки выноски
      for (final clearance in columnClearances) {
        for (final shiftY in columnVerticalShifts) {
          // Влево
          final leftEntry = Offset(anchorMm.dx - clearance, anchorMm.dy + shiftY);
          final leftAngle = math.atan2(shiftY, -clearance);
          final leftRadius = math.sqrt(clearance * clearance + shiftY * shiftY);
          tryAddCandidate(
            entryShelf: leftEntry,
            isRight: false,
            radius: leftRadius,
            angleRad: leftAngle,
            isColumnSlot: true,
          );

          // Вправо
          final rightEntry = Offset(anchorMm.dx + clearance, anchorMm.dy + shiftY);
          final rightAngle = math.atan2(shiftY, clearance);
          final rightRadius = math.sqrt(clearance * clearance + shiftY * shiftY);
          tryAddCandidate(
            entryShelf: rightEntry,
            isRight: true,
            radius: rightRadius,
            angleRad: rightAngle,
            isColumnSlot: true,
          );
        }
      }

      // Б. Генерация веерных (радиальных) кандидатов
      for (final radius in defaultRadii) {
        for (final angle in angles) {
          final dx = radius * math.cos(angle);
          final dy = radius * math.sin(angle);
          final isRight = math.cos(angle) >= 0;
          final entryShelf = Offset(anchorMm.dx + dx, anchorMm.dy + dy);

          tryAddCandidate(
            entryShelf: entryShelf,
            isRight: isRight,
            radius: radius,
            angleRad: angle,
            isColumnSlot: false,
          );
        }
      }

      // В. Формирование сбалансированного пула кандидатов по дистанционным корзинам
      // (гарантирует наличие как близких, так и глубоких выносок вправо и влево!)
      final pool = <CalloutCandidateSlot>[];
      final buckets = <List<CalloutCandidateSlot>>[
        [], // [0..18 мм]
        [], // [18..28 мм]
        [], // [28..40 мм]
        [], // [40..54 мм]
        [], // [>54 мм]
      ];

      for (final cand in allRawCandidates) {
        final d = cand.radius;
        if (d <= 18.0) {
          buckets[0].add(cand);
        } else if (d <= 28.0) {
          buckets[1].add(cand);
        } else if (d <= 40.0) {
          buckets[2].add(cand);
        } else if (d <= 54.0) {
          buckets[3].add(cand);
        } else {
          buckets[4].add(cand);
        }
      }

      for (final bucket in buckets) {
        if (bucket.isEmpty) continue;
        bucket.sort((a, b) => a.localStaticCost.compareTo(b.localStaticCost));

        // Берем до 4 лучших правых и до 4 лучших левых слотов из каждой дистанционной корзины
        final rightSlots = bucket.where((c) => c.isRight).take(4);
        final leftSlots = bucket.where((c) => !c.isRight).take(4);

        pool.addAll(rightSlots);
        pool.addAll(leftSlots);
      }

      // Fallback при пустом пуле
      if (pool.isEmpty) {
        const fbAngle = 45.0 * math.pi / 180.0;
        const fbRadius = 18.0;
        final entry = Offset(anchorMm.dx + fbRadius * 0.7071, anchorMm.dy - fbRadius * 0.7071);
        final end = Offset(entry.dx + textWidthMm, entry.dy);
        final box = Rect.fromLTWH(entry.dx - 0.8, entry.dy - topH - 1.8, textWidthMm + 1.6, topH + bottomH + 2.0);
        pool.add(CalloutCandidateSlot(
          anchor: anchorMm,
          entryShelf: entry,
          shelfEnd: end,
          isRight: true,
          boundingBox: box,
          radius: fbRadius,
          angleRad: fbAngle,
          localStaticCost: 500.0,
        ));
      }

      // Сортировка пула и ограничение по размеру
      pool.sort((a, b) => a.localStaticCost.compareTo(b.localStaticCost));
      pools[callout.id] = pool.take(maxCandidatesPerCallout).toList();
    }

    return pools;
  }
}
