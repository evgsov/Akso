import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/valve.dart';

void main() {
  group('Callout Generation & Fitting Welds Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    test('syncFittingWeldJoints creates welds for elbows, tees and reducers', () {
      // 1. Отвод 90° в узле n2
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 1000, y: 1000, z: 0);

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 80,
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys1',
        dn: 80,
      );

      network.fittings['n2'] = const Fitting(
        id: 'fit_n2',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        dn: 80,
        radiusMm: 120.0,
        name: 'Отвод 90° 80х4',
      );

      // До вызова синхронизации/генерации сварных стыков нет (нет авто-стыков при добавлении)
      expect(network.weldJoints.length, equals(0));

      network.syncFittingWeldJoints();

      // Для отвода должно быть сгенерировано 2 шва: на seg1 в ratio 1.0 и на seg2 в ratio 0.0
      expect(network.weldJoints.length, equals(2));
      final w1 = network.weldJoints.values.firstWhere((w) => w.segmentId == 'seg1');
      final w2 = network.weldJoints.values.firstWhere((w) => w.segmentId == 'seg2');
      expect((w1.ratio - 1.0).abs() < 0.01, isTrue);
      expect((w2.ratio - 0.0).abs() < 0.01, isTrue);
    });

    test('generateMissingCallouts creates callouts for segments, fittings, welds, valves, and equipments', () {
      // Добавляем трубу
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 2000, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
        material: 'Сталь 20',
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys1',
        dn: 100,
        material: 'Сталь 20',
      );

      // Добавляем арматуру
      network.valves['v1'] = const Valve(
        id: 'v1',
        segmentId: 'seg1',
        ratio: 0.3,
        valveType: ValveType.gateValve,
        dn: 100,
        lengthMm: 200.0,
        name: 'Задвижка 30с41нж',
      );

      // Добавляем фитинг (отвод)
      network.fittings['n2'] = const Fitting(
        id: 'fit_n2',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
        name: 'Отвод 90° ГОСТ 17375',
      );

      // Добавляем сварной стык вручную
      network.addWeldJoint(segmentId: 'seg1', ratio: 0.7);

      // Добавляем аппарат
      network.addEquipment(const Equipment(
        id: 'eq1',
        name: 'Емкость Е-1',
        type: EquipmentType.cylinderVertical,
        x: 3000,
        y: 0,
        z: 0,
        width: 1000,
        length: 1000,
        height: 2000,
      ));

      final added = network.generateMissingCallouts();
      expect(added, greaterThanOrEqualTo(4));

      // Проверяем наличие выносок каждого типа
      final types = network.callouts.values.map((c) => c.targetType).toSet();
      expect(types.contains(CalloutTargetType.segment), isTrue);
      expect(types.contains(CalloutTargetType.valve), isTrue);
      expect(types.contains(CalloutTargetType.fitting), isTrue);
      expect(types.contains(CalloutTargetType.weld), isTrue);
      expect(types.contains(CalloutTargetType.equipment), isTrue);

      // Проверяем текст выноски фитинга
      final fitCallout = network.callouts.values.firstWhere((c) => c.targetType == CalloutTargetType.fitting);
      final fitText = network.generateCalloutText(fitCallout, const {});
      expect(fitText.contains('Отвод 90° ГОСТ 17375'), isTrue);

      // Проверяем текст выноски оборудования
      final eqCallout = network.callouts.values.firstWhere((c) => c.targetType == CalloutTargetType.equipment);
      final eqText = network.generateCalloutText(eqCallout, const {});
      expect(eqText, equals('Емкость Е-1'));
    });
  });
}
