import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/editor_screen.dart';

PipingNetwork _buildNetworkWithValve({bool isFlanged = true}) {
  final net = PipingNetwork();
  const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
  const n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
  net.nodes[n1.id] = n1;
  net.nodes[n2.id] = n2;
  final seg = PipeSegment(
    id: 'seg1',
    startNodeId: 'n1',
    endNodeId: 'n2',
    dn: 100,
    outerDiameterMm: 108.0,
    wallThicknessMm: 4.0,
    systemId: net.systems.keys.first,
  );
  net.addSegment(seg);
  final valve = Valve(
    id: 'v1',
    segmentId: 'seg1',
    ratio: 0.5,
    valveType: ValveType.ballValve,
    dn: 100,
    name: 'КШ-100',
    lengthMm: 230.0,
    isFlanged: isFlanged,
    includeCounterFlanges: true,
    handleAngleDeg: 0.0,
  );
  net.valves[valve.id] = valve;
  net.generateElementWeldJoints();
  net.recalculateSpools();
  return net;
}

void main() {
  group('Property Inspector keyboard isolation & text selection stability', () {
    testWidgets(
      'Pressing CAD shortcut keys (Delete, Backspace, R, D, Escape) while inspector TextField is focused does not trigger global CAD commands',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = PipingInputController(
          network: _buildNetworkWithValve(),
          projector: const AxonometryProjector(),
        );
        controller.setLayoutMode(UiLayoutMode.desktopCad);
        controller.setTool(CanvasTool.select);
        controller.selectedValveId = 'v1';

        await tester.pumpWidget(
          MaterialApp(
            home: EditorScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        // Find the valve name TextField ('КШ-100')
        final nameFieldFinder = find.widgetWithText(TextField, 'КШ-100');
        expect(nameFieldFinder, findsOneWidget);

        await tester.tap(nameFieldFinder);
        await tester.pumpAndSettle();

        // Send Delete, Backspace, R, D keys while TextField is focused
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
        await tester.pumpAndSettle();

        // Valve must still exist, keep its handle angle, and tool must still be select
        expect(controller.network.valves.containsKey('v1'), isTrue);
        expect(controller.network.valves['v1']!.handleAngleDeg, equals(0.0));
        expect(controller.currentTool, equals(CanvasTool.select));
        expect(controller.selectedValveId, equals('v1'));

        // Pressing Escape should unfocus the TextField without clearing the CAD selection
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(controller.selectedValveId, equals('v1'));

        controller.dispose();
      },
    );

    testWidgets(
      'Focusing and selecting text in valve L1 field is not overwritten by other fields or canvas pointer hover',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = PipingInputController(
          network: _buildNetworkWithValve(),
          projector: const AxonometryProjector(),
        );
        controller.setLayoutMode(UiLayoutMode.desktopCad);
        controller.selectedValveId = 'v1';

        await tester.pumpWidget(
          MaterialApp(
            home: EditorScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        // Initial L1 for 2000mm segment with 230+2*45=320mm total valve length at ratio 0.5 is 840mm
        final l1FieldFinder = find.widgetWithText(TextField, '840').first;
        expect(l1FieldFinder, findsOneWidget);
        final l1Widget = tester.widget<TextField>(l1FieldFinder);
        final l1Ctrl = l1Widget.controller!;

        await tester.tap(find.byWidget(l1Widget));
        await tester.pumpAndSettle();

        // Type partial value and select all text in L1 field
        await tester.enterText(find.byWidget(l1Widget), '500');
        l1Ctrl.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
        await tester.pump();

        // Simulate canvas pointer hover (which triggers notifyListeners on controller)
        controller.handlePointerMove(const Offset(300, 300));
        await tester.pump();

        // Text and selection in focused L1 field must remain intact!
        expect(l1Ctrl.text, equals('500'));
        expect(l1Ctrl.selection.baseOffset, equals(0));
        expect(l1Ctrl.selection.extentOffset, equals(3));

        // Now tap another field (valve name) -> L1 loses focus and commits 500mm
        final nameFieldFinder = find.widgetWithText(TextField, 'КШ-100');
        await tester.tap(nameFieldFinder);
        await tester.pumpAndSettle();

        // L2 should have updated to 2000 - 320 - 500 = 1180mm
        expect(find.widgetWithText(TextField, '1180'), findsOneWidget);

        controller.dispose();
      },
    );
  });

  group('Property Inspector vertical bounds & scroll layout', () {
    testWidgets(
      'Flanged valve Property Inspector does not extend into top hint bar on compact viewport height',
      (tester) async {
        // Compact viewport height (600px) where flanged valve inspector previously overflowed upward
        tester.view.physicalSize = const Size(1280, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = PipingInputController(
          network: _buildNetworkWithValve(isFlanged: true),
          projector: const AxonometryProjector(),
        );
        controller.setLayoutMode(UiLayoutMode.desktopCad);
        controller.selectedValveId = 'v1';

        await tester.pumpWidget(
          MaterialApp(
            home: EditorScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        // Verify the inspector header ('Арматура') is visible and below the top bar (y >= 64)
        final headerFinder = find.text('Арматура');
        expect(headerFinder, findsOneWidget);
        final headerRect = tester.getRect(headerFinder);
        expect(headerRect.top, greaterThanOrEqualTo(64.0));

        // Verify bottom delete button can be scrolled into view cleanly
        final deleteBtnFinder = find.text('Удалить арматуру (Del)');
        await tester.ensureVisible(deleteBtnFinder);
        await tester.pumpAndSettle();
        expect(deleteBtnFinder, findsOneWidget);

        controller.dispose();
      },
    );
  });
}
