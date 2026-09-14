import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/domain/models/linear_dimension.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('LinearDimension Model & Network Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    test('Создание и расчет длины LinearDimension', () {
      const dim = LinearDimension(
        id: 'dim_1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        startPoint: Node3D(id: 'n1', x: 0, y: 0, z: 0),
        endPoint: Node3D(id: 'n2', x: 3000, y: 4000, z: 0),
        offsetDistance: 200,
      );

      expect(dim.measuredLength, closeTo(5000.0, 0.001));
      expect(dim.displayText, equals('5000'));
    });

    test('Сериализация и десериализация LinearDimension в JSON', () {
      const dim = LinearDimension(
        id: 'dim_test',
        startNodeId: 'n1',
        endNodeId: 'n2',
        startPoint: Node3D(id: 'n1', x: 100, y: 200, z: 300),
        endPoint: Node3D(id: 'n2', x: 1100, y: 200, z: 300),
        offsetDistance: 150.0,
      );

      final json = dim.toJson();
      final restored = LinearDimension.fromJson(json);

      expect(restored.id, equals('dim_test'));
      expect(restored.startNodeId, equals('n1'));
      expect(restored.endNodeId, equals('n2'));
      expect(restored.startPoint.x, equals(100));
      expect(restored.endPoint.x, equals(1100));
      expect(restored.offsetDistance, equals(150.0));
      expect(restored.measuredLength, closeTo(1000.0, 0.001));
    });

    test('Добавление, удаление и параметрический сдвиг размеров в PipingNetwork', () {
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 2500, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 100);

      const dim = LinearDimension(
        id: 'dim_1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        startPoint: n1,
        endPoint: n2,
        offsetDistance: 300,
      );
      network.addDimension(dim);

      expect(network.dimensions.containsKey(dim.id), isTrue);
      expect(network.dimensions[dim.id]?.measuredLength, closeTo(2500.0, 0.001));

      // Параметрический сдвиг n2: размер должен автоматически пересчитаться
      network.moveNode('n2', 4000, 0, 0);
      expect(network.dimensions[dim.id]?.endPoint.x, equals(4000.0));
      expect(network.dimensions[dim.id]?.measuredLength, closeTo(4000.0, 0.001));

      // Удаление размера
      network.removeDimension(dim.id);
      expect(network.dimensions.containsKey(dim.id), isFalse);
    });

    test('Сохранение и восстановление размеров в PipingNetwork JSON', () {
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1500, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      const dim = LinearDimension(
        id: 'dim_json',
        startNodeId: 'n1',
        endNodeId: 'n2',
        startPoint: n1,
        endPoint: n2,
        offsetDistance: 250,
      );
      network.addDimension(dim);

      final netJson = network.toJson();
      expect(netJson.containsKey('dimensions'), isTrue);

      final restoredNetwork = PipingNetwork();
      restoredNetwork.loadFromJson(netJson);

      expect(restoredNetwork.dimensions.containsKey(dim.id), isTrue);
      final restoredDim = restoredNetwork.dimensions[dim.id]!;
      expect(restoredDim.measuredLength, closeTo(1500.0, 0.001));
      expect(restoredDim.offsetDistance, equals(250.0));
    });
  });

  group('DXF Export of Dimensions and Auxiliary Lines', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    test('DXF экспорт содержит слои АКСО_РАЗМЕРЫ и АКСО_РАЗМЕРЫ_ТЕКСТ с размером', () {
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 100);

      const dim = LinearDimension(
        id: 'dim_dxf',
        startNodeId: 'n1',
        endNodeId: 'n2',
        startPoint: n1,
        endPoint: n2,
        offsetDistance: 200,
      );
      network.addDimension(dim);

      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network);
      expect(dxf2d.contains(DxfWriter.toAutoCadString('АКСО_РАЗМЕРЫ')), isTrue);
      expect(dxf2d.contains(DxfWriter.toAutoCadString('АКСО_РАЗМЕРЫ_ТЕКСТ')), isTrue);
      expect(dxf2d.contains('3000'), isTrue);

      final dxf3d = DxfWriter.generate3dDxf(network);
      expect(dxf3d.contains(DxfWriter.toAutoCadString('АКСО_РАЗМЕРЫ')), isTrue);
      expect(dxf3d.contains(DxfWriter.toAutoCadString('АКСО_РАЗМЕРЫ_ТЕКСТ')), isTrue);
      expect(dxf3d.contains('3000'), isTrue);
    });

    test('Вспомогательные направляющие линии экспортируются на слой АКСО_ВСПОМОГАТЕЛЬНЫЕ', () {
      const auxAxis = ConstructionAxis(
        id: 'aux_1',
        label: '',
        startPoint: Node3D(id: '', x: 0, y: 0, z: 0),
        endPoint: Node3D(id: '', x: 5000, y: 5000, z: 0),
        isBuildingGrid: false,
      );
      network.axes['aux_1'] = auxAxis;

      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network);
      expect(dxf2d.contains(DxfWriter.toAutoCadString('АКСО_ВСПОМОГАТЕЛЬНЫЕ')), isTrue);
      expect(dxf2d.contains('DASHDOT'), isTrue);
    });
  });
}
