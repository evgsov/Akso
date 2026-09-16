import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/domain/enums/valve_type.dart';

void main() {
  group('Task 4: Cascading Spool Length & Spool Inspector Tests', () {
    late PipingNetwork net;

    setUp(() {
      net = PipingNetwork();
      net.systems['sys1'] = const PipingSystem(
        id: 'sys1',
        name: 'Водоснабжение',
        code: 'В1',
        colorValue: 0xFF2196F3,
        dxfAciColor: 5,
      );
    });

    test('changeSpoolLength on single segment cascades downstream nodes', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      net.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 1000, z: 0);

      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      net.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 100);

      net.recalculateSpools();

      final spoolS1 = net.spools.values.firstWhere((sp) => sp.segmentId == 's1');
      // В n2 отвод Ду100 с вычетом тангенса 150 мм -> рез 1850 мм
      expect(spoolS1.cutLengthMm, closeTo(1850.0, 1.0));

      // Удлиняем катушку s1 на 500 мм реза -> 2350 мм
      net.changeSpoolLength(spoolS1.id, 2350.0);

      expect(net.nodes['n2']!.x, closeTo(2500.0, 1.0));
      expect(net.nodes['n3']!.x, closeTo(2500.0, 1.0));
      expect(net.nodes['n3']!.y, closeTo(1000.0, 1.0));

      final updatedSpool = net.spools[spoolS1.id]!;
      expect(updatedSpool.cutLengthMm, closeTo(2350.0, 1.0));
    });

    test('changeSpoolLength on segmented pipe shifts downstream valve and preserves second spool', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      // Задвижка по центру ratio = 0.5 (x = 1000)
      net.addValve(segmentId: 's1', ratio: 0.5, valveType: ValveType.gateValve, dn: 100);
      net.recalculateSpools();

      final spools = net.spools.values.where((sp) => sp.segmentId == 's1').toList();
      expect(spools.length, equals(2));

      final spool1 = spools.firstWhere((sp) => (sp.startPoint?.x ?? 0) < 500);
      final spool2 = spools.firstWhere((sp) => (sp.startPoint?.x ?? 0) > 500);

      final oldSpool2Len = spool2.cutLengthMm;
      final oldSpool1Len = spool1.cutLengthMm;

      // Удлиняем первую катушку на 300 мм
      net.changeSpoolLength(spool1.id, oldSpool1Len + 300.0);

      final updatedSpool1 = net.spools[spool1.id]!;
      final updatedSpool2 = net.spools[spool2.id]!;

      expect(updatedSpool1.cutLengthMm, closeTo(oldSpool1Len + 300.0, 1.0));
      expect(updatedSpool2.cutLengthMm, closeTo(oldSpool2Len, 1.0));

      // Конечный узел s1 сдвинулся на 300 мм
      expect(net.nodes['n2']!.x, closeTo(2300.0, 1.0));
    });

    test('setSpoolMetadata preserves custom name and serial number across recalculation', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 1500, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      net.recalculateSpools();

      final spoolId = net.spools.values.first.id;
      net.setSpoolMetadata(spoolId, name: 'К-101', serialNumber: 'SN-7788');

      expect(net.spools[spoolId]!.name, equals('К-101'));
      expect(net.spools[spoolId]!.serialNumber, equals('SN-7788'));

      // Пересчет сети сохраняет метаданные
      net.recalculateSpools();
      expect(net.spools[spoolId]!.name, equals('К-101'));
      expect(net.spools[spoolId]!.serialNumber, equals('SN-7788'));
    });
  });
}
