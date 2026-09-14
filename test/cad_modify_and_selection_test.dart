import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/core/math/snap_engine.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/domain/models/linear_dimension.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('AutoCAD / Revit Style CAD Tools & Selection Tests', () {
    late PipingNetwork network;
    late AxonometryProjector projector;
    late PipingInputController controller;
    late SnapEngine snapEngine;

    setUp(() {
      network = PipingNetwork();
      projector = AxonometryProjector();
      controller = PipingInputController(network: network, projector: projector);
      snapEngine = SnapEngine();
    });

    group('1. Marquee / Box Selection', () {
      test('Left-to-right (window selection) selects only elements entirely inside', () {
        final n1 = const Node3D(id: 'n1', x: 100, y: 100, z: 0);
        final n2 = const Node3D(id: 'n2', x: 200, y: 100, z: 0);
        final n3 = const Node3D(id: 'n3', x: 500, y: 500, z: 0);
        network.nodes['n1'] = n1;
        network.nodes['n2'] = n2;
        network.nodes['n3'] = n3;

        final seg1 = const PipeSegment(
          id: 's1',
          startNodeId: 'n1',
          endNodeId: 'n2',
          systemId: 'sys_t1',
          dn: 50,
        );
        final seg2 = const PipeSegment(
          id: 's2',
          startNodeId: 'n2',
          endNodeId: 'n3',
          systemId: 'sys_t1',
          dn: 50,
        );
        network.addSegment(seg1);
        network.addSegment(seg2);

        final p1 = projector.project(n1);
        final p2 = projector.project(n2);

        // Тянем рамку слева направо (start.dx < end.dx), охватывая n1 и n2, но не n3
        final boxStart = Offset(p1.dx - 20, p1.dy - 20);
        final boxEnd = Offset(p2.dx + 20, p2.dy + 20);

        controller.setTool(CanvasTool.select);
        controller.handlePointerDown(boxStart);
        controller.handlePointerMove(boxEnd);
        controller.handlePointerUp();

        // n1 и n2 целиком внутри, seg1 целиком внутри
        expect(controller.selectedNodeIds.contains('n1'), isTrue);
        expect(controller.selectedNodeIds.contains('n2'), isTrue);
        expect(controller.selectedSegmentIds.contains('s1'), isTrue);
        // seg2 выходит за пределы рамки к n3, поэтому не должен быть выбран в обычном окне
        expect(controller.selectedSegmentIds.contains('s2'), isFalse);
        expect(controller.selectedNodeIds.contains('n3'), isFalse);
      });

      test('Right-to-left (crossing selection) selects elements crossed by box', () {
        final n1 = const Node3D(id: 'n1', x: 100, y: 100, z: 0);
        final n2 = const Node3D(id: 'n2', x: 800, y: 100, z: 0);
        network.nodes['n1'] = n1;
        network.nodes['n2'] = n2;

        final seg1 = const PipeSegment(
          id: 's1',
          startNodeId: 'n1',
          endNodeId: 'n2',
          systemId: 'sys_t1',
          dn: 50,
        );
        network.addSegment(seg1);

        final p1 = projector.project(n1);
        final p2 = projector.project(n2);
        final mid = (p1 + p2) / 2;

        // Рамка справа-налево (start.dx > end.dx), пересекающая середину трубы
        final boxStart = Offset(mid.dx + 30, mid.dy + 30);
        final boxEnd = Offset(mid.dx - 30, mid.dy - 30);

        controller.setTool(CanvasTool.select);
        controller.handlePointerDown(boxStart);
        controller.handlePointerMove(boxEnd);
        controller.handlePointerUp();

        // Секущая рамка должна выбрать s1, даже если концы n1 и n2 снаружи
        expect(controller.selectedSegmentIds.contains('s1'), isTrue);
      });

      test('Selection box captures equipment, axes, and dimensions', () {
        final eq = const Equipment(
          id: 'eq1',
          name: 'Е-1',
          x: 100,
          y: 100,
          z: 0,
          width: 200,
          length: 200,
          height: 200,
        );
        network.equipments['eq1'] = eq;

        final axis = const ConstructionAxis(
          id: 'ax1',
          label: '1',
          startPoint: Node3D(id: 'a1', x: 50, y: 50, z: 0),
          endPoint: Node3D(id: 'a2', x: 150, y: 50, z: 0),
        );
        network.axes['ax1'] = axis;

        final dim = const LinearDimension(
          id: 'd1',
          startPoint: Node3D(id: 'dp1', x: 60, y: 60, z: 0),
          endPoint: Node3D(id: 'dp2', x: 120, y: 60, z: 0),
          offsetDistance: 35,
        );
        network.dimensions['d1'] = dim;

        final pEq = projector.project(const Node3D(id: '', x: 100, y: 100, z: 0));
        final boxStart = Offset(pEq.dx - 150, pEq.dy - 150);
        final boxEnd = Offset(pEq.dx + 150, pEq.dy + 150);

        controller.setTool(CanvasTool.select);
        controller.handlePointerDown(boxStart);
        controller.handlePointerMove(boxEnd);
        controller.handlePointerUp();

        expect(controller.selectedEquipmentIds.contains('eq1'), isTrue);
        expect(controller.selectedAxisIds.contains('ax1'), isTrue);
        expect(controller.selectedDimensionIds.contains('d1'), isTrue);
      });
    });

    group('2. Extended OSNAP (Midpoint, Nearest, Intersection)', () {
      test('Midpoint snap on pipe segment', () {
        network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
        network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
        network.segments['s1'] = const PipeSegment(
          id: 's1',
          startNodeId: 'n1',
          endNodeId: 'n2',
          systemId: 'sys_t1',
          dn: 50,
        );

        // Точная середина отрезка в координатах мира (1000, 0, 0)
        final midWorld = const Node3D(id: '', x: 1000, y: 0, z: 0);
        final midScreen = projector.project(midWorld);
        final cursor = midScreen.translate(4.0, -3.0); // В пределах радиуса snapThreshold

        final snap = snapEngine.findSnap(
          screenPos: cursor,
          network: network,
          projector: projector,
          currentElevationZ: 0.0,
        );

        expect(snap.type, equals(SnapType.midpoint));
        expect(snap.label, contains('Середина'));
        expect(snap.snappedSegmentId, equals('s1'));
      });

      test('Midpoint snap on construction axis', () {
        final axis = const ConstructionAxis(
          id: 'ax_mid',
          label: 'A',
          startPoint: Node3D(id: 'a1', x: 0, y: 500, z: 0),
          endPoint: Node3D(id: 'a2', x: 0, y: 1500, z: 0),
        );
        network.axes['ax_mid'] = axis;

        final midWorld = const Node3D(id: '', x: 0, y: 1000, z: 0);
        final midScreen = projector.project(midWorld);
        final cursor = midScreen.translate(-3.0, 2.0);

        final snap = snapEngine.findSnap(
          screenPos: cursor,
          network: network,
          projector: projector,
          currentElevationZ: 0.0,
        );

        expect(snap.type, equals(SnapType.midpoint));
        expect(snap.label, contains('Середина оси'));
      });

      test('Intersection snap on two crossing construction axes', () {
        // Ось X: от (0, 1000) до (2000, 1000)
        network.axes['ax_h'] = const ConstructionAxis(
          id: 'ax_h',
          label: '1',
          startPoint: Node3D(id: 'h1', x: 0, y: 1000, z: 0),
          endPoint: Node3D(id: 'h2', x: 2000, y: 1000, z: 0),
        );
        // Ось Y: от (1000, 0) до (1000, 2000)
        network.axes['ax_v'] = const ConstructionAxis(
          id: 'ax_v',
          label: 'A',
          startPoint: Node3D(id: 'v1', x: 1000, y: 0, z: 0),
          endPoint: Node3D(id: 'v2', x: 1000, y: 2000, z: 0),
        );

        // Точка пересечения: (1000, 1000, 0)
        final interWorld = const Node3D(id: '', x: 1000, y: 1000, z: 0);
        final interScreen = projector.project(interWorld);
        final cursor = interScreen.translate(5.0, 5.0);

        final snap = snapEngine.findSnap(
          screenPos: cursor,
          network: network,
          projector: projector,
          currentElevationZ: 0.0,
        );

        expect(snap.type, equals(SnapType.intersection));
        expect(snap.label, contains('Пересечение'));
      });

      test('Perpendicular snap on pipe segment from start point', () {
        // Труба по оси X от (0, 0, 0) до (2000, 0, 0)
        network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
        network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
        network.segments['s1'] = const PipeSegment(
          id: 's1',
          startNodeId: 'n1',
          endNodeId: 'n2',
          systemId: 'sys_t1',
          dn: 50,
        );

        // Начальная точка трассировки со смещением по Y: (1200, 800, 0)
        final startNode = const Node3D(id: 'start', x: 1200, y: 800, z: 0);
        // Перпендикуляр падает строго в точку (1200, 0, 0) на трубе s1
        final perpWorld = const Node3D(id: '', x: 1200, y: 0, z: 0);
        final perpScreen = projector.project(perpWorld);
        final cursor = perpScreen.translate(3.0, -2.0);

        final snap = snapEngine.findSnap(
          screenPos: cursor,
          network: network,
          projector: projector,
          currentElevationZ: 0.0,
          traceStartNode: startNode,
        );

        expect(snap.type, equals(SnapType.perpendicular));
        expect(snap.snappedSegmentId, equals('s1'));
        expect(snap.label, contains('Перпендикуляр 90°'));
        expect(snap.worldPoint.x, closeTo(1200.0, 1.0));
        expect(snap.worldPoint.y, closeTo(0.0, 1.0));
      });

      test('Perpendicular snap on construction axis from start point', () {
        // Ось вдоль X на y=1000
        network.axes['ax_grid'] = const ConstructionAxis(
          id: 'ax_grid',
          label: '2',
          startPoint: Node3D(id: 'g1', x: 0, y: 1000, z: 0),
          endPoint: Node3D(id: 'g2', x: 2000, y: 1000, z: 0),
        );

        // Начальная точка (750, 200, 0)
        final startNode = const Node3D(id: 'start2', x: 750, y: 200, z: 0);
        // Основание перпендикуляра: (750, 1000, 0)
        final perpWorld = const Node3D(id: '', x: 750, y: 1000, z: 0);
        final perpScreen = projector.project(perpWorld);
        final cursor = perpScreen.translate(-2.0, 3.0);

        final snap = snapEngine.findSnap(
          screenPos: cursor,
          network: network,
          projector: projector,
          currentElevationZ: 0.0,
          traceStartNode: startNode,
        );

        expect(snap.type, equals(SnapType.perpendicular));
        expect(snap.snappedSegmentId, equals('ax_grid'));
        expect(snap.label, contains('Перпендикуляр 90° [Ось 2]'));
        expect(snap.worldPoint.x, closeTo(750.0, 1.0));
        expect(snap.worldPoint.y, closeTo(1000.0, 1.0));
      });

      test('Relative 90-degree normal angle tracking to connected pipe', () {
        // Труба под 45 градусов: (0, 0, 0) -> (1000, 1000, 0)
        final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
        final n2 = const Node3D(id: 'n2', x: 1000, y: 1000, z: 0);
        network.nodes['n1'] = n1;
        network.nodes['n2'] = n2;
        network.segments['s1'] = const PipeSegment(
          id: 's1',
          startNodeId: 'n1',
          endNodeId: 'n2',
          systemId: 'sys_t1',
          dn: 50,
        );

        // Чертим из n2 (1000, 1000, 0). Перпендикуляр к трубе: 45° + 90° = 135°
        // Направление 135°: dx = -1000, dy = 1000 -> target (0, 2000, 0)
        final targetWorld = const Node3D(id: 'target', x: 0, y: 2000, z: 0);
        final targetScreen = projector.project(targetWorld);

        final snap = snapEngine.findSnap(
          screenPos: targetScreen,
          network: network,
          projector: projector,
          currentElevationZ: 0.0,
          traceStartNode: n2,
        );

        expect(snap.type, equals(SnapType.polarAngle));
        expect(snap.label, contains('∠90° к трубе (Перпендикуляр)'));
      });

      test('Connecting a branch pipe via perpendicular snap splits the pipe and creates branch', () {
        final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
        final n2 = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
        network.nodes['n1'] = n1;
        network.nodes['n2'] = n2;
        network.segments['s1'] = const PipeSegment(
          id: 's1',
          startNodeId: 'n1',
          endNodeId: 'n2',
          systemId: 'sys_t1',
          dn: 50,
        );

        final startNode = Node3D(id: 'branch_start', x: 1400, y: 600, z: 0);
        network.nodes['branch_start'] = startNode;
        controller.setTool(CanvasTool.trace);
        controller.traceStartNode = startNode;

        final perpWorld = const Node3D(id: '', x: 1400, y: 0, z: 0);
        final perpScreen = projector.project(perpWorld);

        controller.handlePointerMove(perpScreen);
        expect(controller.currentSnapResult?.type, equals(SnapType.perpendicular));

        controller.handlePointerDown(perpScreen);

        expect(network.segments.containsKey('s1'), isFalse);
        expect(network.segments.length, greaterThanOrEqualTo(2));
        final junctionNode = network.nodes.values.firstWhere(
          (n) => (n.x - 1400.0).abs() < 10.0 && (n.y - 0.0).abs() < 10.0,
        );
        expect(junctionNode, isNotNull);
      });
    });

    group('3. CAD Modify Tools (Move, Copy, Rotate)', () {
      test('CanvasTool.move shifts selected items by delta between two clicks', () {
        final n1 = const Node3D(id: 'n1', x: 100, y: 100, z: 0);
        final n2 = const Node3D(id: 'n2', x: 300, y: 100, z: 0);
        network.nodes['n1'] = n1;
        network.nodes['n2'] = n2;
        final seg1 = const PipeSegment(
          id: 's1',
          startNodeId: 'n1',
          endNodeId: 'n2',
          systemId: 'sys_t1',
          dn: 50,
        );
        network.addSegment(seg1);

        controller.selectedNodeIds.addAll(['n1', 'n2']);
        controller.selectedSegmentIds.add('s1');

        // Переключаемся в инструмент перемещения (выделение сохраняется)
        controller.setTool(CanvasTool.move);
        expect(controller.selectedSegmentIds.contains('s1'), isTrue);

        final p1 = projector.project(n1);
        // 1-й клик: базовая точка в n1 (100, 100)
        controller.handlePointerDown(p1);
        expect(controller.modifyBasePointWorld, isNotNull);
        expect(controller.modifyBasePointWorld!.x, closeTo(100, 1.0));

        // 2-й клик: смещение в (1100, 100) -> delta dx=+1000, dy=0
        final pTarget = projector.project(const Node3D(id: '', x: 1100, y: 100, z: 0));
        controller.handlePointerDown(pTarget);

        // Инструмент возвращается в select, узлы сдвинуты на +1000
        expect(controller.currentTool, equals(CanvasTool.select));
        expect(network.nodes['n1']!.x, closeTo(1100, 1.0));
        expect(network.nodes['n2']!.x, closeTo(1300, 1.0));
      });

      test('CanvasTool.move with Direct Distance Entry', () {
        final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
        network.nodes['n1'] = n1;
        controller.selectedNodeIds.add('n1');

        controller.setTool(CanvasTool.move);
        final pBase = projector.project(n1);
        controller.handlePointerDown(pBase);

        // Ввод расстояния 500 мм вдоль направления +X
        controller.commitTraceWithLength(500.0, dirX: 1.0, dirY: 0.0, dirZ: 0.0);

        expect(network.nodes['n1']!.x, closeTo(500.0, 0.1));
        expect(network.nodes['n1']!.y, closeTo(0.0, 0.1));
        expect(controller.currentTool, equals(CanvasTool.select));
      });

      test('CanvasTool.copy duplicates selected items with offset', () {
        final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
        final n2 = const Node3D(id: 'n2', x: 500, y: 0, z: 0);
        network.nodes['n1'] = n1;
        network.nodes['n2'] = n2;
        final seg1 = const PipeSegment(
          id: 's1',
          startNodeId: 'n1',
          endNodeId: 'n2',
          systemId: 'sys_t1',
          dn: 50,
        );
        network.addSegment(seg1);

        controller.selectedNodeIds.addAll(['n1', 'n2']);
        controller.selectedSegmentIds.add('s1');

        controller.setTool(CanvasTool.copy);
        final p1 = projector.project(n1);
        controller.handlePointerDown(p1);

        // 2-й клик: вставка копии на смещение dx=0, dy=1000
        final pCopy1 = projector.project(const Node3D(id: '', x: 0, y: 1000, z: 0));
        controller.handlePointerDown(pCopy1);

        // Должно стать 4 узла и 2 сегмента
        expect(network.nodes.length, equals(4));
        expect(network.segments.length, equals(2));

        // Проверяем координаты новой трубы
        final newSeg = network.segments.values.firstWhere((s) => s.id != 's1');
        final newStart = network.nodes[newSeg.startNodeId]!;
        final newEnd = network.nodes[newSeg.endNodeId]!;
        expect(newStart.y, closeTo(1000.0, 1.0));
        expect(newEnd.y, closeTo(1000.0, 1.0));
      });

      test('CanvasTool.rotate rotates selected elements around base point', () {
        final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
        final n2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
        network.nodes['n1'] = n1;
        network.nodes['n2'] = n2;
        final seg1 = const PipeSegment(
          id: 's1',
          startNodeId: 'n1',
          endNodeId: 'n2',
          systemId: 'sys_t1',
          dn: 50,
        );
        network.addSegment(seg1);

        controller.selectedNodeIds.addAll(['n1', 'n2']);
        controller.selectedSegmentIds.add('s1');

        // Поворот на 90 градусов вокруг (0, 0, 0)
        controller.rotateSelectionAroundZ(90, customCenter: n1);

        expect(network.nodes['n1']!.x, closeTo(0.0, 0.1));
        expect(network.nodes['n1']!.y, closeTo(0.0, 0.1));
        // (1000, 0) повернется в (0, 1000)
        expect(network.nodes['n2']!.x, closeTo(0.0, 1.0));
        expect(network.nodes['n2']!.y, closeTo(1000.0, 1.0));
      });

      test('deleteSelected cascades across nodes, segments, equipment, axes, dimensions', () {
        final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
        final n2 = const Node3D(id: 'n2', x: 500, y: 0, z: 0);
        network.nodes['n1'] = n1;
        network.nodes['n2'] = n2;
        network.segments['s1'] = const PipeSegment(
          id: 's1',
          startNodeId: 'n1',
          endNodeId: 'n2',
          systemId: 'sys_t1',
          dn: 50,
        );
        network.equipments['eq1'] = const Equipment(id: 'eq1', name: 'Tank', x: 0, y: 0, z: 0, width: 100, length: 100, height: 100);
        network.axes['ax1'] = const ConstructionAxis(id: 'ax1', label: '1', startPoint: Node3D(id: 'a1', x: 0, y: 0, z: 0), endPoint: Node3D(id: 'a2', x: 100, y: 0, z: 0));
        network.dimensions['dim1'] = const LinearDimension(id: 'dim1', startPoint: Node3D(id: 'd1', x: 0, y: 0, z: 0), endPoint: Node3D(id: 'd2', x: 100, y: 0, z: 0), offsetDistance: 35);

        controller.selectedNodeIds.addAll(['n1', 'n2']);
        controller.selectedSegmentIds.add('s1');
        controller.selectedEquipmentIds.add('eq1');
        controller.selectedAxisIds.add('ax1');
        controller.selectedDimensionIds.add('dim1');

        controller.deleteSelected();

        expect(network.nodes.isEmpty, isTrue);
        expect(network.segments.isEmpty, isTrue);
        expect(network.equipments.isEmpty, isTrue);
        expect(network.axes.isEmpty, isTrue);
        expect(network.dimensions.isEmpty, isTrue);
      });
    });

    group('5. Axis Endpoint Snapping and Distance Competition (6000 vs 5960 mm)', () {
      test('Привязка к краю оси (SnapType.endpoint) имеет приоритет перед близким пересечением, если курсор ближе к краю', () {
        // Ось 1: от (0, 0, 0) до (6000, 0, 0)
        final axis1 = const ConstructionAxis(
          id: 'ax_main',
          label: 'A',
          startPoint: Node3D(id: 'a1', x: 0, y: 0, z: 0),
          endPoint: Node3D(id: 'a2', x: 6000, y: 0, z: 0),
          isBuildingGrid: true,
        );
        // Ось 2: пересекает Ось 1 на x = 5960
        final axis2 = const ConstructionAxis(
          id: 'ax_cross',
          label: '1',
          startPoint: Node3D(id: 'b1', x: 5960, y: -1000, z: 0),
          endPoint: Node3D(id: 'b2', x: 5960, y: 1000, z: 0),
          isBuildingGrid: true,
        );
        network.axes[axis1.id] = axis1;
        network.axes[axis2.id] = axis2;

        final pEnd = projector.project(axis1.endPoint); // (6000, 0, 0)
        final pInter = projector.project(const Node3D(id: '', x: 5960, y: 0, z: 0));

        // 1. Курсор находится рядом с краем оси (6000 мм)
        final cursorNearEnd = pEnd.translate(1.0, 0.0);
        final snapNearEnd = snapEngine.findSnap(
          screenPos: cursorNearEnd,
          network: network,
          projector: projector,
          currentElevationZ: 0.0,
        );

        // Должен выиграть Край оси (SnapType.endpoint), а НЕ пересечение на 5960!
        expect(snapNearEnd.type, equals(SnapType.endpoint));
        expect(snapNearEnd.worldPoint.x, closeTo(6000.0, 0.1));
        expect(snapNearEnd.worldPoint.y, closeTo(0.0, 0.1));
        expect(snapNearEnd.label, contains('Край оси A'));

        // 2. Курсор находится ближе к точке пересечения (5960 мм)
        final cursorNearInter = pInter.translate(1.0, 0.0);
        final snapNearInter = snapEngine.findSnap(
          screenPos: cursorNearInter,
          network: network,
          projector: projector,
          currentElevationZ: 0.0,
        );

        // Должно выиграть Пересечение
        expect(snapNearInter.type, equals(SnapType.intersection));
        expect(snapNearInter.worldPoint.x, closeTo(5960.0, 0.1));
        expect(snapNearInter.label, contains('Пересечение'));
      });

      test('Копирование оси и трубы от края (6000 мм) копирует на точное расстояние без искажений 5960', () {
        final axis = const ConstructionAxis(
          id: 'ax1',
          label: 'A',
          startPoint: Node3D(id: 'a1', x: 0, y: 0, z: 0),
          endPoint: Node3D(id: 'a2', x: 6000, y: 0, z: 0),
          isBuildingGrid: true,
        );
        final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
        final n2 = const Node3D(id: 'n2', x: 6000, y: 0, z: 0);
        final seg = const PipeSegment(
          id: 's1',
          startNodeId: 'n1',
          endNodeId: 'n2',
          systemId: 'sys_1',
          dn: 100,
        );
        network.axes[axis.id] = axis;
        network.nodes['n1'] = n1;
        network.nodes['n2'] = n2;
        network.addSegment(seg);

        // Выделяем ось и трубу
        controller.selectedAxisIds.add(axis.id);
        controller.selectedSegmentIds.add(seg.id);
        controller.selectedNodeIds.addAll(['n1', 'n2']);

        controller.setTool(CanvasTool.copy);

        // 1-й клик: базовая точка на краю (6000, 0, 0)
        final pBase = projector.project(axis.endPoint);
        controller.handlePointerDown(pBase);
        expect(controller.modifyBasePointWorld, isNotNull);
        expect(controller.modifyBasePointWorld!.x, closeTo(6000.0, 0.1));

        // 2-й клик: вставка со смещением dy = 2000
        final pDest = projector.project(const Node3D(id: '', x: 6000, y: 2000, z: 0));
        controller.handlePointerDown(pDest);

        // Проверяем скопированные элементы
        expect(network.axes.length, equals(2));
        expect(network.segments.length, equals(2));

        final copiedAxis = network.axes.values.firstWhere((a) => a.id != 'ax1');
        expect(copiedAxis.startPoint.y, closeTo(2000.0, 0.1));
        expect(copiedAxis.endPoint.y, closeTo(2000.0, 0.1));
        expect((copiedAxis.endPoint.x - copiedAxis.startPoint.x).abs(), closeTo(6000.0, 0.1));
      });

      test('Перемещение от точки пересечения (5960 мм) до края (6000 мм) сдвигает ровно на 40 мм', () {
        final axis1 = const ConstructionAxis(
          id: 'ax1',
          label: 'A',
          startPoint: Node3D(id: 'a1', x: 0, y: 0, z: 0),
          endPoint: Node3D(id: 'a2', x: 6000, y: 0, z: 0),
          isBuildingGrid: true,
        );
        final crossAxis = const ConstructionAxis(
          id: 'ax_cross',
          label: '1',
          startPoint: Node3D(id: 'b1', x: 5960, y: -500, z: 0),
          endPoint: Node3D(id: 'b2', x: 5960, y: 500, z: 0),
          isBuildingGrid: true,
        );
        network.axes[axis1.id] = axis1;
        network.axes[crossAxis.id] = crossAxis;

        final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
        network.nodes['n1'] = n1;
        controller.selectedNodeIds.add('n1');

        controller.setTool(CanvasTool.move);

        // 1-й клик: базовая точка на пересечении (5960, 0, 0)
        final pInter = projector.project(const Node3D(id: '', x: 5960, y: 0, z: 0));
        controller.handlePointerDown(pInter);
        expect(controller.modifyBasePointWorld!.x, closeTo(5960.0, 0.1));

        // 2-й клик: целевая точка на краю оси (6000, 0, 0)
        final pEnd = projector.project(const Node3D(id: '', x: 6000, y: 0, z: 0));
        controller.handlePointerDown(pEnd);

        // Узел n1 должен переместиться ровно на +40 мм (6000 - 5960)
        expect(network.nodes['n1']!.x, closeTo(40.0, 0.1));
        expect(network.nodes['n1']!.y, closeTo(0.0, 0.1));
      });

      test('Клик по краю вспомогательной опорной линии выделяет ее в режиме select', () {
        final refLine = const ConstructionAxis(
          id: 'ref_aux_1',
          label: '',
          startPoint: Node3D(id: 'r1', x: 1000, y: 2000, z: 0),
          endPoint: Node3D(id: 'r2', x: 5000, y: 2000, z: 0),
          isBuildingGrid: false,
        );
        network.axes[refLine.id] = refLine;

        controller.setTool(CanvasTool.select);

        // Кликаем точно по краю (r2)
        final pEnd = projector.project(refLine.endPoint);
        controller.handlePointerDown(pEnd);

        expect(controller.selectedAxisId, equals('ref_aux_1'));
        expect(controller.selectedAxisIds.contains('ref_aux_1'), isTrue);
      });
    });
  });
}
