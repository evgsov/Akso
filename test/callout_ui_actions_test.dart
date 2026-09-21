import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/callout_manager_panel.dart';
import 'package:akso/ui/features/editor/widgets/sheet_toolbar.dart';
import 'package:akso/ui/features/editor/widgets/desktop_cad_layout.dart';

void main() {
  testWidgets('CalloutManagerPanel shows auto-layout button and triggers layout', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final network = PipingNetwork();
    network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
    network.nodes['n2'] = const Node3D(id: 'n2', x: 3000, y: 0, z: 0);
    network.segments['seg'] = const PipeSegment(
      id: 'seg',
      startNodeId: 'n1',
      endNodeId: 'n2',
      outerDiameterMm: 89,
      systemId: 'sys1',
      dn: 80,
    );
    final controller = PipingInputController(initialNetwork: network);
    controller.generateMissingCallouts();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalloutManagerPanel(controller: controller),
        ),
      ),
    );

    final autoLayoutButton = find.byKey(const Key('auto_layout_callouts_button'));
    expect(autoLayoutButton, findsOneWidget);

    await tester.tap(autoLayoutButton);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);

    // Test pin toggle button in table row
    final pinButton = find.byIcon(Icons.push_pin_outlined).first;
    expect(pinButton, findsOneWidget);
    await tester.tap(pinButton);
    await tester.pumpAndSettle();

    // Now it should be pinned
    expect(find.byIcon(Icons.push_pin), findsWidgets);

    controller.dispose();
  });

  testWidgets('SheetToolbar shows auto-layout button and triggers layout', (tester) async {
    final network = PipingNetwork();
    network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
    network.nodes['n2'] = const Node3D(id: 'n2', x: 3000, y: 0, z: 0);
    network.segments['seg'] = const PipeSegment(
      id: 'seg',
      startNodeId: 'n1',
      endNodeId: 'n2',
      outerDiameterMm: 89,
      systemId: 'sys1',
      dn: 80,
    );
    final controller = PipingInputController(initialNetwork: network);
    final sheet = controller.addSheet();
    controller.selectSheet(sheet.id);
    controller.generateMissingCallouts();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SheetToolbar(controller: controller),
        ),
      ),
    );

    final autoLayoutBtn = find.byKey(const Key('sheet_auto_layout_callouts_button'));
    expect(autoLayoutBtn, findsOneWidget);

    await tester.tap(autoLayoutBtn);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);

    controller.dispose();
  });

  testWidgets('DesktopCadLayout shows auto-layout button and triggers layout', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final network = PipingNetwork();
    network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
    network.nodes['n2'] = const Node3D(id: 'n2', x: 3000, y: 0, z: 0);
    network.segments['seg'] = const PipeSegment(
      id: 'seg',
      startNodeId: 'n1',
      endNodeId: 'n2',
      outerDiameterMm: 89,
      systemId: 'sys1',
      dn: 80,
    );
    final controller = PipingInputController(initialNetwork: network);
    controller.generateMissingCallouts();

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

    final cadAutoLayoutBtn = find.byKey(const Key('cad_auto_layout_callouts_button'));
    expect(cadAutoLayoutBtn, findsOneWidget);

    await tester.tap(cadAutoLayoutBtn);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);

    controller.dispose();
  });
}
