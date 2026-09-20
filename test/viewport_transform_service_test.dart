import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/services/viewport_transform_service.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/enums/projection_type.dart';

void main() {
  group('ViewportTransformService', () {
    test('calculateAutoFit calculates correct scale and center for network', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 4000, y: 2000, z: 1000);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        dn: 50,
        systemId: 'sys_b1',
      );
      network.segments[seg.id] = seg;

      const viewport = SheetViewport(
        xMm: 25.0,
        yMm: 10.0,
        widthMm: 250.0,
        heightMm: 200.0,
      );

      final result = ViewportTransformService.calculateAutoFit(
        network: network,
        projectionType: ProjectionType.gostFrontal45,
        viewport: viewport,
        marginMm: 15.0,
      );

      expect(result.scale, greaterThan(0.0));
      expect(result.scale, lessThan(1.0));
      expect(result.centerX, isNotNull);
      expect(result.centerY, isNotNull);
    });

    test('model2dToSheetMm and sheetMmToModel2d are exact inverses', () {
      const viewport = SheetViewport(
        xMm: 20.0,
        yMm: 10.0,
        widthMm: 300.0,
        heightMm: 200.0,
        modelCenterX: 500.0,
        modelCenterY: 300.0,
        viewScale: 0.02, // 1:50
      );

      const rawModelPoint = Offset(750.0, 450.0);
      final sheetPoint = ViewportTransformService.model2dToSheetMm(rawModelPoint, viewport);

      // Model center should map directly to viewport center on sheet
      final centerSheetPoint = ViewportTransformService.model2dToSheetMm(
        const Offset(500.0, 300.0),
        viewport,
      );
      expect(centerSheetPoint.dx, equals(20.0 + 150.0));
      expect(centerSheetPoint.dy, equals(10.0 + 100.0));

      final invertedModelPoint = ViewportTransformService.sheetMmToModel2d(sheetPoint, viewport);
      expect(invertedModelPoint.dx, closeTo(rawModelPoint.dx, 1e-6));
      expect(invertedModelPoint.dy, closeTo(rawModelPoint.dy, 1e-6));
    });

    test('annotative text scaling keeps constant paper height across zoom levels', () {
      final scale1to50 = 1.0 / 50.0;
      final scale1to100 = 1.0 / 100.0;

      final textScale50 = ViewportTransformService.calculateAnnotationScale(scale1to50);
      final textScale100 = ViewportTransformService.calculateAnnotationScale(scale1to100);

      expect(textScale100, equals(textScale50 * 2.0));
      expect(ViewportTransformService.formatScaleText(0.02), equals('М 1:50'));
      expect(ViewportTransformService.formatScaleText(0.01), equals('М 1:100'));
      expect(ViewportTransformService.formatScaleText(0.05), equals('М 1:20'));
    });

    test('system visibility filter isolates systems in bounding box', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = Node3D(id: 'n3', x: 5000, y: 5000, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      network.nodes[n3.id] = n3;

      final seg1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'sys_b1');
      final seg2 = PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', dn: 50, systemId: 'sys_t3');
      network.segments[seg1.id] = seg1;
      network.segments[seg2.id] = seg2;

      final boundsAll = ViewportTransformService.calculateModel2dBounds(
        network,
        ProjectionType.gostFrontal45,
      );
      final boundsOnlyB1 = ViewportTransformService.calculateModel2dBounds(
        network,
        ProjectionType.gostFrontal45,
        visibleSystemIds: {'sys_b1'},
      );

      expect(boundsOnlyB1.width, lessThan(boundsAll.width));
    });
  });
}
