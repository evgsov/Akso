import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/services/element_3d_geometry.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/painters/support_painter.dart';
import 'package:akso/ui/features/editor/widgets/desktop_cad_layout.dart';

void main() {
  group('Fitting Selection & Hit-Testing Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      controller = PipingInputController(network: network);
      controller.enableDragDelay = false;
    });

    tearDown(() {
      controller.dispose();
    });

    test('Hit-testing and selecting an Elbow fitting along its curve', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 1000, y: 1000, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 100);

      const elbow = Fitting(
        id: 'fit_elbow',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
      );
      network.fittings['n2'] = elbow;

      final elbowScreenPos = controller.projector.project(const Node3D(id: 'test', x: 1000, y: 0, z: 0));
      final hitNode = controller.findFittingAtScreenPos(elbowScreenPos);
      expect(hitNode, equals('n2'));

      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(elbowScreenPos);
      expect(controller.selectedNodeId, equals('n2'));
      expect(controller.network.fittings.containsKey('n2'), isTrue);
    });

    test('Hit-testing and selecting a Reducer fitting by its body wireframe', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50);

      const reducer = Fitting(
        id: 'fit_red',
        nodeId: 'n2',
        fittingType: FittingType.reducerConcentric,
        dn: 100,
        dnSecondary: 50,
        radiusMm: 60.0,
      );
      network.fittings['n2'] = reducer;

      final redPos = controller.projector.project(const Node3D(id: 't_red', x: 1000, y: 0, z: 0));
      final hitNode = controller.findFittingAtScreenPos(redPos);
      expect(hitNode, equals('n2'));

      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(redPos);
      expect(controller.selectedNodeId, equals('n2'));
      expect(controller.selectedSegmentId, isNull);
    });

    test('Hit-testing and selecting a Flange fitting on pipe end', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1500, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 80);

      const flange = Fitting(
        id: 'fit_flange',
        nodeId: 'n2',
        fittingType: FittingType.flange,
        dn: 80,
        radiusMm: 40.0,
        flangeConnectionType: FlangeConnectionType.toEquipment,
      );
      network.fittings['n2'] = flange;

      final flangePos = controller.projector.project(const Node3D(id: 't_flange', x: 1500, y: 0, z: 0));
      final hitNode = controller.findFittingAtScreenPos(flangePos);
      expect(hitNode, equals('n2'));

      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(flangePos);
      expect(controller.selectedNodeId, equals('n2'));
    });

    test('Hit-testing and selecting an Elliptical Cap fitting', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 800, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50);

      const cap = Fitting(
        id: 'fit_cap',
        nodeId: 'n2',
        fittingType: FittingType.cap,
        dn: 50,
        radiusMm: 25.0,
      );
      network.fittings['n2'] = cap;

      final capPos = controller.projector.project(const Node3D(id: 't_cap', x: 800, y: 0, z: 0));
      final hitNode = controller.findFittingAtScreenPos(capPos);
      expect(hitNode, equals('n2'));

      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(capPos);
      expect(controller.selectedNodeId, equals('n2'));
    });

    test('Hit-testing and selecting Tee and DirectBranch fittings', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.nodes['n4'] = const Node3D(id: 'n4', x: 1000, y: 1000, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 100);
      network.segments['s3'] = const PipeSegment(id: 's3', startNodeId: 'n2', endNodeId: 'n4', systemId: 'sys1', dn: 50);

      const tee = Fitting(
        id: 'fit_tee',
        nodeId: 'n2',
        fittingType: FittingType.tee,
        dn: 100,
        dnSecondary: 50,
        radiusMm: 100.0,
      );
      network.fittings['n2'] = tee;

      final teePos = controller.projector.project(const Node3D(id: 't_tee', x: 1000, y: 0, z: 0));
      expect(controller.findFittingAtScreenPos(teePos), equals('n2'));

      // Switch to direct branch
      network.fittings['n2'] = tee.copyWith(
        fittingType: FittingType.directBranch,
        radiusMm: 0.0,
      );
      expect(controller.findFittingAtScreenPos(teePos), equals('n2'));
    });
  });

  group('3D Support Wireframe & SupportPainter Tests', () {
    test('Element3dGeometry generates wireframes for all 4 support types', () {
      const start = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const end = Node3D(id: 'n2', x: 2000, y: 0, z: 0);

      for (final type in PipeSupportType.values) {
        final sup = PipeSupport(
          id: 'sup_${type.name}',
          segmentId: 's1',
          distanceRatio: 0.5,
          type: type,
        );

        final wireframes = Element3dGeometry.generateSupport3d(
          sup,
          start,
          end,
          pipeOuterDiameter: 89.0,
        );

        expect(wireframes, isNotEmpty);
        expect(wireframes.every((w) => w.layer == Element3dGeometry.layerSupports), isTrue);

        // Fixed support must have diagonal ribs
        if (type == PipeSupportType.fixed) {
          expect(wireframes.length, greaterThanOrEqualTo(20));
        }
        // Spring support must have helical coils
        if (type == PipeSupportType.spring) {
          expect(wireframes.length, greaterThanOrEqualTo(40));
        }
        // Guide support has side guide stops
        if (type == PipeSupportType.guide) {
          expect(wireframes.length, greaterThanOrEqualTo(24));
        }
      }
    });

    test('SupportPainter renders 3D wireframe in orbit3d projection mode', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      final support = PipeSupport(
        id: 'sup_test',
        segmentId: 's1',
        distanceRatio: 0.4,
        type: PipeSupportType.sliding,
        name: 'ОП-1',
      );
      network.supports[support.id] = support;

      final orbitProjector = AxonometryProjector(
        projectionType: ProjectionType.orbit3d,
        scale: 1.0,
        panOffset: Offset.zero,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      // Verify it paints without exceptions in 3D orbit mode
      expect(
        () => SupportPainter.paint(
          canvas,
          orbitProjector,
          network,
          selectedSupportId: support.id,
        ),
        returnsNormally,
      );

      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });
  });

  group('Fitting Inspector UI & DesktopCadLayout Widget Tests', () {
    testWidgets('Displays dedicated Fitting Inspector and modifies Reducer properties', (tester) async {
      final network = PipingNetwork();
      final controller = PipingInputController(network: network);
      controller.enableDragDelay = false;

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50);

      const reducer = Fitting(
        id: 'fit_red',
        nodeId: 'n2',
        fittingType: FittingType.reducerConcentric,
        dn: 100,
        dnSecondary: 50,
        radiusMm: 60.0,
        material: 'Сталь 20',
      );
      network.fittings['n2'] = reducer;
      controller.selectedNodeId = 'n2';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopCadLayout(
              controller: controller,
              canvasWidget: const SizedBox(width: 800, height: 600),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header shows fitting title
      expect(find.text('Переход концентрический'), findsOneWidget);
      expect(find.text('Исполнение перехода:'), findsOneWidget);
      expect(find.text('Концентр.'), findsOneWidget);
      expect(find.text('Эксцентр.'), findsOneWidget);

      // Tap eccentric toggle
      await tester.tap(find.text('Эксцентр.'));
      await tester.pumpAndSettle();

      expect(network.fittings['n2']?.fittingType, equals(FittingType.reducerEccentric));

      controller.dispose();
    });

    testWidgets('Displays dedicated Flange Inspector and toggles PN and Flip 180°', (tester) async {
      final network = PipingNetwork();
      final controller = PipingInputController(network: network);
      controller.enableDragDelay = false;

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 80);

      const flange = Fitting(
        id: 'fit_flange',
        nodeId: 'n2',
        fittingType: FittingType.flange,
        dn: 80,
        radiusMm: 40.0,
        pressurePn: 16,
        isFlangePair: true,
      );
      network.fittings['n2'] = flange;
      controller.selectedNodeId = 'n2';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopCadLayout(
              controller: controller,
              canvasWidget: const SizedBox(width: 800, height: 600),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Фланец'), findsOneWidget);
      expect(find.text('Давл. Ру:'), findsOneWidget);
      expect(find.text('PN 25'), findsOneWidget);

      // Tap PN 25 chip
      await tester.tap(find.text('PN 25'));
      await tester.pumpAndSettle();
      expect(network.fittings['n2']?.pressurePn, equals(25));

      // Tap Flip 180° button
      await tester.tap(find.text('Зеркало 0°'));
      await tester.pumpAndSettle();
      expect(network.fittings['n2']?.isFlipped, isTrue);

      controller.dispose();
    });

    testWidgets('Displays Cap Inspector and detaches cap', (tester) async {
      final network = PipingNetwork();
      final controller = PipingInputController(network: network);
      controller.enableDragDelay = false;

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50);

      const cap = Fitting(
        id: 'fit_cap',
        nodeId: 'n2',
        fittingType: FittingType.cap,
        dn: 50,
        radiusMm: 25.0,
      );
      network.fittings['n2'] = cap;
      controller.selectedNodeId = 'n2';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopCadLayout(
              controller: controller,
              canvasWidget: const SizedBox(width: 800, height: 600),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Заглушка (Днище)'), findsOneWidget);
      expect(find.text('Снять'), findsOneWidget);

      // Tap detach
      await tester.tap(find.text('Снять'));
      await tester.pumpAndSettle();

      expect(network.fittings.containsKey('n2'), isFalse);

      controller.dispose();
    });
  });
}
