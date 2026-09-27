import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/sheet_format.dart';
import 'package:akso/domain/enums/sheet_format_type.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';
import 'package:akso/domain/services/callout_candidate_generator.dart';

void main() {
  group('CalloutCandidateGenerator', () {
    const projector = AxonometryProjector();

    test('generates dense candidate pool for visible callouts without stamp overlaps', () {
      final net = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      net.nodes['n1'] = n1;
      net.nodes['n2'] = n2;

      final seg = PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'T1',
        outerDiameterMm: 108.0,
      );
      net.segments['seg1'] = seg;

      final callout = Callout(
        id: 'c1',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
        textHeight: 3.5,
      );
      net.callouts['c1'] = callout;

      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.02),
      );

      final obstacleMap = CalloutObstacleMap.buildSheetMap(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      final pools = CalloutCandidateGenerator.generateCandidatePools(
        sheet: sheet,
        network: net,
        projector: projector,
        obstacleMap: obstacleMap,
        maxCandidatesPerCallout: 40,
      );

      expect(pools.containsKey('c1'), isTrue);
      final slots = pools['c1']!;
      expect(slots.isNotEmpty, isTrue);
      expect(slots.length, lessThanOrEqualTo(40));

      // Проверяем, что ни один слот не пересекает штамп листа
      final stamp = obstacleMap.getRect('stamp')!;
      for (final slot in slots) {
        expect(slot.boundingBox.overlaps(stamp.rect), isFalse);
        expect(slot.radius, greaterThanOrEqualTo(5.0));
        expect(slot.radius, lessThanOrEqualTo(45.0));
      }
    });

    test('angles include dense 5-degree increments', () {
      final angles = CalloutCandidateGenerator.generateCandidateAngles();
      expect(angles.length, greaterThanOrEqualTo(50));

      // Проверяем, что углы идут с шагом ~5 градусов (0.087 рад)
      for (int i = 1; i < angles.length; i++) {
        final diffDeg = (angles[i] - angles[i - 1]).abs() * 180 / math.pi;
        if (diffDeg < 20.0) {
          expect(diffDeg, closeTo(5.0, 0.5));
        }
      }
    });
  });
}
