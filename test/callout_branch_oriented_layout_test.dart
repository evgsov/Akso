import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/sheet_format.dart';
import 'package:akso/domain/enums/sheet_format_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';
import 'package:akso/domain/services/viewport_transform_service.dart';

void main() {
  const projector = AxonometryProjector();

  group('Branch-Oriented Mini-Stack Layout Engine', () {
    test('places callouts locally beside branch rather than on sheet boundary margins', () {
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 1000, y: 1000, z: 0),
          'n2': const Node3D(id: 'n2', x: 2000, y: 1000, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.3, name: 'Кран 1', dn: 50, lengthMm: 100, valveType: ValveType.ballValve),
          'v2': const Valve(id: 'v2', segmentId: 's1', ratio: 0.7, name: 'Кран 2', dn: 50, lengthMm: 100, valveType: ValveType.ballValve),
        },
        callouts: {
          'c1': const Callout(id: 'c1', targetType: CalloutTargetType.valve, targetId: 'v1', textHeight: 3.5),
          'c2': const Callout(id: 'c2', targetType: CalloutTargetType.valve, targetId: 'v2', textHeight: 3.5),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
        sheetNumber: 1,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 1500, modelCenterY: 1000),
      );

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      expect(layout.length, equals(2));

      for (final entry in layout.entries) {
        final c = net.callouts[entry.key]!;
        final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
        final raw = projector.projectRaw(anchor.x, anchor.y, anchor.z);
        final anchorMm = ViewportTransformService.model2dToSheetMm(raw, sheet.viewport);
        final offMm = entry.value * 0.35;
        final shelfStart = anchorMm + offMm;

        final distToAnchor = (shelfStart - anchorMm).distance;
        // Local placement: clearance should be beside branch (approx 14 to 35 mm), not 150+ mm to sheet edges!
        expect(distToAnchor, greaterThanOrEqualTo(12.0));
        expect(distToAnchor, lessThanOrEqualTo(45.0));

        // Confirm NOT on sheet margins (left frame is 22 mm, right frame is 415 mm)
        expect(shelfStart.dx, greaterThan(60.0));
        expect(shelfStart.dx, lessThan(360.0));
      }
    });

    test('arranges shelves vertically in a mini-stack with dynamic adaptive pitch', () {
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 2000, y: 0, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 80, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.2, name: 'Кран 1', dn: 80, lengthMm: 120, valveType: ValveType.ballValve),
          'v2': const Valve(id: 'v2', segmentId: 's1', ratio: 0.5, name: 'Кран 2', dn: 80, lengthMm: 120, valveType: ValveType.ballValve),
          'v3': const Valve(id: 'v3', segmentId: 's1', ratio: 0.8, name: 'Кран 3', dn: 80, lengthMm: 120, valveType: ValveType.ballValve),
        },
        callouts: {
          'c1': const Callout(id: 'c1', targetType: CalloutTargetType.valve, targetId: 'v1', textHeight: 3.5),
          'c2': const Callout(id: 'c2', targetType: CalloutTargetType.valve, targetId: 'v2', textHeight: 3.5),
          'c3': const Callout(id: 'c3', targetType: CalloutTargetType.valve, targetId: 'v3', textHeight: 3.5),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_pitch',
        name: 'Sheet Pitch',
        sheetNumber: 1,
        groupMultiLevelCallouts: false,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 1000, modelCenterY: 0),
      );

      // 1. With default pitch (approx 2.1 * textHeight = 7.35 mm)
      final layoutDefault = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      final shelfStartsDefault = <Offset>[];
      for (final id in ['c1', 'c2', 'c3']) {
        final c = net.callouts[id]!;
        final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
        final raw = projector.projectRaw(anchor.x, anchor.y, anchor.z);
        final anchorMm = ViewportTransformService.model2dToSheetMm(raw, sheet.viewport);
        final offMm = layoutDefault[id]! * 0.35;
        shelfStartsDefault.add(anchorMm + offMm);
      }

      // All shelves in mini-stack share the same vertical alignment axis Xstack
      expect((shelfStartsDefault[0].dx - shelfStartsDefault[1].dx).abs(), lessThan(0.01));
      expect((shelfStartsDefault[1].dx - shelfStartsDefault[2].dx).abs(), lessThan(0.01));

      // Vertical distance matches adaptive pitch
      final dy01 = (shelfStartsDefault[1].dy - shelfStartsDefault[0].dy).abs();
      final dy12 = (shelfStartsDefault[2].dy - shelfStartsDefault[1].dy).abs();
      expect(dy01, closeTo(3.5 * 2.1, 0.5));
      expect(dy12, closeTo(3.5 * 2.1, 0.5));

      // 2. With customPitchMm
      final layoutCustom = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
        customPitchMm: 9.0,
      );

      final shelfStartsCustom = <Offset>[];
      for (final id in ['c1', 'c2', 'c3']) {
        final c = net.callouts[id]!;
        final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
        final raw = projector.projectRaw(anchor.x, anchor.y, anchor.z);
        final anchorMm = ViewportTransformService.model2dToSheetMm(raw, sheet.viewport);
        final offMm = layoutCustom[id]! * 0.35;
        shelfStartsCustom.add(anchorMm + offMm);
      }

      final dyCustom01 = (shelfStartsCustom[1].dy - shelfStartsCustom[0].dy).abs();
      expect(dyCustom01, closeTo(9.0, 0.1));
    });

    test('guarantees zero leader line crossings along the branch', () {
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 1500, y: 1500, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.15, name: 'Вентиль 1', dn: 50, lengthMm: 100, valveType: ValveType.gateValve),
          'v2': const Valve(id: 'v2', segmentId: 's1', ratio: 0.35, name: 'Вентиль 2', dn: 50, lengthMm: 100, valveType: ValveType.gateValve),
          'v3': const Valve(id: 'v3', segmentId: 's1', ratio: 0.55, name: 'Вентиль 3', dn: 50, lengthMm: 100, valveType: ValveType.gateValve),
          'v4': const Valve(id: 'v4', segmentId: 's1', ratio: 0.75, name: 'Вентиль 4', dn: 50, lengthMm: 100, valveType: ValveType.gateValve),
          'v5': const Valve(id: 'v5', segmentId: 's1', ratio: 0.90, name: 'Вентиль 5', dn: 50, lengthMm: 100, valveType: ValveType.gateValve),
        },
        callouts: {
          'c1': const Callout(id: 'c1', targetType: CalloutTargetType.valve, targetId: 'v1', textHeight: 3.5),
          'c2': const Callout(id: 'c2', targetType: CalloutTargetType.valve, targetId: 'v2', textHeight: 3.5),
          'c3': const Callout(id: 'c3', targetType: CalloutTargetType.valve, targetId: 'v3', textHeight: 3.5),
          'c4': const Callout(id: 'c4', targetType: CalloutTargetType.valve, targetId: 'v4', textHeight: 3.5),
          'c5': const Callout(id: 'c5', targetType: CalloutTargetType.valve, targetId: 'v5', textHeight: 3.5),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_crossing',
        name: 'Sheet Crossings',
        sheetNumber: 1,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 750, modelCenterY: 750),
      );

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      expect(layout.length, equals(5));

      final leaders = <List<Offset>>[];
      for (final entry in layout.entries) {
        final c = net.callouts[entry.key]!;
        final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
        final raw = projector.projectRaw(anchor.x, anchor.y, anchor.z);
        final anchorMm = ViewportTransformService.model2dToSheetMm(raw, sheet.viewport);
        final shelfStart = anchorMm + entry.value * 0.35;
        leaders.add([anchorMm, shelfStart]);
      }

      bool segmentsIntersect(Offset a1, Offset a2, Offset b1, Offset b2) {
        double ccw(Offset a, Offset b, Offset c) {
          return (c.dy - a.dy) * (b.dx - a.dx) - (b.dy - a.dy) * (c.dx - a.dx);
        }
        return (ccw(a1, b1, b2) * ccw(a2, b1, b2) < 0) &&
               (ccw(a1, a2, b1) * ccw(a1, a2, b2) < 0);
      }

      for (int i = 0; i < leaders.length; i++) {
        for (int j = i + 1; j < leaders.length; j++) {
          final cross = segmentsIntersect(leaders[i][0], leaders[i][1], leaders[j][0], leaders[j][1]);
          expect(cross, isFalse, reason: 'Leader lines $i and $j intersect!');
        }
      }
    });

    test('strictly avoids sheet stamp (185x55 mm) and specification tables', () {
      // Pipe placed near bottom-right corner where stamp is located
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 2500, y: 2000, z: 0),
          'n2': const Node3D(id: 'n2', x: 3500, y: 2000, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.5, name: 'Задвижка', dn: 100, lengthMm: 150, valveType: ValveType.gateValve),
        },
        callouts: {
          'c1': const Callout(id: 'c1', targetType: CalloutTargetType.valve, targetId: 'v1', textHeight: 3.5),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_stamp',
        name: 'Sheet Stamp Avoidance',
        sheetNumber: 1,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 3000, modelCenterY: 2000),
        tables: const [
          SheetTableItem(
            id: 'spec_table',
            type: SheetTableType.materialsSpecification,
            xMm: 230.0,
            yMm: 100.0,
            widthMm: 185.0,
            heightMm: 60.0,
          ),
        ],
      );

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      expect(layout.containsKey('c1'), isTrue);

      final c = net.callouts['c1']!;
      final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
      final raw = projector.projectRaw(anchor.x, anchor.y, anchor.z);
      final anchorMm = ViewportTransformService.model2dToSheetMm(raw, sheet.viewport);
      final shelfStart = anchorMm + layout['c1']! * 0.35;

      // Stamp Rect: A3 landscape 420x297, frameRight=5, frameBottom=5 -> 230..415, 237..292
      final stampRect = Rect.fromLTWH(
        420.0 - 5.0 - 185.0,
        297.0 - 5.0 - 55.0,
        185.0,
        55.0,
      );

      final tableRect = const Rect.fromLTWH(230.0, 100.0, 185.0, 60.0);

      expect(stampRect.contains(shelfStart), isFalse);
      expect(tableRect.contains(shelfStart), isFalse);
    });

    test('groupMultiLevelCallouts merges co-located items when true and keeps separate when false', () {
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 1000, y: 0, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.5, name: 'Кран', dn: 50, lengthMm: 100, valveType: ValveType.ballValve),
        },
        weldJoints: {
          'w1': const WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.5, number: 1, stamp: '1'),
        },
        callouts: {
          'c_valve': const Callout(id: 'c_valve', targetType: CalloutTargetType.valve, targetId: 'v1', textHeight: 3.5),
          'c_weld': const Callout(id: 'c_weld', targetType: CalloutTargetType.weld, targetId: 'w1', textHeight: 3.5),
        },
      );

      final sheetGrouped = DrawingSheet(
        id: 'sheet_grouped',
        name: 'Grouped',
        sheetNumber: 1,
        groupMultiLevelCallouts: true,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 500, modelCenterY: 0),
      );

      final layoutGrouped = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheetGrouped,
        network: net,
        projector: projector,
      );

      expect(layoutGrouped.length, equals(2));
      final offValveG = layoutGrouped['c_valve']! * 0.35;
      final offWeldG = layoutGrouped['c_weld']! * 0.35;

      // Both items in multi-level cluster share identical dx
      expect((offValveG.dx - offWeldG.dx).abs(), lessThan(0.01));
      // Stacked vertically by pitch
      expect((offValveG.dy - offWeldG.dy).abs(), greaterThanOrEqualTo(3.5 + 1.0));

      final sheetUngrouped = DrawingSheet(
        id: 'sheet_ungrouped',
        name: 'Ungrouped',
        sheetNumber: 1,
        groupMultiLevelCallouts: false,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 500, modelCenterY: 0),
      );

      final layoutUngrouped = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheetUngrouped,
        network: net,
        projector: projector,
      );

      expect(layoutUngrouped.length, equals(2));
    });

    test('elevation callouts stay isolated next to their nodes', () {
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 500, y: 500, z: 1200),
        },
        callouts: {
          'c_elev': const Callout(
            id: 'c_elev',
            targetId: 'n1',
            targetType: CalloutTargetType.node,
            elevationStyle: ElevationMarkStyle.gostOutline,
            textHeight: 3.5,
          ),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_elev',
        name: 'Sheet Elevation',
        sheetNumber: 1,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 500, modelCenterY: 500),
      );

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      expect(layout.length, equals(1));
      final offMm = layout['c_elev']! * 0.35;

      // dx is strictly 0.0 (directly above the node)
      expect(offMm.dx, equals(0.0));
      // dy is strictly negative: -(textHeight * 2.2 + 3.0)
      final expectedDy = -(3.5 * 2.2 + 3.0);
      expect(offMm.dy, closeTo(expectedDy, 0.001));
    });

    test('splits into multi-tier columns when branch items exceed 6', () {
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 4000, y: 0, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'T1'),
        },
        valves: {
          for (int i = 1; i <= 8; i++)
            'v$i': Valve(id: 'v$i', segmentId: 's1', ratio: i / 10.0, name: 'Кран $i', dn: 100, lengthMm: 100, valveType: ValveType.ballValve),
        },
        callouts: {
          for (int i = 1; i <= 8; i++)
            'c$i': Callout(id: 'c$i', targetType: CalloutTargetType.valve, targetId: 'v$i', textHeight: 3.5),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_multitier',
        name: 'Multi-Tier Sheet',
        sheetNumber: 1,
        groupMultiLevelCallouts: false,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 2000, modelCenterY: 0),
      );

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      expect(layout.length, equals(8));

      // With 8 items (> 6), shelves should be distributed into more than 1 column X coordinate
      final xCoords = <double>{};
      for (final entry in layout.entries) {
        final c = net.callouts[entry.key]!;
        final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
        final raw = projector.projectRaw(anchor.x, anchor.y, anchor.z);
        final anchorMm = ViewportTransformService.model2dToSheetMm(raw, sheet.viewport);
        final shelfStart = anchorMm + entry.value * 0.35;
        // Round to 1 decimal place to group by column
        xCoords.add((shelfStart.dx * 10).round() / 10.0);
      }

      // Should have at least 2 distinct tier columns
      expect(xCoords.length, greaterThanOrEqualTo(2));
    });
  });
}
