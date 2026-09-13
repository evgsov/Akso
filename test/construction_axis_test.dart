import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('ConstructionAxis Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    test('Создание и сериализация строительных осей в PipingNetwork', () {
      const axis1 = ConstructionAxis(
        id: 'axis_1',
        label: '1',
        startPoint: Node3D(id: '', x: 0, y: -1000, z: 0),
        endPoint: Node3D(id: '', x: 0, y: 5000, z: 0),
        isBuildingGrid: true,
      );

      const axisA = ConstructionAxis(
        id: 'axis_a',
        label: 'А',
        startPoint: Node3D(id: '', x: -1000, y: 0, z: 0),
        endPoint: Node3D(id: '', x: 5000, y: 0, z: 0),
        isBuildingGrid: true,
      );

      network.axes['axis_1'] = axis1;
      network.axes['axis_a'] = axisA;

      final json = network.toJson();
      expect(json.containsKey('axes'), isTrue);

      final restored = PipingNetwork();
      restored.loadFromJson(json);

      expect(restored.axes.length, equals(2));
      expect(restored.axes['axis_1']?.label, equals('1'));
      expect(restored.axes['axis_a']?.label, equals('А'));
      expect(restored.axes['axis_1']?.isBuildingGrid, isTrue);
    });

    test('DXF экспорт включает слой АКСО_ОСИ и текстовые марки осей', () {
      const axis = ConstructionAxis(
        id: 'axis_1',
        label: '1',
        startPoint: Node3D(id: '', x: 0, y: 0, z: 0),
        endPoint: Node3D(id: '', x: 0, y: 3000, z: 0),
        isBuildingGrid: true,
      );
      network.axes['axis_1'] = axis;

      final dxfContent = DxfWriter.generate2dGostAxonometryDxf(network);

      expect(dxfContent.contains(DxfWriter.toAutoCadString('АКСО_ОСИ')), isTrue);
      expect(dxfContent.contains('DASHDOT'), isTrue);
      expect(dxfContent.contains('1'), isTrue); // Марка оси
    });
  });
}
