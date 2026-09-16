import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/painters/pipe_painter.dart';

void main() {
  group('Task 2: Centerline and Spool Rendering Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;
    const projector = AxonometryProjector(projectionType: ProjectionType.gostFrontal45);

    setUp(() {
      network = PipingNetwork();
      network.systems['sys1'] = const PipingSystem(
        id: 'sys1',
        name: 'Водоснабжение',
        code: 'В1',
        colorValue: 0xFF2196F3,
        dxfAciColor: 5,
      );
      controller = PipingInputController(network: network);
    });

    test('isCenterlineMode defaults to false and can be toggled', () {
      expect(controller.isCenterlineMode, isFalse);

      bool notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.toggleCenterlineMode();
      expect(controller.isCenterlineMode, isTrue);
      expect(notified, isTrue);

      controller.toggleCenterlineMode();
      expect(controller.isCenterlineMode, isFalse);
    });

    test('PipePainter renders spools and skips butt-joint segments without spools', () {
      // 1. Сегмент отвод-отвод встык
      network.nodes['n1'] = const Node3D(id: 'n1', x: -1000, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 300, z: 0);
      network.nodes['n4'] = const Node3D(id: 'n4', x: 1000, y: 300, z: 0);

      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 100);
      network.segments['s3'] = const PipeSegment(id: 's3', startNodeId: 'n3', endNodeId: 'n4', systemId: 'sys1', dn: 100);

      network.recalculateSpools();

      // s2 не имеет катушек
      expect(network.spools.values.where((sp) => sp.segmentId == 's2'), isEmpty);

      // Проверяем, что PipePainter.paint выполняется успешно для сети с катушками и отводами встык
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final screenPoints = <String, Offset>{};
      for (final n in network.nodes.values) {
        screenPoints[n.id] = projector.project(n);
      }

      expect(() {
        PipePainter.paint(
          canvas,
          const Size(800, 600),
          projector,
          network,
          null,
          null,
          screenPoints,
          false,
          false,
          null,
          false, // isCenterlineMode
        );
      }, returnsNormally);
    });

    test('PipePainter in centerline mode renders dash-dot lines without error', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      network.recalculateSpools();

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final screenPoints = <String, Offset>{};
      for (final n in network.nodes.values) {
        screenPoints[n.id] = projector.project(n);
      }

      expect(() {
        PipePainter.paint(
          canvas,
          const Size(800, 600),
          projector,
          network,
          null,
          null,
          screenPoints,
          false,
          false,
          null,
          true, // isCenterlineMode
        );
      }, returnsNormally);
    });
  });
}
