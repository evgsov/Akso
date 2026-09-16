import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/callout_manager_panel.dart';

void main() {
  group('Element and Weld Generation Domain & Controller Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      controller = PipingInputController(network: network);

      // Строим сеть: n1 (0,0,0) -> n2 (2000,0,0) -> n3 (2000, 2000, 0)
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

      // Добавляем задвижку на seg1
      network.addValve(
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
      );

      // В узле n2 - отвод 90°
      network.fittings['n2'] = const Fitting(
        id: 'fit_n2',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
      );

      // В узле n3 - заглушка
      network.attachCapToNode('n3');
    });

    test('При вставке элементов стыки автоматически не создаются', () {
      expect(network.weldJoints, isEmpty);
      expect(network.valves.length, equals(1));
      expect(network.fittings.length, equals(2)); // отвод и заглушка
    });

    test('generateElementWeldJoints генерирует стыки для всех элементов и идемпотентен', () {
      final added = network.generateElementWeldJoints();
      // Задвижка: 2 стыка С17
      // Отвод n2: 2 стыка С17 (на seg1 и seg2)
      // Заглушка n3: 1 стык С17 (на seg2)
      // Всего: 5 стыков
      expect(added, equals(5));
      expect(network.weldJoints.length, equals(5));

      // Повторный вызов не дублирует стыки
      final addedAgain = network.generateElementWeldJoints();
      expect(addedAgain, equals(0));
      expect(network.weldJoints.length, equals(5));
    });

    test('generateElementCallouts создает выноски только для элементов, без стыков', () {
      final added = controller.generateElementCallouts();
      expect(added, greaterThanOrEqualTo(3)); // задвижка, отвод, заглушка

      // Проверяем типы созданных выносок: ни одной выноски для сварного стыка
      final types = network.callouts.values.map((c) => c.targetType).toSet();
      expect(types.contains(CalloutTargetType.valve), isTrue);
      expect(types.contains(CalloutTargetType.fitting), isTrue);
      expect(types.contains(CalloutTargetType.weld), isFalse);

      // Сварные стыки по-прежнему не созданы
      expect(network.weldJoints, isEmpty);
    });

    test('generateWeldsAndCallouts генерирует швы и выноски для них', () {
      final res = controller.generateWeldsAndCallouts();
      expect(res['welds'], equals(5));
      expect(res['callouts'], equals(5));

      final weldCallouts = network.callouts.values.where((c) => c.targetType == CalloutTargetType.weld).toList();
      expect(weldCallouts.length, equals(5));
    });
  });

  group('CalloutManagerPanel UI Widget Tests', () {
    testWidgets('Отображаются аккуратные кнопки "Стыки" и "Элементы" и реагируют на нажатия', (tester) async {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
      network.addValve(segmentId: 'seg1', ratio: 0.5, valveType: ValveType.gateValve);

      final controller = PipingInputController(network: network);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CalloutManagerPanel(controller: controller),
        ),
      ));
      await tester.pumpAndSettle();

      // Проверяем наличие всех 3 кнопок панели
      expect(find.text('Сгенерировать недостающие'), findsOneWidget);
      expect(find.text('Стыки'), findsOneWidget);
      expect(find.text('Элементы'), findsOneWidget);

      // Нажимаем на "Элементы"
      await tester.tap(find.text('Элементы'));
      await tester.pumpAndSettle();

      // Должна появиться выноска элемента и сообщение
      expect(find.textContaining('выносок для элементов'), findsOneWidget);
      expect(network.callouts.values.any((c) => c.targetType == CalloutTargetType.valve), isTrue);
      // Стыки не должны быть созданы
      expect(network.weldJoints, isEmpty);

      // Теперь нажимаем на "Стыки"
      await tester.tap(find.text('Стыки'));
      await tester.pumpAndSettle();

      // Должны появиться стыки и выноски для них
      expect(network.weldJoints.length, equals(2));
      expect(network.callouts.values.any((c) => c.targetType == CalloutTargetType.weld), isTrue);

      controller.dispose();
    });
  });
}
