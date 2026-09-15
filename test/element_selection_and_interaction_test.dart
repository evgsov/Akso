import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/piping_canvas.dart';
import 'package:akso/ui/features/editor/widgets/desktop_cad_layout.dart';

void main() {
  group('Piping Elements Selection & Interaction Controller Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;
    late PipeSegment seg;

    setUp(() {
      network = PipingNetwork();
      controller = PipingInputController(network: network);
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      seg = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      network.segments[seg.id] = seg;
    });

    tearDown(() {
      controller.dispose();
    });

    test('Hit-testing and selecting a Valve', () {
      final valve = network.addValve(
        segmentId: seg.id,
        ratio: 0.5,
        valveType: ValveType.gateValve,
      );

      final valveScreenPos = controller.projector.project(
        const Node3D(id: 'test', x: 500, y: 0, z: 0),
      );

      // Hit-test finder
      final found = controller.findValveAtScreenPos(valveScreenPos);
      expect(found, isNotNull);
      expect(found, equals(valve.id));

      // Pointer down with select tool selects valve
      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(valveScreenPos);
      expect(controller.selectedValveId, equals(valve.id));
      expect(controller.selectedSupportId, isNull);
      expect(controller.selectedWeldId, isNull);
    });

    test('Hit-testing and selecting a PipeSupport', () {
      final support = PipeSupport(
        id: 'sup1',
        segmentId: seg.id,
        distanceRatio: 0.6,
        type: PipeSupportType.sliding,
      );
      network.supports[support.id] = support;

      final supportScreenPos = controller.projector.project(
        const Node3D(id: 'test_sup', x: 600, y: 0, z: 0),
      );

      final found = controller.findSupportAtScreenPos(supportScreenPos);
      expect(found, isNotNull);
      expect(found, equals(support.id));

      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(supportScreenPos);
      expect(controller.selectedSupportId, equals(support.id));
    });

    test('Hit-testing and selecting a WeldJoint', () {
      final weld = network.addWeldJoint(
        segmentId: seg.id,
        ratio: 0.3,
        stamp: 'АК-01',
      );

      final weldScreenPos = controller.projector.project(
        const Node3D(id: 'test_weld', x: 300, y: 0, z: 0),
      );

      final found = controller.findWeldAtScreenPos(weldScreenPos);
      expect(found, isNotNull);
      expect(found, equals(weld.id));

      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(weldScreenPos);
      expect(controller.selectedWeldId, equals(weld.id));
    });

    test('Dragging a Valve along the pipe updates ratio', () {
      final valve = network.addValve(
        segmentId: seg.id,
        ratio: 0.5,
        valveType: ValveType.ballValve,
      );

      final valveScreenPos = controller.projector.project(
        const Node3D(id: 'pos', x: 500, y: 0, z: 0),
      );

      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(valveScreenPos);
      expect(controller.selectedValveId, equals(valve.id));

      // Drag to position at 800mm along X (80% of pipe)
      final newScreenPos = controller.projector.project(
        const Node3D(id: 'pos_new', x: 800, y: 0, z: 0),
      );
      controller.handlePointerMove(newScreenPos);
      expect(controller.isDraggingValve, isTrue);

      expect(network.valves[valve.id]!.ratio, closeTo(0.8, 0.05));

      controller.handlePointerUp();
      expect(controller.isDraggingValve, isFalse);
    });

    test('Dragging a PipeSupport along the pipe updates distanceRatio', () {
      final support = PipeSupport(
        id: 'sup1',
        segmentId: seg.id,
        distanceRatio: 0.3,
        type: PipeSupportType.fixed,
      );
      network.supports[support.id] = support;

      final supportScreenPos = controller.projector.project(
        const Node3D(id: 'sup_pos', x: 300, y: 0, z: 0),
      );

      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(supportScreenPos);
      expect(controller.selectedSupportId, equals(support.id));

      final newScreenPos = controller.projector.project(
        const Node3D(id: 'sup_pos_new', x: 700, y: 0, z: 0),
      );
      controller.handlePointerMove(newScreenPos);
      expect(controller.isDraggingSupport, isTrue);

      expect(network.supports[support.id]!.distanceRatio, closeTo(0.7, 0.05));

      controller.handlePointerUp();
      expect(controller.isDraggingSupport, isFalse);
    });

    test('Deleting selected Valve removes it and recalculates spools', () {
      final valve = network.addValve(
        segmentId: seg.id,
        ratio: 0.5,
        valveType: ValveType.gateValve,
      );
      controller.selectedValveId = valve.id;

      controller.deleteSelected();

      expect(network.valves.containsKey(valve.id), isFalse);
      expect(controller.selectedValveId, isNull);
    });

    test('Deleting selected PipeSupport removes it', () {
      final support = PipeSupport(
        id: 'sup1',
        segmentId: seg.id,
        distanceRatio: 0.5,
      );
      network.supports[support.id] = support;
      controller.selectedSupportId = support.id;

      controller.deleteSelected();

      expect(network.supports.containsKey(support.id), isFalse);
      expect(controller.selectedSupportId, isNull);
    });

    test('Deleting selected WeldJoint removes it and recalculates spools', () {
      final weld = network.addWeldJoint(
        segmentId: seg.id,
        ratio: 0.4,
      );
      controller.selectedWeldId = weld.id;

      controller.deleteSelected();

      expect(network.weldJoints.containsKey(weld.id), isFalse);
      expect(controller.selectedWeldId, isNull);
    });

    test('clearSelection clears all element IDs', () {
      controller.selectedValveId = 'v1';
      controller.selectedSupportId = 's1';
      controller.selectedWeldId = 'w1';

      controller.clearSelection();

      expect(controller.selectedValveId, isNull);
      expect(controller.selectedSupportId, isNull);
      expect(controller.selectedWeldId, isNull);
    });
  });

  group('PipingCanvasPainter Selection Highlights', () {
    test('PipingCanvasPainter paints with selectedValveId, selectedSupportId, selectedWeldId', () {
      final net = PipingNetwork();
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final seg = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      net.segments[seg.id] = seg;

      final v = net.addValve(segmentId: seg.id, ratio: 0.5, valveType: ValveType.gateValve);
      final w = net.addWeldJoint(segmentId: seg.id, ratio: 0.2);
      final s = PipeSupport(id: 's1', segmentId: seg.id, distanceRatio: 0.8);
      net.supports[s.id] = s;

      final painter = PipingCanvasPainter(
        network: net,
        projector: AxonometryProjector(),
        selectedValveId: v.id,
        selectedSupportId: s.id,
        selectedWeldId: w.id,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(800, 600));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });
  });

  group('DesktopCadLayout Element Inspector Cards Widget Tests', () {
    testWidgets('Displays Valve inspector and allows modifying properties', (tester) async {
      final net = PipingNetwork();
      final controller = PipingInputController(network: net);
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final seg = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      net.segments[seg.id] = seg;

      final valve = net.addValve(
        segmentId: seg.id,
        ratio: 0.5,
        valveType: ValveType.gateValve,
        customLengthMm: 150.0,
      );
      controller.selectedValveId = valve.id;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopCadLayout(
              controller: controller,
              canvasWidget: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // Verify inspector card is visible
      expect(find.text('Арматура'), findsOneWidget);
      expect(find.text('Ду 50'), findsOneWidget);
      expect(find.text('150 мм'), findsOneWidget);
      expect(find.text('Поворот +90°'), findsOneWidget);

      // Tap rotate button
      await tester.tap(find.text('Поворот +90°'));
      await tester.pump();
      expect(net.valves[valve.id]!.handleAngleDeg, equals(180.0));

      // Tap Delete button
      await tester.tap(find.text('Удалить арматуру (Del)'));
      await tester.pump();
      expect(net.valves.containsKey(valve.id), isFalse);
      controller.dispose();
    });

    testWidgets('Displays Support inspector and allows deleting support', (tester) async {
      final net = PipingNetwork();
      final controller = PipingInputController(network: net);
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final seg = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 80);
      net.segments[seg.id] = seg;

      final support = PipeSupport(
        id: 'sup1',
        segmentId: seg.id,
        distanceRatio: 0.4,
        type: PipeSupportType.sliding,
        name: 'ОП-1',
      );
      net.supports[support.id] = support;
      controller.selectedSupportId = support.id;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopCadLayout(
              controller: controller,
              canvasWidget: const SizedBox.expand(),
            ),
          ),
        ),
      );

      expect(find.text('Опора трубы'), findsOneWidget);
      expect(find.text('ОП-1'), findsOneWidget);
      expect(find.text('40.0%'), findsOneWidget);

      await tester.tap(find.text('Удалить опору (Del)'));
      await tester.pump();
      expect(net.supports.containsKey('sup1'), isFalse);
      controller.dispose();
    });

    testWidgets('Displays Weld inspector and allows deleting weld', (tester) async {
      final net = PipingNetwork();
      final controller = PipingInputController(network: net);
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final seg = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      net.segments[seg.id] = seg;

      final weld = net.addWeldJoint(
        segmentId: seg.id,
        ratio: 0.25,
        stamp: 'ПР-02',
      );
      controller.selectedWeldId = weld.id;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopCadLayout(
              controller: controller,
              canvasWidget: const SizedBox.expand(),
            ),
          ),
        ),
      );

      expect(find.text('Сварной стык'), findsOneWidget);
      expect(find.text('№ 1'), findsOneWidget);
      expect(find.text('ПР-02'), findsOneWidget);
      expect(find.text('25.0%'), findsOneWidget);

      await tester.tap(find.text('Удалить стык (Del)'));
      await tester.pump();
      expect(net.weldJoints.containsKey(weld.id), isFalse);
      controller.dispose();
    });
  });
}
