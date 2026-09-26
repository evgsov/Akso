import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/sheet_format.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';
import 'package:akso/domain/services/viewport_transform_service.dart';
import 'package:akso/domain/enums/sheet_format_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/core/math/axonometry_projector.dart';

void main() {
  test('calculateSheetLayout generates 0 crossing leader lines in boundary column mode', () {
    final nodes = <String, Node3D>{};
    final segments = <String, PipeSegment>{};
    final valves = <String, Valve>{};
    final callouts = <String, Callout>{};

    // Создаем цепочку узлов и элементов
    for (int i = 0; i < 20; i++) {
      final n1 = Node3D(id: 'n_$i', x: i * 150.0, y: (i % 4) * 120.0, z: (i % 3) * 60.0);
      nodes[n1.id] = n1;
      if (i > 0) {
        final seg = PipeSegment(
          id: 'seg_$i',
          startNodeId: 'n_${i - 1}',
          endNodeId: 'n_$i',
          outerDiameterMm: 57.0,
          wallThicknessMm: 3.5,
          dn: 50,
          systemId: 'T1',
        );
        segments[seg.id] = seg;

        final v = Valve(
          id: 'val_$i',
          segmentId: seg.id,
          ratio: 0.5,
          name: 'Кран $i',
          dn: 50,
          lengthMm: 100.0,
          valveType: ValveType.ballValve,
        );
        valves[v.id] = v;

        final c = Callout(
          id: 'call_$i',
          targetType: CalloutTargetType.valve,
          targetId: v.id,
          customText: 'А-$i',
        );
        callouts[c.id] = c;
      }
    }

    final net = PipingNetwork(
      nodes: nodes,
      segments: segments,
      valves: valves,
      callouts: callouts,
    );

    final sheet = DrawingSheet(
      id: 'sheet_test',
      name: 'Схема',
      sheetNumber: 1,
      format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
      viewport: const SheetViewport(),
    );

    const projector = AxonometryProjector();
    final layout = CalloutLayoutEngine.calculateSheetLayout(
      sheet: sheet,
      network: net,
      projector: projector,
    );

    expect(layout.length, equals(callouts.length));

    // Проверяем, что ни одна полочка не заходит на штамп 185x55 мм
    final stampRect = Rect.fromLTWH(
      sheet.format.widthMm - sheet.format.frameRightMm - 185.0,
      sheet.format.heightMm - sheet.format.frameBottomMm - 55.0,
      185.0,
      55.0,
    );

    final leftLeaders = <List<Offset>>[];
    final rightLeaders = <List<Offset>>[];

    for (final entry in layout.entries) {
      final c = callouts[entry.key]!;
      final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
      final pRaw = projector.projectRaw(anchor.x, anchor.y, anchor.z);
      final pMm = ViewportTransformService.model2dToSheetMm(pRaw, sheet.viewport);
      final offMm = entry.value * 0.35;
      final shelfStart = pMm + offMm;

      expect(stampRect.contains(shelfStart), isFalse, reason: 'Callout ${entry.key} overlaps stamp');

      if (offMm.dx < 0) {
        leftLeaders.add([pMm, shelfStart]);
      } else {
        rightLeaders.add([pMm, shelfStart]);
      }
    }

    bool segmentsIntersect(Offset a1, Offset a2, Offset b1, Offset b2) {
      double ccw(Offset a, Offset b, Offset c) {
        return (c.dy - a.dy) * (b.dx - a.dx) - (b.dy - a.dy) * (c.dx - a.dx);
      }
      return (ccw(a1, b1, b2) * ccw(a2, b1, b2) < 0) &&
             (ccw(a1, a2, b1) * ccw(a1, a2, b2) < 0);
    }

    // Проверяем отсутствие пересечений линий в левой колонке
    for (int i = 0; i < leftLeaders.length; i++) {
      for (int j = i + 1; j < leftLeaders.length; j++) {
        expect(
          segmentsIntersect(leftLeaders[i][0], leftLeaders[i][1], leftLeaders[j][0], leftLeaders[j][1]),
          isFalse,
          reason: 'Left leader lines $i and $j intersect',
        );
      }
    }

    // Проверяем отсутствие пересечений линий в правой колонке
    for (int i = 0; i < rightLeaders.length; i++) {
      for (int j = i + 1; j < rightLeaders.length; j++) {
        expect(
          segmentsIntersect(rightLeaders[i][0], rightLeaders[i][1], rightLeaders[j][0], rightLeaders[j][1]),
          isFalse,
          reason: 'Right leader lines $i and $j intersect',
        );
      }
    }
  });

  test('groupMultiLevelCallouts groups coincident valve and weld callouts', () {
    final net = PipingNetwork(
      nodes: {
        'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
        'n2': const Node3D(id: 'n2', x: 1000, y: 0, z: 0),
      },
      segments: {
        's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'T1'),
      },
      valves: {
        'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.5, name: 'Кран', dn: 50, lengthMm: 100.0, valveType: ValveType.ballValve),
      },
      weldJoints: {
        'w1': const WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.5, number: 1, stamp: '1'),
      },
      callouts: {
        'c_valve': const Callout(id: 'c_valve', targetId: 'v1', targetType: CalloutTargetType.valve),
        'c_weld': const Callout(id: 'c_weld', targetId: 'w1', targetType: CalloutTargetType.weld),
      },
    );

    final sheet = DrawingSheet(
      id: 'sheet_cluster',
      name: 'Лист с этажеркой',
      sheetNumber: 1,
      groupMultiLevelCallouts: true,
      viewport: const SheetViewport(),
    );

    const projector = AxonometryProjector();
    final layout = CalloutLayoutEngine.calculateSheetLayout(
      sheet: sheet,
      network: net,
      projector: projector,
    );

    expect(layout.length, equals(2));
    final offValve = layout['c_valve']! * 0.35;
    final offWeld = layout['c_weld']! * 0.35;

    // Обе выноски находятся на одной вертикальной оси колонки
    expect((offValve.dx - offWeld.dx).abs(), lessThan(0.01));
    // Слоты идут последовательно по вертикали
    expect((offValve.dy - offWeld.dy).abs(), greaterThan(3.0));
  });

  test('elevation callouts are isolated near their nodes', () {
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
        ),
      },
    );

    final sheet = DrawingSheet(
      id: 'sheet_elev',
      name: 'Лист с отметкой',
      sheetNumber: 1,
      viewport: const SheetViewport(),
    );

    const projector = AxonometryProjector();
    final layout = CalloutLayoutEngine.calculateSheetLayout(
      sheet: sheet,
      network: net,
      projector: projector,
    );

    expect(layout.length, equals(1));
    final offMm = layout['c_elev']! * 0.35;

    // Отметка расположена строго вертикально над узлом (dx == 0, dy < 0)
    expect(offMm.dx, equals(0.0));
    expect(offMm.dy, lessThan(0.0));
  });
}
