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

  group('CalloutObstacleMap.segmentsIntersect API & Precision', () {
    test('detects intersection between crossing segments', () {
      const a1 = Offset(0.0, 0.0);
      const a2 = Offset(10.0, 10.0);
      const b1 = Offset(0.0, 10.0);
      const b2 = Offset(10.0, 0.0);

      expect(CalloutObstacleMap.segmentsIntersect(a1, a2, b1, b2), isTrue);
    });

    test('returns false for parallel or disjoint segments', () {
      const a1 = Offset(0.0, 0.0);
      const a2 = Offset(10.0, 0.0);
      const b1 = Offset(0.0, 5.0);
      const b2 = Offset(10.0, 5.0);

      expect(CalloutObstacleMap.segmentsIntersect(a1, a2, b1, b2), isFalse);

      const c1 = Offset(20.0, 20.0);
      const c2 = Offset(30.0, 30.0);
      expect(CalloutObstacleMap.segmentsIntersect(a1, a2, c1, c2), isFalse);
    });

    test('respects endpoint tolerance to avoid false positives at shared endpoints', () {
      const a1 = Offset(0.0, 0.0);
      const a2 = Offset(10.0, 0.0);
      const b1 = Offset(10.0, 0.0);
      const b2 = Offset(10.0, 10.0);

      // Default tolerance (0.02) treats touch at endpoint as non-crossing
      expect(CalloutObstacleMap.segmentsIntersect(a1, a2, b1, b2, tolerance: 0.02), isFalse);
      // Zero tolerance detects endpoint contact
      expect(CalloutObstacleMap.segmentsIntersect(a1, a2, b1, b2, tolerance: 0.0), isTrue);
    });
  });

  group('Comprehensive Callout Branch Layout Suite', () {
    test('Zero leader-line crossings between all branches', () {
      // 3 intersecting and parallel branches simulating a realistic manifold
      final net = PipingNetwork(
        nodes: {
          // Branch A (horizontal header)
          'nA1': const Node3D(id: 'nA1', x: 0, y: 0, z: 0),
          'nA2': const Node3D(id: 'nA2', x: 3000, y: 0, z: 0),
          // Branch B (vertical branch from tee at 1000)
          'nB1': const Node3D(id: 'nB1', x: 1000, y: 0, z: 0),
          'nB2': const Node3D(id: 'nB2', x: 1000, y: 2500, z: 0),
          // Branch C (parallel run)
          'nC1': const Node3D(id: 'nC1', x: 0, y: 1500, z: 0),
          'nC2': const Node3D(id: 'nC2', x: 3000, y: 1500, z: 0),
        },
        segments: {
          'sA': const PipeSegment(id: 'sA', startNodeId: 'nA1', endNodeId: 'nA2', dn: 80, systemId: 'T1'),
          'sB': const PipeSegment(id: 'sB', startNodeId: 'nB1', endNodeId: 'nB2', dn: 50, systemId: 'T1'),
          'sC': const PipeSegment(id: 'sC', startNodeId: 'nC1', endNodeId: 'nC2', dn: 65, systemId: 'T1'),
        },
        valves: {
          'vA1': const Valve(id: 'vA1', segmentId: 'sA', ratio: 0.25, name: 'Кран A1', dn: 80, lengthMm: 120, valveType: ValveType.ballValve),
          'vA2': const Valve(id: 'vA2', segmentId: 'sA', ratio: 0.75, name: 'Кран A2', dn: 80, lengthMm: 120, valveType: ValveType.ballValve),
          'vB1': const Valve(id: 'vB1', segmentId: 'sB', ratio: 0.35, name: 'Кран B1', dn: 50, lengthMm: 100, valveType: ValveType.gateValve),
          'vB2': const Valve(id: 'vB2', segmentId: 'sB', ratio: 0.75, name: 'Кран B2', dn: 50, lengthMm: 100, valveType: ValveType.gateValve),
          'vC1': const Valve(id: 'vC1', segmentId: 'sC', ratio: 0.30, name: 'Кран C1', dn: 65, lengthMm: 110, valveType: ValveType.ballValve),
          'vC2': const Valve(id: 'vC2', segmentId: 'sC', ratio: 0.70, name: 'Кран C2', dn: 65, lengthMm: 110, valveType: ValveType.ballValve),
        },
        callouts: {
          'cA1': const Callout(id: 'cA1', targetType: CalloutTargetType.valve, targetId: 'vA1', textHeight: 3.5),
          'cA2': const Callout(id: 'cA2', targetType: CalloutTargetType.valve, targetId: 'vA2', textHeight: 3.5),
          'cB1': const Callout(id: 'cB1', targetType: CalloutTargetType.valve, targetId: 'vB1', textHeight: 3.5),
          'cB2': const Callout(id: 'cB2', targetType: CalloutTargetType.valve, targetId: 'vB2', textHeight: 3.5),
          'cC1': const Callout(id: 'cC1', targetType: CalloutTargetType.valve, targetId: 'vC1', textHeight: 3.5),
          'cC2': const Callout(id: 'cC2', targetType: CalloutTargetType.valve, targetId: 'vC2', textHeight: 3.5),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_cross_branches',
        name: 'Cross Branches Test',
        sheetNumber: 1,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 1500, modelCenterY: 1000),
      );

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      expect(layout.length, equals(6));

      // Build leader line segments for all placed callouts
      final leaders = <String, List<Offset>>{};
      for (final entry in layout.entries) {
        final c = net.callouts[entry.key]!;
        final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
        final raw = projector.projectRaw(anchor.x, anchor.y, anchor.z);
        final anchorMm = ViewportTransformService.model2dToSheetMm(raw, sheet.viewport);
        final shelfStart = anchorMm + entry.value * 0.35;
        leaders[entry.key] = [anchorMm, shelfStart];
      }

      // Verify ZERO intersections across any pair of leader lines from all branches
      final leaderList = leaders.entries.toList();
      int intersectionCount = 0;

      for (int i = 0; i < leaderList.length; i++) {
        for (int j = i + 1; j < leaderList.length; j++) {
          final l1 = leaderList[i].value;
          final l2 = leaderList[j].value;
          final intersects = CalloutObstacleMap.segmentsIntersect(l1[0], l1[1], l2[0], l2[1]);
          if (intersects) {
            intersectionCount++;
          }
          expect(
            intersects,
            isFalse,
            reason: 'Leader line ${leaderList[i].key} intersects with ${leaderList[j].key}',
          );
        }
      }

      expect(intersectionCount, equals(0));
    });

    test('Avoidance of sheet stamp (185x55 mm) and tables even when pipeline runs directly above or beside stamp', () {
      // Pipeline located in bottom-right corner of sheet space
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 4000, y: 3500, z: 0),
          'n2': const Node3D(id: 'n2', x: 5500, y: 3500, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.3, name: 'Кран 1', dn: 100, lengthMm: 140, valveType: ValveType.gateValve),
          'v2': const Valve(id: 'v2', segmentId: 's1', ratio: 0.7, name: 'Кран 2', dn: 100, lengthMm: 140, valveType: ValveType.gateValve),
        },
        callouts: {
          'c1': const Callout(id: 'c1', targetType: CalloutTargetType.valve, targetId: 'v1', textHeight: 3.5),
          'c2': const Callout(id: 'c2', targetType: CalloutTargetType.valve, targetId: 'v2', textHeight: 3.5),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_stamp_avoid',
        name: 'Stamp Avoidance Test',
        sheetNumber: 1,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 4750, modelCenterY: 3500),
        tables: const [
          SheetTableItem(
            id: 'spec_table',
            type: SheetTableType.materialsSpecification,
            xMm: 230.0,
            yMm: 80.0,
            widthMm: 185.0,
            heightMm: 70.0,
          ),
          SheetTableItem(
            id: 'weld_table',
            type: SheetTableType.weldJointsTable,
            xMm: 230.0,
            yMm: 160.0,
            widthMm: 185.0,
            heightMm: 50.0,
          ),
        ],
      );

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      expect(layout.length, equals(2));

      // Stamp: 185x55 mm in bottom-right corner (width 420, height 297, right=5, bottom=5)
      final stampRect = Rect.fromLTWH(
        420.0 - 5.0 - 185.0 - 2.0,
        297.0 - 5.0 - 55.0 - 2.0,
        185.0 + 4.0,
        55.0 + 4.0,
      );

      final specTableRect = const Rect.fromLTWH(230.0 - 2.0, 80.0 - 2.0, 185.0 + 4.0, 70.0 + 4.0);
      final weldTableRect = const Rect.fromLTWH(230.0 - 2.0, 160.0 - 2.0, 185.0 + 4.0, 50.0 + 4.0);

      for (final id in ['c1', 'c2']) {
        final c = net.callouts[id]!;
        final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
        final raw = projector.projectRaw(anchor.x, anchor.y, anchor.z);
        final anchorMm = ViewportTransformService.model2dToSheetMm(raw, sheet.viewport);
        final offMm = layout[id]! * 0.35;
        final shelfStart = anchorMm + offMm;

        final shelfRect = Rect.fromLTWH(
          shelfStart.dx - 40.0,
          shelfStart.dy - c.textHeight - 1.0,
          80.0,
          c.textHeight + 2.0,
        );

        // Neither the shelf start nor the shelf body can intersect stamp or tables
        expect(stampRect.contains(shelfStart), isFalse, reason: '$id shelf start inside stamp');
        expect(stampRect.overlaps(shelfRect), isFalse, reason: '$id shelf rect overlaps stamp');

        expect(specTableRect.contains(shelfStart), isFalse, reason: '$id inside spec table');
        expect(specTableRect.overlaps(shelfRect), isFalse, reason: '$id overlaps spec table');

        expect(weldTableRect.contains(shelfStart), isFalse, reason: '$id inside weld table');
        expect(weldTableRect.overlaps(shelfRect), isFalse, reason: '$id overlaps weld table');

        // Confirmed within sheet margins (left 20mm, right 415mm, top 5mm, bottom 292mm)
        expect(shelfStart.dx, greaterThanOrEqualTo(20.0));
        expect(shelfStart.dx, lessThanOrEqualTo(415.0));
        expect(shelfStart.dy, greaterThanOrEqualTo(5.0));
        expect(shelfStart.dy, lessThanOrEqualTo(292.0));
      }
    });

    test('Dynamic adaptive pitch (Delta Y) adapts to font height (2.5 mm, 3.5 mm, 5.0 mm)', () {
      final textHeights = [2.5, 3.5, 5.0];
      final observedPitches = <double, double>{};

      for (final th in textHeights) {
        final net = PipingNetwork(
          nodes: {
            'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
            'n2': const Node3D(id: 'n2', x: 2000, y: 0, z: 0),
          },
          segments: {
            's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 80, systemId: 'T1'),
          },
          valves: {
            'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.25, name: 'К1', dn: 80, lengthMm: 100, valveType: ValveType.ballValve),
            'v2': const Valve(id: 'v2', segmentId: 's1', ratio: 0.50, name: 'К2', dn: 80, lengthMm: 100, valveType: ValveType.ballValve),
            'v3': const Valve(id: 'v3', segmentId: 's1', ratio: 0.75, name: 'К3', dn: 80, lengthMm: 100, valveType: ValveType.ballValve),
          },
          callouts: {
            'c1': Callout(id: 'c1', targetType: CalloutTargetType.valve, targetId: 'v1', textHeight: th),
            'c2': Callout(id: 'c2', targetType: CalloutTargetType.valve, targetId: 'v2', textHeight: th),
            'c3': Callout(id: 'c3', targetType: CalloutTargetType.valve, targetId: 'v3', textHeight: th),
          },
        );

        final sheet = DrawingSheet(
          id: 'sheet_pitch_$th',
          name: 'Pitch Test $th',
          sheetNumber: 1,
          groupMultiLevelCallouts: false,
          format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
          viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 1000, modelCenterY: 0),
        );

        final layout = CalloutLayoutEngine.calculateSheetLayout(
          sheet: sheet,
          network: net,
          projector: projector,
        );

        expect(layout.length, equals(3));

        final shelfYs = <double>[];
        for (final id in ['c1', 'c2', 'c3']) {
          final c = net.callouts[id]!;
          final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
          final raw = projector.projectRaw(anchor.x, anchor.y, anchor.z);
          final anchorMm = ViewportTransformService.model2dToSheetMm(raw, sheet.viewport);
          final offMm = layout[id]! * 0.35;
          shelfYs.add(anchorMm.dy + offMm.dy);
        }

        shelfYs.sort();
        final pitch = (shelfYs[1] - shelfYs[0]);
        observedPitches[th] = pitch;

        // Ideal pitch is approx th * 2.1
        final expectedPitch = th * 2.1;
        expect(pitch, closeTo(expectedPitch, 0.6), reason: 'Pitch for textHeight $th should be close to $expectedPitch');
      }

      // Verify pitch strictly scales with font height: 2.5mm < 3.5mm < 5.0mm
      expect(observedPitches[2.5]!, lessThan(observedPitches[3.5]!));
      expect(observedPitches[3.5]!, lessThan(observedPitches[5.0]!));

      // Also verify customPitchMm overrides font-based calculation
      final netCustom = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 2000, y: 0, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 80, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.3, name: 'К1', dn: 80, lengthMm: 100, valveType: ValveType.ballValve),
          'v2': const Valve(id: 'v2', segmentId: 's1', ratio: 0.7, name: 'К2', dn: 80, lengthMm: 100, valveType: ValveType.ballValve),
        },
        callouts: {
          'c1': const Callout(id: 'c1', targetType: CalloutTargetType.valve, targetId: 'v1', textHeight: 2.5),
          'c2': const Callout(id: 'c2', targetType: CalloutTargetType.valve, targetId: 'v2', textHeight: 2.5),
        },
      );

      final sheetCustom = DrawingSheet(
        id: 'sheet_custom_pitch',
        name: 'Custom Pitch',
        sheetNumber: 1,
        groupMultiLevelCallouts: false,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 1000, modelCenterY: 0),
      );

      final layoutCustom = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheetCustom,
        network: netCustom,
        projector: projector,
        customPitchMm: 12.0,
      );

      final y1 = layoutCustom['c1']!.dy * 0.35;
      final y2 = layoutCustom['c2']!.dy * 0.35;
      expect((y2 - y1).abs(), closeTo(12.0, 0.2));
    });

    test('Multi-level callout toggle (groupMultiLevelCallouts) groups items at identical/close positions', () {
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 1500, y: 0, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.5, name: 'Кран 1', dn: 50, lengthMm: 100, valveType: ValveType.ballValve),
        },
        weldJoints: {
          'w1': const WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.5, number: 10, stamp: 'W10'),
        },
        callouts: {
          'c_valve': const Callout(id: 'c_valve', targetType: CalloutTargetType.valve, targetId: 'v1', textHeight: 3.5),
          'c_weld': const Callout(id: 'c_weld', targetType: CalloutTargetType.weld, targetId: 'w1', textHeight: 3.5),
        },
      );

      // Case A: groupMultiLevelCallouts = true (default)
      final sheetGrouped = DrawingSheet(
        id: 'sheet_grp_true',
        name: 'Grouped True',
        sheetNumber: 1,
        groupMultiLevelCallouts: true,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 750, modelCenterY: 0),
      );

      final layoutGrouped = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheetGrouped,
        network: net,
        projector: projector,
      );

      expect(layoutGrouped.length, equals(2));
      final offValveG = layoutGrouped['c_valve']! * 0.35;
      final offWeldG = layoutGrouped['c_weld']! * 0.35;

      // Grouped shelves must share exact vertical stack axis X
      expect((offValveG.dx - offWeldG.dx).abs(), lessThan(0.01));
      // Stacking delta Y must be at least textHeight + 1.0
      expect((offValveG.dy - offWeldG.dy).abs(), greaterThanOrEqualTo(3.5 + 1.0));

      // Case B: groupMultiLevelCallouts = false
      final sheetUngrouped = DrawingSheet(
        id: 'sheet_grp_false',
        name: 'Grouped False',
        sheetNumber: 1,
        groupMultiLevelCallouts: false,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 750, modelCenterY: 0),
      );

      final layoutUngrouped = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheetUngrouped,
        network: net,
        projector: projector,
      );

      expect(layoutUngrouped.length, equals(2));
      // Both callouts are still successfully placed without error
      expect(layoutUngrouped.containsKey('c_valve'), isTrue);
      expect(layoutUngrouped.containsKey('c_weld'), isTrue);
    });

    test('Multi-tier splitting when a branch has > 6 callouts', () {
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 5000, y: 0, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'T1'),
        },
        valves: {
          for (int i = 1; i <= 9; i++)
            'v$i': Valve(
              id: 'v$i',
              segmentId: 's1',
              ratio: i / 10.0,
              name: 'Кран $i',
              dn: 100,
              lengthMm: 100,
              valveType: ValveType.ballValve,
            ),
        },
        callouts: {
          for (int i = 1; i <= 9; i++)
            'c$i': Callout(id: 'c$i', targetType: CalloutTargetType.valve, targetId: 'v$i', textHeight: 3.5),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_multitier_dense',
        name: 'Multi-Tier Dense',
        sheetNumber: 1,
        groupMultiLevelCallouts: false,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 2500, modelCenterY: 0),
      );

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      expect(layout.length, equals(9));

      // Extract distinct column X coordinates of shelves
      final tierXCoords = <double>{};
      final leaders = <List<Offset>>[];

      for (final entry in layout.entries) {
        final c = net.callouts[entry.key]!;
        final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
        final raw = projector.projectRaw(anchor.x, anchor.y, anchor.z);
        final anchorMm = ViewportTransformService.model2dToSheetMm(raw, sheet.viewport);
        final shelfStart = anchorMm + entry.value * 0.35;
        // Round to 1 decimal to cluster columns
        tierXCoords.add((shelfStart.dx * 10).round() / 10.0);
        leaders.add([anchorMm, shelfStart]);
      }

      // Branch with 9 items (> 6) must be split into at least 2 tiers
      expect(tierXCoords.length, greaterThanOrEqualTo(2));

      // Verify zero leader-line intersections even with multi-tier layout
      for (int i = 0; i < leaders.length; i++) {
        for (int j = i + 1; j < leaders.length; j++) {
          final cross = CalloutObstacleMap.segmentsIntersect(
            leaders[i][0],
            leaders[i][1],
            leaders[j][0],
            leaders[j][1],
          );
          expect(cross, isFalse, reason: 'Tiers leader intersection between callout $i and $j');
        }
      }
    });

    test('Pinned callout preservation and unpinned collision avoidance', () {
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 2000, y: 0, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.25, name: 'К1', dn: 50, lengthMm: 100, valveType: ValveType.ballValve),
          'v2': const Valve(id: 'v2', segmentId: 's1', ratio: 0.50, name: 'К2', dn: 50, lengthMm: 100, valveType: ValveType.ballValve),
          'v3': const Valve(id: 'v3', segmentId: 's1', ratio: 0.75, name: 'К3', dn: 50, lengthMm: 100, valveType: ValveType.ballValve),
        },
        callouts: {
          // Pinned with sheet-specific override
          'c_pinned_sheet': const Callout(
            id: 'c_pinned_sheet',
            targetType: CalloutTargetType.valve,
            targetId: 'v1',
            isPinned: true,
            sheetOffsets: {'sheet_pinned': Offset(95.0, -75.0)},
            textHeight: 3.5,
          ),
          // Pinned with base screen offset
          'c_pinned_base': const Callout(
            id: 'c_pinned_base',
            targetType: CalloutTargetType.valve,
            targetId: 'v2',
            isPinned: true,
            screenOffsetX: 40.0,
            screenOffsetY: 50.0,
            textHeight: 3.5,
          ),
          // Unpinned callout
          'c_unpinned': const Callout(
            id: 'c_unpinned',
            targetType: CalloutTargetType.valve,
            targetId: 'v3',
            isPinned: false,
            textHeight: 3.5,
          ),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_pinned',
        name: 'Pinned Sheet Test',
        sheetNumber: 1,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 1000, modelCenterY: 0),
      );

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
        onlyUnpinned: true,
      );

      expect(layout.length, equals(3));

      // c_pinned_sheet: strictly preserved from sheetOffsets['sheet_pinned']
      expect(layout['c_pinned_sheet'], equals(const Offset(95.0, -75.0)));

      // c_pinned_base: strictly preserved from screenOffsetX, screenOffsetY
      expect(layout['c_pinned_base'], equals(const Offset(40.0, 50.0)));

      // c_unpinned: computed by layout engine
      expect(layout.containsKey('c_unpinned'), isTrue);
      expect(layout['c_unpinned']!.dx, isNotNull);
      expect(layout['c_unpinned']!.dy, isNotNull);

      // Verify unpinned callout shelf does not overlap the pinned callout shelf
      final unpinnedC = net.callouts['c_unpinned']!;
      final unpinnedAnchor = CalloutLayoutEngine.computeAnchorNode(unpinnedC, net)!;
      final unpinnedRaw = projector.projectRaw(unpinnedAnchor.x, unpinnedAnchor.y, unpinnedAnchor.z);
      final unpinnedAnchorMm = ViewportTransformService.model2dToSheetMm(unpinnedRaw, sheet.viewport);
      final unpinnedShelfStart = unpinnedAnchorMm + layout['c_unpinned']! * 0.35;
      final unpinnedRect = Rect.fromLTWH(unpinnedShelfStart.dx, unpinnedShelfStart.dy - 4.5, 40.0, 5.5);

      final pinned1C = net.callouts['c_pinned_sheet']!;
      final pinned1Anchor = CalloutLayoutEngine.computeAnchorNode(pinned1C, net)!;
      final pinned1Raw = projector.projectRaw(pinned1Anchor.x, pinned1Anchor.y, pinned1Anchor.z);
      final pinned1AnchorMm = ViewportTransformService.model2dToSheetMm(pinned1Raw, sheet.viewport);
      final pinned1ShelfStart = pinned1AnchorMm + layout['c_pinned_sheet']! * 0.35;
      final pinned1Rect = Rect.fromLTWH(pinned1ShelfStart.dx, pinned1ShelfStart.dy - 4.5, 40.0, 5.5);

      expect(unpinnedRect.overlaps(pinned1Rect), isFalse, reason: 'Unpinned shelf overlaps pinned shelf');
    });

    test('Vertical branch centering: stack is vertically centered on tierMeanY without arbitrary downward offset', () {
      // Purely vertical pipe along Y in 2D (normal.dy == 0)
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 1000, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 1000, y: 0, z: 2000), // Along Z -> vertical in standard projection
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.3, name: 'К1', dn: 50, lengthMm: 100, valveType: ValveType.ballValve),
          'v2': const Valve(id: 'v2', segmentId: 's1', ratio: 0.7, name: 'К2', dn: 50, lengthMm: 100, valveType: ValveType.ballValve),
        },
        callouts: {
          'c1': const Callout(id: 'c1', targetType: CalloutTargetType.valve, targetId: 'v1', textHeight: 3.5),
          'c2': const Callout(id: 'c2', targetType: CalloutTargetType.valve, targetId: 'v2', textHeight: 3.5),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_vert_center',
        name: 'Vertical Center Test',
        sheetNumber: 1,
        groupMultiLevelCallouts: false,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.05, modelCenterX: 1000, modelCenterY: 0),
      );

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      expect(layout.length, equals(2));

      // Calculate the mean anchor Y on the sheet
      final a1 = CalloutLayoutEngine.computeAnchorNode(net.callouts['c1']!, net)!;
      final a2 = CalloutLayoutEngine.computeAnchorNode(net.callouts['c2']!, net)!;
      final raw1 = projector.projectRaw(a1.x, a1.y, a1.z);
      final raw2 = projector.projectRaw(a2.x, a2.y, a2.z);
      final aMm1 = ViewportTransformService.model2dToSheetMm(raw1, sheet.viewport);
      final aMm2 = ViewportTransformService.model2dToSheetMm(raw2, sheet.viewport);
      final meanAnchorY = (aMm1.dy + aMm2.dy) / 2.0;

      // Calculate the mean shelf Y
      final shelfY1 = aMm1.dy + layout['c1']!.dy * 0.35;
      final shelfY2 = aMm2.dy + layout['c2']!.dy * 0.35;
      final meanShelfY = (shelfY1 + shelfY2) / 2.0;

      // With shiftY = 0.0, the stack should be centered right around meanAnchorY (within 2.0 mm)
      // and NOT shifted arbitrarily down by clearance (+18..26 mm)!
      expect((meanShelfY - meanAnchorY).abs(), lessThanOrEqualTo(2.0));
    });
  });
}
