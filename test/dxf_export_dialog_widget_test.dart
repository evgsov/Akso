import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/dxf_callout_options.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/features/editor/widgets/dxf_export_dialog.dart';

void main() {
  group('DxfExportDialog Widget Tests', () {
    late PipingNetwork net;

    setUp(() {
      net = PipingNetwork();
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 2000);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 50);
    });

    testWidgets('Renders 2D by default and expands 3D options when toggled', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DxfExportDialog(
              network: net,
              currentProjection: ProjectionType.gostFrontal45,
            ),
          ),
        ),
      );

      // Initially 2D mode is active
      expect(find.text('Плоская схема в аксонометрии ГОСТ / СПДС (2D DXF)'), findsOneWidget);
      expect(find.text('Пространственная 3D-модель (3D DXF)'), findsOneWidget);
      expect(find.text('Тип выносок в AutoCAD:'), findsNothing);

      // Toggle to 3D mode
      await tester.tap(find.text('Пространственная 3D-модель (3D DXF)'));
      await tester.pumpAndSettle();

      // Now 3D callout controls are visible
      expect(find.text('Тип выносок в AutoCAD:'), findsOneWidget);
      expect(find.text(DxfCalloutType.monolithicBlock.displayName), findsOneWidget);
      expect(find.text(DxfCalloutType.monolithicBlock.description), findsOneWidget);

      expect(find.text('Ракурс / Положение выносок в 3D:'), findsOneWidget);
      expect(find.text(DxfCalloutOrientation.cameraFacing.displayName), findsOneWidget);

      // Change Callout Type to nativeLeader
      await tester.tap(find.text(DxfCalloutType.monolithicBlock.displayName));
      await tester.pumpAndSettle();
      await tester.tap(find.text(DxfCalloutType.nativeLeader.displayName).last);
      await tester.pumpAndSettle();

      expect(find.text(DxfCalloutType.nativeLeader.description), findsOneWidget);

      // Change Callout Type to mleaderScript
      await tester.tap(find.text(DxfCalloutType.nativeLeader.displayName));
      await tester.pumpAndSettle();
      await tester.tap(find.text(DxfCalloutType.mleaderScript.displayName).last);
      await tester.pumpAndSettle();

      expect(find.text(DxfCalloutType.mleaderScript.description), findsOneWidget);

      // Change Orientation to viewFront
      await tester.tap(find.text(DxfCalloutOrientation.cameraFacing.displayName));
      await tester.pumpAndSettle();
      await tester.tap(find.text(DxfCalloutOrientation.viewFront.displayName).last);
      await tester.pumpAndSettle();

      expect(find.text(DxfCalloutOrientation.viewFront.displayName), findsOneWidget);
    });
  });
}
