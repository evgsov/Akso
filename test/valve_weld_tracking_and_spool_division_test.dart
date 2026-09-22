import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Valve Weld Tracking and Spool Division Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      controller = PipingInputController(network: network);

      // Сегмент трубы 3000 мм: (0,0,0) -> (3000,0,0), Ду100
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
        material: 'Сталь 20',
      );
    });

    test('1. Добавление арматуры, генерация стыков и нарезка на 2 катушки', () {
      final valve = network.addValve(
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
        customLengthMm: 200,
        isFlanged: true,
        includeCounterFlanges: true,
        counterFlangeLengthMm: 45,
      );

      expect(valve.id, isNotEmpty);
      // До генерации стыков - стыков нет
      expect(network.weldJoints, isEmpty);

      // Автоматическая расстановка стыков
      final added = network.generateElementWeldJoints();
      expect(added, equals(2));
      expect(network.weldJoints.length, equals(2));

      // Проверяем, что создано ровно 2 катушки (L1 и L2)
      final spools = network.spools.values.where((s) => s.segmentId == 'seg1').toList();
      expect(spools.length, equals(2));

      // Полная длина арматуры с фланцами: 200 + 2*45 = 290 мм
      // Свободная длина трубы: 3000 - 290 = 2710 мм
      // При ratio = 0.5: L1 = 1355 мм, L2 = 1355 мм
      expect(spools[0].cutLengthMm, closeTo(1355.0, 1.0));
      expect(spools[1].cutLengthMm, closeTo(1355.0, 1.0));
    });

    test('2. Перемещение арматуры (slideValve) перемещает стыки и не создает дубликатов и миникатушек', () {
      final valve = network.addValve(
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
        customLengthMm: 200,
        isFlanged: true,
        includeCounterFlanges: true,
        counterFlangeLengthMm: 45,
      );
      network.generateElementWeldJoints();
      expect(network.weldJoints.length, equals(2));

      final initialWeldIds = network.weldJoints.keys.toSet();

      // Сдвигаем арматуру на ratio = 0.75
      network.slideValve(valve.id, 0.75);

      // Стыки не должны продублироваться! Их количество строго 2
      expect(network.weldJoints.length, equals(2));
      // Идентификаторы стыков сохранились (не пересоздались)
      expect(network.weldJoints.keys.toSet(), equals(initialWeldIds));

      // Катушек строго 2 (никаких паразитных миникатушек!)
      final spools = network.spools.values.where((s) => s.segmentId == 'seg1').toList();
      expect(spools.length, equals(2));

      // L1 должна вырасти, L2 уменьшиться
      expect(spools[0].cutLengthMm, greaterThan(2000.0));
      expect(spools[1].cutLengthMm, lessThan(700.0));
    });

    test('3. Многократное интерактивное перемещение не оставляет призрачных швов', () {
      final valve = network.addValve(
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
        customLengthMm: 200,
      );
      network.generateElementWeldJoints();

      // Имитируем 20 шагов перетаскивания мыши / стилуса
      for (int i = 0; i < 20; i++) {
        final t = 0.2 + (i / 20.0) * 0.6;
        network.valves[valve.id] = network.valves[valve.id]!.copyWith(ratio: t);
        network.syncValveWelds(network.valves[valve.id]!);
      }
      network.recalculateSpools();

      // После 20 шагов движения: ровно 2 шва и ровно 2 катушки!
      expect(network.weldJoints.length, equals(2));
      final spools = network.spools.values.where((s) => s.segmentId == 'seg1').toList();
      expect(spools.length, equals(2));
    });

    test('4. Перемещение через контроллер по L1 и L2 (updateValvePositionByPrevSection / NextSection)', () {
      final valve = network.addValve(
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
        customLengthMm: 200,
        isFlanged: true,
        includeCounterFlanges: true,
        counterFlangeLengthMm: 45,
      );
      network.generateElementWeldJoints();

      // Задаем L1 = 500 мм
      controller.updateValvePositionByPrevSection(valve.id, 500.0);

      expect(network.weldJoints.length, equals(2));
      var spools = network.spools.values.where((s) => s.segmentId == 'seg1').toList();
      expect(spools.length, equals(2));
      expect(spools[0].cutLengthMm, closeTo(500.0, 1.5));

      // Задаем L2 = 800 мм
      controller.updateValvePositionByNextSection(valve.id, 800.0);

      expect(network.weldJoints.length, equals(2));
      spools = network.spools.values.where((s) => s.segmentId == 'seg1').toList();
      expect(spools.length, equals(2));
      expect(spools[1].cutLengthMm, closeTo(800.0, 1.5));
    });

    test('5. Повторный вызов generateElementWeldJoints после перемещения арматуры идемпотентен', () {
      final valve = network.addValve(
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
        customLengthMm: 200,
      );
      network.generateElementWeldJoints();
      expect(network.weldJoints.length, equals(2));

      network.slideValve(valve.id, 0.8);
      expect(network.weldJoints.length, equals(2));

      // Повторный запуск генерации
      final addedAgain = network.generateElementWeldJoints();
      expect(addedAgain, equals(0));
      expect(network.weldJoints.length, equals(2));

      final spools = network.spools.values.where((s) => s.segmentId == 'seg1').toList();
      expect(spools.length, equals(2));
    });

    test('6. Удаление арматуры (removeValve) убирает ее стыки и восстанавливает целую катушку', () {
      final valve = network.addValve(
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
        customLengthMm: 200,
      );
      network.generateElementWeldJoints();
      expect(network.weldJoints.length, equals(2));
      expect(network.spools.length, equals(2));

      // Удаляем арматуру
      final removed = network.removeValve(valve.id);
      expect(removed, isTrue);

      // Стыки арматуры удалены
      expect(network.weldJoints, isEmpty);

      // Труба восстановилась в 1 целую катушку длиной 3000 мм
      final spools = network.spools.values.where((s) => s.segmentId == 'seg1').toList();
      expect(spools.length, equals(1));
      expect(spools[0].cutLengthMm, closeTo(3000.0, 1.0));
    });

    test('7. Пользовательские ручные стыки (isManual: true) защищены от автоудаления', () {
      // Пользователь вручную врезал стык на трубе
      final manualWeld = network.addWeldJoint(
        segmentId: 'seg1',
        ratio: 0.25,
        isManual: true,
        weldType: WeldType.c17,
        stamp: 'РУЧ-01',
      );

      final valve = network.addValve(
        segmentId: 'seg1',
        ratio: 0.7,
        valveType: ValveType.gateValve,
        dn: 100,
      );
      network.generateElementWeldJoints();

      // Всего 3 стыка: 1 ручной + 2 от арматуры
      expect(network.weldJoints.length, equals(3));
      expect(network.weldJoints.containsKey(manualWeld.id), isTrue);

      // Двигаем арматуру
      network.slideValve(valve.id, 0.8);
      expect(network.weldJoints.length, equals(3));
      expect(network.weldJoints.containsKey(manualWeld.id), isTrue);

      // Удаляем арматуру
      network.removeValve(valve.id);

      // Ручной стык остался!
      expect(network.weldJoints.length, equals(1));
      expect(network.weldJoints.containsKey(manualWeld.id), isTrue);
      expect(network.weldJoints[manualWeld.id]!.stamp, equals('РУЧ-01'));
    });

    test('8. Концевой монтаж на открытый торец (терминальный шов подавляется и восстанавливается)', () {
      final valve = network.addValve(
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
        customLengthMm: 300,
        isFlanged: true,
        includeCounterFlanges: true,
        counterFlangeLengthMm: 45,
      );
      network.generateElementWeldJoints();
      expect(network.weldJoints.length, equals(2));

      // Сдвигаем арматуру вплотную к началу открытого торца трубы (n1)
      network.slideValve(valve.id, 0.05);

      // Внешний шов (со стороны открытого конца) удален, внутренний остался
      expect(network.weldJoints.length, equals(1));
      expect(network.weldJoints.values.first.sourceElementId, equals('${valve.id}_end'));

      // Отодвигаем арматуру обратно в середину
      network.slideValve(valve.id, 0.5);

      // Повторная генерация восстанавливает оба монтажных стыка
      network.generateElementWeldJoints();
      expect(network.weldJoints.length, equals(2));
    });
  });
}
