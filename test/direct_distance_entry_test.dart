import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/core/math/snap_engine.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/editor_screen.dart';
import 'package:akso/ui/features/editor/widgets/trace_length_input.dart';

void main() {
  group('PipingInputController commitTraceWithLength tests', () {
    test('commitTraceWithLength commits pipe along X axis in ortho mode', () {
      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );

      final startNode = const Node3D(id: 'start', x: 100, y: 100, z: 0);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;
      controller.angleSnapMode = AngleSnapMode.ortho90;

      // Cursor is to the right (+X)
      controller.currentCursorScreenPos = controller.projector.project(const Node3D(id: '', x: 500, y: 100, z: 0));
      controller.currentSnapResult = null;

      controller.commitTraceWithLength(1500.0);

      expect(controller.network.segments.length, equals(1));
      final seg = controller.network.segments.values.first;
      expect(seg.startNodeId, equals('start'));

      final endNode = controller.network.nodes[seg.endNodeId];
      expect(endNode, isNotNull);
      expect(endNode!.x, closeTo(1600.0, 0.01));
      expect(endNode.y, closeTo(100.0, 0.01));
      expect(startNode.distanceTo(endNode), closeTo(1500.0, 0.01));

      // Controller should continue tracing from the new endpoint
      expect(controller.traceStartNode?.id, equals(endNode.id));

      controller.dispose();
    });

    test('commitTraceWithLength commits pipe along Y axis in ortho mode', () {
      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );

      final startNode = const Node3D(id: 'start', x: 200, y: 300, z: 0);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;
      controller.angleSnapMode = AngleSnapMode.ortho90;

      // Cursor is upward (+Y)
      controller.currentCursorScreenPos = controller.projector.project(const Node3D(id: '', x: 200, y: 800, z: 0));
      controller.currentSnapResult = null;

      controller.commitTraceWithLength(2400.0);

      expect(controller.network.segments.length, equals(1));
      final seg = controller.network.segments.values.first;
      final endNode = controller.network.nodes[seg.endNodeId];
      expect(endNode, isNotNull);
      expect(endNode!.x, closeTo(200.0, 0.01));
      expect(endNode.y, closeTo(2700.0, 0.01));
      expect(startNode.distanceTo(endNode), closeTo(2400.0, 0.01));

      controller.dispose();
    });

    test('commitTraceWithLength follows polar angle snap result when active', () {
      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );

      final startNode = const Node3D(id: 'start', x: 0, y: 0, z: 0);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;

      // Active snap result at 45 degrees
      final snapTarget = const Node3D(id: '', x: 1000, y: 1000, z: 0);
      controller.currentSnapResult = SnapResult(
        type: SnapType.polarAngle,
        screenPoint: controller.projector.project(snapTarget),
        worldPoint: snapTarget,
        snappedAngleDegrees: 45.0,
      );

      controller.commitTraceWithLength(1000.0);

      expect(controller.network.segments.length, equals(1));
      final seg = controller.network.segments.values.first;
      final endNode = controller.network.nodes[seg.endNodeId]!;
      expect(startNode.distanceTo(endNode), closeTo(1000.0, 0.1));

      controller.dispose();
    });

    test('commitTraceWithLength works sequentially for polyline pipe tracing', () {
      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );

      final startNode = const Node3D(id: 'n0', x: 0, y: 0, z: 0);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;
      controller.angleSnapMode = AngleSnapMode.ortho90;

      // Segment 1: +X direction by 2000
      controller.handlePointerMove(controller.projector.project(const Node3D(id: '', x: 500, y: 0, z: 0)));
      controller.commitTraceWithLength(2000.0);

      expect(controller.network.segments.length, equals(1));
      final n1 = controller.traceStartNode!;
      expect(n1.x, closeTo(2000.0, 0.01));
      expect(n1.y, closeTo(0.0, 0.01));

      // Segment 2: +Y direction by 1500
      controller.handlePointerMove(controller.projector.project(const Node3D(id: '', x: 2000, y: 500, z: 0)));
      controller.commitTraceWithLength(1500.0);

      expect(controller.network.segments.length, equals(2));
      final n2 = controller.traceStartNode!;
      expect(n2.x, closeTo(2000.0, 0.01));
      expect(n2.y, closeTo(1500.0, 0.01));

      // Undo should rollback segment 2
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(controller.network.segments.length, equals(1));

      controller.dispose();
    });

    test('commitTraceWithLength draws construction axis when tool is drawAxis', () {
      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );

      controller.currentTool = CanvasTool.drawAxis;
      controller.currentAxisLabel = '1';
      final startNode = const Node3D(id: 'axis_start', x: 0, y: 0, z: 0);
      controller.axisStartNode = startNode;
      controller.currentCursorScreenPos = controller.projector.project(const Node3D(id: '', x: 0, y: 3000, z: 0));

      controller.commitTraceWithLength(6000.0);

      expect(controller.network.axes.length, equals(1));
      final axis = controller.network.axes.values.first;
      expect(axis.label, equals('1'));
      expect(axis.startPoint.y, closeTo(0.0, 0.01));
      expect(axis.endPoint.y, closeTo(6000.0, 0.01));
      expect(controller.currentAxisLabel, equals('2'));
      expect(controller.axisStartNode, isNull);

      controller.dispose();
    });

    test('commitTraceWithLength ignores non-positive or invalid length', () {
      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );

      final startNode = const Node3D(id: 'start', x: 0, y: 0, z: 0);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;

      controller.commitTraceWithLength(0.0);
      controller.commitTraceWithLength(-100.0);
      controller.commitTraceWithLength(double.nan);

      expect(controller.network.segments, isEmpty);
      controller.dispose();
    });
  });

  group('TraceLengthInput Widget tests', () {
    testWidgets('TraceLengthInput renders initial value and responds to enter key', (tester) async {
      double? submittedValue;
      bool cancelled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TraceLengthInput(
              initialValue: '5',
              onSubmitted: (val) => submittedValue = val,
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('мм'), findsOneWidget);
      expect(find.byIcon(Icons.straighten), findsOneWidget);

      // Enter more digits: '5000'
      await tester.enterText(find.byType(TextField), '5000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(submittedValue, equals(5000.0));
      expect(cancelled, isFalse);
    });

    testWidgets('TraceLengthInput clicking check icon submits length', (tester) async {
      double? submittedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TraceLengthInput(
              initialValue: '1250',
              onSubmitted: (val) => submittedValue = val,
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final checkBtn = find.byKey(const Key('trace_length_submit_button'));
      expect(checkBtn, findsOneWidget);
      await tester.tap(checkBtn);
      await tester.pumpAndSettle();

      expect(submittedValue, equals(1250.0));
    });

    testWidgets('TraceLengthInput clicking close icon or pressing Esc cancels', (tester) async {
      bool cancelled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TraceLengthInput(
              initialValue: '300',
              onSubmitted: (_) {},
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final closeBtn = find.byKey(const Key('trace_length_cancel_button'));
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
    });
  });

  group('EditorScreen Direct Distance Entry Integration tests', () {
    testWidgets('Pressing digit key during trace pops up TraceLengthInput and Enter commits segment', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );
      controller.setLayoutMode(UiLayoutMode.desktopCad);

      await tester.pumpWidget(
        MaterialApp(
          home: EditorScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      // Start tracing from (100, 100, 0)
      final startNode = const Node3D(id: 'n_start', x: 100, y: 100, z: 0);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;
      controller.currentCursorScreenPos = controller.projector.project(const Node3D(id: '', x: 500, y: 100, z: 0));
      controller.refresh();
      await tester.pumpAndSettle();

      // Press digit '5'
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pumpAndSettle();

      // TraceLengthInput should be visible
      expect(find.byType(TraceLengthInput), findsOneWidget);
      expect(find.text('5'), findsOneWidget);

      // Type remaining '000' -> '5000'
      await tester.enterText(find.byKey(const Key('trace_length_text_field')), '5000');
      await tester.pumpAndSettle();

      // Press Enter
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Input should close
      expect(find.byType(TraceLengthInput), findsNothing);

      // Segment should be committed
      expect(controller.network.segments.length, equals(1));
      final seg = controller.network.segments.values.first;
      final endNode = controller.network.nodes[seg.endNodeId]!;
      expect(startNode.distanceTo(endNode), closeTo(5000.0, 0.01));

      controller.dispose();
    });

    testWidgets('Pressing Esc cancels TraceLengthInput without committing', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );
      controller.setLayoutMode(UiLayoutMode.desktopCad);

      await tester.pumpWidget(
        MaterialApp(
          home: EditorScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      // Start tracing
      final startNode = const Node3D(id: 'n_start', x: 0, y: 0, z: 0);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;
      controller.refresh();
      await tester.pumpAndSettle();

      // Press digit '7'
      await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
      await tester.pumpAndSettle();
      expect(find.byType(TraceLengthInput), findsOneWidget);

      // Press Esc
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(TraceLengthInput), findsNothing);
      expect(controller.network.segments, isEmpty);

      controller.dispose();
    });
  });
}
