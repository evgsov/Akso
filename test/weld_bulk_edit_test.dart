import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/inspection_method.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('Weld Bulk Edit Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );

      // Добавляем 3 стыка
      network.addWeldJoint(segmentId: 'seg1', ratio: 0.2, stamp: 'ИВ-01');
      network.addWeldJoint(segmentId: 'seg1', ratio: 0.5, stamp: 'ИВ-01');
      network.addWeldJoint(segmentId: 'seg1', ratio: 0.8, stamp: 'ИВ-01');
    });

    test('bulkUpdateWeldJoints updates stamp, inspectionMethod, date and electrodeGrade for selected ids', () {
      final ids = network.weldJoints.keys.toList();
      expect(ids.length, equals(3));

      // Обновляем только первые 2 стыка
      final targetIds = [ids[0], ids[1]];
      network.bulkUpdateWeldJoints(
        targetIds,
        stamp: 'ПЕТРОВ-12',
        inspectionMethod: InspectionMethod.rk,
        date: '2026-09-14',
        electrodeGrade: 'ЦЛ-11',
        steelGrade: '12Х18Н10Т',
      );

      final w0 = network.weldJoints[ids[0]]!;
      final w1 = network.weldJoints[ids[1]]!;
      final w2 = network.weldJoints[ids[2]]!;

      expect(w0.stamp, equals('ПЕТРОВ-12'));
      expect(w0.inspectionMethod, equals(InspectionMethod.rk));
      expect(w0.date, equals('2026-09-14'));
      expect(w0.electrodeGrade, equals('ЦЛ-11'));
      expect(w0.steelGrade, equals('12Х18Н10Т'));

      expect(w1.stamp, equals('ПЕТРОВ-12'));
      expect(w1.inspectionMethod, equals(InspectionMethod.rk));

      // Третий стык остался неизменным
      expect(w2.stamp, equals('ИВ-01'));
      expect(w2.inspectionMethod, equals(InspectionMethod.vik));
      expect(w2.electrodeGrade, equals('УОНИ 13/55'));
    });

    test('updateWeldJoint single update via updater callback works correctly', () {
      final id = network.weldJoints.keys.first;
      network.updateWeldJoint(id, (w) => w.copyWith(stamp: 'СИДОРОВ-03', notes: 'УЗК 100% годен'));

      final updated = network.weldJoints[id]!;
      expect(updated.stamp, equals('СИДОРОВ-03'));
      expect(updated.notes, equals('УЗК 100% годен'));
    });
  });
}
