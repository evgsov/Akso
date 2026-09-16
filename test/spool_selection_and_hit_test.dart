import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Task 3: Spool Selection and Hit-Testing Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;
    const projector = AxonometryProjector(projectionType: ProjectionType.gostFrontal45);

    setUp(() {
      network = PipingNetwork();
      network.systems['sys1'] = const PipingSystem(
        id: 'sys1',
        name: 'Водоснабжение',
        code: 'В1',
        colorValue: 0xFF2196F3,
        dxfAciColor: 5,
      );
      controller = PipingInputController(network: network);
      controller.setTool(CanvasTool.select);
    });

    test('Elbow-to-elbow butt joint has no spool, hit-testing does not select ghost pipe', () {
      // s1: (-1000, 0, 0) -> (0, 0, 0)
      // s2: (0, 0, 0) -> (0, 300, 0) [отвод-отвод встык: 150 + 150 = 300 мм]
      // s3: (0, 300, 0) -> (1000, 300, 0)
      network.nodes['n1'] = const Node3D(id: 'n1', x: -1000, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 300, z: 0);
      network.nodes['n4'] = const Node3D(id: 'n4', x: 1000, y: 300, z: 0);

      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 100);
      network.segments['s3'] = const PipeSegment(id: 's3', startNodeId: 'n3', endNodeId: 'n4', systemId: 'sys1', dn: 100);

      network.recalculateSpools();

      // s2 не имеет катушек
      expect(network.spools.values.where((sp) => sp.segmentId == 's2'), isEmpty);

      // Клик в середину стыка отводов (0, 150, 0)
      final midPoint = const Node3D(id: 'mid', x: 0, y: 150, z: 0);
      final screenPos = projector.project(midPoint);

      controller.handlePointerDown(screenPos);

      // В обычном режиме труба s2 НЕ должна выделяться
      expect(controller.selectedSegmentId, isNot('s2'));
      expect(controller.selectedSpoolId, isNull);
    });

    test('Clicking on segment with valve selects individual spools before and after valve', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      // Добавляем задвижку по центру
      network.addValve(segmentId: 's1', ratio: 0.5, valveType: ValveType.gateValve, dn: 100);
      network.recalculateSpools();

      final spools = network.spools.values.where((sp) => sp.segmentId == 's1').toList();
      expect(spools.length, equals(2));

      final spool1 = spools.firstWhere((sp) => (sp.startPoint?.x ?? 0) < 500);
      final spool2 = spools.firstWhere((sp) => (sp.startPoint?.x ?? 0) > 500);

      // Клик по первой катушке (x = 300)
      final pSpool1 = projector.project(const Node3D(id: 'pt1', x: 300, y: 0, z: 0));
      controller.handlePointerDown(pSpool1);

      expect(controller.selectedSpoolId, equals(spool1.id));
      expect(controller.selectedSegmentId, equals('s1'));

      // Клик по второй катушке (x = 1700)
      final pSpool2 = projector.project(const Node3D(id: 'pt2', x: 1700, y: 0, z: 0));
      controller.handlePointerDown(pSpool2);

      expect(controller.selectedSpoolId, equals(spool2.id));
      expect(controller.selectedSegmentId, equals('s1'));
    });

    test('In centerline mode, clicking on centerline segment selects the entire segment', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 300, z: 0);
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      network.recalculateSpools();

      controller.isCenterlineMode = true;

      final midScreen = projector.project(const Node3D(id: 'mid', x: 0, y: 150, z: 0));
      controller.handlePointerDown(midScreen);

      expect(controller.selectedSegmentId, equals('s1'));
    });
  });
}
