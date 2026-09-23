import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/project_model.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/desktop_cad_layout.dart';

void main() {
  testWidgets('DesktopCadLayout renders rich Revit-style axis inspector controls', (tester) async {
    final net = PipingNetwork();
    net.axes['ax1'] = const ConstructionAxis(
      id: 'ax1',
      label: '1',
      startPoint: Node3D(id: 'n1', x: 0, y: 0, z: 0),
      endPoint: Node3D(id: 'n2', x: 0, y: 10000, z: 0),
      showStartBubble: true,
      showEndBubble: false,
      is3dPlaneOriented: true,
    );

    final controller = PipingInputController(
      network: net,
      projector: const AxonometryProjector(),
    );
    controller.currentProject = ProjectModel(
      id: 'p1',
      title: 'Test',
      network: net,
    );
    controller.selectedAxisId = 'ax1';

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

    // Inspector should display mark label, bubble checkboxes, 3D orientation toggle
    expect(find.text('Марка:'), findsOneWidget);
    expect(find.text('В начале'), findsOneWidget);
    expect(find.text('В конце'), findsOneWidget);
    expect(find.text('3D в плоскости'), findsOneWidget);
    expect(find.text('Создать смещение (Offset)'), findsOneWidget);

    controller.dispose();
  });
}
