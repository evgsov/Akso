import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/weld_joint_style.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/vector_scene.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/services/sheet_geometry_builder.dart';

void main() {
  group('SheetGeometryBuilder', () {
    test('builds scene with frame, pipes and spools without phantom gaps', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = PipeSegment(id: 'seg_1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'sys_1');
      network.segments[seg.id] = seg;

      // Add a weld in the middle
      final weld = WeldJoint(id: 'w1', segmentId: 'seg_1', ratio: 0.5, number: 1, stamp: 'W1');
      network.weldJoints[weld.id] = weld;
      network.recalculateSpools();

      expect(network.spools.length, equals(2));

      final sheet = DrawingSheet.createDefault(id: 'sheet_1', name: 'Лист 1', sheetNumber: 1);
      final scene = SheetGeometryBuilder.buildScene(sheet: sheet, network: network);

      expect(scene.widthMm, equals(sheet.format.widthMm));
      expect(scene.heightMm, equals(sheet.format.heightMm));

      final pipeItems = scene.items.where((it) => it.layer == VectorSceneLayer.pipes).toList();
      // Should have 2 polylines for the 2 spools, both having smoothJoin == true
      expect(pipeItems.length, equals(2));
      for (final it in pipeItems) {
        final poly = it.primitive as VectorPolyline;
        expect(poly.smoothJoin, isTrue);
        expect(poly.points.length, equals(2));
      }

      // Check weld item
      final weldItems = scene.items.where((it) => it.layer == VectorSceneLayer.welds).toList();
      expect(weldItems, isNotEmpty);

      // Check frame and stamp
      final frameItems = scene.items.where((it) => it.layer == VectorSceneLayer.frameAndStamp).toList();
      expect(frameItems, isNotEmpty);
    });

    test('builds elbow as a continuous smooth polyline rather than disconnected segments', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 1000, z: 0);
      final nCenter = Node3D(id: 'nCenter', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[nCenter.id] = nCenter;
      network.nodes[n2.id] = n2;

      final s1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'nCenter', dn: 50, systemId: 'sys_1');
      final s2 = PipeSegment(id: 's2', startNodeId: 'nCenter', endNodeId: 'n2', dn: 50, systemId: 'sys_1');
      network.segments[s1.id] = s1;
      network.segments[s2.id] = s2;

      final elbow = Fitting(id: 'fit_1', nodeId: 'nCenter', fittingType: FittingType.elbow90, dn: 50, radiusMm: 50.0);
      network.fittings[nCenter.id] = elbow;

      final sheet = DrawingSheet.createDefault(id: 'sheet_1', name: 'Лист 1', sheetNumber: 1);
      final scene = SheetGeometryBuilder.buildScene(sheet: sheet, network: network);

      final fittingItems = scene.items.where((it) => it.layer == VectorSceneLayer.fittings).toList();
      expect(fittingItems, isNotEmpty);

      final poly = fittingItems.first.primitive as VectorPolyline;
      expect(poly.smoothJoin, isTrue);
      // Continuous polyline has 9 points (8 segments)
      expect(poly.points.length, greaterThanOrEqualTo(8));
    });

    test('supports 3D ring style for welds', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'sys_1');
      network.segments[seg.id] = seg;

      final weld = WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.5, number: 1, stamp: 'W1', style: WeldJointStyle.ring3d);
      network.weldJoints[weld.id] = weld;

      final sheet = DrawingSheet.createDefault(id: 'sheet_1', name: 'Лист 1', sheetNumber: 1);
      final scene = SheetGeometryBuilder.buildScene(sheet: sheet, network: network);

      final weldItems = scene.items.where((it) => it.layer == VectorSceneLayer.welds).toList();
      // ring3d produces a 16-segment spatial ring
      expect(weldItems.length, equals(16));
      for (final it in weldItems) {
        final poly = it.primitive as VectorPolyline;
        expect(poly.smoothJoin, isTrue);
      }
    });

    test('includes all GOST 21.101-2020 Form 3 title block lines matching SheetCanvasPainter', () {
      final network = PipingNetwork();
      final sheet = DrawingSheet.createDefault(id: 'sheet_1', name: 'Лист 1', sheetNumber: 1);
      final scene = SheetGeometryBuilder.buildScene(sheet: sheet, network: network);

      final polylines = scene.items
          .where((it) => it.layer == VectorSceneLayer.frameAndStamp && it.primitive is VectorPolyline)
          .map((it) => it.primitive as VectorPolyline)
          .toList();

      final stampRight = sheet.format.widthMm - sheet.format.frameRightMm;
      final stampBottom = sheet.format.heightMm - sheet.format.frameBottomMm;
      final stampLeft = stampRight - 185.0;
      final stampTop = stampBottom - 55.0;
      final xApprovalsEnd = stampLeft + 65.0;
      final xStageStart = stampLeft + 135.0;

      bool hasSegment(double x1, double y1, double x2, double y2) {
        return polylines.any((p) =>
            p.points.length == 2 &&
            (p.points[0].dx - x1).abs() < 0.01 &&
            (p.points[0].dy - y1).abs() < 0.01 &&
            (p.points[1].dx - x2).abs() < 0.01 &&
            (p.points[1].dy - y2).abs() < 0.01);
      }

      // 1. Horizontal divider between Graph 4 (documentCode) and Graph 1 (projectName)
      expect(hasSegment(xApprovalsEnd, stampTop + 10.0, stampRight, stampTop + 10.0), isTrue);

      // 2. Horizontal divider at stampTop + 40.0 spanning from xApprovalsEnd to stampRight (Graph 2 / Graph 3 & Stage/Organization)
      expect(hasSegment(xApprovalsEnd, stampTop + 40.0, stampRight, stampTop + 40.0), isTrue);

      // 3. Vertical divider at xStageStart from stampTop + 25.0 to stampBottom (Graph 3 / Graph 9)
      expect(hasSegment(xStageStart, stampTop + 25.0, xStageStart, stampBottom), isTrue);

      // 4. Vertical dividers for Стадия | Лист | Листов starting from stampTop + 25.0 to stampTop + 40.0
      expect(hasSegment(xStageStart + 15.0, stampTop + 25.0, xStageStart + 15.0, stampTop + 40.0), isTrue);
      expect(hasSegment(xStageStart + 30.0, stampTop + 25.0, xStageStart + 30.0, stampTop + 40.0), isTrue);

      // 5. Approval role/surname vertical divider at stampLeft + 20.0 (from stampTop + 25.0 to stampBottom)
      expect(hasSegment(stampLeft + 20.0, stampTop + 25.0, stampLeft + 20.0, stampBottom), isTrue);
    });

    test('aligns callout text directly on shelf without opaque white mask and respects ShelfDirection', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = PipeSegment(id: 'seg_1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'sys_1');
      network.segments[seg.id] = seg;

      // Callout with positive offsetX but explicit ShelfDirection.left
      final callout = Callout(
        id: 'c_left',
        targetType: CalloutTargetType.segment,
        targetId: 'seg_1',
        customText: 'Труба Ду50',
        screenOffsetX: 30.0,
        screenOffsetY: -25.0,
        shelfDirection: ShelfDirection.left,
      );
      network.callouts[callout.id] = callout;

      final sheet = DrawingSheet.createDefault(id: 'sheet_1', name: 'Лист 1', sheetNumber: 1);
      final scene = SheetGeometryBuilder.buildScene(
        sheet: sheet,
        network: network,
        measureTextWidthMm: (text, fontSizeMm, {isBold = false}) => 14.0,
      );

      final calloutItems = scene.items.where((it) => it.layer == VectorSceneLayer.callouts).toList();
      final polylines = calloutItems.where((it) => it.primitive is VectorPolyline).map((it) => it.primitive as VectorPolyline).toList();
      final texts = calloutItems.where((it) => it.primitive is VectorText).map((it) => it.primitive as VectorText).toList();

      expect(polylines, hasLength(2));
      expect(texts, hasLength(1));

      final shelfPoly = polylines[1];
      expect(shelfPoly.points.length, equals(2));
      final leaderEnd = shelfPoly.points[0];
      final shelfEnd = shelfPoly.points[1];

      // Shelf must go left because shelfDirection == ShelfDirection.left
      expect(shelfEnd.dx, lessThan(leaderEnd.dx));
      // Shelf length must equal measured width (14.0) + 2.0mm padding = 16.0mm
      expect((leaderEnd.dx - shelfEnd.dx), closeTo(16.0, 0.001));

      final vt = texts.first;
      // Text must NOT have an opaque white mask that erases pipes or the shelf line
      expect(vt.maskFillColorValue, isNull);
      // Text must start at shelfEnd.dx + 1.0mm (centered on the 16.0mm shelf)
      expect(vt.position.dx, closeTo(shelfEnd.dx + 1.0, 0.001));
    });
  });
}

