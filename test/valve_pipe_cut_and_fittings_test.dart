import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/services/element_3d_geometry.dart';
import 'package:akso/domain/services/fitting_detector.dart';
import 'package:akso/ui/canvas/painters/pipe_painter.dart';

void main() {
  group('Valve Pipe Cut & Element Geometry Tests', () {
    late PipingNetwork network;
    late AxonometryProjector projector;

    setUp(() {
      network = PipingNetwork();
      projector = AxonometryProjector(projectionType: ProjectionType.topPlan2d, scale: 1.0);

      network.systems['sys1'] = const PipingSystem(
        id: 'sys1',
        name: 'Вода',
        code: 'В1',
        colorValue: 0xFF0000FF,
        dxfAciColor: 5,
      );

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
    });

    test('calcPipeDrawableIntervals3d: одиночная арматура вырезает трубу на 2 отрезка', () {
      final valve = Valve(
        id: 'v1',
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Задвижка Ду100',
        dn: 100,
        lengthMm: 200.0,
      );

      final intervals = Element3dGeometry.calcPipeDrawableIntervals3d(
        network.nodes['n1']!,
        network.nodes['n2']!,
        [valve],
      );

      expect(intervals.length, 2);

      // До арматуры: x от 0 до 400 (центр 500 - 100)
      expect(intervals[0].$1.x, closeTo(0.0, 0.1));
      expect(intervals[0].$2.x, closeTo(400.0, 0.1));

      // После арматуры: x от 600 (центр 500 + 100) до 1000
      expect(intervals[1].$1.x, closeTo(600.0, 0.1));
      expect(intervals[1].$2.x, closeTo(1000.0, 0.1));
    });

    test('calcPipeDrawableIntervals3d: непроходные приборы (манометр) не вырезают трубу', () {
      final gauge = Valve(
        id: 'g1',
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.pressureGauge,
        name: 'Манометр',
        dn: 100,
        lengthMm: 60.0,
      );

      final intervals = Element3dGeometry.calcPipeDrawableIntervals3d(
        network.nodes['n1']!,
        network.nodes['n2']!,
        [gauge],
      );

      expect(intervals.length, 1);
      expect(intervals[0].$1.x, closeTo(0.0, 0.1));
      expect(intervals[0].$2.x, closeTo(1000.0, 0.1));
    });

    test('calcPipeDrawableIntervals3d: две арматуры на сегменте вырезают трубу на 3 отрезка', () {
      final v1 = Valve(
        id: 'v1',
        segmentId: 'seg1',
        ratio: 0.25,
        valveType: ValveType.ballValve,
        name: 'Кран 1',
        dn: 100,
        lengthMm: 100.0,
      );
      final v2 = Valve(
        id: 'v2',
        segmentId: 'seg1',
        ratio: 0.75,
        valveType: ValveType.ballValve,
        name: 'Кран 2',
        dn: 100,
        lengthMm: 100.0,
      );

      final intervals = Element3dGeometry.calcPipeDrawableIntervals3d(
        network.nodes['n1']!,
        network.nodes['n2']!,
        [v1, v2],
      );

      expect(intervals.length, 3);
      // Отрезок 1: 0..200
      expect(intervals[0].$1.x, closeTo(0.0, 0.1));
      expect(intervals[0].$2.x, closeTo(200.0, 0.1));
      // Отрезок 2: 300..700
      expect(intervals[1].$1.x, closeTo(300.0, 0.1));
      expect(intervals[1].$2.x, closeTo(700.0, 0.1));
      // Отрезок 3: 800..1000
      expect(intervals[2].$1.x, closeTo(800.0, 0.1));
      expect(intervals[2].$2.x, closeTo(1000.0, 0.1));
    });

    test('PipePainter.calcPipeDrawableSubsegments: вырезает промежуток под арматуру на экране', () {
      network.addValve(
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
      );

      const drawP1 = Offset(0, 0);
      const drawP2 = Offset(1000, 0);

      final subsegments = PipePainter.calcPipeDrawableSubsegments(
        drawP1: drawP1,
        drawP2: drawP2,
        startNode: network.nodes['n1']!,
        endNode: network.nodes['n2']!,
        seg: network.segments['seg1']!,
        network: network,
        projector: projector,
      );

      expect(subsegments.length, 2);
      expect(subsegments[0].$1.dx, closeTo(0.0, 0.5));
      expect(subsegments[0].$2.dx, lessThan(500.0));
      expect(subsegments[1].$1.dx, greaterThan(500.0));
      expect(subsegments[1].$2.dx, closeTo(1000.0, 0.5));
    });

    test('FittingDetector: сохраняет пользовательские свойства перехода (L, угол поворота, эксцентриситет)', () {
      // Создаем узел nMid с сегментами разных диаметров
      network.nodes['nMid'] = const Node3D(id: 'nMid', x: 500, y: 0, z: 0);
      network.segments['segA'] = const PipeSegment(id: 'segA', startNodeId: 'n1', endNodeId: 'nMid', systemId: 'sys1', dn: 100);
      network.segments['segB'] = const PipeSegment(id: 'segB', startNodeId: 'nMid', endNodeId: 'n2', systemId: 'sys1', dn: 50);

      // Первичная детекция
      FittingDetector.autoDetectFittingsForNode(network, 'nMid');
      expect(network.fittings['nMid'], isNotNull);
      expect(network.fittings['nMid']!.fittingType, FittingType.reducerConcentric);

      // Пользователь настроил эксцентрический переход, длину L=220мм и поворот 90°
      network.fittings['nMid'] = network.fittings['nMid']!.copyWith(
        fittingType: FittingType.reducerEccentric,
        buildingLengthMm: 220.0,
        rotationAngleDeg: 90.0,
      );

      // Повторный вызов детекции (например, при перемещении узлов или топологическом обновлении)
      FittingDetector.autoDetectFittingsForNode(network, 'nMid');

      final preserved = network.fittings['nMid']!;
      expect(preserved.fittingType, FittingType.reducerEccentric);
      expect(preserved.buildingLengthMm, 220.0);
      expect(preserved.rotationAngleDeg, 90.0);
      expect(preserved.dn, 100);
      expect(preserved.dnSecondary, 50);
    });

    test('Element3dGeometry.generateReducerWireframe: ориентирован в плоскости XY и реагирует на угол вращения', () {
      final node = network.nodes['n1']!;
      final other1 = const Node3D(id: 'o1', x: -500, y: 0, z: 0);
      final other2 = const Node3D(id: 'o2', x: 500, y: 0, z: 0);

      final reducer = Fitting(
        id: 'fit1',
        nodeId: node.id,
        fittingType: FittingType.reducerConcentric,
        dn: 100,
        dnSecondary: 50,
        radiusMm: 100.0,
        rotationAngleDeg: 0.0,
      );

      final wire0 = Element3dGeometry.generateReducerWireframe(
        reducer,
        node,
        other1,
        other2,
        d1: 108.0,
        d2: 57.0,
      );

      expect(wire0.isNotEmpty, isTrue);
      // При угле 0° образующие лежат в плоскости XY (dy != 0, dz == 0)
      final hasDy = wire0.any((w) => w.startNode.y.abs() > 1.0);
      expect(hasDy, isTrue);

      // При угле 90° образующие встают в вертикальную плоскость Z (dz != 0)
      final reducer90 = reducer.copyWith(rotationAngleDeg: 90.0);
      final wire90 = Element3dGeometry.generateReducerWireframe(
        reducer90,
        node,
        other1,
        other2,
        d1: 108.0,
        d2: 57.0,
      );
      final hasDz = wire90.any((w) => w.startNode.z.abs() > 1.0);
      expect(hasDz, isTrue);
    });

    test('Element3dGeometry.generateReducer3d: учитывает effectiveBuildingLengthMm и rotationAngleDeg', () {
      final node = network.nodes['n1']!;
      final other1 = const Node3D(id: 'o1', x: -500, y: 0, z: 0);
      final other2 = const Node3D(id: 'o2', x: 500, y: 0, z: 0);

      final reducer = Fitting(
        id: 'fit1',
        nodeId: node.id,
        fittingType: FittingType.reducerConcentric,
        dn: 100,
        dnSecondary: 50,
        radiusMm: 100.0,
        buildingLengthMm: 300.0,
      );

      final lines = Element3dGeometry.generateReducer3d(
        reducer,
        node,
        other1,
        other2,
        d1: 108.0,
        d2: 57.0,
      );

      expect(lines.isNotEmpty, isTrue);
      // Проверяем, что крайние точки по X отдалены от центра на halfL = 150 мм
      final minX = lines.map((l) => math.min(l.x1, l.x2)).reduce(math.min);
      final maxX = lines.map((l) => math.max(l.x1, l.x2)).reduce(math.max);
      expect(maxX - minX, closeTo(300.0, 1.0));
    });
  });
}
