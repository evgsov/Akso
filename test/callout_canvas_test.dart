import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/painters/callout_painter.dart';
import 'package:akso/ui/canvas/piping_canvas.dart';

void main() {
  const projector = AxonometryProjector(
    projectionType: ProjectionType.gostFrontal45,
  );

  group('CalloutPainter Target 3D Anchor Calculation Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 2000, z: 400);
      network.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
      network.valves['v1'] = const Valve(
        id: 'v1',
        segmentId: 's1',
        ratio: 0.25,
        valveType: ValveType.gateValve,
        name: 'Задвижка',
        dn: 100,
        lengthMm: 200,
      );
      network.weldJoints['w1'] = const WeldJoint(
        id: 'w1',
        segmentId: 's1',
        ratio: 0.8,
        number: 5,
        stamp: 'СВ-5',
      );
      network.supports['sup1'] = const PipeSupport(
        id: 'sup1',
        segmentId: 's1',
        distanceRatio: 0.6,
        type: PipeSupportType.sliding,
        name: 'ОПБ2',
      );
      network.equipments['eq1'] = Equipment(
        id: 'eq1',
        name: 'Насос',
        type: EquipmentType.box,
        x: 500,
        y: 600,
        z: 100,
        width: 400,
        length: 800,
        height: 600,
      );
    });

    test('Computes anchor for Node correctly', () {
      const callout = Callout(
        id: 'c_node',
        targetId: 'n2',
        targetType: CalloutTargetType.node,
      );
      final anchor = CalloutPainter.getTarget3DPoint(network, callout);
      expect(anchor, isNotNull);
      expect(anchor!.x, equals(1000));
      expect(anchor.y, equals(2000));
      expect(anchor.z, equals(400));
    });

    test('Computes anchor for Segment as exact midpoint', () {
      const callout = Callout(
        id: 'c_seg',
        targetId: 's1',
        targetType: CalloutTargetType.segment,
      );
      final anchor = CalloutPainter.getTarget3DPoint(network, callout);
      expect(anchor, isNotNull);
      expect(anchor!.x, equals(500));
      expect(anchor.y, equals(1000));
      expect(anchor.z, equals(200));
    });

    test('Computes anchor for Valve at specified ratio', () {
      const callout = Callout(
        id: 'c_valve',
        targetId: 'v1',
        targetType: CalloutTargetType.valve,
      );
      final anchor = CalloutPainter.getTarget3DPoint(network, callout);
      expect(anchor, isNotNull);
      // ratio = 0.25 -> 0 + 1000*0.25 = 250, 0 + 2000*0.25 = 500, 0 + 400*0.25 = 100
      expect(anchor!.x, equals(250));
      expect(anchor.y, equals(500));
      expect(anchor.z, equals(100));
    });

    test('Computes anchor for WeldJoint at specified ratio', () {
      const callout = Callout(
        id: 'c_weld',
        targetId: 'w1',
        targetType: CalloutTargetType.weld,
      );
      final anchor = CalloutPainter.getTarget3DPoint(network, callout);
      expect(anchor, isNotNull);
      // ratio = 0.8 -> 800, 1600, 320
      expect(anchor!.x, equals(800));
      expect(anchor.y, equals(1600));
      expect(anchor.z, equals(320));
    });

    test('Computes anchor for Support at distanceRatio', () {
      const callout = Callout(
        id: 'c_sup',
        targetId: 'sup1',
        targetType: CalloutTargetType.support,
      );
      final anchor = CalloutPainter.getTarget3DPoint(network, callout);
      expect(anchor, isNotNull);
      // ratio = 0.6 -> 600, 1200, 240
      expect(anchor!.x, equals(600));
      expect(anchor.y, equals(1200));
      expect(anchor.z, equals(240));
    });

    test('Computes anchor for Equipment at z + height/2', () {
      const callout = Callout(
        id: 'c_eq',
        targetId: 'eq1',
        targetType: CalloutTargetType.equipment,
      );
      final anchor = CalloutPainter.getTarget3DPoint(network, callout);
      expect(anchor, isNotNull);
      expect(anchor!.x, equals(500));
      expect(anchor.y, equals(600));
      // z (100) + height (600) / 2 = 400
      expect(anchor.z, equals(400));
    });

    test('Returns null if target not found', () {
      const callout = Callout(
        id: 'c_missing',
        targetId: 'non_existing',
        targetType: CalloutTargetType.segment,
      );
      final anchor = CalloutPainter.getTarget3DPoint(network, callout);
      expect(anchor, isNull);
    });
  });

  group('CalloutPainter Hit-Test & Bounds Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
        outerDiameterMm: 108.0,
        wallThicknessMm: 4.0,
        material: 'Сталь 20',
      );
      network.callouts['callout_1'] = const Callout(
        id: 'callout_1',
        targetId: 's1',
        targetType: CalloutTargetType.segment,
        screenOffsetX: 50.0,
        screenOffsetY: -50.0,
        textHeight: 12.0,
      );
    });

    test('Calculates valid bounding rectangle for callout', () {
      final callout = network.callouts['callout_1']!;
      final bounds = CalloutPainter.getCalloutBounds(network, projector, callout);
      expect(bounds, isNotNull);

      // Anchor screen position
      final anchor = CalloutPainter.getTarget3DPoint(network, callout)!;
      final anchorScreen = projector.project(anchor);
      final textPos = anchorScreen + const Offset(50.0, -50.0);

      expect(bounds!.left, closeTo(textPos.dx, 1.0));
      expect(bounds.bottom, greaterThan(bounds.top));
    });

    test('hitTest detects point inside callout text area', () {
      final callout = network.callouts['callout_1']!;
      final bounds = CalloutPainter.getCalloutBounds(network, projector, callout)!;
      final centerPoint = bounds.center;

      final hitId = CalloutPainter.hitTest(centerPoint, network, projector);
      expect(hitId, equals('callout_1'));
    });

    test('hitTest returns null for distant point', () {
      final distantPoint = const Offset(99999.0, 99999.0);
      final hitId = CalloutPainter.hitTest(distantPoint, network, projector);
      expect(hitId, isNull);
    });

    test('Calculates left shelf bounds for negative screenOffsetX', () {
      network.callouts['callout_left'] = const Callout(
        id: 'callout_left',
        targetId: 's1',
        targetType: CalloutTargetType.segment,
        screenOffsetX: -60.0,
        screenOffsetY: -40.0,
        textHeight: 12.0,
      );
      final callout = network.callouts['callout_left']!;
      final bounds = CalloutPainter.getCalloutBounds(network, projector, callout);
      expect(bounds, isNotNull);

      final anchor = CalloutPainter.getTarget3DPoint(network, callout)!;
      final anchorScreen = projector.project(anchor);
      final textPos = anchorScreen + const Offset(-60.0, -40.0);

      // In left mode, rect is to the left of textPos.dx
      expect(bounds!.right, closeTo(textPos.dx, 1.0));
    });
  });

  group('PipingCanvasPainter Callout Painting Tests', () {
    test('Paints network with callouts and selectedCalloutId without throwing', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 80,
      );
      network.callouts['c1'] = const Callout(
        id: 'c1',
        targetId: 's1',
        targetType: CalloutTargetType.segment,
        screenOffsetX: 40.0,
        screenOffsetY: -40.0,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      final painter = PipingCanvasPainter(
        network: network,
        projector: projector,
        selectedCalloutId: 'c1',
        showCallouts: true,
      );

      expect(() => painter.paint(canvas, const Size(800, 600)), returnsNormally);
      final picture = recorder.endRecording();
      picture.dispose();
    });
  });

  group('PipingInputController Callout Interaction & Dragging Tests', () {
    late PipingInputController controller;

    setUp(() {
      controller = PipingInputController(projector: projector);
      final net = controller.network;
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
        outerDiameterMm: 108.0,
        wallThicknessMm: 4.0,
      );
      net.callouts['c1'] = const Callout(
        id: 'c1',
        targetId: 's1',
        targetType: CalloutTargetType.segment,
        screenOffsetX: 50.0,
        screenOffsetY: -50.0,
      );
      controller.history.recordState(net);
    });

    test('Clicking on callout text in select mode selects it and begins drag', () {
      controller.currentTool = CanvasTool.select;

      final callout = controller.network.callouts['c1']!;
      final bounds = CalloutPainter.getCalloutBounds(
        controller.network,
        projector,
        callout,
        templates: controller.currentProject.calloutTemplates,
      )!;

      // Pointer down inside callout text bounds
      controller.handlePointerDown(bounds.center);

      expect(controller.selectedCalloutId, equals('c1'));
      expect(controller.isDraggingCallout, isTrue);
      expect(controller.selectedNodeId, isNull);
      expect(controller.selectedSegmentId, isNull);
      expect(controller.selectedEquipmentId, isNull);
    });

    test('Dragging callout text dynamically updates screenOffsetX and screenOffsetY', () {
      controller.currentTool = CanvasTool.select;

      final callout = controller.network.callouts['c1']!;
      final bounds = CalloutPainter.getCalloutBounds(
        controller.network,
        projector,
        callout,
        templates: controller.currentProject.calloutTemplates,
      )!;

      final startPos = bounds.center;
      controller.handlePointerDown(startPos);

      // Drag 30px right and 20px down
      final dragPos = startPos + const Offset(30.0, 20.0);
      controller.handlePointerMove(dragPos);

      final updatedCallout = controller.network.callouts['c1']!;
      expect(updatedCallout.screenOffsetX, closeTo(50.0 + 30.0, 0.1));
      expect(updatedCallout.screenOffsetY, closeTo(-50.0 + 20.0, 0.1));

      // Pointer up completes drag and commits to history
      controller.handlePointerUp();
      expect(controller.isDraggingCallout, isFalse);

      // Verify undo restores previous offset
      controller.history.undo(controller.network);
      final restored = controller.network.callouts['c1']!;
      expect(restored.screenOffsetX, closeTo(50.0, 0.1));
      expect(restored.screenOffsetY, closeTo(-50.0, 0.1));
    });

    test('deleteSelected removes selected callout and records undo state', () {
      controller.selectCallout('c1');
      expect(controller.selectedCalloutId, equals('c1'));

      controller.deleteSelected();
      expect(controller.network.callouts.containsKey('c1'), isFalse);
      expect(controller.selectedCalloutId, isNull);

      // Undo restores deleted callout
      controller.history.undo(controller.network);
      expect(controller.network.callouts.containsKey('c1'), isTrue);
    });

    test('cancelCurrentOperation resets callout selection and dragging', () {
      controller.selectCallout('c1');
      controller.isDraggingCallout = true;

      controller.cancelCurrentOperation();
      expect(controller.selectedCalloutId, isNull);
      expect(controller.isDraggingCallout, isFalse);
    });
  });

  group('Collision Avoidance in generateMissingCallouts Tests', () {
    test('Automatically offsets multiple callouts on the same segment to prevent text overlap', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
      network.valves['v1'] = const Valve(
        id: 'v1',
        segmentId: 's1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Задвижка ЗКЛ',
        dn: 100,
        lengthMm: 200,
      );
      network.weldJoints['w1'] = const WeldJoint(
        id: 'w1',
        segmentId: 's1',
        ratio: 0.2,
        number: 1,
        stamp: 'СВ-1',
      );

      final added = network.generateMissingCallouts(offsetX: 50.0, offsetY: -50.0);
      expect(added, equals(3));

      // Retrieve the generated callouts
      final segCallout = network.callouts.values.firstWhere((c) => c.targetType == CalloutTargetType.segment);
      final valveCallout = network.callouts.values.firstWhere((c) => c.targetType == CalloutTargetType.valve);
      final weldCallout = network.callouts.values.firstWhere((c) => c.targetType == CalloutTargetType.weld);

      expect(segCallout.screenOffsetY, equals(-50.0));
      // Second and third callouts on the same segment must have stepped screenOffsetY to avoid collision
      expect(valveCallout.screenOffsetY, greaterThan(segCallout.screenOffsetY));
      expect(weldCallout.screenOffsetY, greaterThan(valveCallout.screenOffsetY));

      // Each step must be at least the text height (12.0)
      expect(valveCallout.screenOffsetY - segCallout.screenOffsetY, greaterThanOrEqualTo(12.0));
      expect(weldCallout.screenOffsetY - valveCallout.screenOffsetY, greaterThanOrEqualTo(12.0));
    });
  });
}
