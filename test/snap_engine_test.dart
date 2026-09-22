import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/core/math/drafting_settings.dart';
import 'package:akso/core/math/snap_engine.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('SnapEngine Tests', () {
    late PipingNetwork network;
    late AxonometryProjector projector;
    late SnapEngine snapEngine;

    setUp(() {
      network = PipingNetwork();
      projector = AxonometryProjector();
      snapEngine = SnapEngine();
    });

    test('Примагничивание к существующему узлу в радиусе захвата', () {
      final node = const Node3D(id: 'n1', x: 500, y: 500, z: 0);
      network.nodes['n1'] = node;

      final nodeScreenPos = projector.project(node);
      // Курсор чуть смещен на 10 px
      final cursorScreenPos = nodeScreenPos.translate(8.0, 6.0);

      final result = snapEngine.findSnap(
        screenPos: cursorScreenPos,
        network: network,
        projector: projector,
        currentElevationZ: 0.0,
      );

      expect(result.type, equals(SnapType.node));
      expect(result.snappedNodeId, equals('n1'));
      expect(result.screenPoint, equals(nodeScreenPos));
    });

    test('Примагничивание к оси трубы (для врезки)', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 50,
      );

      // Точка на 1/4 длины трубы (x=500, y=0, z=0) вдали от середины и узлов
      final testPoint = const Node3D(id: '', x: 500, y: 0, z: 0);
      final testScreenPos = projector.project(testPoint);
      // Смещение на 8 пикселей перпендикулярно
      final cursor = testScreenPos.translate(0, 8.0);

      final result = snapEngine.findSnap(
        screenPos: cursor,
        network: network,
        projector: projector,
        currentElevationZ: 0.0,
        settings: const DraftingSettings(snapNearest: true),
      );

      expect(result.type, equals(SnapType.segmentAxis));
      expect(result.snappedSegmentId, equals('seg1'));
    });

    test('Полярное отслеживание угла 45 градусов при трассировке', () {
      final startNode = const Node3D(id: 'start', x: 0, y: 0, z: 0);

      // Вектор под углом ~46 градусов (в пределах допуска 5 градусов)
      // dx = 1000, dy = 1035 -> atan2(1035, 1000) = ~46°
      final rawWorld = const Node3D(id: 'raw', x: 1000, y: 1035, z: 0);
      final rawScreen = projector.project(rawWorld);

      final result = snapEngine.findSnap(
        screenPos: rawScreen,
        network: network,
        projector: projector,
        currentElevationZ: 0.0,
        traceStartNode: startNode,
        angleMode: AngleSnapMode.isometric45,
      );

      expect(result.type, equals(SnapType.polarAngle));
      expect(result.snappedAngleDegrees, equals(45.0));
      expect(result.label.contains('45°'), isTrue);
    });

    test('Полярное отслеживание Орто 90 градусов', () {
      final startNode = const Node3D(id: 'start', x: 0, y: 0, z: 0);

      // Вектор под углом ~88 градусов
      final rawWorld = const Node3D(id: 'raw', x: 50, y: 1500, z: 0);
      final rawScreen = projector.project(rawWorld);

      final result = snapEngine.findSnap(
        screenPos: rawScreen,
        network: network,
        projector: projector,
        currentElevationZ: 0.0,
        traceStartNode: startNode,
        angleMode: AngleSnapMode.ortho90,
      );

      expect(result.type, equals(SnapType.polarAngle));
      expect(result.snappedAngleDegrees, equals(90.0));
    });
  });
}
