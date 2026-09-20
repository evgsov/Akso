import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/features/editor/widgets/materials_specification_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 5: Specification (MTO CSV) for Supports and Equipment', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 5000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        dn: 100,
        outerDiameterMm: 108.0,
        wallThicknessMm: 4.0,
        material: 'Сталь 20',
        systemId: 'sys1',
      );
    });

    test('generateMtoCsv includes equipment in section 1 with dimensions and serial numbers', () {
      final eq1 = const Equipment(
        id: 'eq1',
        name: 'Емкость дренажная Е-1',
        type: EquipmentType.cylinderHorizontal,
        x: 0,
        y: 1000,
        z: 0,
        width: 1200,
        length: 3000,
        height: 1200,
        serialNumber: '7741',
      );
      final eq2 = const Equipment(
        id: 'eq2',
        name: 'Насос центробежный Н-1',
        type: EquipmentType.box,
        x: 0,
        y: 2000,
        z: 0,
        width: 600,
        length: 800,
        height: 500,
      );

      network.addEquipment(eq1);
      network.addEquipment(eq2);

      final csv = DxfWriter.generateMtoCsv(network);

      // Проверка наличия заголовка и записей оборудования
      expect(csv, contains('Поз.;Наименование и техническая характеристика;Тип, марка;ГОСТ / ТУ;Материал;Кол-во;Ед. изм.;Примечание'));
      expect(csv, contains('Емкость дренажная Е-1 (3000×1200×1200 мм)'));
      expect(csv, contains('Цилиндр гор.'));
      expect(csv, contains('Технологическое оборудование (зав. № 7741)'));

      expect(csv, contains('Насос центробежный Н-1 (800×600×500 мм)'));
      expect(csv, contains('Параллелепипед'));
      expect(csv, contains('Технологическое оборудование'));
    });

    test('generateMtoCsv groups identical equipment items', () {
      final eq1 = const Equipment(
        id: 'eq1',
        name: 'Аппарат теплообменный Т-1',
        type: EquipmentType.cylinderVertical,
        x: 0,
        y: 1000,
        z: 0,
        width: 800,
        length: 800,
        height: 2500,
      );
      final eq2 = const Equipment(
        id: 'eq2',
        name: 'Аппарат теплообменный Т-1',
        type: EquipmentType.cylinderVertical,
        x: 0,
        y: 3000,
        z: 0,
        width: 800,
        length: 800,
        height: 2500,
      );

      network.addEquipment(eq1);
      network.addEquipment(eq2);

      final csv = DxfWriter.generateMtoCsv(network);
      // Должна быть одна сгруппированная строка с кол-вом 2
      expect(csv, contains('Аппарат теплообменный Т-1 (800×800×2500 мм);Цилиндр верт.;—;Сталь 09Г2С;2;шт.;Технологическое оборудование'));
    });

    test('generateMtoCsv includes all 4 pipe support types with respective standards and DN', () {
      // 1. Скользящая опора
      network.supports['sup1'] = const PipeSupport(
        id: 'sup1',
        segmentId: 'seg1',
        distanceRatio: 0.2,
        type: PipeSupportType.sliding,
        name: 'ОП-1',
      );

      // 2. Неподвижная опора
      network.supports['sup2'] = const PipeSupport(
        id: 'sup2',
        segmentId: 'seg1',
        distanceRatio: 0.5,
        type: PipeSupportType.fixed,
        name: 'НО-1',
      );

      // 3. Пружинная подвеска
      network.supports['sup3'] = const PipeSupport(
        id: 'sup3',
        segmentId: 'seg1',
        distanceRatio: 0.7,
        type: PipeSupportType.spring,
        name: 'ПП-1',
      );

      // 4. Направляющая опора
      network.supports['sup4'] = const PipeSupport(
        id: 'sup4',
        segmentId: 'seg1',
        distanceRatio: 0.9,
        type: PipeSupportType.guide,
        name: 'ОН-1',
      );

      final csv = DxfWriter.generateMtoCsv(network);

      // Проверка стандартов
      expect(csv, contains('ГОСТ 14911-82')); // Для sliding и fixed
      expect(csv, contains('ГОСТ 16127-78')); // Для spring
      expect(csv, contains('ОСТ 36-146-88')); // Для guide

      // Проверка наименований с диаметром трубы seg1 (⌀108×4 (Ду100))
      expect(csv, contains('Опора скользящая для трубы ⌀108×4 (Ду100);ОП-1;ГОСТ 14911-82;Сталь 3сп5;1;шт.;Опоры и подвески'));
      expect(csv, contains('Опора неподвижная для трубы ⌀108×4 (Ду100);НО-1;ГОСТ 14911-82;Сталь 3сп5;1;шт.;Опоры и подвески'));
      expect(csv, contains('Опора пружинная для трубы ⌀108×4 (Ду100);ПП-1;ГОСТ 16127-78;Сталь 3сп5;1;шт.;Опоры и подвески'));
      expect(csv, contains('Опора направляющая для трубы ⌀108×4 (Ду100);ОН-1;ОСТ 36-146-88;Сталь 3сп5;1;шт.;Опоры и подвески'));
    });

    test('generateMtoCsv groups identical supports without custom name using shortCode', () {
      // Две безымянные скользящие опоры на одной трубе
      network.supports['sup1'] = const PipeSupport(
        id: 'sup1',
        segmentId: 'seg1',
        distanceRatio: 0.25,
        type: PipeSupportType.sliding,
        name: '',
      );
      network.supports['sup2'] = const PipeSupport(
        id: 'sup2',
        segmentId: 'seg1',
        distanceRatio: 0.75,
        type: PipeSupportType.sliding,
        name: '',
      );

      final csv = DxfWriter.generateMtoCsv(network);

      // Группировка: кол-во 2, марка "ОП"
      expect(csv, contains('Опора скользящая для трубы ⌀108×4 (Ду100);ОП;ГОСТ 14911-82;Сталь 3сп5;2;шт.;Опоры и подвески'));
    });

    test('generate2dGostAxonometryDxf exports 2D supports on layers АКСО_3D_ОПОРЫ and АКСО_ОПОРЫ_ТЕКСТ', () {
      network.supports['sup1'] = const PipeSupport(
        id: 'sup1',
        segmentId: 'seg1',
        distanceRatio: 0.5,
        type: PipeSupportType.sliding,
        name: 'ОП-1',
      );

      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network);

      expect(dxf2d, contains(DxfWriter.toAutoCadString('АКСО_3D_ОПОРЫ')));
      expect(dxf2d, contains(DxfWriter.toAutoCadString('АКСО_ОПОРЫ_ТЕКСТ')));
      expect(dxf2d, contains(DxfWriter.toAutoCadString('ОП-1')));
    });

    testWidgets('MaterialsSpecificationDialog renders, filters categories and searches', (tester) async {
      // Добавим в проект оборудование, трубы, арматуру и опоры
      network.addEquipment(const Equipment(
        id: 'eq1',
        name: 'Сепаратор С-1',
        type: EquipmentType.cylinderVertical,
        x: 0,
        y: 500,
        z: 0,
        width: 1000,
        length: 1000,
        height: 2000,
      ));
      network.supports['sup1'] = const PipeSupport(
        id: 'sup1',
        segmentId: 'seg1',
        distanceRatio: 0.4,
        type: PipeSupportType.sliding,
        name: 'ОП-1',
      );

      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MaterialsSpecificationDialog(network: network),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Проверка отображения диалога и элементов
      expect(find.text('Спецификация оборудования, изделий и материалов (СО)'), findsOneWidget);
      expect(find.text('Скопировать CSV'), findsOneWidget);
      expect(find.text('Сохранить CSV'), findsOneWidget);

      // Чипы категорий присутствуют
      expect(find.widgetWithText(FilterChip, 'Все (3)'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Оборудование (1)'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Опоры (1)'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Трубы (1)'), findsOneWidget);

      // Проверка строки оборудования в таблице
      expect(find.textContaining('Сепаратор С-1'), findsOneWidget);
      // Проверка строки опоры в таблице
      expect(find.textContaining('Опора скользящая'), findsOneWidget);

      // Фильтрация по категории: кликаем на чип «Оборудование (1)»
      final eqChip = find.widgetWithText(FilterChip, 'Оборудование (1)');
      await tester.ensureVisible(eqChip);
      await tester.tap(eqChip);
      await tester.pumpAndSettle();

      // Оборудование осталось, опора скрылась
      expect(find.textContaining('Сепаратор С-1'), findsOneWidget);
      expect(find.textContaining('Опора скользящая'), findsNothing);

      // Переключаемся на чип «Опоры (1)»
      final supportChip = find.widgetWithText(FilterChip, 'Опоры (1)');
      await tester.ensureVisible(supportChip);
      await tester.tap(supportChip);
      await tester.pumpAndSettle();

      // Опора осталась, оборудование скрылось
      expect(find.textContaining('Опора скользящая'), findsOneWidget);
      expect(find.textContaining('Сепаратор С-1'), findsNothing);

      // Сбрасываем категорию на «Все (3)»
      final allChip = find.widgetWithText(FilterChip, 'Все (3)');
      await tester.ensureVisible(allChip);
      await tester.tap(allChip);
      await tester.pumpAndSettle();

      // Поиск в строке поиска
      await tester.enterText(find.byType(TextField), 'НесуществующийЭлемент');
      await tester.pumpAndSettle();
      expect(find.text('По заданным фильтрам ничего не найдено'), findsOneWidget);
    });
  });
}
