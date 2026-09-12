import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/main.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/piping_canvas.dart';
import 'package:akso/ui/features/editor/widgets/top_bar.dart';

void main() {
  group('PipingInputController Grid & Snap tests', () {
    test('showGrid defaults to true and toggles correctly', () {
      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );

      expect(controller.showGrid, isTrue);

      var notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.toggleGrid();
      expect(controller.showGrid, isFalse);
      expect(notified, isTrue);

      notified = false;
      controller.toggleGrid();
      expect(controller.showGrid, isTrue);
      expect(notified, isTrue);

      controller.dispose();
    });

    test('toggleSnap flips isSnapEnabled and notifies listeners', () {
      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );

      expect(controller.isSnapEnabled, isTrue);

      var notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.toggleSnap();
      expect(controller.isSnapEnabled, isFalse);
      expect(notified, isTrue);

      controller.dispose();
    });

    test('setting tool to CanvasTool.drawAxis works as expected', () {
      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );

      expect(controller.currentTool, CanvasTool.trace);

      controller.setTool(CanvasTool.drawAxis);
      expect(controller.currentTool, CanvasTool.drawAxis);

      controller.dispose();
    });
  });

  group('EditorTopBar widget tests', () {
    testWidgets('EditorTopBar displays Grid, Snap, and Axes buttons and responds to taps', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(3600, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => EditorTopBar(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gridBtn = find.byTooltip('Сетка (Grid)');
      final snapBtn = find.byTooltip('Привязка (Snap)');
      final axesBtn = find.byTooltip('Осевые линии (Axes)');

      expect(gridBtn, findsOneWidget);
      expect(snapBtn, findsOneWidget);
      expect(axesBtn, findsOneWidget);

      expect(find.byIcon(Icons.grid_4x4), findsOneWidget);
      expect(find.byIcon(Icons.gps_fixed), findsOneWidget);

      // Tap Grid button
      expect(controller.showGrid, isTrue);
      await tester.tap(gridBtn);
      await tester.pumpAndSettle();
      expect(controller.showGrid, isFalse);

      // Tap Snap button
      expect(controller.isSnapEnabled, isTrue);
      await tester.tap(snapBtn);
      await tester.pumpAndSettle();
      expect(controller.isSnapEnabled, isFalse);

      // Tap Axes button
      expect(controller.currentTool, isNot(CanvasTool.drawAxis));
      await tester.tap(axesBtn);
      await tester.pumpAndSettle();
      expect(controller.currentTool, CanvasTool.drawAxis);

      controller.dispose();
    });
  });

  group('DesktopCadLayout header buttons test', () {
    testWidgets('DesktopCadLayout contains Grid, Snap, and Axes buttons', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = PipingInputController(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
      );
      controller.setLayoutMode(UiLayoutMode.desktopCad);

      await tester.pumpWidget(AksoApp(controller: controller));
      await tester.pumpAndSettle();

      final gridBtn = find.byTooltip('Сетка (Grid)');
      final snapBtn = find.byTooltip('Привязка (Snap)');
      final axesBtn = find.byTooltip('Осевые линии (Axes)');

      expect(gridBtn, findsOneWidget);
      expect(snapBtn, findsWidgets); // Status bar or header might have snap indicator
      expect(axesBtn, findsWidgets); // Palette and header

      // Tap header grid button
      expect(controller.showGrid, isTrue);
      await tester.tap(gridBtn.first);
      await tester.pumpAndSettle();
      expect(controller.showGrid, isFalse);

      // Tap header snap button
      expect(controller.isSnapEnabled, isTrue);
      await tester.tap(snapBtn.first);
      await tester.pumpAndSettle();
      expect(controller.isSnapEnabled, isFalse);

      // Tap axes button
      await tester.tap(axesBtn.first);
      await tester.pumpAndSettle();
      expect(controller.currentTool, CanvasTool.drawAxis);

      controller.dispose();
    });
  });

  group('PipingCanvasPainter showGrid test', () {
    test('PipingCanvasPainter respects showGrid property', () {
      final painterWithGrid = PipingCanvasPainter(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
        showGrid: true,
      );
      expect(painterWithGrid.showGrid, isTrue);

      final painterWithoutGrid = PipingCanvasPainter(
        network: PipingNetwork(),
        projector: const AxonometryProjector(),
        showGrid: false,
      );
      expect(painterWithoutGrid.showGrid, isFalse);
    });
  });
}
