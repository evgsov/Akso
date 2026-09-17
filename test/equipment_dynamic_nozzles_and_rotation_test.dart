import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('Equipment and Nozzle Data Model Tests', () {
    test('Equipment supports rotationAngleDeg and default is 0.0', () {
      const eqDefault = Equipment(
        id: 'eq1',
        name: 'Емкость Е-1',
        x: 1000,
        y: 1000,
        z: 0,
        width: 1000,
        length: 1000,
        height: 2000,
      );

      expect(eqDefault.rotationAngleDeg, equals(0.0));

      final eqRotated = eqDefault.copyWith(rotationAngleDeg: 90.0);
      expect(eqRotated.rotationAngleDeg, equals(90.0));

      final json = eqRotated.toJson();
      expect(json['rotationAngleDeg'], equals(90.0));

      final fromJson = Equipment.fromJson(json);
      expect(fromJson.rotationAngleDeg, equals(90.0));
      expect(fromJson, equals(eqRotated));
    });

    test('Equipment fromJson without rotationAngleDeg defaults to 0.0 (backward compatibility)', () {
      final legacyJson = {
        'id': 'eq_legacy',
        'name': 'Насос Н-1',
        'type': 'box',
        'x': 500.0,
        'y': 500.0,
        'z': 0.0,
        'width': 800.0,
        'length': 1200.0,
        'height': 600.0,
        'nozzles': <dynamic>[],
      };

      final eq = Equipment.fromJson(legacyJson);
      expect(eq.rotationAngleDeg, equals(0.0));
    });

    test('Nozzle supports face and includeInMto fields', () {
      const nozzle = Nozzle(
        id: 'noz1',
        equipmentId: 'eq1',
        name: 'Ш-1',
        localX: 0,
        localY: 0,
        localZ: 2000,
        face: EquipmentFace.top,
        includeInMto: false,
      );

      expect(nozzle.face, equals(EquipmentFace.top));
      expect(nozzle.includeInMto, isFalse);

      final json = nozzle.toJson();
      expect(json['face'], equals('top'));
      expect(json['includeInMto'], isFalse);

      final fromJson = Nozzle.fromJson(json);
      expect(fromJson.face, equals(EquipmentFace.top));
      expect(fromJson.includeInMto, isFalse);
      expect(fromJson, equals(nozzle));

      final nozzleMto = nozzle.copyWith(includeInMto: true, face: EquipmentFace.left);
      expect(nozzleMto.includeInMto, isTrue);
      expect(nozzleMto.face, equals(EquipmentFace.left));
    });
  });

  group('PipingNetwork Equipment Topological Management Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    test('addEquipment creates clean equipment with no dummy nodes when nozzles is empty', () {
      const eq = Equipment(
        id: 'eq1',
        name: 'Емкость Е-1',
        x: 1000,
        y: 1000,
        z: 0,
        width: 1000,
        length: 1000,
        height: 2000,
        nozzles: [],
      );

      network.addEquipment(eq);

      expect(network.equipments.containsKey('eq1'), isTrue);
      expect(network.nodes.values.any((n) => n.equipmentId == 'eq1'), isFalse);
    });

    test('attachNozzleAtWorldPoint creates Nozzle on top face with normal (0, 0, 1) and registers Node3D', () {
      const eq = Equipment(
        id: 'eq1',
        name: 'Емкость Е-1',
        x: 1000,
        y: 1000,
        z: 0,
        width: 1000,
        length: 1000,
        height: 2000,
        nozzles: [],
      );
      network.addEquipment(eq);

      // Клик по верхней крышке в центре: (1000, 1000, 2000)
      final nozNode = network.attachNozzleAtWorldPoint(
        'eq1',
        Node3D(id: 'temp', x: 1000, y: 1000, z: 2000),
        dn: 80,
      );

      expect(network.nodes.containsKey(nozNode.id), isTrue);
      expect(nozNode.equipmentId, equals('eq1'));
      expect(nozNode.x, closeTo(1000.0, 0.1));
      expect(nozNode.y, closeTo(1000.0, 0.1));
      expect(nozNode.z, closeTo(2000.0, 0.1));

      final updatedEq = network.equipments['eq1']!;
      expect(updatedEq.nozzles.length, equals(1));
      final nozzle = updatedEq.nozzles.first;
      expect(nozzle.id, equals(nozNode.id));
      expect(nozzle.dn, equals(80));
      expect(nozzle.face, equals(EquipmentFace.top));
      expect(nozzle.dirZ, equals(1.0));
      expect(nozzle.includeInMto, isFalse);
    });

    test('rotateEquipment rotates nozzle coordinates around equipment center', () {
      const eq = Equipment(
        id: 'eq1',
        name: 'Емкость Е-1',
        x: 1000,
        y: 1000,
        z: 0,
        width: 1000,
        length: 2000,
        height: 1500,
        nozzles: [],
      );
      network.addEquipment(eq);

      // Штуцер на правой стенке: X = 1000 + 500 = 1500, Y = 1000, Z = 500
      final nozNode = network.attachNozzleAtWorldPoint(
        'eq1',
        Node3D(id: 'temp', x: 1500, y: 1000, z: 500),
        dn: 50,
      );

      // Поворачиваем на +90 градусов вокруг (1000, 1000)
      // Вектор (500, 0) при повороте на +90° становится (0, 500) -> новые координаты (1000, 1500, 500)
      network.rotateEquipment('eq1', 90.0);

      expect(network.equipments['eq1']!.rotationAngleDeg, closeTo(90.0, 0.1));
      final rotatedNode = network.nodes[nozNode.id]!;
      expect(rotatedNode.x, closeTo(1000.0, 0.1));
      expect(rotatedNode.y, closeTo(1500.0, 0.1));
      expect(rotatedNode.z, closeTo(500.0, 0.1));
    });

    test('updateEquipment preserves nozzle on top face when height is modified', () {
      const eq = Equipment(
        id: 'eq1',
        name: 'Емкость Е-1',
        x: 1000,
        y: 1000,
        z: 0,
        width: 1000,
        length: 1000,
        height: 2000,
        nozzles: [],
      );
      network.addEquipment(eq);

      final nozNode = network.attachNozzleAtWorldPoint(
        'eq1',
        Node3D(id: 'temp', x: 1000, y: 1000, z: 2000),
      );

      // Пользователь меняет высоту аппарата с 2000 на 3000 в свойствах
      final updatedEq = network.equipments['eq1']!.copyWith(height: 3000.0);
      network.updateEquipment(updatedEq);

      final updatedNode = network.nodes[nozNode.id]!;
      // Узел штуцера на верхней крышке должен автоматически подняться на Z = 3000!
      expect(updatedNode.z, closeTo(3000.0, 0.1));
      final updatedNozzle = network.equipments['eq1']!.nozzles.first;
      expect(updatedNozzle.localZ, closeTo(3000.0, 0.1));
    });

    test('cleanupUnusedEquipmentNozzles removes disconnected nozzles but preserves connected ones', () {
      const eq = Equipment(
        id: 'eq1',
        name: 'Емкость Е-1',
        x: 1000,
        y: 1000,
        z: 0,
        width: 1000,
        length: 1000,
        height: 2000,
        nozzles: [],
      );
      network.addEquipment(eq);

      // Добавляем 2 штуцера
      final noz1 = network.attachNozzleAtWorldPoint('eq1', Node3D(id: 't1', x: 1000, y: 1000, z: 2000));
      final noz2 = network.attachNozzleAtWorldPoint('eq1', Node3D(id: 't2', x: 1500, y: 1000, z: 1000));

      // К noz1 подключаем трубу
      final pipeEnd = Node3D(id: 'pEnd', x: 1000, y: 1000, z: 3000);
      network.nodes[pipeEnd.id] = pipeEnd;
      network.addSegment(PipeSegment(id: 's1', startNodeId: noz1.id, endNodeId: pipeEnd.id, dn: 80, systemId: 'sys1'));

      // noz2 остался неподключенным
      network.cleanupUnusedEquipmentNozzles();

      // noz1 должен остаться, noz2 должен быть зачищен
      expect(network.nodes.containsKey(noz1.id), isTrue);
      expect(network.nodes.containsKey(noz2.id), isFalse);

      final currentEq = network.equipments['eq1']!;
      expect(currentEq.nozzles.length, equals(1));
      expect(currentEq.nozzles.first.id, equals(noz1.id));
    });
  });
}

