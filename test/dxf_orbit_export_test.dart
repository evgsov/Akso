import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('DXF Orbit & Annotative Blocks Export Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
        material: 'Сталь 20',
      );

      network.callouts['c1'] = const Callout(
        id: 'c1',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
        screenOffsetX: 60.0,
        screenOffsetY: -40.0,
      );
    });

    test('generate2dGostAxonometryDxf exports orbit3d projection with activeProjector', () {
      final orbitProjector = AxonometryProjector(
        projectionType: ProjectionType.orbit3d,
        orbitAzimuth: 0.5,
        orbitElevation: 0.8,
        scale: 0.25,
      );

      final dxf = DxfWriter.generate2dGostAxonometryDxf(
        network,
        projection: ProjectionType.orbit3d,
        activeProjector: orbitProjector,
      );

      expect(dxf.contains('SECTION'), isTrue);
      expect(dxf.contains('ENTITIES'), isTrue);
      expect(dxf.contains('BLOCKS'), isTrue);
      expect(dxf.contains('EOF'), isTrue);
    });

    test('DXF contains native AutoCAD BLOCKS and INSERT with ATTRIB and SEQEND for callouts', () {
      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network);

      // Проверяем наличие секции BLOCKS с определением блока выноски
      expect(dxf2d.contains('BLOCK'), isTrue);
      expect(dxf2d.contains('ENDBLK'), isTrue);
      expect(dxf2d.contains('ATTDEF'), isTrue);

      // Проверяем вставку блока через INSERT с атрибутом ATTRIB
      expect(dxf2d.contains('INSERT'), isTrue);
      expect(dxf2d.contains('ATTRIB'), isTrue);
      expect(dxf2d.contains('SEQEND'), isTrue);

      // Проверяем экранирование спецсимволов и кириллицы \U+
      expect(dxf2d.contains(r'\U+'), isTrue);

      // 3D DXF содержит монолитные блоки выносок
      final dxf3d = DxfWriter.generate3dDxf(network);
      expect(dxf3d.contains('BLOCK'), isTrue);
      expect(dxf3d.contains('INSERT'), isTrue);
      expect(dxf3d.contains('CALLOUT_SHELF_'), isTrue);
    });
  });
}
