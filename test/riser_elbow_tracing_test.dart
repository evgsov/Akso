import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/models/acquired_tracking_point.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/services/fitting_detector.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Riser & Elbow Tracing Tests', () {
    test('1. Vertical transition with elbow creates clean welds and spools', () {
      final network = PipingNetwork();

      // n1: (0, 0, 2800) -> n2: (2000, 0, 2800) -> n3: (2000, 0, 600)
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 2800);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 2800);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 600);

      network.addSegment(const PipeSegment(id: 'seg_h', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50));
      network.addSegment(const PipeSegment(id: 'seg_v', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50));

      FittingDetector.autoDetectAllFittings(network);
      expect(network.fittings['n2']?.fittingType, equals(FittingType.elbow90));

      network.generateElementWeldJoints();
      network.recalculateSpools();

      // Должно быть ровно 2 шва отвода: на горизонтальной трубе и на стояке
      expect(network.weldJoints.length, equals(2));
      final hWeld = network.weldJoints.values.firstWhere((w) => w.segmentId == 'seg_h');
      final vWeld = network.weldJoints.values.firstWhere((w) => w.segmentId == 'seg_v');

      expect(hWeld.sourceElementId, equals('fit_n2_seg_h'));
      expect(vWeld.sourceElementId, equals('fit_n2_seg_v'));

      // Тангенс отвода Ду50 = 75 мм.
      // seg_h: длина 2000, шов на 1925 мм (r = 0.9625)
      expect((hWeld.ratio - 0.9625).abs(), lessThan(0.001));
      // seg_v: длина 2200, шов на 75 мм от начала (r = 75 / 2200 = 0.03409)
      expect((vWeld.ratio - (75.0 / 2200.0)).abs(), lessThan(0.001));

      // Катушки: на каждой трубе ровно по одной катушке, начинающейся/заканчивающейся строго у стыка отвода
      expect(network.spools.length, equals(2));
      final hSpool = network.spools.values.firstWhere((s) => s.segmentId == 'seg_h');
      final vSpool = network.spools.values.firstWhere((s) => s.segmentId == 'seg_v');

      expect(hSpool.cutLengthMm, equals(1925.0));
      expect(hSpool.endPoint?.x, equals(1925.0));

      expect(vSpool.cutLengthMm, equals(2125.0));
      expect(vSpool.startPoint?.z, equals(2725.0)); // 2800 - 75 = 2725
      expect(vSpool.endPoint?.z, equals(600.0));
    });

    test('2. Step 3 ignores non-collinear pipes and does not generate coaxial weld at 90 deg', () {
      final network = PipingNetwork();

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 2800);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 2800);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 600);

      // Добавляем сегменты напрямую без детектора фитингов
      network.segments['seg_h'] = const PipeSegment(id: 'seg_h', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50);
      network.segments['seg_v'] = const PipeSegment(id: 'seg_v', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50);

      // Даже если фитинг в n2 еще не создан, Step 3 не должен создавать соосный шов
      final added = network.generateElementWeldJoints();
      expect(added, equals(0));
      expect(network.weldJoints.isEmpty, isTrue);
    });

    test('3. Step 3 creates coaxial weld only for truly collinear straight pipes', () {
      final network = PipingNetwork();

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 2800);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 2800);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 4000, y: 0, z: 2800);

      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50);

      final added = network.generateElementWeldJoints();
      expect(added, equals(1));
      expect(network.weldJoints.length, equals(1));
      final weld = network.weldJoints.values.first;
      expect(weld.sourceElementId, equals('coaxial_n2'));
    });

    test('4. Obsolete coaxial weld is cleaned up when pipe turns', () {
      final network = PipingNetwork();

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 2800);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 2800);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 4000, y: 0, z: 2800);

      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50);

      network.generateElementWeldJoints();
      expect(network.weldJoints.length, equals(1));

      // Теперь поворачиваем n3 вниз, превращая трубу в стояк
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 600);

      // Вызываем очистку и генерацию
      network.generateElementWeldJoints();
      FittingDetector.autoDetectAllFittings(network);
      network.generateElementWeldJoints();

      // Старый coaxial_n2 должен быть удален, а вместо него созданы швы отвода
      expect(network.weldJoints.values.any((w) => w.sourceElementId == 'coaxial_n2'), isFalse);
    });

    test('5. SpoolCalculator prevents ghost pipe spool inside fitting deduction zone', () {
      final network = PipingNetwork();

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 2800);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 2800);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 600);

      network.addSegment(const PipeSegment(id: 'seg_h', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50));
      network.addSegment(const PipeSegment(id: 'seg_v', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50));

      FittingDetector.autoDetectAllFittings(network);
      network.generateElementWeldJoints();

      // Принудительно вставляем шов на отметке 20 мм (внутри 75-мм тангенса отвода)
      network.addWeldJoint(segmentId: 'seg_v', ratio: 20.0 / 2200.0, weldType: WeldType.c17, sourceElementId: 'test_inner');

      network.recalculateSpools();

      // Никакой катушки внутри зоны [0, 75] мм не должно быть создано!
      for (final sp in network.spools.values.where((s) => s.segmentId == 'seg_v')) {
        expect(sp.startPoint!.z, lessThanOrEqualTo(2725.01)); // Не выше стыка отвода (2725)
      }
    });

    test('6. Interactive tracing: commitTraceWithLength vertical riser', () {
      final network = PipingNetwork();
      final projector = const AxonometryProjector(projectionType: ProjectionType.iso30);
      final controller = PipingInputController(network: network, projector: projector);

      controller.currentTool = CanvasTool.trace;
      // Start at 0,0,0
      controller.handlePointerDown(projector.project(const Node3D(id: '', x: 0, y: 0, z: 0)));
      // Horizontal seg 1: length 1000 (+X)
      controller.commitTraceWithLength(1000.0, dirX: 1.0, dirY: 0.0, dirZ: 0.0);
      // Vertical riser: length 1000 (+Z)
      controller.commitTraceWithLength(1000.0, dirX: 0.0, dirY: 0.0, dirZ: 1.0);
      // Horizontal seg 2: length 1000 (+X)
      controller.commitTraceWithLength(1000.0, dirX: 1.0, dirY: 0.0, dirZ: 0.0);

      // Verify elbows, welds, and spools
      expect(network.fittings.values.where((f) => f.fittingType == FittingType.elbow90).length, equals(2));
      expect(network.weldJoints.length, equals(4));
      expect(network.spools.length, equals(3));
    });

    test('7. Interactive tracing: addVerticalRiser', () {
      final network = PipingNetwork();
      final projector = const AxonometryProjector(projectionType: ProjectionType.iso30);
      final controller = PipingInputController(network: network, projector: projector);

      controller.currentTool = CanvasTool.trace;
      controller.handlePointerDown(projector.project(const Node3D(id: '', x: 0, y: 0, z: 0)));
      controller.commitTraceWithLength(1000.0, dirX: 1.0, dirY: 0.0, dirZ: 0.0);
      // Vertical riser to Z=1000
      controller.addVerticalRiser(1000.0);
      // Next horizontal segment:
      controller.commitTraceWithLength(1000.0, dirX: 1.0, dirY: 0.0, dirZ: 0.0);

      expect(controller.currentElevationZ, equals(1000.0));
      expect(network.fittings.values.where((f) => f.fittingType == FittingType.elbow90).length, equals(2));
      expect(network.weldJoints.length, equals(4));
      expect(network.spools.length, equals(3));
    });

    test('8. Canvas click after commitTraceWithLength (+Z)', () {
      final network = PipingNetwork();
      final projector = const AxonometryProjector(projectionType: ProjectionType.iso30);
      final controller = PipingInputController(network: network, projector: projector);

      controller.currentTool = CanvasTool.trace;
      controller.handlePointerDown(projector.project(const Node3D(id: '', x: 0, y: 0, z: 0)));
      controller.commitTraceWithLength(1000.0, dirX: 1.0, dirY: 0.0, dirZ: 0.0);
      // Vertical riser to Z=1000 via length entry:
      controller.commitTraceWithLength(1000.0, dirX: 0.0, dirY: 0.0, dirZ: 1.0);

      // Now user clicks on canvas at projected position of (2000, 0, 1000)
      final clickPos = projector.project(const Node3D(id: '', x: 2000, y: 0, z: 1000));
      controller.handlePointerDown(clickPos);

      expect(controller.currentElevationZ, equals(1000.0));
      expect(network.fittings.values.where((f) => f.fittingType == FittingType.elbow90).length, equals(2));
      expect(network.weldJoints.length, equals(4));
      expect(network.spools.length, equals(3));
    });

    test('9. Tracing: click start -> click horiz -> addVerticalRiser -> click horiz on canvas', () {
      final network = PipingNetwork();
      final projector = const AxonometryProjector(projectionType: ProjectionType.iso30);
      final controller = PipingInputController(network: network, projector: projector);

      controller.currentTool = CanvasTool.trace;
      controller.handlePointerDown(projector.project(const Node3D(id: '', x: 0, y: 0, z: 0)));
      controller.handlePointerDown(projector.project(const Node3D(id: '', x: 1000, y: 0, z: 0)));
      controller.addVerticalRiser(1000.0);
      controller.handlePointerDown(projector.project(const Node3D(id: '', x: 2000, y: 0, z: 1000)));

      expect(controller.currentElevationZ, equals(1000.0));
      expect(network.fittings.values.where((f) => f.fittingType == FittingType.elbow90).length, equals(2));
      expect(network.weldJoints.length, equals(4));
      expect(network.spools.length, equals(3));
    });

    test('10. Tracing vertical riser via OTRACK extension ray', () {
      final network = PipingNetwork();
      final projector = const AxonometryProjector(projectionType: ProjectionType.iso30);
      final controller = PipingInputController(network: network, projector: projector);

      controller.currentTool = CanvasTool.trace;
      controller.handlePointerDown(projector.project(const Node3D(id: '', x: 0, y: 0, z: 0)));
      controller.handlePointerDown(projector.project(const Node3D(id: '', x: 1000, y: 0, z: 0)));

      final cornerNode = controller.traceStartNode!;
      // Simulate hover-acquire of cornerNode for OTRACK
      controller.tracingController.acquiredPoints.add(AcquiredTrackingPoint(
        worldPoint: cornerNode,
        screenPoint: projector.project(cornerNode),
        nodeId: cornerNode.id,
        acquiredAt: DateTime.now(),
      ));

      // Move mouse vertically up to Z=1000
      final screenUp = projector.project(Node3D(id: '', x: cornerNode.x, y: cornerNode.y, z: 1000.0));
      controller.handlePointerMove(screenUp);

      expect(controller.currentSnapResult?.isElevationTransition, isTrue);

      // Click to commit vertical riser
      controller.handlePointerDown(screenUp);

      expect(controller.currentElevationZ, equals(1000.0));
      expect(network.fittings.values.where((f) => f.fittingType == FittingType.elbow90).length, equals(1));
      expect(network.weldJoints.length, equals(2));

      // Now continue horizontally to (2000, 0, 1000)
      final nextHoriz = projector.project(const Node3D(id: '', x: 2000, y: 0, z: 1000));
      controller.handlePointerMove(nextHoriz);
      controller.handlePointerDown(nextHoriz);

      expect(network.fittings.values.where((f) => f.fittingType == FittingType.elbow90).length, equals(2));
      expect(network.weldJoints.length, equals(4));
      expect(network.spools.length, equals(3));
    });

    test('11. Changing node elevation converts straight pipe to elbow and replaces coaxial weld cleanly', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);

      network.addSegment(const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50));
      network.addSegment(const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50));

      // Изначально прямая труба со стыком посередине
      network.generateElementWeldJoints();
      expect(network.weldJoints.length, equals(1));
      expect(network.weldJoints.values.first.sourceElementId, equals('coaxial_n2'));

      // Меняем отметку n2 на Z = 1.0 м (1000 мм) -> образуется поворот под 90 градусов
      network.setNodeElevation('n2', 1.0);

      // Проверяем: отвод обнаружен, шов coaxial_n2 удален/мигрирован, созданы ровно 2 шва отвода
      expect(network.fittings['n2']?.fittingType, equals(FittingType.elbow90));
      expect(network.weldJoints.length, equals(2));
      expect(network.weldJoints.values.any((w) => w.sourceElementId == 'coaxial_n2'), isFalse);
      expect(network.weldJoints.values.any((w) => w.sourceElementId == 'fit_n2_s1'), isTrue);
      expect(network.weldJoints.values.any((w) => w.sourceElementId == 'fit_n2_s2'), isTrue);

      // Катушки: ровно по одной катушке на каждом сегменте, никаких паразитных катушек
      expect(network.spools.length, equals(2));
    });

    test('12. Short segment (ratio > 0.35) migrates legacy terminal weld without duplication', () {
      final network = PipingNetwork();
      // Сегмент длиной всего 180 мм при Ду50 (тангенс отвода 75 мм, ratio = 75 / 180 = 0.4167 > 0.35)
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 180, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 180, y: 0, z: 1000);

      network.addSegment(const PipeSegment(id: 's_short', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50));
      network.addSegment(const PipeSegment(id: 's_riser', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50));

      // Имитируем старый стык на самом краю короткого сегмента (r = 1.0)
      network.addWeldJoint(segmentId: 's_short', ratio: 1.0, weldType: WeldType.c17, sourceElementId: 'legacy_end');

      FittingDetector.autoDetectAllFittings(network);
      network.generateElementWeldJoints();

      // На s_short должен остаться ровно 1 шов отвода (старый мигрирован, дубликата нет)
      final shortWelds = network.weldJoints.values.where((w) => w.segmentId == 's_short').toList();
      expect(shortWelds.length, equals(1));
      expect(shortWelds.first.sourceElementId, equals('fit_n2_s_short'));
      expect((shortWelds.first.ratio - (1.0 - 75.0 / 180.0)).abs(), lessThan(0.001));
    });

    test('13. Redundant non-manual weld inside elbow deduction zone is purged and does not regenerate', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 1000, y: 0, z: 1000);

      network.addSegment(const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50));
      network.addSegment(const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50));

      FittingDetector.autoDetectAllFittings(network);
      network.generateElementWeldJoints();

      // Принудительно внедряем ложный стык прямо в углу (r = 0.01 на s2, внутри 75мм тангенса отвода)
      network.addWeldJoint(segmentId: 's2', ratio: 0.01, weldType: WeldType.c17, sourceElementId: 'ghost_weld');

      // Запуск валидации и генерации
      network.validateAndCleanWeldJoints();
      network.generateElementWeldJoints();

      // Ложный шов должен быть удален, остаются только 2 штатных шва отвода
      expect(network.weldJoints.length, equals(2));
      expect(network.weldJoints.values.any((w) => w.sourceElementId == 'ghost_weld'), isFalse);
    });

    test('14. Tracing: click near traceStartNode does not split connected segment into micro-pieces', () {
      final network = PipingNetwork();
      final projector = const AxonometryProjector(projectionType: ProjectionType.iso30);
      final controller = PipingInputController(network: network, projector: projector);

      controller.currentTool = CanvasTool.trace;
      controller.handlePointerDown(projector.project(const Node3D(id: '', x: 0, y: 0, z: 0)));
      // Горизонтальный отрезок до (1000, 0, 0)
      controller.handlePointerDown(projector.project(const Node3D(id: '', x: 1000, y: 0, z: 0)));

      expect(network.segments.length, equals(1));

      // Клик очень близко к traceStartNode (например, на расстоянии 5 пикселей от угла)
      final cornerScreen = projector.project(const Node3D(id: '', x: 1000, y: 0, z: 0));
      final nearClick = cornerScreen + const Offset(5.0, 5.0);

      controller.handlePointerDown(nearClick);

      // Исходный сегмент НЕ должен быть разрезан через splitSegmentAtRatio на два куска!
      expect(network.segments.keys.any((k) => k.endsWith('_a') || k.endsWith('_b')), isFalse);
    });
  });
}
