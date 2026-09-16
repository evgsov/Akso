import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('PipingNetwork Topology Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();

      // Создаем базовую сеть: Стояк -> Угол -> Горизонтальный участок
      // N1(0, 0, 0) --(Seg1: стояк)--> N2(0, 0, 2500) --(Seg2: горизонталь)--> N3(0, 3000, 2500)
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 0, y: 0, z: 2500);
      final n3 = const Node3D(id: 'n3', x: 0, y: 3000, z: 2500);

      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

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

      network.recalculateSpools();
    });

    test('Перемещение узла n2 сохраняет герметичность и пересчитывает длины обеих труб', () {
      // Изначально Seg1 = 2500 мм, Seg2 = 3000 мм
      expect(network.segments['seg1']!.calculateLength(network.nodes['n1']!, network.nodes['n2']!), 2500.0);
      expect(network.segments['seg2']!.calculateLength(network.nodes['n2']!, network.nodes['n3']!), 3000.0);

      // Сдвигаем узел n2 (угол) вверх на отметку 3000 (+500 мм)
      network.moveNode('n2', 0, 0, 3000);

      // Стояк удлинился до 3000 мм
      expect(network.segments['seg1']!.calculateLength(network.nodes['n1']!, network.nodes['n2']!), 3000.0);
      // При этом труба Seg2 осталась привязана к N2 и N3, ее длина пересчиталась по теореме Пифагора (dy=3000, dz=-500)
      final newLen2 = network.segments['seg2']!.calculateLength(network.nodes['n2']!, network.nodes['n3']!);
      expect(newLen2, closeTo(3041.38, 0.1));
    });

    test('Перемещение стояка (n1 и n2) сдвигает всю привязанную ветку', () {
      // Сдвигаем стояк по оси Y на +500 мм
      network.moveRiser(['n1', 'n2'], 0, 500);

      expect(network.nodes['n1']!.y, 500.0);
      expect(network.nodes['n2']!.y, 500.0);

      // Длина стояка не изменилась (оба узла сдвинулись вместе)
      expect(network.segments['seg1']!.calculateLength(network.nodes['n1']!, network.nodes['n2']!), 2500.0);

      // А горизонтальная труба Seg2 сократилась с 3000 до 2500 мм, оставаясь соединенной с N3
      expect(network.segments['seg2']!.calculateLength(network.nodes['n2']!, network.nodes['n3']!), 2500.0);
    });

    test('Врезка задвижки автоматически создает сварные стыки и делит катушку', () {
      // Изначально на seg2 одна катушка
      expect(network.spools.values.where((s) => s.segmentId == 'seg2').length, 1);

      // Врезаем задвижку клиновую Ду50 посередине трубы (ratio = 0.5)
      final valve = network.addValve(
        segmentId: 'seg2',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 50,
      );

      expect(valve.valveType, ValveType.gateValve);
      // Сварные стыки не создаются автоматически (добавляются пользователем)
      final segWelds = network.weldJoints.values.where((w) => w.segmentId == 'seg2').toList();
      expect(segWelds.length, 0);

      // Катушек на участке теперь 2 (до задвижки и после)
      final spools = network.spools.values.where((s) => s.segmentId == 'seg2').toList();
      expect(spools.length, 2);

      // Суммарная длина катушек + длина задвижки + строительная длина отвода в узле n2 (75 мм) равна полной длине трубы
      final valveLength = valve.lengthMm;
      final sumCutLengths = spools[0].cutLengthMm + spools[1].cutLengthMm;
      final elbowDeduction = network.fittings['n2']?.effectiveRadiusMm ?? 0.0;
      expect(sumCutLengths + valveLength + elbowDeduction, closeTo(3000.0, 1.0));
    });

    test('Каскадное изменение длины сегмента seg1 смещает последующие узлы', () {
      // Увеличиваем длину стояка с 2500 до 3500 мм (+1000 мм)
      network.changeSegmentLength('seg1', 3500);

      // Узел n2 поднялся на Z=3500
      expect(network.nodes['n2']!.z, 3500.0);
      // Узел n3 также каскадно поднялся на Z=3500!
      expect(network.nodes['n3']!.z, 3500.0);

      // Длина горизонтальной трубы осталась неизменной (3000 мм)
      expect(network.segments['seg2']!.calculateLength(network.nodes['n2']!, network.nodes['n3']!), 3000.0);
    });

    test('Врезка перехода диаметров (концентрического и эксцентрического)', () {
      // Изначально seg2 имеет диаметр Ду50
      expect(network.segments['seg2']!.dn, 50);

      // Врезаем переход на Ду80 на 40% длины
      final fitting = network.insertReducer(
        segmentId: 'seg2',
        ratio: 0.4,
        newDn: 80,
        isEccentric: false,
      );

      expect(fitting, isNotNull);
      expect(fitting!.fittingType, FittingType.reducerConcentric);
      expect(fitting.dn, 50);
      expect(fitting.dnSecondary, 80);

      // Исходный seg2 удален, появились seg2_a и seg2_b
      expect(network.segments.containsKey('seg2'), isFalse);
      expect(network.segments['seg2_a']!.dn, 50);
      expect(network.segments['seg2_b']!.dn, 80);

      // Длины: seg2_a ~ 1200 мм (0.4 * 3000), seg2_b ~ 1800 мм (0.6 * 3000)
      final midNode = network.nodes[fitting.nodeId]!;
      expect(network.segments['seg2_a']!.calculateLength(network.nodes['n2']!, midNode), closeTo(1200.0, 0.1));
      expect(network.segments['seg2_b']!.calculateLength(midNode, network.nodes['n3']!), closeTo(1800.0, 0.1));

      // Проверяем сварные стыки (больше не создаются автоматически)
      final weldsA = network.weldJoints.values.where((w) => w.segmentId == 'seg2_a').toList();
      final weldsB = network.weldJoints.values.where((w) => w.segmentId == 'seg2_b').toList();
      expect(weldsA.length, 0);
      expect(weldsB.length, 0);
    });

    test('Генерация ID сущностей использует UUIDv4 вместо миллисекунд', () {
      final uuidRegex = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false);

      // 1. Сварной стык (weld_${uuid}_$number)
      final weld = network.addWeldJoint(segmentId: 'seg1', ratio: 0.3);
      final weldParts = weld.id.split('_');
      expect(weldParts.length, 3);
      expect(weldParts[0], 'weld');
      expect(uuidRegex.hasMatch(weldParts[1]), isTrue, reason: 'Weld UUID should match UUIDv4');

      // 2. Арматура (valve_${uuid})
      final valve = network.addValve(
        segmentId: 'seg1',
        ratio: 0.7,
        valveType: ValveType.gateValve,
      );
      expect(valve.id.startsWith('valve_'), isTrue);
      final valveUuid = valve.id.substring('valve_'.length);
      expect(uuidRegex.hasMatch(valveUuid), isTrue, reason: 'Valve UUID should match UUIDv4');

      // 3. Разделение сегмента (node_${uuid})
      final midNode = network.splitSegmentAtRatio('seg2', 0.5);
      expect(midNode, isNotNull);
      expect(midNode!.id.startsWith('node_'), isTrue);
      final nodeUuid = midNode.id.substring('node_'.length);
      expect(uuidRegex.hasMatch(nodeUuid), isTrue, reason: 'Split node UUID should match UUIDv4');

      // 4. Ответвление (seg_${uuid})
      final branchEnd = const Node3D(id: 'n_branch_end', x: 100, y: 100, z: 2500);
      network.nodes['n_branch_end'] = branchEnd;
      final fit = network.connectBranchToSegment(
        hostSegmentId: 'seg2_a',
        ratio: 0.5,
        branchEndNodeId: 'n_branch_end',
      );
      expect(fit, isNotNull);
      final branchSeg = network.segments.values.firstWhere((s) => s.endNodeId == 'n_branch_end');
      expect(branchSeg.id.startsWith('seg_'), isTrue);
      final segUuid = branchSeg.id.substring('seg_'.length);
      expect(uuidRegex.hasMatch(segUuid), isTrue, reason: 'Branch segment UUID should match UUIDv4');
    });
  });
}
