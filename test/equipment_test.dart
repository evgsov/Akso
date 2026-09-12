import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Equipment and Nozzles Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    test('addEquipment creates Node3D for each nozzle at absolute world coordinates', () {
      final nozzle1 = const Nozzle(
        id: 'noz_in',
        equipmentId: 'pump_1',
        name: 'Входной штуцер',
        localX: -300,
        localY: 0,
        localZ: 400,
        dirX: -1,
        dirY: 0,
        dirZ: 0,
        dn: 100,
      );
      final nozzle2 = const Nozzle(
        id: 'noz_out',
        equipmentId: 'pump_1',
        name: 'Напорный штуцер',
        localX: 0,
        localY: 0,
        localZ: 800,
        dirX: 0,
        dirY: 0,
        dirZ: 1,
        dn: 80,
      );

      final pump = Equipment(
        id: 'pump_1',
        name: 'Насос Н-1',
        type: EquipmentType.box,
        x: 1000,
        y: 2000,
        z: 100,
        width: 800,
        length: 600,
        height: 800,
        nozzles: [nozzle1, nozzle2],
      );

      network.addEquipment(pump);

      expect(network.equipments.containsKey('pump_1'), isTrue);
      expect(network.nodes.containsKey('noz_in'), isTrue);
      expect(network.nodes.containsKey('noz_out'), isTrue);

      final n1 = network.nodes['noz_in']!;
      expect(n1.x, equals(1000 - 300));
      expect(n1.y, equals(2000));
      expect(n1.z, equals(100 + 400));
      expect(n1.equipmentId, equals('pump_1'));
      expect(n1.nozzleId, equals('noz_in'));

      final n2 = network.nodes['noz_out']!;
      expect(n2.x, equals(1000));
      expect(n2.y, equals(2000));
      expect(n2.z, equals(100 + 800));
      expect(n2.equipmentId, equals('pump_1'));
      expect(n2.nozzleId, equals('noz_out'));
    });

    test('Moving equipment moves all nozzle nodes and connected pipes follow', () {
      final nozzle = const Nozzle(
        id: 'noz_top',
        equipmentId: 'tank_1',
        name: 'Ш-1',
        localX: 0,
        localY: 0,
        localZ: 2000,
        dirX: 0,
        dirY: 0,
        dirZ: 1,
        dn: 50,
      );
      final tank = Equipment(
        id: 'tank_1',
        name: 'Емкость Е-1',
        type: EquipmentType.cylinderVertical,
        x: 1000,
        y: 1000,
        z: 0,
        width: 1000,
        length: 1000,
        height: 2000,
        nozzles: [nozzle],
      );
      network.addEquipment(tank);

      // Connect pipe from tank nozzle to an external node
      final extNode = const Node3D(id: 'ext_node', x: 3000, y: 1000, z: 2000);
      network.nodes['ext_node'] = extNode;

      final pipe = const PipeSegment(
        id: 'pipe_1',
        startNodeId: 'noz_top',
        endNodeId: 'ext_node',
        systemId: 'sys_1',
        dn: 50,
      );
      network.addSegment(pipe);

      expect(network.nodes['noz_top']!.x, equals(1000.0));
      expect(network.nodes['noz_top']!.y, equals(1000.0));
      expect(network.nodes['noz_top']!.z, equals(2000.0));

      // Move equipment by (+500, -200, +100)
      network.moveEquipment('tank_1', 500, -200, 100);

      final updatedTank = network.equipments['tank_1']!;
      expect(updatedTank.x, equals(1500.0));
      expect(updatedTank.y, equals(800.0));
      expect(updatedTank.z, equals(100.0));

      // Nozzle node moved automatically
      final updatedNozNode = network.nodes['noz_top']!;
      expect(updatedNozNode.x, equals(1500.0));
      expect(updatedNozNode.y, equals(800.0));
      expect(updatedNozNode.z, equals(2100.0));

      // Connected pipe still references the nozzle node
      final connectedPipe = network.segments['pipe_1']!;
      expect(connectedPipe.startNodeId, equals('noz_top'));
      expect(network.nodes[connectedPipe.startNodeId]!.x, equals(1500.0));
      expect(network.nodes[connectedPipe.endNodeId]!.x, equals(3000.0));
    });

    test('Moving a nozzle node delegates to moving the entire equipment', () {
      final nozzle = const Nozzle(
        id: 'noz_top',
        equipmentId: 'tank_1',
        name: 'Ш-1',
        localX: 0,
        localY: 0,
        localZ: 2000,
        dirX: 0,
        dirY: 0,
        dirZ: 1,
        dn: 50,
      );
      final tank = Equipment(
        id: 'tank_1',
        name: 'Емкость Е-1',
        type: EquipmentType.cylinderVertical,
        x: 1000,
        y: 1000,
        z: 0,
        width: 1000,
        length: 1000,
        height: 2000,
        nozzles: [nozzle],
      );
      network.addEquipment(tank);

      // Drag nozzle node from (1000, 1000, 2000) to (1200, 1400, 2000)
      network.moveNode('noz_top', 1200, 1400, 2000);

      final updatedTank = network.equipments['tank_1']!;
      expect(updatedTank.x, equals(1200.0));
      expect(updatedTank.y, equals(1400.0));
      expect(updatedTank.z, equals(0.0));

      final updatedNozzleNode = network.nodes['noz_top']!;
      expect(updatedNozzleNode.x, equals(1200.0));
      expect(updatedNozzleNode.y, equals(1400.0));
      expect(updatedNozzleNode.z, equals(2000.0));
    });

    test('Removing equipment cascades deletion to nozzles, attached pipes and fittings', () {
      final nozzle = const Nozzle(
        id: 'noz_1',
        equipmentId: 'tank_1',
        name: 'Ш-1',
        localX: 0,
        localY: 0,
        localZ: 1000,
        dirX: 0,
        dirY: 0,
        dirZ: 1,
        dn: 50,
      );
      final tank = Equipment(
        id: 'tank_1',
        name: 'Емкость',
        type: EquipmentType.box,
        x: 0,
        y: 0,
        z: 0,
        width: 500,
        length: 500,
        height: 1000,
        nozzles: [nozzle],
      );
      network.addEquipment(tank);

      final extNode = const Node3D(id: 'n_ext', x: 2000, y: 0, z: 1000);
      network.nodes['n_ext'] = extNode;

      final pipe = const PipeSegment(
        id: 'seg_attached',
        startNodeId: 'noz_1',
        endNodeId: 'n_ext',
        systemId: 'sys_1',
        dn: 50,
      );
      network.addSegment(pipe);

      expect(network.equipments.containsKey('tank_1'), isTrue);
      expect(network.nodes.containsKey('noz_1'), isTrue);
      expect(network.segments.containsKey('seg_attached'), isTrue);

      network.removeEquipment('tank_1');

      expect(network.equipments.containsKey('tank_1'), isFalse);
      expect(network.nodes.containsKey('noz_1'), isFalse);
      expect(network.segments.containsKey('seg_attached'), isFalse);
      // External node should still remain
      expect(network.nodes.containsKey('n_ext'), isTrue);
    });

    test('PipingInputController handles CanvasTool.insertEquipment and deletion', () {
      final controller = PipingInputController(network: network);
      addTearDown(() => controller.dispose());

      controller.setTool(CanvasTool.insertEquipment);
      expect(controller.currentTool, equals(CanvasTool.insertEquipment));

      // Pointer down to place equipment
      controller.handlePointerDown(const Offset(200, 200));

      expect(controller.network.equipments.isNotEmpty, isTrue);
      expect(controller.selectedEquipmentId, isNotNull);

      final placedEqId = controller.selectedEquipmentId!;
      final placedEq = controller.network.equipments[placedEqId]!;
      expect(placedEq.name, equals('Емкость Е-1'));
      expect(placedEq.nozzles.length, equals(1));
      expect(controller.network.nodes.containsKey(placedEq.nozzles.first.id), isTrue);

      // Deleting selected equipment
      controller.deleteSelected();
      expect(controller.network.equipments.containsKey(placedEqId), isFalse);
      expect(controller.network.nodes.containsKey(placedEq.nozzles.first.id), isFalse);
      expect(controller.selectedEquipmentId, isNull);
    });
  });
}
