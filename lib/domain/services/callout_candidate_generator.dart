import 'dart:math' as math;
import 'dart:ui';
import '../../core/math/axonometry_projector.dart';
import '../models/callout.dart';
import '../models/callout_candidate_slot.dart';
import '../models/drawing_sheet.dart';
import '../models/piping_network.dart';
import 'callout_layout_engine.dart';
import 'viewport_transform_service.dart';

/// Генератор плотного пула слотов-кандидатов (с шагом 5°) для глобальной оптимизации выносок
class CalloutCandidateGenerator {
  /// Генерирует веер из 60 направлений (шаг 5° во всех 4 квадрантах, исключая чисто ортогональные)
  static List<double> generateCandidateAngles() {
    final angles = <double>[];
    const degToRad = math.pi / 180.0;

    // 1-й квадрант: 10°..80° (15 углов)
    for (int deg = 10; deg <= 80; deg += 5) {
      angles.add(deg * degToRad);
    }
    // 2-й квадрант: 100°..170° (15 углов)
    for (int deg = 100; deg <= 170; deg += 5) {
      angles.add(deg * degToRad);
    }
    // 3-й квадрант: 190°..260° (15 углов)
    for (int deg = 190; deg <= 260; deg += 5) {
      angles.add(deg * degToRad);
    }
    // 4-й квадрант: 280°..350° (15 углов)
    for (int deg = 280; deg <= 350; deg += 5) {
      angles.add(deg * degToRad);
    }

    return angles;
  }

  /// Стандартный набор радиальных колец волны (от 6 до 38 мм)
  static const List<double> defaultRadii = [
    6.0,
    7.5,
    9.5,
    12.0,
    15.0,
    19.0,
    24.0,
    30.0,
    38.0,
  ];

  /// Формирует пул лучших кандидатов для каждой видимой выноски листа
  static Map<String, List<CalloutCandidateSlot>> generateCandidatePools({
    required DrawingSheet sheet,
    required PipingNetwork network,
    required AxonometryProjector projector,
    required CalloutObstacleMap obstacleMap,
    Map<String, String>? calloutTemplates,
    int maxCandidatesPerCallout = 40,
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

      final candidates = <CalloutCandidateSlot>[];

      for (final radius in defaultRadii) {
        for (final angle in angles) {
          final dx = radius * math.cos(angle);
          final dy = radius * math.sin(angle);
          final isRight = math.cos(angle) >= 0;

          final entryShelf = Offset(anchorMm.dx + dx, anchorMm.dy + dy);
          final shelfEnd = Offset(
            isRight ? entryShelf.dx + textWidthMm : entryShelf.dx - textWidthMm,
            entryShelf.dy,
          );

          final rectLeft = isRight ? entryShelf.dx : entryShelf.dx - textWidthMm;
          final rectRight = isRight ? entryShelf.dx + textWidthMm : entryShelf.dx;
          final rectTop = entryShelf.dy - topH - 1.0;
          final rectBottom = entryShelf.dy + bottomH + 1.0;

          // Защитный прямоугольник (с зазором 0.8 мм)
          final boundingBox = Rect.fromLTRB(
            rectLeft - 0.8,
            rectTop - 0.8,
            rectRight + 0.8,
            rectBottom + 0.8,
          );

          // Жесткое отсечение (Hard Pruning):
          // 1. Выход за пределы листа
          if (boundingBox.left < frameLeft ||
              boundingBox.right > frameRight ||
              boundingBox.top < frameTop ||
              boundingBox.bottom > frameBottom) {
            continue;
          }

          // 2. Наложение на штамп или таблицы
          if (boundingBox.overlaps(stampRect)) continue;
          bool overlapsTable = false;
          for (final obs in obstacleMap.rects) {
            if (obs.id != null &&
                (obs.id == 'stamp' || obs.id!.startsWith('table_') || obs.id == 'tech_reqs')) {
              if (boundingBox.overlaps(obs.rect)) {
                overlapsTable = true;
                break;
              }
            }
          }
          if (overlapsTable) continue;

          // Статическая оценка стоимости (Local Static Cost):
          double cost = radius * 2.0;
          if (radius > 12.0) {
            final extra = radius - 12.0;
            cost += extra * extra * 15.0;
          }

          // Эстетический бонус за классические углы 45°, 30°, 60°
          final deg = (angle * 180.0 / math.pi) % 90.0;
          if ((deg - 45.0).abs() <= 3.0) {
            cost -= 12.0; // классический 45°
          } else if ((deg - 30.0).abs() <= 3.0 || (deg - 60.0).abs() <= 3.0) {
            cost -= 6.0; // классические 30° / 60°
          }

          // Оценка направления относительно оси трубы
          if (pipeDir2D != null) {
            final leaderDist = math.sqrt(dx * dx + dy * dy);
            if (leaderDist > 1e-4) {
              final leaderDir = Offset(dx / leaderDist, dy / leaderDist);
              final cosTheta = (leaderDir.dx * pipeDir2D.dx + leaderDir.dy * pipeDir2D.dy).abs();
              if (cosTheta > 0.45) {
                cost += (cosTheta - 0.45) * 100.0; // соосно с трубой — штраф
              } else if (cosTheta < 0.3) {
                cost -= 20.0; // перпендикулярно трубе — бонус
              }
            }
          }

          // Проверка наложения полки на трубы
          if (obstacleMap.testShelfPipeCollision(boundingBox, maxRadius: 1.0)) {
            cost += 60000.0;
          }

          // Проверка наложения полки на элементы сети (компактный бокс 2.5 мм)
          for (final obs in obstacleMap.rects) {
            if (obs.id != null && (obs.id == 'stamp' || obs.id!.startsWith('table_') || obs.id == 'tech_reqs' || obs.id!.startsWith('callout_'))) {
              continue;
            }
            if (obs.id != null && callout.targetId == obs.id) continue;
            final compactElem = Rect.fromCenter(center: obs.rect.center, width: 2.5, height: 2.5);
            if (boundingBox.overlaps(compactElem)) {
              cost += 30000.0;
            }
          }

          // Проверка пересечения ножки с чужими трубами
          for (final pipe in obstacleMap.pipes) {
            if (pipe.id != null && connectedSegIds.contains(pipe.id)) continue;
            if ((anchorMm - pipe.p1).distance < 0.8 || (anchorMm - pipe.p2).distance < 0.8) continue;
            if (CalloutObstacleMap.segmentsIntersect(anchorMm, entryShelf, pipe.p1, pipe.p2, tolerance: 0.05)) {
              cost += 50000.0;
            }
          }

          candidates.add(CalloutCandidateSlot(
            anchor: anchorMm,
            entryShelf: entryShelf,
            shelfEnd: shelfEnd,
            isRight: isRight,
            boundingBox: boundingBox,
            radius: radius,
            angleRad: angle,
            localStaticCost: cost,
          ));
        }
      }

      // Сортировка по возрастанию стоимости и отбор лучших
      candidates.sort((a, b) => a.localStaticCost.compareTo(b.localStaticCost));

      if (candidates.isEmpty) {
        // Гарантированный fallback (под 45° на радиусе 12 мм)
        const fbAngle = 45.0 * math.pi / 180.0;
        const fbRadius = 12.0;
        final entry = Offset(anchorMm.dx + fbRadius * 0.7071, anchorMm.dy - fbRadius * 0.7071);
        final end = Offset(entry.dx + textWidthMm, entry.dy);
        final box = Rect.fromLTWH(entry.dx - 0.8, entry.dy - topH - 1.8, textWidthMm + 1.6, topH + bottomH + 2.0);
        candidates.add(CalloutCandidateSlot(
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

      pools[callout.id] = candidates.take(maxCandidatesPerCallout).toList();
    }

    return pools;
  }
}
