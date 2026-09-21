import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/core/math/axonometry_projector.dart';

void main() {
  group('CalloutObstacleMap', () {
    test('detects shelf overlap with existing callout rects', () {
      final map = CalloutObstacleMap();
      map.addRect(const Rect.fromLTWH(100, 100, 80, 20));

      // Overlapping rect
      expect(map.testShelfCollision(const Rect.fromLTWH(120, 110, 80, 20)), isTrue);
      // Disjoint rect
      expect(map.testShelfCollision(const Rect.fromLTWH(250, 100, 80, 20)), isFalse);
    });

    test('detects shelf collision with pipe corridor', () {
      final map = CalloutObstacleMap();
      map.addPipe(const Offset(0, 50), const Offset(200, 50), 10.0);

      // Shelf intersecting pipe
      expect(map.testShelfCollision(const Rect.fromLTWH(50, 45, 60, 20)), isTrue);
      // Shelf clearly outside pipe corridor
      expect(map.testShelfCollision(const Rect.fromLTWH(50, 80, 60, 20)), isFalse);
    });

    test('counts leader line intersections with pipes and other leader lines', () {
      final map = CalloutObstacleMap();
      // Pipe across Y=100
      map.addPipe(const Offset(0, 100), const Offset(200, 100), 5.0);

      // Leader crossing the pipe
      final count1 = map.countLeaderLineIntersections(const Offset(50, 50), const Offset(50, 150));
      expect(count1, equals(1));

      // Leader not crossing the pipe
      final count2 = map.countLeaderLineIntersections(const Offset(50, 110), const Offset(50, 150));
      expect(count2, equals(0));
    });
  });

  group('CalloutLayoutEngine', () {
    test('findBestCandidate avoids obstacles and chooses clear quadrant', () {
      final map = CalloutObstacleMap();
      // Block top-right quadrant with a pipe and obstacle
      map.addRect(const Rect.fromLTWH(110, 80, 100, 40));
      map.addPipe(const Offset(100, 100), const Offset(200, 50), 8.0);

      const anchor = Offset(100, 100);
      const textWidth = 60.0;
      const textHeight = 12.0;

      final best = CalloutLayoutEngine.evaluateBestOffset(
        anchor: anchor,
        textWidth: textWidth,
        textHeight: textHeight,
        obstacleMap: map,
      );

      expect(best, isNotNull);
      // The chosen shelf rect must not collide with the obstacle
      final chosenBounds = Rect.fromLTWH(
        anchor.dx + best!.dx,
        anchor.dy + best.dy - textHeight - 4.0,
        textWidth + 10.0,
        textHeight + 8.0,
      );
      expect(map.testShelfCollision(chosenBounds), isFalse);
    });

    test('calculateLayout aligns parallel pipe callouts into a stacked column', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 5000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 500, z: 0);
      network.nodes['n4'] = const Node3D(id: 'n4', x: 5000, y: 500, z: 0);
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', outerDiameterMm: 108, systemId: 'sys1', dn: 100);
      network.segments['seg2'] = const PipeSegment(id: 'seg2', startNodeId: 'n3', endNodeId: 'n4', outerDiameterMm: 108, systemId: 'sys1', dn: 100);

      final c1 = Callout(id: 'c1', targetId: 'seg1', targetType: CalloutTargetType.segment);
      final c2 = Callout(id: 'c2', targetId: 'seg2', targetType: CalloutTargetType.segment);
      network.callouts[c1.id] = c1;
      network.callouts[c2.id] = c2;

      const projector = AxonometryProjector();
      final offsets = CalloutLayoutEngine.calculateLayout(
        network: network,
        projector: projector,
      );

      expect(offsets.containsKey('c1'), isTrue);
      expect(offsets.containsKey('c2'), isTrue);

      final off1 = offsets['c1']!;
      final off2 = offsets['c2']!;

      // They should not have identical offsets and their shelves must not collide
      expect((off1.dy - off2.dy).abs() >= 16.0 || (off1.dx - off2.dx).abs() >= 40.0, isTrue);
    });

    test('calculateLayout respects isPinned callouts and does not alter their offsets', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.segments['seg'] = const PipeSegment(id: 'seg', startNodeId: 'n1', endNodeId: 'n2', outerDiameterMm: 89, systemId: 'sys1', dn: 80);
      const customOffset = Offset(123.0, -88.0);
      final pinnedCallout = Callout(
        id: 'cp',
        targetId: 'seg',
        targetType: CalloutTargetType.segment,
        screenOffsetX: customOffset.dx,
        screenOffsetY: customOffset.dy,
        isPinned: true,
      );
      network.callouts[pinnedCallout.id] = pinnedCallout;

      final offsets = CalloutLayoutEngine.calculateLayout(
        network: network,
        projector: const AxonometryProjector(),
        onlyUnpinned: true,
      );

      expect(offsets['cp'], equals(customOffset));
    });
  });
}



