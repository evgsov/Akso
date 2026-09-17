import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/services/fitting_detector.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Direct Branch vs Tee Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      controller = PipingInputController(network: network);
    });

    test('PipingInputController useDirectBranch toggles catalog.defaultBranchId correctly', () {
      expect(controller.useDirectBranch, isFalse);
      expect(network.catalog.defaultBranchId, equals('tee_gost_17376'));

      controller.useDirectBranch = true;
      expect(controller.useDirectBranch, isTrue);
      expect(network.catalog.defaultBranchId, equals('direct_branch_u18'));

      final def = network.catalog.getDefinition(network.catalog.defaultBranchId);
      expect(def, isNotNull);
      expect(def!.fittingType, equals(FittingType.directBranch));
      expect(def.weldType, equals(WeldType.u18));
      expect(def.cutsMainPipe, isFalse);

      controller.useDirectBranch = false;
      expect(controller.useDirectBranch, isFalse);
      expect(network.catalog.defaultBranchId, equals('tee_gost_17376'));
    });

    test('FittingDetector creates direct branch with 1 U18 weld when defaultBranchId is direct_branch_u18', () {
      // Магистраль: от (0,0,0) до (2000,0,0), разделенная в (1000,0,0)
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n_mid'] = const Node3D(id: 'n_mid', x: 1000, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      // Ответвление: от (1000,0,0) до (1000,1000,0)
      network.nodes['n_branch'] = const Node3D(id: 'n_branch', x: 1000, y: 1000, z: 0);

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n_mid',
        systemId: 'sys1',
        dn: 100,
        material: 'Сталь 20',
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n_mid',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
        material: 'Сталь 20',
      );
      network.segments['seg_branch'] = const PipeSegment(
        id: 'seg_branch',
        startNodeId: 'n_mid',
        endNodeId: 'n_branch',
        systemId: 'sys1',
        dn: 50,
        material: 'Сталь 20',
      );

      // Включаем прямую врезку
      network.catalog.defaultBranchId = 'direct_branch_u18';

      FittingDetector.autoDetectFittingsForNode(network, 'n_mid');

      final fit = network.fittings['n_mid'];
      expect(fit, isNotNull);
      expect(fit!.fittingType, equals(FittingType.directBranch));
      expect(fit.cutsMainPipe, isFalse);
      expect(fit.radiusMm, equals(0.0));
      expect(fit.weldType, equals(WeldType.u18));

      // До запуска генерации стыки отсутствуют
      expect(network.weldJoints, isEmpty);

      // Генерация швов создает ровно 1 шов У18 на ответвлении seg_branch
      network.syncFittingWeldJoints();
      final branchWelds = network.weldJoints.values.where((w) => w.segmentId == 'seg_branch').toList();
      expect(branchWelds.length, equals(1));
      // Шов У18 позиционируется на наружной образующей магистрали (R_маг = 54 мм на 1000 мм трубе -> ratio = 0.054)
      expect(branchWelds.first.ratio, closeTo(0.054, 0.001));
    });

    test('FittingDetector creates tee when defaultBranchId is tee_gost_17376', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n_mid'] = const Node3D(id: 'n_mid', x: 1000, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes['n_branch'] = const Node3D(id: 'n_branch', x: 1000, y: 1000, z: 0);

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n_mid',
        systemId: 'sys1',
        dn: 100,
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n_mid',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
      network.segments['seg_branch'] = const PipeSegment(
        id: 'seg_branch',
        startNodeId: 'n_mid',
        endNodeId: 'n_branch',
        systemId: 'sys1',
        dn: 50,
      );

      network.catalog.defaultBranchId = 'tee_gost_17376';
      FittingDetector.autoDetectFittingsForNode(network, 'n_mid');

      final fit = network.fittings['n_mid'];
      expect(fit, isNotNull);
      expect(fit!.fittingType, equals(FittingType.tee));
      expect(fit.cutsMainPipe, isTrue);
      expect(fit.weldType, equals(WeldType.c17));

      // До генерации стыков швов нет
      expect(network.weldJoints, isEmpty);

      // Генерация создает 3 шва С17
      network.syncFittingWeldJoints();
      expect(network.weldJoints.length, equals(3));
      for (final w in network.weldJoints.values) {
        expect(w.weldType, equals(WeldType.c17));
      }
    });
  });
}
