import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/painters/callout_painter.dart';
import 'package:akso/ui/features/editor/widgets/callout_manager_panel.dart';

PipingNetwork _buildSampleNetwork() {
  final network = PipingNetwork();
  network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
  network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
  network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 2000, z: 0);

  network.segments['seg1'] = const PipeSegment(
    id: 'seg1',
    startNodeId: 'n1',
    endNodeId: 'n2',
    outerDiameterMm: 89,
    systemId: 'sys1',
    dn: 80,
  );
  network.segments['seg2'] = const PipeSegment(
    id: 'seg2',
    startNodeId: 'n2',
    endNodeId: 'n3',
    outerDiameterMm: 89,
    systemId: 'sys1',
    dn: 80,
  );

  network.valves['v1'] = const Valve(
    id: 'v1',
    segmentId: 'seg1',
    ratio: 0.5,
    name: 'Задвижка',
    dn: 80,
    lengthMm: 150,
    valveType: ValveType.gateValve,
  );

  network.weldJoints['w1'] = const WeldJoint(
    id: 'w1',
    segmentId: 'seg1',
    ratio: 0.25,
    number: 1,
    stamp: 'С-01',
    isManual: true,
  );

  network.supports['sup1'] = const PipeSupport(
    id: 'sup1',
    segmentId: 'seg2',
    distanceRatio: 0.5,
    type: PipeSupportType.sliding,
    name: 'ОП-1',
  );

  network.callouts['c_pipe'] = const Callout(
    id: 'c_pipe',
    targetId: 'seg1',
    targetType: CalloutTargetType.segment,
    text: 'Ø89x4.0',
    screenOffsetX: 50,
    screenOffsetY: -40,
  );
  network.callouts['c_valve'] = const Callout(
    id: 'c_valve',
    targetId: 'v1',
    targetType: CalloutTargetType.valve,
    text: 'Задвижка DN80',
    screenOffsetX: 40,
    screenOffsetY: -40,
    isPinned: true,
  );
  network.callouts['c_weld'] = const Callout(
    id: 'c_weld',
    targetId: 'w1',
    targetType: CalloutTargetType.weld,
    text: 'Стык №1',
    screenOffsetX: -30,
    screenOffsetY: -30,
  );
  network.callouts['c_sup'] = const Callout(
    id: 'c_sup',
    targetId: 'sup1',
    targetType: CalloutTargetType.support,
    text: 'ОП-1',
    screenOffsetX: 25,
    screenOffsetY: 25,
  );
  network.callouts['c_elev'] = const Callout(
    id: 'c_elev',
    targetId: 'n1',
    targetType: CalloutTargetType.node,
    text: '+0.000',
    elevationStyle: ElevationMarkStyle.gostOutline,
  );

  return network;
}

void main() {
  group('Non-destructive 3D Callout Visibility & Individual Hiding', () {
    test('Hiding callouts in 3D Model Space preserves callouts on sheets and templates', () {
      final network = _buildSampleNetwork();
      final controller = PipingInputController(initialNetwork: network);
      final sheet = controller.addSheet();

      expect(controller.showCalloutsInModelSpace, isTrue);
      expect(controller.network.callouts.length, 5);

      // Hide all callouts in 3D Model Space
      controller.toggleShowCalloutsInModelSpace();
      expect(controller.showCalloutsInModelSpace, isFalse);

      // Callouts still exist in network and remain visible on DrawingSheet!
      expect(controller.network.callouts.length, 5);
      for (final c in controller.network.callouts.values) {
        expect(sheet.isCalloutVisible(c), isTrue);
      }

      // Hide specific category in 3D Model Space
      controller.setShowCalloutsInModelSpace(true);
      controller.toggleCalloutTypeVisibilityInModelSpace(CalloutTargetType.weld);
      expect(
        controller.hiddenCalloutTypes.contains(CalloutTargetType.weld),
        isTrue,
      );
      expect(sheet.isCalloutVisible(controller.network.callouts['c_weld']!), isTrue);

      controller.showAllCalloutTypesInModelSpace();
      expect(controller.hiddenCalloutTypes, isEmpty);

      controller.dispose();
    });

    test('Callout.isHidden serializes properly and hides individual callout without deleting it', () {
      final network = _buildSampleNetwork();
      final controller = PipingInputController(initialNetwork: network);
      final sheet = controller.addSheet();

      expect(controller.network.callouts['c_pipe']!.isHidden, isFalse);
      expect(sheet.isCalloutVisible(controller.network.callouts['c_pipe']!), isTrue);

      // Hide individual callout
      controller.toggleCalloutHidden('c_pipe');
      final hiddenCallout = controller.network.callouts['c_pipe']!;
      expect(hiddenCallout.isHidden, isTrue);
      expect(sheet.isCalloutVisible(hiddenCallout), isFalse);

      // Verify JSON round-trip preserves isHidden
      final json = hiddenCallout.toJson();
      final restored = Callout.fromJson(json);
      expect(restored.isHidden, isTrue);
      expect(restored, equals(hiddenCallout));

      // Unhide all hidden callouts
      final unhiddenCount = controller.unhideAllCallouts();
      expect(unhiddenCount, 1);
      expect(controller.network.callouts['c_pipe']!.isHidden, isFalse);

      controller.dispose();
    });

    test('CalloutPainter.hitTest skips hidden callouts and hidden 3D categories', () {
      final network = _buildSampleNetwork();
      final projector = AxonometryProjector(projectionType: ProjectionType.iso30);

      final boundsPipe = CalloutPainter.getCalloutBounds(
        network,
        projector,
        network.callouts['c_pipe']!,
      )!;
      final hitPos = boundsPipe.center;

      final hitNormal = CalloutPainter.hitTest(
        hitPos,
        network,
        projector,
      );
      expect(hitNormal, 'c_pipe');

      // When CalloutTargetType.segment is in hiddenTypes, hitTest skips c_pipe
      final hitWhenTypeHidden = CalloutPainter.hitTest(
        hitPos,
        network,
        projector,
        hiddenTypes: {CalloutTargetType.segment},
      );
      expect(hitWhenTypeHidden, isNot('c_pipe'));

      // When callout.isHidden is true, hitTest skips c_pipe
      network.callouts['c_pipe'] = network.callouts['c_pipe']!.copyWith(isHidden: true);
      final hitWhenIndividualHidden = CalloutPainter.hitTest(
        hitPos,
        network,
        projector,
      );
      expect(hitWhenIndividualHidden, isNot('c_pipe'));
    });
  });

  group('Group / Category Callout Deletion & Preset Safety', () {
    test('deleteCalloutsByTypes deletes only selected categories, respects keepPinned, and preserves presets & Undo', () {
      final network = _buildSampleNetwork();
      final controller = PipingInputController(initialNetwork: network);
      controller.updateCalloutTemplate('segment', 'PIPE: {DN}');
      final sheet = controller.addSheet();

      // Delete weld and valve with keepPinned: true (c_valve is pinned, so only c_weld is deleted)
      final removedCount = controller.deleteCalloutsByTypes(
        {CalloutTargetType.weld, CalloutTargetType.valve},
        keepPinned: true,
      );

      expect(removedCount, 1);
      expect(controller.network.callouts.containsKey('c_weld'), isFalse);
      expect(controller.network.callouts.containsKey('c_valve'), isTrue);
      expect(controller.network.callouts.containsKey('c_pipe'), isTrue);
      // Presets and sheets are untouched
      expect(controller.currentProject.calloutTemplates['segment'], equals('PIPE: {DN}'));
      expect(controller.sheets.any((s) => s.id == sheet.id), isTrue);

      // Undo restores c_weld
      controller.undo();
      expect(controller.network.callouts.containsKey('c_weld'), isTrue);

      // Delete with keepPinned: false removes both c_weld and pinned c_valve
      final removedBoth = controller.deleteCalloutsByTypes(
        {CalloutTargetType.weld, CalloutTargetType.valve},
        keepPinned: false,
      );
      expect(removedBoth, 2);
      expect(controller.network.callouts.containsKey('c_weld'), isFalse);
      expect(controller.network.callouts.containsKey('c_valve'), isFalse);

      controller.dispose();
    });

    test('deleteAllCallouts with keepPinned: true keeps pinned callouts and preserves templates', () {
      final network = _buildSampleNetwork();
      final controller = PipingInputController(initialNetwork: network);
      controller.updateCalloutTemplate('segment', 'CUSTOM_{DN}');
      final templateCountBefore = controller.currentProject.calloutTemplates.length;

      final deleted = controller.deleteAllCallouts(keepPinned: true);
      expect(deleted, 4); // 5 total minus 1 pinned (c_valve)
      expect(controller.network.callouts.keys.toList(), ['c_valve']);
      expect(controller.currentProject.calloutTemplates.length, templateCountBefore);
      expect(controller.currentProject.calloutTemplates['segment'], 'CUSTOM_{DN}');

      // Undo restores all 5 callouts
      controller.undo();
      expect(controller.network.callouts.length, 5);

      controller.dispose();
    });
  });

  group('CalloutManagerPanel UI for 3D Hiding and Group Deletion', () {
    testWidgets('CalloutManagerPanel toggles 3D visibility and opens group deletion dialog', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final network = _buildSampleNetwork();
      final controller = PipingInputController(initialNetwork: network);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalloutManagerPanel(controller: controller),
          ),
        ),
      );

      // 1. Toggle 3D visibility button inside CalloutManagerPanel
      final toggle3dBtn = find.byKey(const Key('toggle_3d_callouts_visibility_button'));
      expect(toggle3dBtn, findsOneWidget);
      expect(controller.showCalloutsInModelSpace, isTrue);

      await tester.tap(toggle3dBtn);
      await tester.pumpAndSettle();
      expect(controller.showCalloutsInModelSpace, isFalse);

      // 2. Open Group Delete dialog
      final groupDeleteBtn = find.byKey(const Key('open_batch_delete_callouts_dialog_button'));
      expect(groupDeleteBtn, findsOneWidget);

      await tester.tap(groupDeleteBtn);
      await tester.pumpAndSettle();

      expect(find.text('Групповое скрытие и удаление выносок'), findsOneWidget);

      // Select all categories in the dialog
      final selectAllBtn = find.byKey(const Key('batch_select_all_types_button'));
      expect(selectAllBtn, findsOneWidget);
      await tester.tap(selectAllBtn);
      await tester.pumpAndSettle();

      // Confirm deletion of selected categories (with keepPinned = true by default)
      final confirmBtn = find.byKey(const Key('confirm_batch_delete_callouts_button'));
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Pinned c_valve should still be preserved because keepPinned defaults to true
      expect(controller.network.callouts.containsKey('c_valve'), isTrue);
      expect(controller.network.callouts.length, 1);

      controller.dispose();
    });
  });

  group('Elbow Callout Anchor at Arc Midpoint', () {
    test('Elbow90 callout anchor is placed at the midpoint of the quadratic Bézier arc instead of the corner node', () {
      final network = _buildSampleNetwork();
      // Place a 90° elbow at node n2 (2000, 0, 0), connecting n1 (0, 0, 0) and n3 (2000, 2000, 0)
      const elbow = Fitting(
        id: 'fit_n2',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        dn: 80,
        radiusMm: 120.0,
      );
      network.fittings['n2'] = elbow;

      const elbowCallout = Callout(
        id: 'c_elbow',
        targetId: 'fit_n2',
        targetType: CalloutTargetType.fitting,
        text: 'Отвод 90° DN80',
      );
      network.callouts['c_elbow'] = elbowCallout;

      // For a 90° bend at (2000, 0, 0) with arms along -X (u1 = (-1, 0, 0)) and +Y (u2 = (0, 1, 0))
      // and tangent t = R * tan(90° / 2) = 120 * 1 = 120 mm:
      // B(0.5) = N + 0.25 * (u1 * t + u2 * t) = (2000 - 30, 0 + 30, 0) = (1970, 30, 0)
      final anchorPainter = CalloutPainter.getTarget3DPoint(network, elbowCallout);
      final anchorLayout = CalloutLayoutEngine.computeAnchorNode(elbowCallout, network);

      expect(anchorPainter, isNotNull);
      expect(anchorLayout, isNotNull);
      expect(anchorPainter!.x, closeTo(1970.0, 1e-3));
      expect(anchorPainter.y, closeTo(30.0, 1e-3));
      expect(anchorPainter.z, closeTo(0.0, 1e-3));

      expect(anchorLayout!.x, closeTo(1970.0, 1e-3));
      expect(anchorLayout.y, closeTo(30.0, 1e-3));
      expect(anchorLayout.z, closeTo(0.0, 1e-3));
    });
  });
}

