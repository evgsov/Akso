import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/desktop_cad_layout.dart';
import 'package:akso/ui/features/editor/widgets/riser_sectioning_dialog.dart';

void main() {
  group('RiserSectioningDialog & CAD Inspectors Widget Tests', () {
    late PipingNetwork net;
    late PipingInputController controller;

    setUp(() {
      net = PipingNetwork();
      net.systems['sys1'] = const PipingSystem(
        id: 'sys1',
        name: 'Отопление',
        code: 'Т1',
        colorValue: 0xFFF44336,
        dxfAciColor: 1,
      );

      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 6000);
      net.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );

      controller = PipingInputController(initialNetwork: net);
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('RiserSectioningDialog interactive preview and batch dividing', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => RiserSectioningDialog.show(
                  ctx,
                  controller: controller,
                  segmentId: 's1',
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Check header and 3 tabs
      expect(find.text('Нарезка стояка на катушки'), findsOneWidget);
      expect(find.text('Равный шаг'), findsOneWidget);
      expect(find.text('Цепочка длин'), findsOneWidget);
      expect(find.text('Отметки этажей'), findsOneWidget);

      // Default step is 2500 mm: pipe is 6000 mm -> 3 spools (2500, 2500, 1000) and 2 welds
      expect(find.text('Катушек: 3 • Стыков: 2'), findsOneWidget);

      // Switch to 'Отметки этажей'
      await tester.tap(find.text('Отметки этажей'));
      await tester.pumpAndSettle();

      // Check floor elevations info
      expect(find.text('Отметки этажей (Z):'), findsOneWidget);

      // Apply sectioning
      final applyBtn = find.widgetWithText(FilledButton, 'Нарезать (создать 2 стык.)');
      expect(applyBtn, findsOneWidget);
      await tester.tap(applyBtn);
      await tester.pumpAndSettle();

      // Dialog closed and 2 welds created
      expect(find.text('Нарезка стояка на катушки'), findsNothing);
      expect(controller.network.weldJoints.values.where((w) => w.segmentId == 's1').length, equals(2));
      expect(controller.network.spools.values.where((sp) => sp.segmentId == 's1').length, equals(3));
    });

    testWidgets('DesktopCadLayout displays mutual positioning card for selected valve and toggles elevation callout', (tester) async {
      tester.view.physicalSize = const Size(1400, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Add a valve to s1
      final v = controller.network.addValve(
        segmentId: 's1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
      );
      controller.selectedValveId = v.id;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopCadLayout(
              controller: controller,
              canvasWidget: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should display mutual positioning card
      expect(find.text('Позиция / Отметка Z:'), findsOneWidget);
      expect(find.text('Отметка Z:'), findsOneWidget);
      expect(find.text('∇ Добавить отметку оси'), findsOneWidget);

      // Toggle elevation mark
      await tester.tap(find.text('∇ Добавить отметку оси'));
      await tester.pumpAndSettle();

      expect(find.text('∇ Отметка оси: ВКЛ'), findsOneWidget);
      expect(controller.valveHasElevationCallout(v.id), isTrue);
    });

    testWidgets('DesktopCadLayout displays _DesktopWeldInspector for selected weld with mutual positioning card', (tester) async {
      tester.view.physicalSize = const Size(1400, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Add a weld to s1
      final w = controller.network.addWeldJoint(
        segmentId: 's1',
        ratio: 0.4,
      );
      controller.selectedWeldId = w.id;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopCadLayout(
              controller: controller,
              canvasWidget: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should display weld inspector
      expect(find.text('Номер шва:'), findsOneWidget);
      expect(find.text('Позиция / Отметка Z:'), findsOneWidget);
      expect(find.text('∇ Добавить отметку оси'), findsOneWidget);

      // Toggle elevation mark for weld
      await tester.tap(find.text('∇ Добавить отметку оси'));
      await tester.pumpAndSettle();

      expect(find.text('∇ Отметка оси: ВКЛ'), findsOneWidget);
      expect(controller.weldHasElevationCallout(w.id), isTrue);
    });
  });
}
