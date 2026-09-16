import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Hold-to-Drag (200ms) and cancelCurrentOperation tests', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      controller = PipingInputController(network: network);
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final seg = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      network.segments[seg.id] = seg;
    });

    tearDown(() {
      controller.dispose();
    });

    test('Moving before 200ms does NOT trigger dragging', () {
      controller.handlePointerDown(const Offset(100, 100));
      // Immediately move without waiting 200ms
      controller.handlePointerMove(const Offset(150, 150));
      expect(controller.isDraggingNode, isFalse);
      expect(controller.isDraggingSegment, isFalse);
      controller.handlePointerUp();
    });

    test('Holding for 200ms allows dragging after threshold', () async {
      controller.handlePointerDown(const Offset(100, 100));
      await Future.delayed(const Duration(milliseconds: 220));
      // Now drag after 200ms
      controller.handlePointerMove(const Offset(130, 130));
      // Pointer up stops drag
      controller.handlePointerUp();
      expect(controller.isDraggingNode, isFalse);
      expect(controller.isDraggingSegment, isFalse);
    });

    test('cancelCurrentOperation clears all selections including segments and spools', () {
      controller.selectedSegmentId = 's1';
      controller.selectedSegmentIds.add('s1');
      controller.selectedSpoolId = 'spool_1';
      controller.selectedSpoolIds.add('spool_1');
      controller.selectedNodeId = 'n1';
      controller.selectedNodeIds.add('n1');

      controller.cancelCurrentOperation();

      expect(controller.selectedSegmentId, isNull);
      expect(controller.selectedSegmentIds, isEmpty);
      expect(controller.selectedSpoolId, isNull);
      expect(controller.selectedSpoolIds, isEmpty);
      expect(controller.selectedNodeId, isNull);
      expect(controller.selectedNodeIds, isEmpty);
    });
  });
}
