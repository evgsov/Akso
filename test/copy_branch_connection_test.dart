import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Copy Branch Connection Scenarios', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      controller = PipingInputController(initialNetwork: network);
    });

    tearDown(() {
      controller.dispose();
    });

    test('Scenario 1: Branch with internal tee - when copied, internal tee and sub-branches are preserved', () {
      network.nodes['b1'] = const Node3D(id: 'b1', x: 0, y: 0, z: 1000);
      network.nodes['b2'] = const Node3D(id: 'b2', x: 1000, y: 0, z: 1000);
      network.nodes['b3'] = const Node3D(id: 'b3', x: 2000, y: 0, z: 1000);
      network.nodes['b4'] = const Node3D(id: 'b4', x: 1000, y: 500, z: 1000);

      network.segments['seg_b1_b2'] = const PipeSegment(id: 'seg_b1_b2', startNodeId: 'b1', endNodeId: 'b2', systemId: 'sys1', dn: 50);
      network.segments['seg_b2_b3'] = const PipeSegment(id: 'seg_b2_b3', startNodeId: 'b2', endNodeId: 'b3', systemId: 'sys1', dn: 50);
      network.segments['seg_b2_b4'] = const PipeSegment(id: 'seg_b2_b4', startNodeId: 'b2', endNodeId: 'b4', systemId: 'sys1', dn: 32);

      network.autoDetectAllFittings();
      expect(network.fittings['b2']?.fittingType, equals(FittingType.tee));

      // Select all 3 segments of this branch assembly
      controller.selectedSegmentIds.addAll(['seg_b1_b2', 'seg_b2_b3', 'seg_b2_b4']);

      // Duplicate with offset dz: 2000 (copied to z = 3000)
      controller.duplicateSelection(dx: 0, dy: 0, dz: 2000);

      // Verify that the new assembly has 4 new nodes, 3 new segments, and the internal tee is preserved at the corresponding node
      expect(network.nodes.length, equals(8));
      expect(network.segments.length, equals(6));

      // Find the copied middle node (should be at x=1000, y=0, z=3000)
      final copiedMidNode = network.nodes.values.firstWhere(
        (n) => n.id != 'b2' && (n.x - 1000).abs() < 1 && (n.y - 0).abs() < 1 && (n.z - 3000).abs() < 1,
      );
      expect(network.getConnectedSegments(copiedMidNode.id).length, equals(3));
      expect(network.fittings[copiedMidNode.id]?.fittingType, equals(FittingType.tee));
    });

    test('Scenario 2: Copying a branch onto a main pipe - currently without auto-connect vs with auto-connect', () {
      // Main vertical pipe (riser): from (0, 0, 0) to (0, 0, 6000)
      network.nodes['r1'] = const Node3D(id: 'r1', x: 0, y: 0, z: 0);
      network.nodes['r2'] = const Node3D(id: 'r2', x: 0, y: 0, z: 6000);
      network.segments['seg_riser'] = const PipeSegment(id: 'seg_riser', startNodeId: 'r1', endNodeId: 'r2', systemId: 'sys1', dn: 100);

      // Branch 1 at z = 1000: from (0, 0, 1000) to (1500, 0, 1000)
      final splitNode = network.splitSegmentAtRatio('seg_riser', 1000 / 6000)!;

      network.nodes['b_end1'] = const Node3D(id: 'b_end1', x: 1500, y: 0, z: 1000);
      network.segments['seg_branch1'] = PipeSegment(id: 'seg_branch1', startNodeId: splitNode.id, endNodeId: 'b_end1', systemId: 'sys1', dn: 50);

      network.autoDetectAllFittings();
      expect(network.fittings[splitNode.id]?.fittingType, equals(FittingType.tee));

      // Now the user selects ONLY the branch: seg_branch1 (and its end node / junction node)
      controller.selectedSegmentIds.add('seg_branch1');

      // The user copies the branch 2000 mm up the riser (dz = 2000, so base lands at z = 3000)
      controller.duplicateSelection(dx: 0, dy: 0, dz: 2000);

      // Find the copied junction node at z = 3000
      final copiedJunction = network.nodes.values.firstWhere(
        (n) => (n.x - 0).abs() < 1 && (n.y - 0).abs() < 1 && (n.z - 3000).abs() < 1,
      );

      expect(network.getConnectedSegments(copiedJunction.id).length, equals(3));
      expect(network.fittings[copiedJunction.id]?.fittingType, equals(FittingType.tee));
    });

    test('Scenario 3: Copying a branch with useDirectBranch=true creates Direct Branch (Врезка У18)', () {
      controller.useDirectBranch = true;

      // Main horizontal pipe: from (0, 0, 0) to (5000, 0, 0)
      network.nodes['m1'] = const Node3D(id: 'm1', x: 0, y: 0, z: 0);
      network.nodes['m2'] = const Node3D(id: 'm2', x: 5000, y: 0, z: 0);
      network.segments['seg_main'] = const PipeSegment(id: 'seg_main', startNodeId: 'm1', endNodeId: 'm2', systemId: 'sys1', dn: 100);

      // Branch 1 at x = 1000: from (1000, 0, 0) to (1000, 1000, 0)
      final splitNode = network.splitSegmentAtRatio('seg_main', 1000 / 5000)!;
      network.nodes['b_end1'] = const Node3D(id: 'b_end1', x: 1000, y: 1000, z: 0);
      network.segments['seg_branch1'] = PipeSegment(id: 'seg_branch1', startNodeId: splitNode.id, endNodeId: 'b_end1', systemId: 'sys1', dn: 50);

      network.autoDetectAllFittings();
      expect(network.fittings[splitNode.id]?.fittingType, equals(FittingType.directBranch));

      // Select branch1
      controller.selectedSegmentIds.add('seg_branch1');

      // Duplicate branch along main pipe with dx = 1500 (so it lands at x = 2500 on seg_main_b)
      controller.duplicateSelection(dx: 1500, dy: 0, dz: 0);

      // Find the copied junction node at x = 2500
      final copiedJunction = network.nodes.values.firstWhere(
        (n) => (n.x - 2500).abs() < 1 && (n.y - 0).abs() < 1 && (n.z - 0).abs() < 1,
      );

      expect(network.getConnectedSegments(copiedJunction.id).length, equals(3));
      expect(network.fittings[copiedJunction.id]?.fittingType, equals(FittingType.directBranch));
    });

    test('Scenario 4: Copying branch into empty space leaves open ends without crashing or false connections', () {
      network.nodes['m1'] = const Node3D(id: 'm1', x: 0, y: 0, z: 0);
      network.nodes['m2'] = const Node3D(id: 'm2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'm1', endNodeId: 'm2', systemId: 'sys1', dn: 50);

      controller.selectedSegmentIds.add('seg1');

      // Copy with large offset into empty space
      controller.duplicateSelection(dx: 0, dy: 2000, dz: 1500);

      expect(network.segments.length, equals(2));
      expect(network.nodes.length, equals(4));

      // The new segment has 2 open nodes
      final newSeg = network.segments.values.firstWhere((s) => s.id != 'seg1');
      expect(network.getConnectedSegments(newSeg.startNodeId).length, equals(1));
      expect(network.getConnectedSegments(newSeg.endNodeId).length, equals(1));
      expect(network.fittings.containsKey(newSeg.startNodeId), isFalse);
      expect(network.fittings.containsKey(newSeg.endNodeId), isFalse);
    });
  });
}
