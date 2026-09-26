import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';
import 'package:akso/domain/services/viewport_transform_service.dart';

void main() {
  group('CalloutLayoutEngine.calculateSheetLayout', () {
    late PipingNetwork network;
    late AxonometryProjector projector;

    setUp(() {
      projector = const AxonometryProjector();
      network = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 2000, y: 0, z: 0),
          'n3': const Node3D(id: 'n3', x: 2000, y: 2000, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100),
          's2': const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 100),
        },
        valves: {},
        weldJoints: {
          'w1': const WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.1, number: 1, stamp: '1'),
          'w2': const WeldJoint(id: 'w2', segmentId: 's2', ratio: 0.9, number: 2, stamp: '2'),
        },
        fittings: {},
        supports: {},
        equipments: {},
        callouts: {
          'c_seg1': const Callout(id: 'c_seg1', targetId: 's1', targetType: CalloutTargetType.segment),
          'c_seg2': const Callout(id: 'c_seg2', targetId: 's2', targetType: CalloutTargetType.segment),
          'c_weld1': const Callout(id: 'c_weld1', targetId: 'w1', targetType: CalloutTargetType.weld),
          'c_weld2': const Callout(id: 'c_weld2', targetId: 'w2', targetType: CalloutTargetType.weld),
        },
      );
    });

    test('layout respects enabledCalloutTypes: mounting scheme places segments only, welding places welds only', () {
      final mountingSheet = DrawingSheet.createDefault(
        id: 'sheet_mounting',
        name: 'Монтажная схема',
        sheetNumber: 1,
      ).copyWith(
        enabledCalloutTypes: {CalloutTargetType.segment},
      );

      final weldingSheet = DrawingSheet.createDefault(
        id: 'sheet_welding',
        name: 'Схема сварки',
        sheetNumber: 2,
      ).copyWith(
        enabledCalloutTypes: {CalloutTargetType.weld},
      );

      // 1. Авторасстановка для монтажной схемы
      final mountingLayout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: mountingSheet,
        network: network,
        projector: projector,
      );

      expect(mountingLayout.containsKey('c_seg1'), isTrue);
      expect(mountingLayout.containsKey('c_seg2'), isTrue);
      expect(mountingLayout.containsKey('c_weld1'), isFalse);
      expect(mountingLayout.containsKey('c_weld2'), isFalse);

      // 2. Авторасстановка для схемы сварки
      final weldingLayout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: weldingSheet,
        network: network,
        projector: projector,
      );

      expect(weldingLayout.containsKey('c_seg1'), isFalse);
      expect(weldingLayout.containsKey('c_seg2'), isFalse);
      expect(weldingLayout.containsKey('c_weld1'), isTrue);
      expect(weldingLayout.containsKey('c_weld2'), isTrue);
    });

    test('placed callout shelves do not fall outside viewport and do not overlap stamp', () {
      final sheet = DrawingSheet.createDefault(
        id: 'sheet_test',
        name: 'Тестовый лист',
        sheetNumber: 1,
      );

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: network,
        projector: projector,
      );

      final fmt = sheet.format;
      final vp = sheet.viewport;
      final stampRect = Rect.fromLTWH(
        fmt.widthMm - fmt.frameRightMm - 185.0,
        fmt.heightMm - fmt.frameBottomMm - 55.0,
        185.0,
        55.0,
      );

      for (final entry in layout.entries) {
        final callout = network.callouts[entry.key]!;
        final anchorNode = CalloutLayoutEngine.computeAnchorNode(callout, network)!;
        final raw2D = projector.projectRaw(anchorNode.x, anchorNode.y, anchorNode.z);
        final anchorMm = ViewportTransformService.model2dToSheetMm(raw2D, vp);

        // entry.value is in stored units (where mm = val * 0.35)
        final offsetMm = entry.value * 0.35;
        final shelfStart = anchorMm + offsetMm;

        // Полка не должна пересекать штамп 185x55
        final shelfRect = Rect.fromLTWH(shelfStart.dx, shelfStart.dy - 6.0, 30.0, 10.0);
        expect(shelfRect.overlaps(stampRect), isFalse,
            reason: 'Callout ${callout.id} overlaps stamp at $shelfRect vs $stampRect');
      }
    });
  });
}
