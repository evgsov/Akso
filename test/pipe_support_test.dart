import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('PipeSupport Model Tests', () {
    test('calculatePosition correctly computes 3D position along nodes', () {
      const start = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const end = Node3D(id: 'n2', x: 1000, y: 2000, z: 3000);

      const support = PipeSupport(
        id: 'sup1',
        segmentId: 'seg1',
        distanceRatio: 0.25,
        type: PipeSupportType.sliding,
        name: 'ОП-1',
      );

      final pos = support.calculatePosition(start, end);
      expect(pos.x, closeTo(250.0, 0.001));
      expect(pos.y, closeTo(500.0, 0.001));
      expect(pos.z, closeTo(750.0, 0.001));
    });

    test('calculatePosition clamps distanceRatio between 0.0 and 1.0', () {
      const start = Node3D(id: 'n1', x: 100, y: 100, z: 100);
      const end = Node3D(id: 'n2', x: 200, y: 200, z: 200);

      const supUnder = PipeSupport(
        id: 's_under',
        segmentId: 'seg1',
        distanceRatio: -0.5,
      );
      final posUnder = supUnder.calculatePosition(start, end);
      expect(posUnder.x, closeTo(100.0, 0.001));

      const supOver = PipeSupport(
        id: 's_over',
        segmentId: 'seg1',
        distanceRatio: 1.5,
      );
      final posOver = supOver.calculatePosition(start, end);
      expect(posOver.x, closeTo(200.0, 0.001));
    });

    test('toJson and fromJson round-trip', () {
      const support = PipeSupport(
        id: 'sup_fixed',
        segmentId: 'seg_main',
        distanceRatio: 0.65,
        type: PipeSupportType.fixed,
        name: 'НО-1',
      );

      final json = support.toJson();
      final restored = PipeSupport.fromJson(json);

      expect(restored.id, equals(support.id));
      expect(restored.segmentId, equals(support.segmentId));
      expect(restored.distanceRatio, closeTo(0.65, 0.001));
      expect(restored.type, equals(PipeSupportType.fixed));
      expect(restored.name, equals('НО-1'));
      expect(restored, equals(support));
    });

    test('copyWith updates specified fields', () {
      const support = PipeSupport(
        id: 'sup1',
        segmentId: 'seg1',
        distanceRatio: 0.3,
        type: PipeSupportType.sliding,
        name: 'ОП-1',
      );

      final updated = support.copyWith(
        distanceRatio: 0.8,
        type: PipeSupportType.spring,
        name: 'ПП-1',
      );

      expect(updated.id, 'sup1');
      expect(updated.segmentId, 'seg1');
      expect(updated.distanceRatio, 0.8);
      expect(updated.type, PipeSupportType.spring);
      expect(updated.name, 'ПП-1');
    });
  });

  group('PipingNetwork Support Management Tests', () {
    late PipingNetwork network;
    const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
    const n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
    const seg = PipeSegment(
      id: 'seg1',
      startNodeId: 'n1',
      endNodeId: 'n2',
      dn: 100,
      systemId: 'sys1',
    );

    setUp(() {
      network = PipingNetwork(
        nodes: {'n1': n1, 'n2': n2},
        segments: {'seg1': seg},
      );
    });

    test('addSupport adds support to network with correct defaults', () {
      final sup = network.addSupport(
        segmentId: 'seg1',
        distanceRatio: 0.5,
        type: PipeSupportType.sliding,
      );

      expect(network.supports.containsKey(sup.id), isTrue);
      expect(sup.segmentId, 'seg1');
      expect(sup.distanceRatio, 0.5);
      expect(sup.type, PipeSupportType.sliding);
      expect(sup.name, startsWith('ОП-'));
    });

    test('support automatically follows pipe when nodes move', () {
      final sup = network.addSupport(
        segmentId: 'seg1',
        distanceRatio: 0.5,
        type: PipeSupportType.fixed,
      );

      var pos = sup.calculatePosition(network.nodes['n1']!, network.nodes['n2']!);
      expect(pos.x, closeTo(1000.0, 0.001));
      expect(pos.y, closeTo(0.0, 0.001));

      // Stretch pipe: move n2 from 2000 to 4000
      network.nodes['n2'] = const Node3D(id: 'n2', x: 4000, y: 0, z: 0);
      pos = sup.calculatePosition(network.nodes['n1']!, network.nodes['n2']!);
      expect(pos.x, closeTo(2000.0, 0.001));

      // Shift entire pipe up along Y by 500
      network.shiftSegment('seg1', 0, 500, 0);
      pos = sup.calculatePosition(network.nodes['n1']!, network.nodes['n2']!);
      expect(pos.x, closeTo(2000.0, 0.001));
      expect(pos.y, closeTo(500.0, 0.001));
    });

    test('splitSegmentAtRatio redistributes supports and conserves 3D coordinates', () {
      // Place support 1 at 20% (x = 400)
      final s1 = network.addSupport(
        segmentId: 'seg1',
        distanceRatio: 0.2,
        type: PipeSupportType.fixed,
        name: 'НО-1',
      );

      // Place support 2 at 80% (x = 1600)
      final s2 = network.addSupport(
        segmentId: 'seg1',
        distanceRatio: 0.8,
        type: PipeSupportType.guide,
        name: 'ОН-1',
      );

      final pos1Before = s1.calculatePosition(network.nodes['n1']!, network.nodes['n2']!);
      final pos2Before = s2.calculatePosition(network.nodes['n1']!, network.nodes['n2']!);

      // Split segment at 50% (x = 1000)
      final midNode = network.splitSegmentAtRatio('seg1', 0.5);
      expect(midNode, isNotNull);

      // Segments should be seg1_a (0..1000) and seg1_b (1000..2000)
      expect(network.segments.containsKey('seg1_a'), isTrue);
      expect(network.segments.containsKey('seg1_b'), isTrue);

      final updatedS1 = network.supports[s1.id]!;
      final updatedS2 = network.supports[s2.id]!;

      // s1 was at 0.2, split at 0.5 -> new ratio = 0.2 / 0.5 = 0.4 on seg1_a
      expect(updatedS1.segmentId, 'seg1_a');
      expect(updatedS1.distanceRatio, closeTo(0.4, 0.001));

      // s2 was at 0.8, split at 0.5 -> new ratio = (0.8 - 0.5) / 0.5 = 0.6 on seg1_b
      expect(updatedS2.segmentId, 'seg1_b');
      expect(updatedS2.distanceRatio, closeTo(0.6, 0.001));

      // Check 3D positions are conserved!
      final segA = network.segments['seg1_a']!;
      final segB = network.segments['seg1_b']!;
      final pos1After = updatedS1.calculatePosition(
        network.nodes[segA.startNodeId]!,
        network.nodes[segA.endNodeId]!,
      );
      final pos2After = updatedS2.calculatePosition(
        network.nodes[segB.startNodeId]!,
        network.nodes[segB.endNodeId]!,
      );

      expect(pos1After.x, closeTo(pos1Before.x, 0.001));
      expect(pos1After.y, closeTo(pos1Before.y, 0.001));
      expect(pos1After.z, closeTo(pos1Before.z, 0.001));

      expect(pos2After.x, closeTo(pos2Before.x, 0.001));
      expect(pos2After.y, closeTo(pos2Before.y, 0.001));
      expect(pos2After.z, closeTo(pos2Before.z, 0.001));
    });

    test('removeSupport removes support from network', () {
      final sup = network.addSupport(segmentId: 'seg1', distanceRatio: 0.5);
      expect(network.supports.containsKey(sup.id), isTrue);

      network.removeSupport(sup.id);
      expect(network.supports.containsKey(sup.id), isFalse);
    });

    test('clone copies supports map correctly', () {
      network.addSupport(segmentId: 'seg1', distanceRatio: 0.3, type: PipeSupportType.spring);
      final copy = network.clone();

      expect(copy.supports.length, equals(1));
      expect(copy.supports.values.first.type, equals(PipeSupportType.spring));

      // Modifying copy should not mutate original
      copy.supports.clear();
      expect(copy.supports.isEmpty, isTrue);
      expect(network.supports.length, equals(1));
    });

    test('toJson and fromJson network serialization preserves supports', () {
      network.addSupport(
        segmentId: 'seg1',
        distanceRatio: 0.75,
        type: PipeSupportType.spring,
        name: 'ПП-5',
      );

      final json = network.toJson();
      final restored = PipingNetwork.fromJson(json);

      expect(restored.supports.length, equals(1));
      final sup = restored.supports.values.first;
      expect(sup.segmentId, 'seg1');
      expect(sup.distanceRatio, closeTo(0.75, 0.001));
      expect(sup.type, PipeSupportType.spring);
      expect(sup.name, 'ПП-5');
    });
  });
}
