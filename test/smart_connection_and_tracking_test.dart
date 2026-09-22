import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/core/math/snap_engine.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/models/acquired_tracking_point.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('SnapEngine - Smart 90° Multi-Elevation & Object Tracking', () {
    late PipingNetwork network;
    late AxonometryProjector projector;
    late SnapEngine snapEngine;

    setUp(() {
      network = PipingNetwork();
      projector = AxonometryProjector();
      snapEngine = const SnapEngine();
    });

    test('Identifies multi-elevation pipe and returns smartElevationBranch snap', () {
      // Существующая магистральная труба на отметке Z = 1500 мм: от (0, 1000, 1500) до (2000, 1000, 1500)
      final n1 = Node3D(id: 'n1', x: 0, y: 1000, z: 1500);
      final n2 = Node3D(id: 'n2', x: 2000, y: 1000, z: 1500);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      final seg = PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'T1',
        dn: 100,
      );
      network.addSegment(seg);

      // Начало новой трассы на отметке Z = 0 мм: в точке (1000, 0, 0)
      final startNode = Node3D(id: 'start', x: 1000, y: 0, z: 0);
      network.nodes['start'] = startNode;

      // Курсор проецируется на экран в районе перпендикулярного опуска в (1000, 1000)
      // На текущей высоте Z = 0 точка поворота (1000, 1000, 0), точка врезки (1000, 1000, 1500)
      final targetWorld = Node3D(id: '', x: 1000, y: 1000, z: 1500);
      final screenTarget = projector.project(targetWorld);

      final snap = snapEngine.findSnap(
        screenPos: screenTarget,
        network: network,
        projector: projector,
        currentElevationZ: 0.0,
        traceStartNode: startNode,
        angleMode: AngleSnapMode.ortho90,
      );

      expect(snap.type, SnapType.smartElevationBranch);
      expect(snap.isElevationTransition, isTrue);
      expect(snap.elevationDeltaMm, 1500.0);
      expect(snap.intermediateTurnPoint, isNotNull);
      expect(snap.intermediateTurnPoint!.x, closeTo(1000, 1));
      expect(snap.intermediateTurnPoint!.y, closeTo(1000, 1));
      expect(snap.intermediateTurnPoint!.z, 0.0);
      expect(snap.worldPoint.z, 1500.0);
    });

    test('Returns regular perpendicular snap when pipes are on the same elevation', () {
      // Труба на Z = 0
      final n1 = Node3D(id: 'n1', x: 0, y: 1000, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 1000, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      final seg = PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'T1', dn: 100);
      network.addSegment(seg);

      final startNode = Node3D(id: 'start', x: 1000, y: 0, z: 0);
      network.nodes['start'] = startNode;

      final targetWorld = Node3D(id: '', x: 1000, y: 1000, z: 0);
      final screenTarget = projector.project(targetWorld);

      final snap = snapEngine.findSnap(
        screenPos: screenTarget,
        network: network,
        projector: projector,
        currentElevationZ: 0.0,
        traceStartNode: startNode,
      );

      expect(snap.type, SnapType.perpendicular);
      expect(snap.isElevationTransition, isFalse);
    });

    test('Detects pipe extension ray (OTRACK Ray Extension)', () {
      // Труба от (0, 500, 0) до (1000, 500, 0)
      final n1 = Node3D(id: 'n1', x: 0, y: 500, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 500, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      final seg = PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'T1', dn: 80);
      network.addSegment(seg);

      // Курсор находится в створе оси трубы дальше конца трубы: (1400, 500, 0)
      final rayWorld = Node3D(id: '', x: 1400, y: 500, z: 0);
      final screenPos = projector.project(rayWorld);

      final snap = snapEngine.findSnap(
        screenPos: screenPos,
        network: network,
        projector: projector,
        currentElevationZ: 0.0,
        enableObjectTracking: true,
        acquiredPoints: [
          AcquiredTrackingPoint(
            worldPoint: n2,
            screenPoint: projector.project(n2),
            nodeId: 'n2',
            acquiredAt: DateTime.now(),
          ),
        ],
      );

      expect(snap.type, SnapType.extensionRay);
      expect(snap.trackingSourcePoint?.id, 'n2');
      expect(snap.worldPoint.y, closeTo(500, 1));
      expect(snap.worldPoint.x, closeTo(1400, 1));
      expect(snap.label, contains('Створ'));
    });

    test('Detects orthogonal alignment guide (OTRACK Alignment Guide)', () {
      // Опорный узел сети в (800, 600, 0)
      final refNode = Node3D(id: 'ref', x: 800, y: 600, z: 0);
      network.nodes['ref'] = refNode;

      // Трассируем от (200, 200, 0)
      final startNode = Node3D(id: 'start', x: 200, y: 200, z: 0);
      network.nodes['start'] = startNode;

      // Курсор выравнивается по оси X = 800 (текущая точка 800, 300, 0)
      final alignWorld = Node3D(id: '', x: 800, y: 300, z: 0);
      final screenPos = projector.project(alignWorld);

      final snap = snapEngine.findSnap(
        screenPos: screenPos,
        network: network,
        projector: projector,
        currentElevationZ: 0.0,
        traceStartNode: startNode,
        enableObjectTracking: true,
        acquiredPoints: [
          AcquiredTrackingPoint(
            worldPoint: refNode,
            screenPoint: projector.project(refNode),
            nodeId: 'ref',
            acquiredAt: DateTime.now(),
          ),
        ],
      );

      expect(snap.type, SnapType.extensionRay);
      expect(snap.trackingSourcePoint?.id, 'ref');
      expect(snap.worldPoint.x, closeTo(800, 1));
      expect(snap.label, contains('Створ'));
    });

    test('Disabling OTRACK ignores extension rays and alignment guides', () {
      final n1 = Node3D(id: 'n1', x: 0, y: 500, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 500, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      final seg = PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'T1', dn: 80);
      network.addSegment(seg);

      final rayWorld = Node3D(id: '', x: 1400, y: 500, z: 0);
      final screenPos = projector.project(rayWorld);

      final snap = snapEngine.findSnap(
        screenPos: screenPos,
        network: network,
        projector: projector,
        currentElevationZ: 0.0,
        enableObjectTracking: false,
        acquiredPoints: [
          AcquiredTrackingPoint(
            worldPoint: n2,
            screenPoint: projector.project(n2),
            nodeId: 'n2',
            acquiredAt: DateTime.now(),
          ),
        ],
      );

      expect(snap.type, isNot(SnapType.extensionRay));
      expect(snap.type, isNot(SnapType.alignmentGuide));
    });
  });

  group('PipingInputController - Smart Elevation 90° Routing & F11 Toggle', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      controller = PipingInputController(network: network);
    });

    test('Toggles OTRACK via toggleObjectTracking and responds to F11 state', () {
      expect(controller.isObjectTrackingEnabled, isTrue);
      controller.toggleObjectTracking();
      expect(controller.isObjectTrackingEnabled, isFalse);
      controller.toggleObjectTracking();
      expect(controller.isObjectTrackingEnabled, isTrue);
    });

    test('Executes smart 90° connection: builds horizontal + vertical riser with elbow and tee', () {
      // Магистральная труба на отметке Z = 1200 мм: вдоль оси X от (0, 1000, 1200) до (2000, 1000, 1200)
      final n1 = Node3D(id: 'm1', x: 0, y: 1000, z: 1200);
      final n2 = Node3D(id: 'm2', x: 2000, y: 1000, z: 1200);
      network.nodes['m1'] = n1;
      network.nodes['m2'] = n2;
      final mainSeg = PipeSegment(
        id: 'main_seg',
        startNodeId: 'm1',
        endNodeId: 'm2',
        systemId: 'T1',
        dn: 100,
      );
      network.addSegment(mainSeg);

      // Начальный узел ответвления на отметке Z = 0: в точке (1000, 0, 0)
      final startNode = Node3D(id: 'branch_start', x: 1000, y: 0, z: 0);
      network.nodes['branch_start'] = startNode;
      controller.history.recordState(network);

      controller.setTool(CanvasTool.trace);
      controller.currentElevationZ = 0.0;
      controller.activeDn = 50;

      // Кликаем по начальному узлу
      final startScreen = controller.projector.project(startNode);
      controller.handlePointerDown(startScreen);
      expect(controller.traceStartNode?.id, 'branch_start');

      // Перемещаем курсор к точке врезки в магистраль (1000, 1000, 1200)
      final targetWorld = Node3D(id: '', x: 1000, y: 1000, z: 1200);
      final targetScreen = controller.projector.project(targetWorld);
      controller.handlePointerMove(targetScreen);

      // Проверяем, что SnapEngine сработал и зафиксировал smartElevationBranch
      expect(controller.currentSnapResult?.type, SnapType.smartElevationBranch);
      expect(controller.currentSnapResult?.isElevationTransition, isTrue);

      // Кликаем для завершения врезки
      controller.handlePointerDown(targetScreen);

      // Проверяем созданную геометрию сети:
      // 1. Исходный сегмент main_seg должен быть разделен тройником в точке (1000, 1000, 1200)
      expect(network.segments.length, greaterThanOrEqualTo(4)); // 2 части магистрали + 1 горизонтальный + 1 вертикальный

      // Должен существовать узел поворота на Z = 0 в (1000, 1000, 0)
      final turnNodes = network.nodes.values.where(
        (n) => (n.x - 1000).abs() < 5 && (n.y - 1000).abs() < 5 && n.z == 0.0,
      );
      expect(turnNodes.isNotEmpty, isTrue, reason: 'Промежуточный узел отвода на Z=0 должен быть создан');
      final turnNode = turnNodes.first;

      // В узле поворота должен быть автоматически определен отвод 90°
      final turnFitting = network.fittings[turnNode.id];
      expect(turnFitting?.fittingType, FittingType.elbow90);

      // В точке врезки в магистраль (1000, 1000, 1200) должен быть узел тройника
      final teeNodes = network.nodes.values.where(
        (n) => (n.x - 1000).abs() < 5 && (n.y - 1000).abs() < 5 && n.z == 1200.0,
      );
      expect(teeNodes.isNotEmpty, isTrue, reason: 'Узел врезки в магистраль на Z=1200 должен быть создан');
      final teeNode = teeNodes.first;

      // В узле врезки должен быть тройник или прямая врезка
      final teeFitting = network.fittings[teeNode.id];
      expect(
        teeFitting?.fittingType == FittingType.tee || teeFitting?.fittingType == FittingType.directBranch,
        isTrue,
        reason: 'Врезка должна детектироваться как тройник или прямая врезка',
      );

      // Должен существовать вертикальный сегмент (стояк) от turnNode к teeNode
      final riserSegments = network.segments.values.where((s) =>
          (s.startNodeId == turnNode.id && s.endNodeId == teeNode.id) ||
          (s.startNodeId == teeNode.id && s.endNodeId == turnNode.id));
      expect(riserSegments.isNotEmpty, isTrue, reason: 'Вертикальный стояк ΔZ = 1200 должен быть создан');

      // Проверяем Undo: одиночный откат должен вернуть сеть в исходное состояние
      expect(controller.canUndo, isTrue);
      controller.undo();

      // Сеть возвращается: только 1 исходный сегмент магистрали
      expect(network.segments.containsKey('main_seg'), isTrue);
      expect(network.nodes.containsKey(turnNode.id), isFalse);
    });

    test('Direct vertical connection when start node is already collinear with target pipe', () {
      // Магистраль на Z = 1000: от (0, 500, 1000) до (2000, 500, 1000)
      final m1 = Node3D(id: 'm1', x: 0, y: 500, z: 1000);
      final m2 = Node3D(id: 'm2', x: 2000, y: 500, z: 1000);
      network.nodes['m1'] = m1;
      network.nodes['m2'] = m2;
      network.addSegment(PipeSegment(id: 'm_seg', startNodeId: 'm1', endNodeId: 'm2', systemId: 'T1', dn: 80));

      // Начальный узел прямо под магистралью: (1000, 500, 0)
      final startNode = Node3D(id: 'vert_start', x: 1000, y: 500, z: 0);
      network.nodes['vert_start'] = startNode;

      controller.setTool(CanvasTool.trace);
      controller.currentElevationZ = 0.0;
      controller.activeDn = 80;

      final startScreen = controller.projector.project(startNode);
      controller.handlePointerDown(startScreen);

      final targetWorld = Node3D(id: '', x: 1000, y: 500, z: 1000);
      final targetScreen = controller.projector.project(targetWorld);
      controller.handlePointerMove(targetScreen);

      // Кликаем по целевой трубе
      controller.handlePointerDown(targetScreen);

      // Должен быть создан только один вертикальный сегмент (без лишнего горизонтального отрезка)
      final verticalSegments = network.segments.values.where((s) {
        final start = network.nodes[s.startNodeId]!;
        final end = network.nodes[s.endNodeId]!;
        return start.x == end.x && start.y == end.y && start.z != end.z;
      });
      expect(verticalSegments.length, 1);
    });
  });
}
