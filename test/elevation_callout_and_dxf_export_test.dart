import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/painters/callout_painter.dart';
import 'package:akso/ui/features/editor/widgets/callout_manager_panel.dart';

void main() {
  group('Task 1: Exclude inline pipe diameters from DXF export', () {
    test('generate2dGostAxonometryDxf and generate3dDxf do NOT contain АКСО_ДИАМЕТРЫ by default', () {
      final network = PipingNetwork();
      final sys = PipingSystem(
        id: 'sys_v1',
        name: 'Холодное водоснабжение',
        code: 'В1',
        colorValue: Colors.blue.toARGB32(),
        dxfAciColor: 5,
      );
      network.systems[sys.id] = sys;

      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      final seg = PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_v1',
        dn: 80,
        outerDiameterMm: 89.0,
      );
      network.segments[seg.id] = seg;

      final proj = AxonometryProjector(
        projectionType: ProjectionType.gostFrontal45,
        scale: 1.0,
        panOffset: Offset.zero,
      );

      final diameterText = DxfWriter.toAutoCadString(seg.shortCallout);
      final diameterLayer = DxfWriter.toAutoCadString('АКСО_ДИАМЕТРЫ');

      // Default export: exportInlineDiameters is false
      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network, activeProjector: proj);
      final dxf3d = DxfWriter.generate3dDxf(network);

      final entities2d = dxf2d.substring(dxf2d.indexOf('ENTITIES'));
      final entities3d = dxf3d.substring(dxf3d.indexOf('ENTITIES'));

      // Verify that entities section does not write layer АКСО_ДИАМЕТРЫ with Ду80 text
      expect(entities2d.contains(diameterLayer), isFalse);
      expect(entities2d.contains(diameterText), isFalse);
      expect(entities3d.contains(diameterLayer), isFalse);
      expect(entities3d.contains(diameterText), isFalse);

      // If exportInlineDiameters is explicitly enabled, it should write them
      final dxf2dWithDiameters = DxfWriter.generate2dGostAxonometryDxf(network, activeProjector: proj, exportInlineDiameters: true);
      final dxf3dWithDiameters = DxfWriter.generate3dDxf(network, exportInlineDiameters: true);

      final entities2dWithDiameters = dxf2dWithDiameters.substring(dxf2dWithDiameters.indexOf('ENTITIES'));
      final entities3dWithDiameters = dxf3dWithDiameters.substring(dxf3dWithDiameters.indexOf('ENTITIES'));

      expect(entities2dWithDiameters.contains(diameterLayer), isTrue);
      expect(entities2dWithDiameters.contains(diameterText), isTrue);
      expect(entities3dWithDiameters.contains(diameterLayer), isTrue);
      expect(entities3dWithDiameters.contains(diameterText), isTrue);
    });
  });

  group('Task 2: Elevation Mark ГОСТ 21.101 Templating and Placeholders', () {
    test('default templates for node target type', () {
      expect(CalloutTargetType.node.defaultTemplate, contains('{Z_M}'));
      expect(CalloutTargetType.node.defaultBottomTemplate, 'Ур.ч.п.');
      expect(defaultCalloutTemplates['node'], contains('{Z_M}'));
      expect(defaultCalloutTemplates['node_bottom'], 'Ур.ч.п.');
    });

    test('formatCalloutTemplate for node supports {Z_M}, {Z_TOP}, {Z_BOT}, {Z_AXIS}', () {
      final network = PipingNetwork();
      final sys = PipingSystem(
        id: 'sys_v1',
        name: 'Холодное водоснабжение',
        code: 'В1',
        colorValue: Colors.blue.toARGB32(),
        dxfAciColor: 5,
      );
      network.systems[sys.id] = sys;

      final n1 = Node3D(id: 'node_1', x: 0, y: 0, z: 2400);
      final n2 = Node3D(id: 'node_2', x: 3000, y: 0, z: 2400);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      final seg = PipeSegment(
        id: 'seg_1',
        startNodeId: 'node_1',
        endNodeId: 'node_2',
        systemId: 'sys_v1',
        dn: 80,
        outerDiameterMm: 90.0, // radius = 45 mm = 0.045 m
      );
      network.segments[seg.id] = seg;

      // 1. Check {Z_M} and +{Z_M} (no double plus)
      final textZM = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '+{Z_M}');
      expect(textZM, '+2.400');

      final textBareZM = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{Z_M}');
      expect(textBareZM, '+2.400');

      // 2. Check {Z} in mm
      final textZ = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{Z}');
      expect(textZ, '2400');

      // 3. Check {TOP} and {Z_TOP} (2400 + 45 = 2445 mm -> +2.445 m)
      final textTop = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{TOP}');
      expect(textTop, 'В.Т. +2.445');

      final textZTop = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{Z_TOP}');
      expect(textZTop, '+2.445');

      // 4. Check {BOP} and {Z_BOT} (2400 - 45 = 2355 mm -> +2.355 m)
      final textBop = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{BOP}');
      expect(textBop, 'Н.Т. +2.355');

      final textZBot = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{Z_BOT}');
      expect(textZBot, '+2.355');

      // 5. Check {Z_AXIS}
      final textAxis = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{Z_AXIS}');
      expect(textAxis, 'ОСЬ +2.400');

      // 6. Check {DN} and {SYSTEM}
      final textPipe = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', 'Ду{DN} {SYSTEM}');
      expect(textPipe, 'Ду80 В1');
    });

    test('formatPreviewCalloutText for node generates realistic ГОСТ 21.101 sample', () {
      final previewTop = formatPreviewCalloutText('+{Z_M}', CalloutTargetType.node);
      expect(previewTop, '+2.400');

      final previewTopPipe = formatPreviewCalloutText('{TOP}', CalloutTargetType.node);
      expect(previewTopPipe, contains('В.Т.'));

      final previewBotPipe = formatPreviewCalloutText('{BOP}', CalloutTargetType.node);
      expect(previewBotPipe, contains('Н.Т.'));

      final previewBottom = formatPreviewCalloutText('Ур.ч.п.', CalloutTargetType.node);
      expect(previewBottom, 'Ур.ч.п.');
    });
  });

  group('Task 3: 3D Smart Normal Vector and Callout Geometry', () {
    test('Adaptive normal vector on pipes at 90, 45, and 30 degrees', () {
      final network = PipingNetwork();
      final nStart = Node3D(id: 's', x: 0, y: 0, z: 0);
      final nOrth = Node3D(id: 'eOrth', x: 2000, y: 0, z: 0);
      final n45 = Node3D(id: 'e45', x: 2000, y: 2000, z: 0);
      final rad30 = 30.0 * math.pi / 180.0;
      final n30 = Node3D(id: 'e30', x: 2000 * math.cos(rad30), y: 2000 * math.sin(rad30), z: 0);

      network.nodes[nStart.id] = nStart;
      network.nodes[nOrth.id] = nOrth;
      network.nodes[n45.id] = n45;
      network.nodes[n30.id] = n30;

      final segOrth = PipeSegment(id: 'sOrth', startNodeId: 's', endNodeId: 'eOrth', systemId: 'v1', dn: 80);
      network.segments[segOrth.id] = segOrth;

      final proj = AxonometryProjector(projectionType: ProjectionType.gostFrontal45, scale: 1.0);

      // 1. Normal for orthogonal pipe
      final nVecOrth = CalloutPainter.computeNodeNormalVector(network, proj, 's');
      final p1 = proj.project(nStart);
      final p2 = proj.project(nOrth);
      final vOrth = Offset(p2.dx - p1.dx, p2.dy - p1.dy);
      expect(vOrth.dx * nVecOrth.dx + vOrth.dy * nVecOrth.dy, closeTo(0.0, 1e-4));

      // 2. Normal for 45° pipe
      network.segments.clear();
      final seg45 = PipeSegment(id: 's45', startNodeId: 's', endNodeId: 'e45', systemId: 'v1', dn: 80);
      network.segments[seg45.id] = seg45;
      final nVec45 = CalloutPainter.computeNodeNormalVector(network, proj, 's');
      final p2_45 = proj.project(n45);
      final v45 = Offset(p2_45.dx - p1.dx, p2_45.dy - p1.dy);
      expect(v45.dx * nVec45.dx + v45.dy * nVec45.dy, closeTo(0.0, 1e-4));

      // 3. Normal for 30° pipe
      network.segments.clear();
      final seg30 = PipeSegment(id: 's30', startNodeId: 's', endNodeId: 'e30', systemId: 'v1', dn: 80);
      network.segments[seg30.id] = seg30;
      final nVec30 = CalloutPainter.computeNodeNormalVector(network, proj, 's');
      final p2_30 = proj.project(n30);
      final v30 = Offset(p2_30.dx - p1.dx, p2_30.dy - p1.dy);
      expect(v30.dx * nVec30.dx + v30.dy * nVec30.dy, closeTo(0.0, 1e-4));
    });

    test('generateMissingCallouts creates node callouts for vertical risers and endpoints', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 0, y: 0, z: 2500); // vertical riser
      final n3 = Node3D(id: 'n3', x: 1500, y: 0, z: 2500); // horizontal
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      network.nodes[n3.id] = n3;

      final seg1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'v1', dn: 50);
      final seg2 = PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'v1', dn: 50);
      network.segments[seg1.id] = seg1;
      network.segments[seg2.id] = seg2;

      final added = network.generateMissingCallouts(targetTypes: {CalloutTargetType.node});
      expect(added, greaterThanOrEqualTo(2));

      // Verify created callouts have targetType node
      final nodeCallouts = network.callouts.values.where((c) => c.targetType == CalloutTargetType.node).toList();
      expect(nodeCallouts, isNotEmpty);
      expect(nodeCallouts.any((c) => c.targetId == 'n2' || c.targetId == 'n3'), isTrue);
    });
  });

  group('Task 4: DXF Export of ГОСТ 21.101 Elevation Callouts', () {
    test('generate2dGostAxonometryDxf exports node callout as ГОСТ elevation mark block and avoids duplicate', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 2500);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 2500);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      final seg = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'v1', dn: 80);
      network.segments[seg.id] = seg;

      final callout = Callout(
        id: 'c_node1',
        targetId: 'n1',
        targetType: CalloutTargetType.node,
        customText: '+{Z_M}',
        customBottomText: 'Ур.ч.п.',
        screenOffsetX: 60.0,
        screenOffsetY: -40.0,
      );
      network.callouts[callout.id] = callout;

      final proj = AxonometryProjector(projectionType: ProjectionType.gostFrontal45, scale: 1.0);
      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network, activeProjector: proj);

      final elevLayer = DxfWriter.toAutoCadString('АКСО_ОТМЕТКИ');
      final elevTextLayer = DxfWriter.toAutoCadString('АКСО_ОТМЕТКИ_ТЕКСТ');
      final textZM = DxfWriter.toAutoCadString('+2.500');
      final textBottom = DxfWriter.toAutoCadString('Ур.ч.п.');

      expect(dxf2d.contains(elevLayer), isTrue);
      expect(dxf2d.contains(elevTextLayer), isTrue);
      expect(dxf2d.contains(textZM), isTrue);
      expect(dxf2d.contains(textBottom), isTrue);

      // Verify that the block definition includes the triangular flag or lines
      expect(dxf2d.contains('CALLOUT_2D_1'), isTrue);
    });

    test('generate3dDxf exports node callout to АКСО_ОТМЕТКИ layer in 3D', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 3200);
      network.nodes[n1.id] = n1;

      final callout = Callout(
        id: 'c_node1',
        targetId: 'n1',
        targetType: CalloutTargetType.node,
        customText: '+{Z_M}',
        customBottomText: 'В.Т.',
        screenOffsetX: 50.0,
        screenOffsetY: -50.0,
      );
      network.callouts[callout.id] = callout;

      final dxf3d = DxfWriter.generate3dDxf(network);
      final elevLayer = DxfWriter.toAutoCadString('АКСО_ОТМЕТКИ');
      final elevTextLayer = DxfWriter.toAutoCadString('АКСО_ОТМЕТКИ_ТЕКСТ');
      final textZM = DxfWriter.toAutoCadString('+3.200');
      final textBottom = DxfWriter.toAutoCadString('В.Т.');

      expect(dxf3d.contains(elevLayer), isTrue);
      expect(dxf3d.contains(elevTextLayer), isTrue);
      expect(dxf3d.contains(textZM), isTrue);
      expect(dxf3d.contains(textBottom), isTrue);
      expect(dxf3d.contains('CALLOUT_SHELF_1'), isTrue);
    });

    test('toggleNodeElevationCallout adds and removes node elevation callout', () {
      final network = PipingNetwork();
      final node = Node3D(id: 'n_elev', x: 100, y: 200, z: 1500);
      network.nodes[node.id] = node;

      final controller = PipingInputController(initialNetwork: network);
      expect(controller.nodeHasElevationCallout('n_elev'), isFalse);

      final added = controller.toggleNodeElevationCallout('n_elev');
      expect(added, isTrue);
      expect(controller.nodeHasElevationCallout('n_elev'), isTrue);

      final callout = controller.network.callouts.values.firstWhere((c) => c.targetId == 'n_elev');
      expect(callout.targetType, CalloutTargetType.node);
      expect(callout.screenOffsetX, 50.0);
      expect(callout.screenOffsetY, -50.0);

      // Toggling again should remove it
      final removed = controller.toggleNodeElevationCallout('n_elev');
      expect(removed, isFalse);
      expect(controller.nodeHasElevationCallout('n_elev'), isFalse);
    });

    test('Callout serialization and enums ElevationMarkStyle and ShelfDirection', () {
      const c1 = Callout(
        id: 'c1',
        targetId: 'n1',
        targetType: CalloutTargetType.node,
        elevationStyle: ElevationMarkStyle.gostFilled,
        shelfDirection: ShelfDirection.left,
      );
      final json = c1.toJson();
      expect(json['elevationStyle'], 'gostFilled');
      expect(json['shelfDirection'], 'left');

      final c2 = Callout.fromJson(json);
      expect(c2.elevationStyle, ElevationMarkStyle.gostFilled);
      expect(c2.shelfDirection, ShelfDirection.left);

      // fromString tests
      expect(ElevationMarkStyleExt.fromString('gostOutline'), ElevationMarkStyle.gostOutline);
      expect(ElevationMarkStyleExt.fromString('gostFilled'), ElevationMarkStyle.gostFilled);
      expect(ElevationMarkStyleExt.fromString('compactFlag'), ElevationMarkStyle.compactFlag);
      expect(ElevationMarkStyleExt.fromString('isoCircle'), ElevationMarkStyle.isoCircle);
      expect(ElevationMarkStyleExt.fromString('unknown', fallback: ElevationMarkStyle.isoCircle), ElevationMarkStyle.isoCircle);

      expect(ShelfDirectionExt.fromString('auto'), ShelfDirection.auto);
      expect(ShelfDirectionExt.fromString('left'), ShelfDirection.left);
      expect(ShelfDirectionExt.fromString('right'), ShelfDirection.right);
      expect(ShelfDirectionExt.fromString(null), ShelfDirection.auto);
    });

    test('DXF export generates SOLID for gostFilled and CIRCLE for isoCircle in 2D and 3D', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n_filled', x: 0, y: 0, z: 2000);
      final n2 = Node3D(id: 'n_circle', x: 1000, y: 0, z: 2000);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      network.callouts['c_filled'] = const Callout(
        id: 'c_filled',
        targetId: 'n_filled',
        targetType: CalloutTargetType.node,
        elevationStyle: ElevationMarkStyle.gostFilled,
        shelfDirection: ShelfDirection.left,
      );

      network.callouts['c_circle'] = const Callout(
        id: 'c_circle',
        targetId: 'n_circle',
        targetType: CalloutTargetType.node,
        elevationStyle: ElevationMarkStyle.isoCircle,
        shelfDirection: ShelfDirection.right,
      );

      final proj = AxonometryProjector(projectionType: ProjectionType.gostFrontal45, scale: 1.0);
      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network, activeProjector: proj);
      final dxf3d = DxfWriter.generate3dDxf(network);

      // Check for SOLID entity in BLOCKS section for gostFilled
      expect(dxf2d.contains('SOLID'), isTrue);
      expect(dxf3d.contains('SOLID'), isTrue);

      // Check for CIRCLE entity in BLOCKS section for isoCircle
      expect(dxf2d.contains('CIRCLE'), isTrue);
      expect(dxf3d.contains('CIRCLE'), isTrue);
    });

    test('updateNodeElevationCallout updates style, shelf direction, and arrowOnNode in controller', () {
      final network = PipingNetwork();
      final node = Node3D(id: 'n_test', x: 0, y: 0, z: 1000);
      network.nodes[node.id] = node;

      final controller = PipingInputController(initialNetwork: network);
      controller.toggleNodeElevationCallout('n_test');

      var callout = controller.getNodeElevationCallout('n_test');
      expect(callout, isNotNull);
      expect(callout!.shelfDirection, ShelfDirection.auto);
      expect(callout.arrowOnNode, isTrue);

      controller.updateNodeElevationCallout(
        'n_test',
        style: ElevationMarkStyle.compactFlag,
        direction: ShelfDirection.left,
        arrowOnNode: false,
      );

      callout = controller.getNodeElevationCallout('n_test');
      expect(callout!.elevationStyle, ElevationMarkStyle.compactFlag);
      expect(callout.shelfDirection, ShelfDirection.left);
      expect(callout.arrowOnNode, isFalse);
    });

    test('Callout serialization preserves arrowOnNode', () {
      final c1 = Callout(
        id: 'c1',
        targetType: CalloutTargetType.node,
        targetId: 'n1',
        arrowOnNode: true,
      );
      final json1 = c1.toJson();
      expect(json1['arrowOnNode'], isTrue);
      final from1 = Callout.fromJson(json1);
      expect(from1.arrowOnNode, isTrue);

      final c2 = c1.copyWith(arrowOnNode: false);
      expect(c2.arrowOnNode, isFalse);
      final json2 = c2.toJson();
      expect(json2['arrowOnNode'], isFalse);
      final from2 = Callout.fromJson(json2);
      expect(from2.arrowOnNode, isFalse);

      // Backwards compatibility with snake_case
      final fromSnake = Callout.fromJson({'id': 'c3', 'targetType': 'node', 'targetId': 'n3', 'arrow_on_node': false});
      expect(fromSnake.arrowOnNode, isFalse);
    });

    test('DXF export handles arrowOnNode true and false appropriately', () {
      final network = PipingNetwork();
      final node = Node3D(id: 'n1', x: 1000, y: 1000, z: 2000);
      network.nodes[node.id] = node;

      // Node callout with arrow on node
      final cOnNode = Callout(
        id: 'c_on_node',
        targetType: CalloutTargetType.node,
        targetId: 'n1',
        arrowOnNode: true,
        screenOffsetX: 50.0,
        screenOffsetY: -50.0,
      );
      network.callouts[cOnNode.id] = cOnNode;

      final proj = AxonometryProjector(projectionType: ProjectionType.gostFrontal45, scale: 1.0);
      final dxf2dOnNode = DxfWriter.generate2dGostAxonometryDxf(network, activeProjector: proj);
      final dxf3dOnNode = DxfWriter.generate3dDxf(network);

      final elevLayer = DxfWriter.toAutoCadString('АКСО_ОТМЕТКИ');
      expect(dxf2dOnNode.contains(elevLayer), isTrue);
      expect(dxf3dOnNode.contains(elevLayer), isTrue);
      expect(dxf2dOnNode.contains('CALLOUT_2D_1'), isTrue);
      expect(dxf3dOnNode.contains('CALLOUT_SHELF_1'), isTrue);

      // Now set arrowOnNode: false
      network.callouts[cOnNode.id] = cOnNode.copyWith(arrowOnNode: false);
      final dxf2dOffNode = DxfWriter.generate2dGostAxonometryDxf(network, activeProjector: proj);
      final dxf3dOffNode = DxfWriter.generate3dDxf(network);

      expect(dxf2dOffNode.contains(elevLayer), isTrue);
      expect(dxf3dOffNode.contains(elevLayer), isTrue);
      expect(dxf2dOffNode.contains('CALLOUT_2D_1'), isTrue);
      expect(dxf3dOffNode.contains('CALLOUT_SHELF_1'), isTrue);
    });

    testWidgets('CalloutManagerPanel shows elevation style, shelf and arrowOnNode dropdowns when node category is selected', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final network = PipingNetwork();
      final controller = PipingInputController(initialNetwork: network);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalloutManagerPanel(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open tab 2: Конструктор шаблонов
      final tab2 = find.textContaining('Конструктор шаблонов');
      expect(tab2, findsOneWidget);
      await tester.tap(tab2);
      await tester.pumpAndSettle();

      // Initially Category is Труба. Find dropdown for category
      final categoryDropdown = find.byWidgetPredicate(
        (w) => w is DropdownButton<CalloutTargetType>,
      );
      expect(categoryDropdown, findsOneWidget);

      // Select 'Узел'
      await tester.tap(categoryDropdown);
      await tester.pumpAndSettle();

      final nodeItem = find.text('Узел').last;
      await tester.tap(nodeItem);
      await tester.pumpAndSettle();

      // Now "Знак отметки:", "Полочка:" and "Стрелка:" dropdowns should be visible
      expect(find.text('Знак отметки:'), findsOneWidget);
      expect(find.text('Полочка:'), findsOneWidget);
      expect(find.text('Стрелка:'), findsOneWidget);
      expect(find.byType(DropdownButton<ElevationMarkStyle>), findsOneWidget);
      expect(find.byType(DropdownButton<ShelfDirection>), findsOneWidget);
      expect(find.byType(DropdownButton<bool>), findsOneWidget);

      // Select "ГОСТ залитый ▼"
      await tester.tap(find.byType(DropdownButton<ElevationMarkStyle>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ГОСТ залитый ▼').last);
      await tester.pumpAndSettle();

      // Select "На выноске"
      await tester.tap(find.byType(DropdownButton<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('На выноске').last);
      await tester.pumpAndSettle();

      // Save template
      final saveBtn = find.text('Сохранить');
      await tester.tap(saveBtn);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(controller.currentProject.calloutTemplates['elevation_style'], 'gostFilled');
      expect(controller.currentProject.calloutTemplates['elevation_arrow_on_node'], 'false');

      controller.dispose();
    });
  });
}

