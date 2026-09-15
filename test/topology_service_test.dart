import 'package:flutter_test/flutter_test.dart';

import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/services/topology_service.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/enums/weld_type.dart';

void main() {
  group('TopologyService Tests', () {
    test('getConnectedSegments finds all connected segments for a node', () {
      final network = PipingNetwork();
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      const n3 = Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      const s1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50);
      const s2 = PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50);
      network.segments['s1'] = s1;
      network.segments['s2'] = s2;

      final connsN1 = TopologyService.getConnectedSegments(network, 'n1');
      expect(connsN1.length, 1);
      expect(connsN1.first.id, 's1');

      final connsN2 = TopologyService.getConnectedSegments(network, 'n2');
      expect(connsN2.length, 2);
      expect(connsN2.map((s) => s.id).toSet(), {'s1', 's2'});
    });

    test('identifyBranchSegment correctly differentiates run vs branch', () {
      final network = PipingNetwork();
      const nCenter = Node3D(id: 'nc', x: 1000, y: 1000, z: 0);
      const nLeft = Node3D(id: 'nL', x: 0, y: 1000, z: 0);
      const nRight = Node3D(id: 'nR', x: 2000, y: 1000, z: 0);
      const nBranch = Node3D(id: 'nB', x: 1000, y: 2000, z: 0);

      network.nodes['nc'] = nCenter;
      network.nodes['nL'] = nLeft;
      network.nodes['nR'] = nRight;
      network.nodes['nB'] = nBranch;

      // Магистраль идет по X от 0 до 2000 через узел nc.
      // Ответвление идет по Y от 1000 до 2000.
      const sRun1 = PipeSegment(id: 'sRun1', startNodeId: 'nL', endNodeId: 'nc', systemId: 'sys1', dn: 100);
      const sRun2 = PipeSegment(id: 'sRun2', startNodeId: 'nc', endNodeId: 'nR', systemId: 'sys1', dn: 100);
      const sBranch = PipeSegment(id: 'sBranch', startNodeId: 'nc', endNodeId: 'nB', systemId: 'sys1', dn: 50);

      network.segments['sRun1'] = sRun1;
      network.segments['sRun2'] = sRun2;
      network.segments['sBranch'] = sBranch;

      final branch = TopologyService.identifyBranchSegment(network, 'nc');
      expect(branch, isNotNull);
      expect(branch!.id, 'sBranch');
    });

    test('splitSegmentAtRatio divides segment and updates network', () {
      final network = PipingNetwork();
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;

      const seg = PipeSegment(id: 'segMain', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50);
      network.segments['segMain'] = seg;

      final midNode = TopologyService.splitSegmentAtRatio(
        network,
        'segMain',
        0.5,
        idGenerator: () => 'mid123',
      );

      expect(midNode, isNotNull);
      expect(midNode!.x, 500);
      expect(midNode.y, 0);
      expect(midNode.z, 0);

      expect(network.segments.containsKey('segMain'), isFalse);
      expect(network.segments.containsKey('segMain_a'), isTrue);
      expect(network.segments.containsKey('segMain_b'), isTrue);

      final segA = network.segments['segMain_a']!;
      expect(segA.startNodeId, 'n1');
      expect(segA.endNodeId, midNode.id);

      final segB = network.segments['segMain_b']!;
      expect(segB.startNodeId, midNode.id);
      expect(segB.endNodeId, 'n2');
    });

    test('findConnectedComponent traverses entire connected subnetwork', () {
      final network = PipingNetwork();
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 100, y: 0, z: 0);
      const n3 = Node3D(id: 'n3', x: 200, y: 0, z: 0);
      const nIsolated = Node3D(id: 'nIso', x: 5000, y: 5000, z: 0);

      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;
      network.nodes['nIso'] = nIsolated;

      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys', dn: 50);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys', dn: 50);

      final comp = TopologyService.findConnectedComponent(network, 'n1');
      expect(comp, {'n1', 'n2', 'n3'});
      expect(comp.contains('nIso'), isFalse);
    });

    test('areSegmentsCollinear checks parallelism of segments', () {
      final network = PipingNetwork();
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 100, y: 0, z: 0);
      const n3 = Node3D(id: 'n3', x: 200, y: 0, z: 0);
      const nUp = Node3D(id: 'nUp', x: 100, y: 100, z: 0);

      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;
      network.nodes['nUp'] = nUp;

      const s1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys', dn: 50);
      const s2 = PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys', dn: 50);
      const sOrthogonal = PipeSegment(id: 'sOrtho', startNodeId: 'n2', endNodeId: 'nUp', systemId: 'sys', dn: 50);

      expect(TopologyService.areSegmentsCollinear(network, s1, s2), isTrue);
      expect(TopologyService.areSegmentsCollinear(network, s1, sOrthogonal), isFalse);
    });

    test('dissolveNode merges two segments and transfers valves, supports, welds and callouts', () {
      final network = PipingNetwork();
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      const n3 = Node3D(id: 'n3', x: 3000, y: 0, z: 0);

      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      const s1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys', dn: 100);
      const s2 = PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys', dn: 100);
      network.segments['s1'] = s1;
      network.segments['s2'] = s2;

      // Арматура на s1 в середине (x = 500)
      network.valves['v1'] = const Valve(
        id: 'v1',
        name: 'Задвижка',
        segmentId: 's1',
        ratio: 0.5,
        lengthMm: 150,
        valveType: ValveType.gateValve,
        dn: 100,
      );

      // Опора на s2 в середине (x = 2000, расстояние от n1 = 2000)
      network.supports['sup1'] = const PipeSupport(
        id: 'sup1',
        segmentId: 's2',
        distanceRatio: 0.5,
        type: PipeSupportType.sliding,
      );

      // Стыковой шов на s1 на ratio 0.2 (x = 200)
      network.weldJoints['w1'] = const WeldJoint(
        id: 'w1',
        number: 1,
        stamp: 'W-01',
        segmentId: 's1',
        ratio: 0.2,
        weldType: WeldType.c17,
      );

      // Растворяем промежуточный узел n2
      final success = TopologyService.dissolveNode(network, 'n2');

      expect(success, isTrue);
      // Узел n2 удален
      expect(network.nodes.containsKey('n2'), isFalse);
      // Остался ровно один объединенный сегмент
      expect(network.segments.length, 1);

      final mergedSeg = network.segments.values.first;
      expect(mergedSeg.startNodeId, 'n1');
      expect(mergedSeg.endNodeId, 'n3');

      // Арматура перенеслась на объединенный сегмент:
      // x = 500 из 3000 -> ratio = 500 / 3000 = 1/6 ~= 0.1667
      final v1 = network.valves['v1'];
      expect(v1, isNotNull);
      expect(v1!.segmentId, mergedSeg.id);
      expect(v1.ratio, closeTo(500.0 / 3000.0, 0.01));

      // Опора перенеслась на объединенный сегмент:
      // x = 2000 из 3000 -> ratio = 2000 / 3000 = 2/3 ~= 0.6667
      final sup1 = network.supports['sup1'];
      expect(sup1, isNotNull);
      expect(sup1!.segmentId, mergedSeg.id);
      expect(sup1.distanceRatio, closeTo(2000.0 / 3000.0, 0.01));

      // Сварной шов: x = 200 из 3000 -> ratio = 200 / 3000 ~= 0.0667
      final w1 = network.weldJoints['w1'];
      expect(w1, isNotNull);
      expect(w1!.segmentId, mergedSeg.id);
      expect(w1.ratio, closeTo(200.0 / 3000.0, 0.01));
    });

    test('dissolveNode on tee node removes branch and merges mainline', () {
      final network = PipingNetwork();
      const nCenter = Node3D(id: 'nc', x: 1000, y: 1000, z: 0);
      const nLeft = Node3D(id: 'nL', x: 0, y: 1000, z: 0);
      const nRight = Node3D(id: 'nR', x: 2000, y: 1000, z: 0);
      const nBranch = Node3D(id: 'nB', x: 1000, y: 2000, z: 0);

      network.nodes['nc'] = nCenter;
      network.nodes['nL'] = nLeft;
      network.nodes['nR'] = nRight;
      network.nodes['nB'] = nBranch;

      const sRun1 = PipeSegment(id: 'sRun1', startNodeId: 'nL', endNodeId: 'nc', systemId: 'sys1', dn: 100);
      const sRun2 = PipeSegment(id: 'sRun2', startNodeId: 'nc', endNodeId: 'nR', systemId: 'sys1', dn: 100);
      const sBranch = PipeSegment(id: 'sBranch', startNodeId: 'nc', endNodeId: 'nB', systemId: 'sys1', dn: 50);

      network.segments['sRun1'] = sRun1;
      network.segments['sRun2'] = sRun2;
      network.segments['sBranch'] = sBranch;

      final success = TopologyService.dissolveNode(network, 'nc');

      expect(success, isTrue);
      expect(network.nodes.containsKey('nc'), isFalse);
      expect(network.segments.containsKey('sBranch'), isFalse);
      expect(network.segments.length, 1);

      final merged = network.segments.values.first;
      expect(merged.startNodeId, 'nL');
      expect(merged.endNodeId, 'nR');
    });

    test('dissolveNode on degree-1 end node deletes the segment and node', () {
      final network = PipingNetwork();
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);

      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;

      const s1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      network.segments['s1'] = s1;

      final success = TopologyService.dissolveNode(network, 'n2');

      expect(success, isTrue);
      expect(network.nodes.containsKey('n2'), isFalse);
      expect(network.nodes.containsKey('n1'), isTrue);
      expect(network.segments.isEmpty, isTrue);
    });
  });
}
