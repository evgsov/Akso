import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/desktop_cad_layout.dart';
import 'package:akso/ui/features/editor/widgets/touch_distance_entry_dialog.dart';

void main() {
  group('PipingInputController commitTraceWithLength with direction vector', () {
    late PipingInputController controller;

    setUp(() {
      controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('commits pipe with explicit +X direction', () {
      final startNode = const Node3D(id: 'n_start', x: 100, y: 100, z: 500);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;

      controller.commitTraceWithLength(1200.0, dirX: 1.0, dirY: 0.0, dirZ: 0.0);

      expect(controller.network.segments.length, equals(1));
      final seg = controller.network.segments.values.first;
      expect(seg.startNodeId, equals('n_start'));
      final endNode = controller.network.nodes[seg.endNodeId]!;
      expect(endNode.x, closeTo(1300.0, 0.01));
      expect(endNode.y, closeTo(100.0, 0.01));
      expect(endNode.z, closeTo(500.0, 0.01));
      expect(controller.traceStartNode?.id, equals(endNode.id));
    });

    test('commits pipe with explicit -X direction', () {
      final startNode = const Node3D(id: 'n_start', x: 500, y: 200, z: 0);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;

      controller.commitTraceWithLength(300.0, dirX: -1.0, dirY: 0.0, dirZ: 0.0);

      final seg = controller.network.segments.values.first;
      final endNode = controller.network.nodes[seg.endNodeId]!;
      expect(endNode.x, closeTo(200.0, 0.01));
      expect(endNode.y, closeTo(200.0, 0.01));
      expect(endNode.z, closeTo(0.0, 0.01));
    });

    test('commits pipe with explicit +Y direction', () {
      final startNode = const Node3D(id: 'n_start', x: 200, y: 300, z: 0);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;

      controller.commitTraceWithLength(1500.0, dirX: 0.0, dirY: 1.0, dirZ: 0.0);

      final seg = controller.network.segments.values.first;
      final endNode = controller.network.nodes[seg.endNodeId]!;
      expect(endNode.x, closeTo(200.0, 0.01));
      expect(endNode.y, closeTo(1800.0, 0.01));
      expect(endNode.z, closeTo(0.0, 0.01));
    });

    test('commits pipe with explicit -Y direction', () {
      final startNode = const Node3D(id: 'n_start', x: 200, y: 1500, z: 0);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;

      controller.commitTraceWithLength(500.0, dirX: 0.0, dirY: -1.0, dirZ: 0.0);

      final seg = controller.network.segments.values.first;
      final endNode = controller.network.nodes[seg.endNodeId]!;
      expect(endNode.x, closeTo(200.0, 0.01));
      expect(endNode.y, closeTo(1000.0, 0.01));
    });

    test('commits vertical pipe with +Z direction (vertical riser)', () {
      final startNode = const Node3D(id: 'n_start', x: 100, y: 100, z: 1000);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;

      controller.commitTraceWithLength(2500.0, dirX: 0.0, dirY: 0.0, dirZ: 1.0);

      final seg = controller.network.segments.values.first;
      final endNode = controller.network.nodes[seg.endNodeId]!;
      expect(endNode.x, closeTo(100.0, 0.01));
      expect(endNode.y, closeTo(100.0, 0.01));
      expect(endNode.z, closeTo(3500.0, 0.01));
    });

    test('commits vertical pipe with -Z direction (vertical drop)', () {
      final startNode = const Node3D(id: 'n_start', x: 100, y: 100, z: 3000);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;

      controller.commitTraceWithLength(1000.0, dirX: 0.0, dirY: 0.0, dirZ: -1.0);

      final seg = controller.network.segments.values.first;
      final endNode = controller.network.nodes[seg.endNodeId]!;
      expect(endNode.x, closeTo(100.0, 0.01));
      expect(endNode.y, closeTo(100.0, 0.01));
      expect(endNode.z, closeTo(2000.0, 0.01));
    });

    test('commits construction axis with explicit direction vector', () {
      final startNode = const Node3D(id: 'axis_start', x: 0, y: 0, z: 0);
      controller.axisStartNode = startNode;
      controller.currentTool = CanvasTool.drawAxis;
      controller.currentAxisLabel = '1';

      controller.commitTraceWithLength(6000.0, dirX: 1.0, dirY: 0.0, dirZ: 0.0);

      expect(controller.network.axes.length, equals(1));
      final axis = controller.network.axes.values.first;
      expect(axis.label, equals('1'));
      expect(axis.endPoint.x, closeTo(6000.0, 0.01));
      expect(axis.endPoint.y, closeTo(0.0, 0.01));
      expect(controller.axisStartNode, isNull);
    });
  });

  group('TouchDistanceEntryDialog widget tests', () {
    testWidgets('renders all dialog elements, chips and direction buttons', (WidgetTester tester) async {
      double? committedLength;
      double? committedDx;
      double? committedDy;
      double? committedDz;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchDistanceEntryDialog(
              onCommit: (len, {dirX, dirY, dirZ}) {
                committedLength = len;
                committedDx = dirX;
                committedDy = dirY;
                committedDz = dirZ;
              },
            ),
          ),
        ),
      );

      expect(find.text('Точная длина и направление'), findsOneWidget);
      expect(find.byKey(const Key('touch_length_input')), findsOneWidget);
      expect(find.text('1000 мм'), findsWidgets);
      expect(find.text('Вперед (+X)'), findsOneWidget);
      expect(find.text('Назад (-X)'), findsOneWidget);
      expect(find.text('Влево (+Y)'), findsOneWidget);
      expect(find.text('Вправо (-Y)'), findsOneWidget);
      expect(find.text('Вверх (+Z)'), findsOneWidget);
      expect(find.text('Вниз (-Z)'), findsOneWidget);
      expect(find.text('Свой угол (°)'), findsOneWidget);
      expect(find.byKey(const Key('touch_cancel_button')), findsOneWidget);
      expect(find.byKey(const Key('touch_build_button')), findsOneWidget);

      // Default is 1000 and +X
      await tester.tap(find.byKey(const Key('touch_build_button')));
      await tester.pumpAndSettle();

      expect(committedLength, equals(1000.0));
      expect(committedDx, equals(1.0));
      expect(committedDy, equals(0.0));
      expect(committedDz, equals(0.0));
    });

    testWidgets('quick length chip updates input and direction button selects -Y', (WidgetTester tester) async {
      double? committedLength;
      double? committedDx;
      double? committedDy;
      double? committedDz;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchDistanceEntryDialog(
              onCommit: (len, {dirX, dirY, dirZ}) {
                committedLength = len;
                committedDx = dirX;
                committedDy = dirY;
                committedDz = dirZ;
              },
            ),
          ),
        ),
      );

      // Tap chip '2000 мм'
      await tester.tap(find.widgetWithText(ActionChip, '2000 мм'));
      await tester.pump();

      // Tap direction -Y (Вправо)
      await tester.tap(find.byKey(const Key('dir_minus_y')));
      await tester.pump();

      // Tap 'Построить'
      await tester.tap(find.byKey(const Key('touch_build_button')));
      await tester.pumpAndSettle();

      expect(committedLength, equals(2000.0));
      expect(committedDx, equals(0.0));
      expect(committedDy, equals(-1.0));
      expect(committedDz, equals(0.0));
    });

    testWidgets('custom angle field appears and computes cos/sin', (WidgetTester tester) async {
      double? committedLength;
      double? committedDx;
      double? committedDy;
      double? committedDz;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchDistanceEntryDialog(
              onCommit: (len, {dirX, dirY, dirZ}) {
                committedLength = len;
                committedDx = dirX;
                committedDy = dirY;
                committedDz = dirZ;
              },
            ),
          ),
        ),
      );

      // Select 'Свой угол (°)'
      await tester.tap(find.byKey(const Key('dir_custom_angle')));
      await tester.pump();

      expect(find.byKey(const Key('touch_angle_input')), findsOneWidget);

      // Enter 90 degrees
      await tester.enterText(find.byKey(const Key('touch_angle_input')), '90');
      await tester.pump();

      // Enter length 1500
      await tester.enterText(find.byKey(const Key('touch_length_input')), '1500');
      await tester.pump();

      await tester.tap(find.byKey(const Key('touch_build_button')));
      await tester.pumpAndSettle();

      expect(committedLength, equals(1500.0));
      expect(committedDx, closeTo(0.0, 1e-6));
      expect(committedDy, closeTo(1.0, 1e-6));
      expect(committedDz, equals(0.0));
    });

    testWidgets('cancels dialog without invoking onCommit', (WidgetTester tester) async {
      bool commitCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchDistanceEntryDialog(
              onCommit: (len, {dirX, dirY, dirZ}) {
                commitCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('touch_cancel_button')));
      await tester.pumpAndSettle();

      expect(commitCalled, isFalse);
    });

    testWidgets('validates length and displays error on invalid number', (WidgetTester tester) async {
      bool commitCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchDistanceEntryDialog(
              onCommit: (len, {dirX, dirY, dirZ}) {
                commitCalled = true;
              },
            ),
          ),
        ),
      );

      // Enter negative length
      await tester.enterText(find.byKey(const Key('touch_length_input')), '-500');
      await tester.tap(find.byKey(const Key('touch_build_button')));
      await tester.pump();

      expect(find.text('Введите корректную длину (> 0 мм)'), findsOneWidget);
      expect(commitCalled, isFalse);
    });
  });

  group('DesktopCadLayout integration with TouchDistanceEntryDialog', () {
    late PipingInputController controller;

    setUp(() {
      controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );
      controller.setLayoutMode(UiLayoutMode.tabletTouch);
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('button "📐 Точная длина" is hidden when not tracing', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DesktopCadLayout(
            controller: controller,
            canvasWidget: const SizedBox(),
          )),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tablet_exact_length_button')), findsNothing);
      expect(find.text('📐 Точная длина'), findsNothing);
    });

    testWidgets('button "📐 Точная длина" appears during pipe tracing and opens dialog to commit segment', (WidgetTester tester) async {
      final startNode = const Node3D(id: 'start_pipe', x: 100, y: 200, z: 0);
      controller.network.nodes[startNode.id] = startNode;
      controller.traceStartNode = startNode;
      controller.currentTool = CanvasTool.trace;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DesktopCadLayout(
            controller: controller,
            canvasWidget: const SizedBox(),
          )),
        ),
      );
      await tester.pumpAndSettle();

      // Button should be visible
      expect(find.byKey(const Key('tablet_exact_length_button')), findsOneWidget);
      expect(find.text('📐 Точная длина'), findsOneWidget);

      // Tap button to open dialog
      await tester.tap(find.byKey(const Key('tablet_exact_length_button')));
      await tester.pumpAndSettle();

      expect(find.byType(TouchDistanceEntryDialog), findsOneWidget);

      // Change length to 3000 and select +Z (Вверх)
      await tester.enterText(find.byKey(const Key('touch_length_input')), '3000');
      await tester.tap(find.byKey(const Key('dir_plus_z')));
      await tester.pump();

      // Tap 'Построить'
      await tester.tap(find.byKey(const Key('touch_build_button')));
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.byType(TouchDistanceEntryDialog), findsNothing);

      // Pipe segment should be committed
      expect(controller.network.segments.length, equals(1));
      final seg = controller.network.segments.values.first;
      expect(seg.startNodeId, equals('start_pipe'));
      final endNode = controller.network.nodes[seg.endNodeId]!;
      expect(endNode.x, closeTo(100.0, 0.01));
      expect(endNode.y, closeTo(200.0, 0.01));
      expect(endNode.z, closeTo(3000.0, 0.01));
    });

    testWidgets('button "📐 Точная длина" appears during axis drawing and commits axis', (WidgetTester tester) async {
      final startNode = const Node3D(id: 'start_axis', x: 0, y: 0, z: 0);
      controller.axisStartNode = startNode;
      controller.currentTool = CanvasTool.drawAxis;
      controller.currentAxisLabel = 'А';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DesktopCadLayout(
            controller: controller,
            canvasWidget: const SizedBox(),
          )),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tablet_exact_length_button')), findsOneWidget);

      // Tap to open dialog
      await tester.tap(find.byKey(const Key('tablet_exact_length_button')));
      await tester.pumpAndSettle();

      // Enter length 6000 and direction +Y (Влево)
      await tester.enterText(find.byKey(const Key('touch_length_input')), '6000');
      await tester.tap(find.byKey(const Key('dir_plus_y')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('touch_build_button')));
      await tester.pumpAndSettle();

      expect(controller.network.axes.length, equals(1));
      final axis = controller.network.axes.values.first;
      expect(axis.label, equals('А'));
      expect(axis.endPoint.x, closeTo(0.0, 0.01));
      expect(axis.endPoint.y, closeTo(6000.0, 0.01));
    });
  });
}
