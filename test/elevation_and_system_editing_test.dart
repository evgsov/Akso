import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Elevation and System Editing Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      controller = PipingInputController();
      controller.network = network;

      // Создаем два узла и горизонтальную трубу Z = 0
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = Node3D(id: 'n3', x: 2000, y: 0, z: 0);

      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      network.addSegment(PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'default',
        dn: 100,
        outerDiameterMm: 108.0,
        wallThicknessMm: 4.0,
      ));

      network.addSegment(PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'default',
        dn: 100,
        outerDiameterMm: 108.0,
        wallThicknessMm: 4.0,
      ));

      network.recalculateSpools();
    });

    test('Single segment system change updates systemId and recalculates spools', () {
      expect(network.segments['seg1']!.systemId, equals('default'));

      network.changeSegmentSystem('seg1', 'sys_b1');
      expect(network.segments['seg1']!.systemId, equals('sys_b1'));
      expect(network.segments['seg2']!.systemId, equals('default'));
    });

    test('Bulk segment system change updates all specified segments', () {
      network.changeSegmentsSystem(['seg1', 'seg2'], 'sys_t3');
      expect(network.segments['seg1']!.systemId, equals('sys_t3'));
      expect(network.segments['seg2']!.systemId, equals('sys_t3'));
    });

    test('Segment elevation change shifts both start and end nodes to target elevation in meters', () {
      // Исходно n1.z = 0, n2.z = 0
      expect(network.nodes['n1']!.z, equals(0.0));
      expect(network.nodes['n2']!.z, equals(0.0));

      // Перемещаем сегмент seg1 на отметку +2.800 м (2800 мм)
      network.changeSegmentElevation('seg1', 2.800);

      expect(network.nodes['n1']!.z, equals(2800.0));
      expect(network.nodes['n2']!.z, equals(2800.0));
    });

    test('Bulk segment elevation shift moves all affected nodes by delta Z', () {
      // Исходно n1=0, n2=0, n3=0
      // Сдвигаем seg1 и seg2 на +1.500 м
      network.shiftSegmentsElevation(['seg1', 'seg2'], 1.500);

      expect(network.nodes['n1']!.z, equals(1500.0));
      expect(network.nodes['n2']!.z, equals(1500.0));
      expect(network.nodes['n3']!.z, equals(1500.0));
    });

    test('Direct node elevation change updates specific node', () {
      network.setNodeElevation('n2', 0.750);
      expect(network.nodes['n2']!.z, equals(750.0));
      expect(network.nodes['n1']!.z, equals(0.0));
    });

    test('Equipment elevation change moves equipment body and its nozzles', () {
      final eq = Equipment(
        id: 'eq1',
        name: 'Насос Н-1',
        type: EquipmentType.box,
        x: 5000,
        y: 5000,
        z: 0,
        width: 1000,
        length: 1000,
        height: 1000,
        nozzles: [
          const Nozzle(id: 'noz1', equipmentId: 'eq1', name: 'N1', localX: 0, localY: 500, localZ: 500, dn: 100),
        ],
      );
      network.addEquipment(eq);

      // Исходно eq.z = 0
      expect(network.equipments['eq1']!.z, equals(0.0));

      // Перемещаем на отметку +1.200 м (1200 мм)
      network.changeEquipmentElevation('eq1', 1.200);

      expect(network.equipments['eq1']!.z, equals(1200.0));
      // Проверяем узел штуцера
      final nozNode = network.nodes['noz1'];
      expect(nozNode, isNotNull);
      expect(nozNode!.z, equals(1200.0 + 500.0));
    });

    test('Controller handles single and multi-selection system changes with undo/redo', () {
      controller.selectedSegmentId = 'seg1';
      controller.selectedSegmentIds.clear();

      controller.changeSelectedSegmentSystem('sys_k1');
      expect(network.segments['seg1']!.systemId, equals('sys_k1'));
      expect(controller.history.canUndo, isTrue);

      // Проверяем множественный выбор
      controller.selectedSegmentIds.addAll(['seg1', 'seg2']);
      controller.changeSelectedSegmentSystem('sys_v1');
      expect(network.segments['seg1']!.systemId, equals('sys_v1'));
      expect(network.segments['seg2']!.systemId, equals('sys_v1'));

      // Undo
      controller.history.undo(network);
      expect(network.segments['seg2']!.systemId, equals('default'));
    });

    test('Controller handles segment and node elevation changes with undo', () {
      controller.selectedSegmentId = 'seg1';
      controller.changeSelectedSegmentElevation(3.500);

      expect(network.nodes['n1']!.z, equals(3500.0));
      expect(network.nodes['n2']!.z, equals(3500.0));

      controller.selectedNodeId = 'n1';
      controller.changeSelectedNodeElevation(4.000);
      expect(network.nodes['n1']!.z, equals(4000.0));

      controller.history.undo(network);
      expect(network.nodes['n1']!.z, equals(3500.0));
    });
  });
}
