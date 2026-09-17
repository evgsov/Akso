import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/models/callout.dart';

void main() {
  group('Физическое позиционирование сварных стыков (WeldJoint)', () {
    test('Отвод 90°: стыки смещены на тангенциальное расстояние T, а не стоят в узле', () {
      final network = PipingNetwork();
      // Узел отвода в n2 (1000, 0, 0), трубы по 1000 мм: n1->n2 и n2->n3
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 1000, y: 1000, z: 0);

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys1',
        dn: 100,
      );

      // Отвод 90° с R = 150 мм -> T = 150 мм
      network.fittings['n2'] = const Fitting(
        id: 'fit_elbow',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
      );
      // Заглушки на свободных концах n1 и n3
      network.attachCapToNode('n1');
      network.attachCapToNode('n3');

      final count = network.generateElementWeldJoints();
      expect(count, equals(4)); // 2 для отвода, 2 для заглушек

      // Стык на seg1 у узла n2:
      // seg1 длина 1000, endNode = n2, T = 150 -> ratio = 1.0 - 150/1000 = 0.85
      final wSeg1 = network.weldJoints.values.firstWhere((w) => w.segmentId == 'seg1' && w.ratio > 0.5);
      expect(wSeg1.ratio, closeTo(0.85, 0.001));

      // Стык на seg2 у узла n2:
      // seg2 длина 1000, startNode = n2, T = 150 -> ratio = 150/1000 = 0.15
      final wSeg2 = network.weldJoints.values.firstWhere((w) => w.segmentId == 'seg2' && w.ratio < 0.5);
      expect(wSeg2.ratio, closeTo(0.15, 0.001));

      // Физические 3D координаты стыков не должны совпадать с координатами узла n2
      final pos1 = wSeg1.calculatePosition(network.nodes['n1']!, network.nodes['n2']!);
      expect(pos1.x, closeTo(850.0, 0.1));
      expect(pos1.y, closeTo(0.0, 0.1));

      final pos2 = wSeg2.calculatePosition(network.nodes['n2']!, network.nodes['n3']!);
      expect(pos2.x, closeTo(1000.0, 0.1));
      expect(pos2.y, closeTo(150.0, 0.1));
    });

    test('Тройник: стыки смещены на плечи L/2 и H', () {
      final network = PipingNetwork();
      // Магистраль: n1(0,0,0) -> n2(1000,0,0) -> n3(2000,0,0)
      // Ответвление: n2(1000,0,0) -> n4(1000,1000,0)
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.nodes['n4'] = const Node3D(id: 'n4', x: 1000, y: 1000, z: 0);

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys1',
        dn: 100,
      );
      network.segments['segBranch'] = const PipeSegment(
        id: 'segBranch',
        startNodeId: 'n2',
        endNodeId: 'n4',
        systemId: 'sys1',
        dn: 100,
      );

      // Тройник с buildingLengthMm = 200 (плечо магистрали 100 мм), branchLengthMm = 120 мм
      network.fittings['n2'] = const Fitting(
        id: 'fit_tee',
        nodeId: 'n2',
        fittingType: FittingType.tee,
        dn: 100,
        radiusMm: 0.0,
        buildingLengthMm: 200.0,
        branchLengthMm: 120.0,
      );
      network.attachCapToNode('n1');
      network.attachCapToNode('n3');
      network.attachCapToNode('n4');

      network.generateElementWeldJoints();

      // Магистраль 1: seg1 (длина 1000, конец в n2, плечо 100) -> ratio = 1 - 100/1000 = 0.90
      final w1 = network.weldJoints.values.firstWhere((w) => w.segmentId == 'seg1' && w.ratio > 0.5);
      expect(w1.ratio, closeTo(0.90, 0.001));

      // Магистраль 2: seg2 (длина 1000, начало в n2, плечо 100) -> ratio = 100/1000 = 0.10
      final w2 = network.weldJoints.values.firstWhere((w) => w.segmentId == 'seg2' && w.ratio < 0.5);
      expect(w2.ratio, closeTo(0.10, 0.001));

      // Ответвление: segBranch (длина 1000, начало в n2, плечо 120) -> ratio = 120/1000 = 0.12
      final wB = network.weldJoints.values.firstWhere((w) => w.segmentId == 'segBranch' && w.ratio < 0.5);
      expect(wB.ratio, closeTo(0.12, 0.001));
    });

    test('Прямая врезка: приваривается только ответвление (У18) на расстоянии R_маг, на магистрали швов нет', () {
      final network = PipingNetwork();
      // Магистраль DN100 (наружный диаметр 108 мм, радиус 54 мм):
      // n1(0,0,0) -> n2(1000,0,0) -> n3(2000,0,0)
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.nodes['n4'] = const Node3D(id: 'n4', x: 1000, y: 1000, z: 0);

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys1',
        dn: 100,
      );
      // Ответвление segBranch DN50 (длина 1000)
      network.segments['segBranch'] = const PipeSegment(
        id: 'segBranch',
        startNodeId: 'n2',
        endNodeId: 'n4',
        systemId: 'sys1',
        dn: 50,
      );

      network.fittings['n2'] = const Fitting(
        id: 'fit_branch',
        nodeId: 'n2',
        fittingType: FittingType.directBranch,
        dn: 100,
        dnSecondary: 50,
        radiusMm: 0.0,
      );
      network.attachCapToNode('n1');
      network.attachCapToNode('n3');
      network.attachCapToNode('n4');

      network.generateElementWeldJoints();

      // На seg1 и seg2 у узла n2 НЕ должно быть швов (магистраль цельная сквозная)
      final seg1NearN2 = network.weldJoints.values.where((w) => w.segmentId == 'seg1' && w.ratio > 0.5);
      expect(seg1NearN2, isEmpty);

      final seg2NearN2 = network.weldJoints.values.where((w) => w.segmentId == 'seg2' && w.ratio < 0.5);
      expect(seg2NearN2, isEmpty);

      // На segBranch у узла n2 должен быть ровно 1 шов У18 на расстоянии R_маг (54 мм / 1000 мм = 0.054)
      final branchWelds = network.weldJoints.values.where((w) => w.segmentId == 'segBranch' && w.ratio < 0.5).toList();
      expect(branchWelds.length, equals(1));
      expect(branchWelds.first.weldType, equals(WeldType.u18));
      expect(branchWelds.first.ratio, closeTo(0.054, 0.005));
    });

    test('Соосный стык двух прямых труб без фитинга: создается ровно 1 шов С17', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys1',
        dn: 100,
      );
      network.attachCapToNode('n1');
      network.attachCapToNode('n3');

      network.generateElementWeldJoints();

      // У узла n2 должен быть ровно 1 шов С17
      final weldsAtN2 = network.weldJoints.values.where(
        (w) => (w.segmentId == 'seg1' && w.ratio > 0.8) || (w.segmentId == 'seg2' && w.ratio < 0.2),
      ).toList();
      expect(weldsAtN2.length, equals(1));
      expect(weldsAtN2.first.weldType, equals(WeldType.c17));
    });
  });

  group('Валидация топологической связности и очистка (validateAndCleanWeldJoints)', () {
    test('Удаляет швы на открытых торцах труб, но сохраняет на заглушках и фланцах', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );

      // Вручную ошибочно добавим швы на обоих концах открытой трубы
      network.addWeldJoint(segmentId: 'seg1', ratio: 0.0, weldType: WeldType.c17);
      network.addWeldJoint(segmentId: 'seg1', ratio: 1.0, weldType: WeldType.c17);
      expect(network.weldJoints.length, equals(2));

      // Без заглушек/фланцев оба шва должны быть удалены
      final removed = network.validateAndCleanWeldJoints();
      expect(removed, equals(2));
      expect(network.weldJoints, isEmpty);

      // Теперь добавляем фланец на n1 и заглушку на n2
      network.fittings['n1'] = const Fitting(
        id: 'fit_flange',
        nodeId: 'n1',
        fittingType: FittingType.flange,
        dn: 100,
        radiusMm: 0.0,
      );
      network.attachCapToNode('n2');

      network.generateElementWeldJoints();
      expect(network.weldJoints.length, equals(2));

      // Валидатор оставляет оба шва
      final removedAfter = network.validateAndCleanWeldJoints();
      expect(removedAfter, equals(0));
      expect(network.weldJoints.length, equals(2));
    });

    test('Удаляет ошибочные швы на сквозной магистрали врезки и перенумеровывает оставшиеся швы', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.nodes['n4'] = const Node3D(id: 'n4', x: 1000, y: 1000, z: 0);

      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      network.segments['seg2'] = const PipeSegment(id: 'seg2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 100);
      network.segments['segBranch'] = const PipeSegment(id: 'segBranch', startNodeId: 'n2', endNodeId: 'n4', systemId: 'sys1', dn: 50);

      network.fittings['n2'] = const Fitting(id: 'fit_branch', nodeId: 'n2', fittingType: FittingType.directBranch, dn: 100, radiusMm: 0.0);
      network.attachCapToNode('n1');
      network.attachCapToNode('n3');
      network.attachCapToNode('n4');

      // Добавим ошибочный шов на магистраль в n2
      network.addWeldJoint(segmentId: 'seg1', ratio: 0.95, weldType: WeldType.c17);
      // И правильный шов на ответвление
      final correctWeld = network.addWeldJoint(segmentId: 'segBranch', ratio: 0.054, weldType: WeldType.u18);

      // Добавим выноску на ошибочный шов
      final errWeld = network.weldJoints.values.firstWhere((w) => w.segmentId == 'seg1');
      network.addCallout(Callout(
        id: 'callout_err',
        targetId: errWeld.id,
        targetType: CalloutTargetType.weld,
        screenOffsetX: 50,
        screenOffsetY: -50,
      ));

      expect(network.callouts.containsKey('callout_err'), isTrue);

      // Запуск валидации
      network.validateAndCleanWeldJoints();

      // Ошибочный шов на магистрали удален
      expect(network.weldJoints.containsKey(errWeld.id), isFalse);
      // Выноска на ошибочный шов автоматически очищена
      expect(network.callouts.containsKey('callout_err'), isFalse);

      // Правильный шов остался и имеет номер 1
      final remaining = network.weldJoints[correctWeld.id];
      expect(remaining, isNotNull);
      expect(remaining!.number, equals(1));
    });
  });
}
