import 'package:flutter_test/flutter_test.dart';

import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/ui/canvas/painters/callout_painter.dart';

void main() {
  group('Callout Hit-Testing Precision & Closest-Match Tests', () {
    late PipingNetwork network;
    late AxonometryProjector projector;

    setUp(() {
      network = PipingNetwork();
      projector = AxonometryProjector(projectionType: ProjectionType.iso30);
    });

    test('Closest match selects target callout when two callouts are stacked closely', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 0);

      // Callout 1 (higher shelf)
      network.callouts['c1'] = const Callout(
        id: 'c1',
        targetId: 'n1',
        targetType: CalloutTargetType.node,
        screenOffsetX: 60,
        screenOffsetY: -40,
        textHeight: 12.0,
      );

      // Callout 2 (lower shelf, 15px below)
      network.callouts['c2'] = const Callout(
        id: 'c2',
        targetId: 'n2',
        targetType: CalloutTargetType.node,
        screenOffsetX: 60,
        screenOffsetY: -25,
        textHeight: 12.0,
      );

      final bounds2 = CalloutPainter.getCalloutBounds(network, projector, network.callouts['c2']!)!;
      // Click directly on Callout 2's text
      final clickPos = bounds2.center;

      final hitId = CalloutPainter.hitTest(
        clickPos,
        network,
        projector,
        hitTolerance: 12.0,
      );

      expect(hitId, equals('c2'));
    });

    test('Direct text hit takes priority over a nearby leader line of another callout', () {
      // Node A and Node B
      network.nodes['nA'] = const Node3D(id: 'nA', x: 0, y: 0, z: 0);
      network.nodes['nB'] = const Node3D(id: 'nB', x: 100, y: 100, z: 0);

      // Callout A text box
      network.callouts['cA'] = const Callout(
        id: 'cA',
        targetId: 'nA',
        targetType: CalloutTargetType.node,
        screenOffsetX: 50,
        screenOffsetY: -30,
        textHeight: 12.0,
      );

      final boundsA = CalloutPainter.getCalloutBounds(network, projector, network.callouts['cA']!)!;

      // Callout B with leader line crossing right next to boundsA
      final anchorB = projector.project(network.nodes['nB']!);
      final dX = boundsA.center.dx - anchorB.dx;
      final dY = boundsA.center.dy - anchorB.dy + 2.0; // 2px offset
      network.callouts['cB'] = Callout(
        id: 'cB',
        targetId: 'nB',
        targetType: CalloutTargetType.node,
        screenOffsetX: dX,
        screenOffsetY: dY,
        textHeight: 12.0,
      );

      // Click directly in center of Callout A's text
      final hitId = CalloutPainter.hitTest(
        boundsA.center,
        network,
        projector,
        hitTolerance: 12.0,
      );

      expect(hitId, equals('cA'), reason: 'Direct text hit on cA must beat proximity to cB leader line');
    });

    test('Selecting merged callout by clicking on any of its fork legs', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 50, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 100, y: 0, z: 0);

      // Merged callout pointing to n1, n2, n3
      network.callouts['merged'] = const Callout(
        id: 'merged',
        targetId: 'n1',
        targetType: CalloutTargetType.node,
        additionalTargetIds: ['n2', 'n3'],
        showQuantity: true,
        screenOffsetX: 40,
        screenOffsetY: -50,
        textHeight: 12.0,
      );

      final anchor2 = projector.project(network.nodes['n2']!);
      final anchor1 = projector.project(network.nodes['n1']!);
      final textPos = Offset(anchor1.dx + 40, anchor1.dy - 50);

      // Midpoint of fork leg connecting n2 to textPos
      final fork2Mid = Offset((anchor2.dx + textPos.dx) / 2.0, (anchor2.dy + textPos.dy) / 2.0);

      final hitId = CalloutPainter.hitTest(
        fork2Mid,
        network,
        projector,
        hitTolerance: 12.0,
      );

      expect(hitId, equals('merged'), reason: 'Clicking on fork leg 2 must select the merged callout');

      // Midpoint of fork leg connecting n3 to textPos
      final anchor3 = projector.project(network.nodes['n3']!);
      final fork3Mid = Offset((anchor3.dx + textPos.dx) / 2.0, (anchor3.dy + textPos.dy) / 2.0);

      final hitId3 = CalloutPainter.hitTest(
        fork3Mid,
        network,
        projector,
        hitTolerance: 12.0,
      );

      expect(hitId3, equals('merged'), reason: 'Clicking on fork leg 3 must select the merged callout');
    });

    test('Selecting merged callout by clicking on its shelf text', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 50, y: 0, z: 0);

      network.callouts['merged'] = const Callout(
        id: 'merged',
        targetId: 'n1',
        targetType: CalloutTargetType.node,
        additionalTargetIds: ['n2'],
        showQuantity: true,
        screenOffsetX: 50,
        screenOffsetY: -40,
        textHeight: 12.0,
      );

      final bounds = CalloutPainter.getCalloutBounds(network, projector, network.callouts['merged']!)!;
      expect(bounds, isNotNull);

      final hitId = CalloutPainter.hitTest(
        bounds.center,
        network,
        projector,
        hitTolerance: 12.0,
      );

      expect(hitId, equals('merged'));
    });

    test('DrawingSheet visibility filtering ignores hidden system callout', () {
      network.systems['s1'] = const PipingSystem(id: 's1', name: 'System 1', code: 'T1', colorValue: 0xFF0000FF, dxfAciColor: 1);
      network.systems['s2'] = const PipingSystem(id: 's2', name: 'System 2', code: 'T2', colorValue: 0xFFFF0000, dxfAciColor: 2);

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 100, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 100, z: 0);
      network.nodes['n4'] = const Node3D(id: 'n4', x: 100, y: 100, z: 0);

      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 's1');
      network.segments['seg2'] = const PipeSegment(id: 'seg2', startNodeId: 'n3', endNodeId: 'n4', systemId: 's2');

      network.callouts['c_visible'] = const Callout(
        id: 'c_visible',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
        screenOffsetX: 40,
        screenOffsetY: -40,
      );

      network.callouts['c_hidden'] = const Callout(
        id: 'c_hidden',
        targetId: 'seg2',
        targetType: CalloutTargetType.segment,
        screenOffsetX: 40,
        screenOffsetY: -40,
      );

      // Sheet only shows system s1
      final sheet = DrawingSheet(
        id: 'sheet1',
        name: 'Sheet 1',
        viewport: const SheetViewport(visibleSystemIds: {'s1'}),
      );

      final boundsHidden = CalloutPainter.getCalloutBounds(network, projector, network.callouts['c_hidden']!)!;

      // Click on hidden callout position with activeSheet filter
      final hitId = CalloutPainter.hitTest(
        boundsHidden.center,
        network,
        projector,
        hitTolerance: 12.0,
        activeSheet: sheet,
      );

      expect(hitId, isNull, reason: 'Callout on hidden system must not be hit-tested');
    });
  });
}
