import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/services/element_3d_geometry.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/ui/canvas/painters/pipe_painter.dart';
import 'package:akso/ui/canvas/painters/fitting_painter.dart';
import 'package:akso/ui/features/editor/widgets/fitting_properties_sheet.dart';
import 'package:akso/data/dxf/dxf_writer.dart';

void main() {
  group('Cap (Днище) Rendering & Calculations', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      network.nodes['n1'] = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['s1'] = PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'T1',
        dn: 100,
        wallThicknessMm: 4.5,
      );
    });

    test('Cap does not create void deduction in spool cut length', () {
      final cap = network.attachCapToNode('n2');
      expect(cap, isNotNull);
      expect(cap!.fittingType, FittingType.cap);

      network.recalculateSpools();
      final spool = network.spools.values.firstWhere((s) => s.segmentId == 's1');

      // Торец трубы должен доходить точно до узла (стыка) без образования пустоты
      expect(spool.cutLengthMm, closeTo(1000.0, 0.1));
      expect(spool.endPoint!.x, closeTo(1000.0, 0.1));
    });

    test('PipePainter.calcPipeTrimmedPoint for cap does not trim pipe away from node', () {
      network.attachCapToNode('n2');
      final p1 = const Offset(100, 200);
      final p2 = const Offset(500, 200);
      final seg = network.segments['s1']!;

      final trimmed = PipePainter.calcPipeTrimmedPoint(
        network: network,
        nodeId: 'n2',
        otherNodeId: 'n1',
        nodeScreen: p2,
        otherScreen: p1,
        seg: seg,
      );

      // Торец трубы должен заканчиваться ровно в p2 (узле приварки днища)
      expect(trimmed.dx, equals(p2.dx));
      expect(trimmed.dy, equals(p2.dy));
    });

    test('2D DXF export contains АКСО_ЗАГЛУШКИ and АКСО_ЗАГЛУШКИ_ТЕКСТ', () {
      network.attachCapToNode('n2');
      final dxf = DxfWriter.generate2dGostAxonometryDxf(network);

      final capLayer = DxfWriter.toAutoCadString('АКСО_ЗАГЛУШКИ');
      final capTextLayer = DxfWriter.toAutoCadString('АКСО_ЗАГЛУШКИ_ТЕКСТ');
      final capText = DxfWriter.toAutoCadString('Заглушка Ду100');

      expect(dxf.contains(capLayer), isTrue, reason: '2D DXF must contain АКСО_ЗАГЛУШКИ layer');
      expect(dxf.contains(capTextLayer), isTrue, reason: '2D DXF must contain АКСО_ЗАГЛУШКИ_ТЕКСТ layer');
      expect(dxf.contains(capText), isTrue);
    });

    test('3D wireframe and 3D DXF contains cap geometry at node', () {
      network.attachCapToNode('n2');
      final wireframes = Element3dGeometry.generateAllElements3d(network);
      expect(wireframes.any((w) => w.layer == Element3dGeometry.layerCaps), isTrue);

      final dxf3d = DxfWriter.generate3dDxf(network);
      final cap3dLayer = DxfWriter.toAutoCadString(Element3dGeometry.layerCaps);
      expect(dxf3d.contains(cap3dLayer), isTrue);
    });
  });

  group('Direct Branch (Прямая врезка У18) Rendering & Calculations', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      // Магистраль вдоль X: n1 -> n2 -> n3
      network.nodes['n1'] = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      // Ответвление вдоль Y: n2 -> n4
      network.nodes['n4'] = Node3D(id: 'n4', x: 1000, y: 500, z: 0);

      network.segments['s_main1'] = PipeSegment(
        id: 's_main1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'T1',
        dn: 100,
        wallThicknessMm: 4.5,
      );
      network.segments['s_main2'] = PipeSegment(
        id: 's_main2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'T1',
        dn: 100,
        wallThicknessMm: 4.5,
      );
      network.segments['s_branch'] = PipeSegment(
        id: 's_branch',
        startNodeId: 'n2',
        endNodeId: 'n4',
        systemId: 'T1',
        dn: 50,
        wallThicknessMm: 3.5,
      );

      // Устанавливаем прямую врезку в узел n2
      network.fittings['n2'] = Fitting(
        id: 'fit_n2',
        nodeId: 'n2',
        fittingType: FittingType.directBranch,
        dn: 100,
        dnSecondary: 50,
        radiusMm: 0.0,
        cutsMainPipe: false,
        weldType: WeldType.u18,
      );
    });

    test('Direct branch branch-segment trims flush to main pipe with zero gap', () {
      final pNode = const Offset(500, 300);
      final pBranchEnd = const Offset(500, 500); // ветка идет вниз
      final segBranch = network.segments['s_branch']!;

      final trimmed = PipePainter.calcPipeTrimmedPoint(
        network: network,
        nodeId: 'n2',
        otherNodeId: 'n4',
        nodeScreen: pNode,
        otherScreen: pBranchEnd,
        seg: segBranch,
      );

      // Труба ответвления должна доходить строго до оси магистрали (узла n2) без зазора
      final distTrim = (trimmed - pNode).distance;
      expect(distTrim, equals(0.0));
      expect(trimmed.dx, equals(pNode.dx));
      expect(trimmed.dy, equals(pNode.dy));
    });

    test('Direct branch spool with large diameter (DN400 / Ø426) has 0 mm deduction and connects flush at node', () {
      final net = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      final n3 = Node3D(id: 'n3', x: 4000, y: 0, z: 0);
      final nBranch = Node3D(id: 'nBranch', x: 2000, y: 1500, z: 0);

      net.nodes['n1'] = n1;
      net.nodes['n2'] = n2;
      net.nodes['n3'] = n3;
      net.nodes['nBranch'] = nBranch;

      net.segments['s_main1'] = PipeSegment(
        id: 's_main1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'T1',
        dn: 400,
        wallThicknessMm: 9.0,
      );
      net.segments['s_main2'] = PipeSegment(
        id: 's_main2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'T1',
        dn: 400,
        wallThicknessMm: 9.0,
      );
      net.segments['s_branch'] = PipeSegment(
        id: 's_branch',
        startNodeId: 'n2',
        endNodeId: 'nBranch',
        systemId: 'T1',
        dn: 200,
        wallThicknessMm: 6.0,
      );

      net.fittings['n2'] = Fitting(
        id: 'fit_direct',
        nodeId: 'n2',
        fittingType: FittingType.directBranch,
        dn: 400,
        dnSecondary: 200,
        radiusMm: 0.0,
        cutsMainPipe: false,
        weldType: WeldType.u18,
      );

      net.recalculateSpools();

      final branchSpool = net.spools.values.firstWhere((s) => s.segmentId == 's_branch');
      // Cut length must be L_заг = L_осев - R_маг = 1500 - 213 = 1287 mm, while startPoint is flush at node (2000, 0, 0)
      expect(branchSpool.cutLengthMm, closeTo(1287.0, 0.1));
      expect(branchSpool.startPoint?.x, closeTo(2000.0, 0.1));
      expect(branchSpool.startPoint?.y, closeTo(0.0, 0.1));
      expect(branchSpool.startPoint?.z, closeTo(0.0, 0.1));
    });

    test('Element3dGeometry generates wireframe for direct branch seam', () {
      final wireframes = Element3dGeometry.generateAllElements3d(network);
      expect(wireframes.any((w) => w.layer == 'АКСО_ВРЕЗКИ'), isTrue,
          reason: 'Should generate wireframe segments on layer АКСО_ВРЕЗКИ');
    });

    test('2D DXF export contains АКСО_ВРЕЗКИ and АКСО_СВАРКА_ТЕКСТ with leader', () {
      final dxf = DxfWriter.generate2dGostAxonometryDxf(network);
      final branchLayer = DxfWriter.toAutoCadString('АКСО_ВРЕЗКИ');
      final weldTextLayer = DxfWriter.toAutoCadString('АКСО_СВАРКА_ТЕКСТ');
      final branchText = DxfWriter.toAutoCadString('Врезка У18');

      expect(dxf.contains(branchLayer), isTrue);
      expect(dxf.contains(weldTextLayer), isTrue);
      expect(dxf.contains(branchText), isTrue);
    });

    test('3D DXF export contains 3D wireframe for direct branch on АКСО_ВРЕЗКИ', () {
      final dxf3d = DxfWriter.generate3dDxf(network);
      final branchLayer = DxfWriter.toAutoCadString('АКСО_ВРЕЗКИ');
      final branchText = DxfWriter.toAutoCadString('Врезка У18');

      expect(dxf3d.contains(branchLayer), isTrue);
      expect(dxf3d.contains(branchText), isTrue);
    });
  });

  group('Unified 3D Wireframe & Properties for Cap & Flange (like Reducers & Valves)', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      network.nodes['n1'] = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['s1'] = PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'T1',
        dn: 100,
        wallThicknessMm: 4.5,
      );
    });

    test('Element3dGeometry.generateCapWireframe generates 3D wireframe for elliptical and flat caps', () {
      final capElliptic = network.attachCapToNode('n2')!;
      final wireElliptic = Element3dGeometry.generateCapWireframe(
        capElliptic,
        network.nodes['n2']!,
        network.nodes['n1']!,
        pipeOuterDiameter: 108.0,
      );
      // Elliptical cap should have base segments, meridian arcs, and axial centerline
      expect(wireElliptic.length, greaterThanOrEqualTo(10));
      expect(wireElliptic.any((w) => w.layer == Element3dGeometry.layerCaps), isTrue);

      // Rotate cap +90 deg and verify rotation produces different coordinates
      final capRotated = capElliptic.copyWith(rotationAngleDeg: 90.0);
      final wireRotated = Element3dGeometry.generateCapWireframe(
        capRotated,
        network.nodes['n2']!,
        network.nodes['n1']!,
        pipeOuterDiameter: 108.0,
      );
      expect(wireRotated.length, equals(wireElliptic.length));
      expect(wireRotated.first.y1 != wireElliptic.first.y1 || wireRotated.first.z1 != wireElliptic.first.z1, isTrue);

      // Flat cap
      final capFlat = capElliptic.copyWith(standard: 'ОСТ 34.10.758', name: 'Заглушка плоская Ду100');
      final wireFlat = Element3dGeometry.generateCapWireframe(
        capFlat,
        network.nodes['n2']!,
        network.nodes['n1']!,
        pipeOuterDiameter: 108.0,
      );
      expect(wireFlat.isNotEmpty, isTrue);
      expect(wireFlat.length, lessThan(wireElliptic.length)); // flat has fewer segments than dome
    });

    test('Element3dGeometry.generateFlangeWireframe generates 3D wireframe for single, pair, blind and equipment flange', () {
      final flangePair = network.attachEndFlangeToNode('n2')!;
      final wirePair = Element3dGeometry.generateFlangeWireframe(
        flangePair,
        network.nodes['n2']!,
        network.nodes['n1']!,
        pipeOuterDiameter: 108.0,
      );
      expect(wirePair.length, greaterThanOrEqualTo(6));

      // Blind flange
      final flangeBlind = flangePair.copyWith(flangeConnectionType: FlangeConnectionType.blindFlange);
      final wireBlind = Element3dGeometry.generateFlangeWireframe(
        flangeBlind,
        network.nodes['n2']!,
        network.nodes['n1']!,
        pipeOuterDiameter: 108.0,
      );
      expect(wireBlind.isNotEmpty, isTrue);

      // Rotate flange +90 deg
      final flangeRotated = flangePair.copyWith(rotationAngleDeg: 90.0);
      final wireRot = Element3dGeometry.generateFlangeWireframe(
        flangeRotated,
        network.nodes['n2']!,
        network.nodes['n1']!,
        pipeOuterDiameter: 108.0,
      );
      expect(wireRot.first.y1 != wirePair.first.y1 || wireRot.first.z1 != wirePair.first.z1, isTrue);
    });

    test('FittingPainter paints Cap and Flange wireframe with selection glow when selected', () {
      network.attachCapToNode('n2');
      final projector = AxonometryProjector();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Paint unselected
      expect(
        () => FittingPainter.paint(canvas, projector, network, null, true),
        returnsNormally,
      );

      // Paint selected (triggers glow and selection stroke)
      expect(
        () => FittingPainter.paint(canvas, projector, network, 'n2', true),
        returnsNormally,
      );

      // Now attach flange and paint
      network.attachEndFlangeToNode('n2');
      expect(
        () => FittingPainter.paint(canvas, projector, network, 'n2', true),
        returnsNormally,
      );
    });

    testWidgets('FittingPropertiesSheet displays Cap options and Flange rotation controls', (tester) async {
      network.attachCapToNode('n2');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FittingPropertiesSheet(
            network: network,
            nodeId: 'n2',
          ),
        ),
      ));

      // Cap properties should show standard choices and rotation button
      expect(find.textContaining('Эллиптическое'), findsOneWidget);
      expect(find.textContaining('Плоское приварное'), findsOneWidget);
      expect(find.textContaining('Поворот вокруг оси'), findsOneWidget);

      // Now switch to Flange
      network.attachEndFlangeToNode('n2');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FittingPropertiesSheet(
            network: network,
            nodeId: 'n2',
          ),
        ),
      ));

      expect(find.textContaining('Поворот вокруг оси'), findsOneWidget);
      expect(find.textContaining('Толщина фланца'), findsOneWidget);
    });
  });
}
