import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/controllers/selection_controller.dart';
import 'package:akso/ui/canvas/controllers/tracing_controller.dart';

void main() {
  group('SelectionController Tests', () {
    late SelectionController controller;
    late PipingNetwork network;
    // panOffset of (0, 500) so positive Y nodes project to positive screen Y
    const projector = AxonometryProjector(
      projectionType: ProjectionType.topPlan2d,
      panOffset: Offset(0, 500),
      scale: 1.0,
    );

    setUp(() {
      controller = SelectionController();
      network = PipingNetwork();

      // n1: x=100, y=400 -> screen: (100, 500 - 400) = (100, 100)
      // n2: x=200, y=400 -> screen: (200, 500 - 400) = (200, 100)
      // n3: x=500, y=0   -> screen: (500, 500 - 0)   = (500, 500)
      final n1 = Node3D(id: 'n1', x: 100, y: 400, z: 0);
      final n2 = Node3D(id: 'n2', x: 200, y: 400, z: 0);
      final n3 = Node3D(id: 'n3', x: 500, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      network.nodes[n3.id] = n3;

      final seg = PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 50,
      );
      network.addSegment(seg);
    });

    test('Single selection sets and clears correctly', () {
      controller.selectedNodeId = 'n1';
      expect(controller.selectedNodeId, 'n1');
      expect(controller.hasSelection, isTrue);

      controller.clearSelection();
      expect(controller.selectedNodeId, isNull);
      expect(controller.hasSelection, isFalse);
    });

    test('Marquee window selection selects elements entirely inside', () {
      // Left-to-right: Window selection around (100, 100) and (200, 100)
      controller.startBoxSelection(const Offset(50, 50));
      controller.updateBoxSelection(const Offset(250, 150));
      expect(controller.isCrossingSelection, isFalse);

      controller.commitBoxSelection(
        network: network,
        projector: projector,
        currentElevationZ: 0,
      );

      expect(controller.selectedNodeIds, containsAll(['n1', 'n2']));
      expect(controller.selectedNodeIds, isNot(contains('n3')));
      expect(controller.selectedSegmentIds, contains('s1'));
    });

    test('Marquee crossing selection selects elements that cross the border', () {
      // Right-to-left: Crossing selection
      controller.startBoxSelection(const Offset(150, 150));
      controller.updateBoxSelection(const Offset(50, 50));
      expect(controller.isCrossingSelection, isTrue);

      controller.commitBoxSelection(
        network: network,
        projector: projector,
        currentElevationZ: 0,
      );

      // Box is [50..150, 50..150]. n1 (100, 100) is inside, n2 (200, 100) is outside, but s1 crosses!
      expect(controller.selectedNodeIds, contains('n1'));
      expect(controller.selectedSegmentIds, contains('s1'));
    });

    test('Shift and Ctrl modifiers work for selection updates', () {
      controller.selectedNodeIds.addAll(['n1', 'n2']);

      // Shift modifier removes items inside box
      controller.startBoxSelection(const Offset(50, 50), isShift: true);
      controller.updateBoxSelection(const Offset(150, 150));
      controller.commitBoxSelection(
        network: network,
        projector: projector,
        currentElevationZ: 0,
      );

      expect(controller.selectedNodeIds, isNot(contains('n1')));
      expect(controller.selectedNodeIds, contains('n2'));
    });
  });

  group('TracingController Tests', () {
    late TracingController controller;
    const projector = AxonometryProjector(
      projectionType: ProjectionType.topPlan2d,
      panOffset: Offset(0, 500),
      scale: 1.0,
    );

    setUp(() {
      controller = TracingController();
    });

    test('computeTraceDirection aligns with Ortho 90 horizontal axis', () {
      final start = Node3D(id: 'start', x: 0, y: 0, z: 0);
      // start projects to (0, 500). Cursor at (300, 500) -> dx = 300, dy = 0 -> dominant X
      final dir = controller.computeTraceDirection(
        startNode: start,
        projector: projector,
        currentElevationZ: 0,
        currentCursorScreenPos: const Offset(300, 500),
      );

      expect(dir.dirX, 1.0);
      expect(dir.dirY, 0.0);
      expect(dir.dirZ, 0.0);
    });

    test('computeTraceDirection aligns with Ortho 90 vertical axis', () {
      final start = Node3D(id: 'start', x: 0, y: 0, z: 0);
      // start projects to (0, 500). Cursor at (0, 200) -> screen Y is -300 -> CAD world Y is +300 -> dominant +Y
      final dir = controller.computeTraceDirection(
        startNode: start,
        projector: projector,
        currentElevationZ: 0,
        currentCursorScreenPos: const Offset(0, 200),
      );

      expect(dir.dirX, 0.0);
      expect(dir.dirY, 1.0);
      expect(dir.dirZ, 0.0);
    });

    test('calculateEndPoint respects explicit length and direction', () {
      final start = Node3D(id: 'start', x: 100, y: 200, z: 0);
      final end = controller.calculateEndPoint(
        startNode: start,
        lengthMm: 1500,
        projector: projector,
        currentElevationZ: 0,
        dirX: 0,
        dirY: 1,
        dirZ: 0,
      );

      expect(end.x, 100.0);
      expect(end.y, 1700.0);
      expect(end.z, 0.0);
    });
  });
}
