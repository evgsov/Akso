import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('DxfWriter Export Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 2000);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 1500, z: 2000);

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 50,
      );

      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys_b1',
        dn: 50,
      );

      network.addValve(
        segmentId: 'seg2',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 50,
      );

      network.recalculateSpools();
    });

    test('3D DXF экспорт содержит обязательные секции и примитивы', () {
      final dxfContent = DxfWriter.generate3dDxf(network);

      expect(dxfContent.contains('SECTION'), isTrue);
      expect(dxfContent.contains('HEADER'), isTrue);
      expect(dxfContent.contains('TABLES'), isTrue);
      expect(dxfContent.contains('ENDTAB'), isTrue);
      expect(dxfContent.contains('ENDSEC'), isTrue);
      expect(dxfContent.contains('LTYPE'), isTrue);
      expect(dxfContent.contains('DASHDOT'), isTrue);
      expect(dxfContent.contains('ENTITIES'), isTrue);
      expect(dxfContent.contains('EOF'), isTrue);

      expect(dxfContent.contains(DxfWriter.toAutoCadString('АКСО_В1')), isTrue);
      expect(dxfContent.contains(DxfWriter.toAutoCadString('АКСО_СВАРКА')), isTrue);
      expect(dxfContent.contains('LINE'), isTrue);
    });

    test('2D ГОСТ DXF экспорт содержит плоские линии и выноски сварки', () {
      final dxfContent = DxfWriter.generate2dGostAxonometryDxf(network);

      expect(dxfContent.contains('SECTION'), isTrue);
      expect(dxfContent.contains('ENTITIES'), isTrue);
      expect(dxfContent.contains('EOF'), isTrue);

      expect(dxfContent.contains(DxfWriter.toAutoCadString('АКСО_СВАРКА_ВЫНОСКИ')), isTrue);
      expect(dxfContent.contains(DxfWriter.toAutoCadString('АКСО_ДИАМЕТРЫ')), isTrue);
      expect(dxfContent.contains('CIRCLE'), isTrue);
    });

    test('Сварочный журнал и ведомость катушек генерируются корректно', () {
      final weldCsv = DxfWriter.generateWeldJournalCsv(network);
      expect(weldCsv.contains('№ шва;Сегмент;Диаметр DN;Марка стали;Сварочные материалы;Тип шва;Клеймо сварщика'), isTrue);
      expect(weldCsv.contains('ГОСТ 16037-С17'), isTrue);

      final spoolCsv = DxfWriter.generateSpoolsCsv(network);
      expect(spoolCsv.contains('№ катушки;Диаметр DN;Стенка S (мм);Длина реза (мм);Материал'), isTrue);
      expect(spoolCsv.contains('К-1'), isTrue);
    });

    test('Экспорт переходов в 2D и 3D DXF создает слой АКСО_ПЕРЕХОДЫ и подписи', () {
      network.insertReducer(segmentId: 'seg1', ratio: 0.5, newDn: 100);

      final dxf3d = DxfWriter.generate3dDxf(network);
      expect(dxf3d.contains(DxfWriter.toAutoCadString('АКСО_ПЕРЕХОДЫ')), isTrue);
      expect(dxf3d.contains(DxfWriter.toAutoCadString('Переход')), isTrue);

      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network);
      expect(dxf2d.contains(DxfWriter.toAutoCadString('АКСО_ПЕРЕХОДЫ')), isTrue);
      expect(dxf2d.contains(DxfWriter.toAutoCadString('50×100')), isTrue);
    });
  });
}
