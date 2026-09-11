import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/ui/features/editor/widgets/piping_systems_dialog.dart';

void main() {
  group('PipingSystem & System Management Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    test('Создание пользовательской системы со сталью и диапазоном диаметров', () {
      const customSystem = PipingSystem(
        id: 'sys_custom_th1',
        code: 'ТХ1',
        name: 'Технологический мазутопровод',
        colorValue: 0xFF4E342E,
        dxfAciColor: 34,
        defaultDn: 80,
        defaultMaterial: '12Х18Н10Т',
        availableDns: [50, 65, 80, 100, 150],
        isCustom: true,
      );

      network.systems[customSystem.id] = customSystem;

      expect(network.systems.containsKey('sys_custom_th1'), isTrue);
      expect(network.systems['sys_custom_th1']?.defaultMaterial, equals('12Х18Н10Т'));
      expect(network.systems['sys_custom_th1']?.availableDns, contains(80));
      expect(network.systems['sys_custom_th1']?.isCustom, isTrue);

      // Проверяем сериализацию
      final json = network.toJson();
      final restored = PipingNetwork();
      restored.loadFromJson(json);

      final sys = restored.systems['sys_custom_th1'];
      expect(sys, isNotNull);
      expect(sys!.name, equals('Технологический мазутопровод'));
      expect(sys.defaultMaterial, equals('12Х18Н10Т'));
      expect(sys.availableDns, equals([50, 65, 80, 100, 150]));
    });

    test('Стандартные системы имеют предустановленные стали и сортамент диаметров', () {
      final b1 = network.systems['sys_b1'];
      expect(b1, isNotNull);
      expect(b1!.defaultMaterial.isNotEmpty, isTrue);
      expect(b1.availableDns.isNotEmpty, isTrue);
    });

    test('Удаление стандартного пресета системы и восстановление по умолчанию', () {
      expect(network.systems.containsKey('sys_ts'), isTrue);

      // Удаляем стандартный пресет ТС
      network.systems.remove('sys_ts');
      expect(network.systems.containsKey('sys_ts'), isFalse);

      // Восстанавливаем стандартные системы
      for (final defaultSys in PipingSystem.defaults) {
        if (!network.systems.containsKey(defaultSys.id)) {
          network.systems[defaultSys.id] = defaultSys;
        }
      }
      expect(network.systems.containsKey('sys_ts'), isTrue);
      expect(network.systems['sys_ts']!.code, 'ТС');
    });

    testWidgets('PipingSystemsDialog отображается без оверфлоу, позволяет удалять стандартные пресеты и редактировать сортамент', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testNetwork = PipingNetwork();
      String activeSysId = 'sys_b1';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PipingSystemsDialog(
              network: testNetwork,
              activeSystemId: activeSysId,
              onSystemSelected: (id) => activeSysId = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Проверяем заголовок и стандартные системы
      expect(find.text('Диспетчер систем трубопроводов'), findsOneWidget);
      expect(find.text('Сброс к ГОСТ'), findsOneWidget);
      expect(find.text('В1 — Холодное водоснабжение'), findsOneWidget);
      expect(find.text('Т3 — Горячее водоснабжение (подача)'), findsOneWidget);

      // Проверяем, что у стандартных пресетов есть кнопка удаления
      final deleteButtons = find.byIcon(Icons.delete_outline);
      expect(deleteButtons, findsWidgets);

      // Удаляем стандартный пресет Т3
      // Ищем плитку Т3 и кликаем кнопку удаления рядом с ней
      final t3Finder = find.widgetWithText(ListTile, 'Т3 — Горячее водоснабжение (подача)');
      final t3DeleteBtn = find.descendant(of: t3Finder, matching: find.byIcon(Icons.delete_outline));
      await tester.tap(t3DeleteBtn);
      await tester.pumpAndSettle();

      // Должен появиться диалог подтверждения
      expect(find.text('Удалить систему Т3?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();

      // Т3 удалена из сети
      expect(testNetwork.systems.containsKey('sys_t3'), isFalse);
      expect(find.text('Т3 — Горячее водоснабжение (подача)'), findsNothing);

      // Восстанавливаем стандартные системы
      await tester.tap(find.text('Сброс к ГОСТ'));
      await tester.pumpAndSettle();

      expect(testNetwork.systems.containsKey('sys_t3'), isTrue);
      expect(find.text('Стандартные системы ГОСТ восстановлены'), findsOneWidget);

      // Открываем редактирование системы В1
      final b1Finder = find.widgetWithText(ListTile, 'В1 — Холодное водоснабжение');
      final b1EditBtn = find.descendant(of: b1Finder, matching: find.byIcon(Icons.edit));
      await tester.tap(b1EditBtn);
      await tester.pumpAndSettle();

      // Проверяем, что в диалоге редактирования кнопки сортамента отображаются без overflow
      expect(find.text('Разрешенный сортамент диаметров (DN):'), findsOneWidget);
      expect(find.text('Все (Ду 15–1420)'), findsOneWidget);
      expect(find.text('ЖКХ (15–200)'), findsOneWidget);
      expect(find.text('Пром. (200–1400)'), findsOneWidget);

      // Кликаем по кнопке «Пром. (200–1400)»
      await tester.tap(find.text('Пром. (200–1400)'));
      await tester.pumpAndSettle();

      // Закрываем диалог редактирования
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
    });
  });
}
