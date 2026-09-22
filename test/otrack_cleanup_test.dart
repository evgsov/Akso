import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/acquired_tracking_point.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('OTRACK Tracking Point Cleanup Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;

      controller = PipingInputController(initialNetwork: network);
      controller.tracingController.isObjectTrackingEnabled = true;
    });

    tearDown(() {
      controller.dispose();
    });

    void addMockAcquiredPoint(Node3D node) {
      final screenPos = controller.projector.project(node);
      controller.tracingController.acquiredPoints.add(
        AcquiredTrackingPoint(
          worldPoint: node,
          screenPoint: screenPos,
          nodeId: node.id,
          acquiredAt: DateTime.now(),
        ),
      );
    }

    test('Switching to CanvasTool.select clears acquired tracking points', () {
      controller.setTool(CanvasTool.trace);
      addMockAcquiredPoint(network.nodes['n1']!);
      expect(controller.tracingController.acquiredPoints, isNotEmpty);

      controller.setTool(CanvasTool.select);
      expect(controller.tracingController.acquiredPoints, isEmpty);
    });

    test('cancelCurrentOperation clears acquired tracking points', () {
      controller.setTool(CanvasTool.trace);
      addMockAcquiredPoint(network.nodes['n1']!);
      expect(controller.tracingController.acquiredPoints, isNotEmpty);

      controller.cancelCurrentOperation();
      expect(controller.tracingController.acquiredPoints, isEmpty);
    });

    test('clearSelection clears acquired tracking points', () {
      addMockAcquiredPoint(network.nodes['n1']!);
      expect(controller.tracingController.acquiredPoints, isNotEmpty);

      controller.clearSelection();
      expect(controller.tracingController.acquiredPoints, isEmpty);
    });

    test('In CanvasTool.select, hovering over node does not acquire tracking points', () {
      controller.setTool(CanvasTool.select);
      final p1 = controller.projector.project(network.nodes['n1']!);

      controller.handlePointerMove(p1);

      expect(controller.tracingController.acquiredPoints, isEmpty);
    });

    test('Starting trace on an acquired node removes it from acquiredPoints', () {
      controller.setTool(CanvasTool.trace);
      addMockAcquiredPoint(network.nodes['n1']!);
      expect(controller.tracingController.acquiredPoints.length, 1);

      final p1 = controller.projector.project(network.nodes['n1']!);
      controller.handlePointerDown(p1);

      // Node n1 was clicked to start tracing, so it shouldn't remain as an acquired OTRACK point
      expect(
        controller.tracingController.acquiredPoints.any((pt) => pt.nodeId == 'n1'),
        isFalse,
      );
      expect(controller.traceStartNode?.id, 'n1');
    });

    test('Placing a trace segment clears acquired points', () {
      controller.setTool(CanvasTool.trace);
      final p1 = controller.projector.project(network.nodes['n1']!);
      controller.handlePointerDown(p1); // Start trace at n1

      // Mock an acquired tracking point during tracing
      addMockAcquiredPoint(network.nodes['n2']!);
      expect(controller.tracingController.acquiredPoints, isNotEmpty);

      // Click to complete segment at n2
      final p2 = controller.projector.project(network.nodes['n2']!);
      controller.handlePointerDown(p2);

      expect(controller.tracingController.acquiredPoints, isEmpty);
    });

    test('commitTraceWithLength clears acquired points', () {
      controller.setTool(CanvasTool.trace);
      final p1 = controller.projector.project(network.nodes['n1']!);
      controller.handlePointerDown(p1); // Start trace at n1

      addMockAcquiredPoint(network.nodes['n2']!);
      expect(controller.tracingController.acquiredPoints, isNotEmpty);

      controller.commitTraceWithLength(500, dirX: 1, dirY: 0, dirZ: 0);

      expect(controller.tracingController.acquiredPoints, isEmpty);
    });

    test('Pointer down in CanvasTool.select clears any acquired points', () {
      addMockAcquiredPoint(network.nodes['n1']!);
      controller.setTool(CanvasTool.select);

      final p = const Offset(50, 50);
      controller.handlePointerDown(p);

      expect(controller.tracingController.acquiredPoints, isEmpty);
    });
  });
}
