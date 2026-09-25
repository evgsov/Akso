import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/enums/fitting_type.dart';

void main() {
  group('No auto weld joints on element insertion', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
        material: 'Сталь 20',
      );
    });

    test('addValve does not auto-create weld joints', () {
      final valve = network.addValve(
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
      );

      expect(valve, isNotNull);
      expect(network.valves.length, equals(1));
      // Стыки не должны создаваться автоматически
      expect(network.weldJoints, isEmpty);
    });

    test('insertReducer does not auto-create weld joints', () {
      final reducer = network.insertReducer(
        segmentId: 'seg1',
        ratio: 0.5,
        newDn: 80,
      );

      expect(reducer, isNotNull);
      expect(network.fittings.length, equals(1));
      // Стыки не должны создаваться автоматически
      expect(network.weldJoints, isEmpty);
    });

    test('insertFlange does not auto-create weld joints', () {
      final flange = network.insertFlange(
        segmentId: 'seg1',
        ratio: 0.5,
        flangeConnectionType: FlangeConnectionType.pipeToPipe,
      );

      expect(flange, isNotNull);
      expect(network.fittings.length, equals(1));
      // Стыки не должны создаваться автоматически
      expect(network.weldJoints, isEmpty);
    });

    test('attachCapToNode does not auto-create weld joints', () {
      final cap = network.attachCapToNode('n2');

      expect(cap, isNotNull);
      expect(network.fittings.length, equals(1));
      // Стыки не должны создаваться автоматически
      expect(network.weldJoints, isEmpty);
    });

    test('attachEndFlangeToNode does not auto-create weld joints', () {
      final flange = network.attachEndFlangeToNode(
        'n2',
        flangeConnectionType: FlangeConnectionType.toEquipment,
      );

      expect(flange, isNotNull);
      expect(network.fittings.length, equals(1));
      // Стыки не должны создаваться автоматически
      expect(network.weldJoints, isEmpty);
    });

    test('connectBranchToSegment does not auto-create weld joints', () {
      network.nodes['n3'] = const Node3D(id: 'n3', x: 1000, y: 1000, z: 0);
      final branch = network.connectBranchToSegment(
        hostSegmentId: 'seg1',
        ratio: 0.5,
        branchEndNodeId: 'n3',
        branchDn: 50,
      );

      expect(branch, isNotNull);
      expect(network.fittings.length, equals(1));
      // Стыки не должны создаваться автоматически
      expect(network.weldJoints, isEmpty);
    });

    test('generateMissingCallouts does not auto-create weld joints or duplicate weld callouts', () {
      // Добавляем арматуру
      network.addValve(
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
      );

      // Генерируем выноски
      final count = network.generateMissingCallouts();

      // Должны быть выноски для двух катушек (до и после арматуры) и для задвижки, но никаких выносок для стыков
      expect(count, equals(3));
      expect(network.callouts.values.any((c) => network.spools.containsKey(c.targetId)), isTrue);
      expect(network.callouts.values.any((c) => c.targetId.startsWith('valve_')), isTrue);
      expect(network.callouts.values.any((c) => c.targetId.startsWith('weld_')), isFalse);
      expect(network.weldJoints, isEmpty);
    });
  });
}
