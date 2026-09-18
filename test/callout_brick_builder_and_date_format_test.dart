import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:flutter/material.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/callout_manager_panel.dart';

void main() {
  group('Date Formatting for Weld Callouts', () {
    test('formatWeldDate handles ISO format and outputs various formats', () {
      const rawIso = '2026-09-18';
      expect(formatWeldDate(rawIso, 'DD.MM.YYYY'), equals('18.09.2026'));
      expect(formatWeldDate(rawIso, 'DD.MM.YY'), equals('18.09.26'));
      expect(formatWeldDate(rawIso, 'YYYY-MM-DD'), equals('2026-09-18'));
      expect(formatWeldDate(rawIso, 'DD/MM/YYYY'), equals('18/09/2026'));
    });

    test('formatWeldDate handles dot-separated dates (18.09.2026)', () {
      const rawDot = '18.09.2026';
      expect(formatWeldDate(rawDot, 'DD.MM.YYYY'), equals('18.09.2026'));
      expect(formatWeldDate(rawDot, 'DD.MM.YY'), equals('18.09.26'));
      expect(formatWeldDate(rawDot, 'YYYY-MM-DD'), equals('2026-09-18'));
    });

    test('formatCalloutTemplate respects dateFormat parameter and defaults to DD.MM.YYYY', () {
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 1000, y: 0, z: 0),
        },
        segments: {
          's1': const PipeSegment(
            id: 's1',
            startNodeId: 'n1',
            endNodeId: 'n2',
            systemId: 'sys1',
            dn: 50,
          ),
        },
        weldJoints: {
          'w1': const WeldJoint(
            id: 'w1',
            segmentId: 's1',
            ratio: 0.5,
            number: 1,
            stamp: 'СВ-1',
            date: '2026-09-18',
            weldType: WeldType.c17,
          ),
        },
      );

      // По умолчанию ISO-дата форматируется как ГОСТ DD.MM.YYYY
      final defaultFormatted = net.formatCalloutTemplate(
        CalloutTargetType.weld,
        'w1',
        '{DATE}',
      );
      expect(defaultFormatted, equals('18.09.2026'));

      // Явный формат DD.MM.YY
      final yyFormatted = net.formatCalloutTemplate(
        CalloutTargetType.weld,
        'w1',
        '{DATE}',
        dateFormat: 'DD.MM.YY',
      );
      expect(yyFormatted, equals('18.09.26'));

      // Явный формат YYYY-MM-DD
      final isoFormatted = net.formatCalloutTemplate(
        CalloutTargetType.weld,
        'w1',
        '{DATE}',
        dateFormat: 'YYYY-MM-DD',
      );
      expect(isoFormatted, equals('2026-09-18'));

      // Инлайн-модификатор в шаблоне {DATE:DD.MM.YY}
      final inlineFormatted = net.formatCalloutTemplate(
        CalloutTargetType.weld,
        'w1',
        '{TYPE} {STAMP} {DATE:DD.MM.YY}',
      );
      expect(inlineFormatted, equals('С17 СВ-1 18.09.26'));
    });

    test('generateCalloutBottomText uses date_format from templates map', () {
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 1000, y: 0, z: 0),
        },
        segments: {
          's1': const PipeSegment(
            id: 's1',
            startNodeId: 'n1',
            endNodeId: 'n2',
            systemId: 'sys1',
            dn: 50,
          ),
        },
        weldJoints: {
          'w1': const WeldJoint(
            id: 'w1',
            segmentId: 's1',
            ratio: 0.5,
            number: 1,
            stamp: 'СВ-1',
            date: '2026-09-18',
            weldType: WeldType.c17,
          ),
        },
      );

      final callout = Callout(
        id: 'c1',
        targetId: 'w1',
        targetType: CalloutTargetType.weld,
      );

      final bottomText = net.generateCalloutBottomText(
        callout,
        {
          'weld_bottom': '{TYPE} {DATE}',
          'date_format': 'DD.MM.YY',
        },
      );

      expect(bottomText, equals('С17 18.09.26'));
    });
  });

  group('TemplateBrick Tokenization and Roundtrip', () {
    test('parseTemplateToBricks splits text into static and placeholder bricks', () {
      const template = '{NAME} Ду{DN} L={L}';
      final bricks = parseTemplateToBricks(template);

      expect(bricks.length, equals(5));
      expect(bricks[0].text, equals('{NAME}'));
      expect(bricks[0].isPlaceholder, isTrue);

      expect(bricks[1].text, equals(' Ду'));
      expect(bricks[1].isPlaceholder, isFalse);

      expect(bricks[2].text, equals('{DN}'));
      expect(bricks[2].isPlaceholder, isTrue);

      expect(bricks[3].text, equals(' L='));
      expect(bricks[3].isPlaceholder, isFalse);

      expect(bricks[4].text, equals('{L}'));
      expect(bricks[4].isPlaceholder, isTrue);

      expect(bricksToTemplate(bricks), equals(template));
    });

    test('reordering bricks produces expected updated template string', () {
      final bricks = parseTemplateToBricks('{TYPE} {STAMP} {DATE}');
      // Swap {DATE} with {STAMP}
      // Original: [0: {TYPE}, 1: ' ', 2: {STAMP}, 3: ' ', 4: {DATE}]
      final reordered = List<TemplateBrick>.from(bricks);
      final dateBrick = reordered.removeAt(4);
      reordered.insert(2, dateBrick);

      final newTemplate = bricksToTemplate(reordered);
      expect(newTemplate, equals('{TYPE} {DATE}{STAMP} '));
    });

    test('deleting a brick removes it cleanly from template', () {
      final bricks = parseTemplateToBricks('№{NUM} {DATE}');
      // Remove {DATE}
      bricks.removeWhere((b) => b.text == '{DATE}');
      expect(bricksToTemplate(bricks).trim(), equals('№{NUM}'));
    });
  });

  group('CalloutManagerPanel Template Builder Widget Tests', () {
    testWidgets('Switching active shelf and inserting chips into bottom shelf', (tester) async {
      final network = PipingNetwork();
      final controller = PipingInputController(network: network);

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CalloutManagerPanel(controller: controller),
        ),
      ));
      await tester.pumpAndSettle();

      // Переключаемся на вкладку конструктора шаблонов
      await tester.tap(find.text('Конструктор шаблонов (ГОСТ / AutoCAD)'));
      await tester.pumpAndSettle();

      expect(find.text('НАД ПОЛКОЙ'), findsWidgets);

      // Кликаем по кнопке "Переключить на "Под полкой""
      await tester.tap(find.text('Переключить на "Под полкой"'));
      await tester.pumpAndSettle();

      // Теперь активна нижняя полка
      expect(find.text('ПОД ПОЛКОЙ'), findsWidgets);

      // Нажимаем на чип {CUT_LENGTH}
      final chipFinder = find.widgetWithText(ActionChip, '{CUT_LENGTH} — Длина заготовки реза (мм)');
      expect(chipFinder, findsOneWidget);
      await tester.ensureVisible(chipFinder);
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      // Проверяем, что {CUT_LENGTH} попал в нижнее поле (было {SYSTEM}, стало {SYSTEM} {CUT_LENGTH})
      expect(find.widgetWithText(TextField, '{SYSTEM} {CUT_LENGTH}'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('Date format dropdown updates date_format in controller', (tester) async {
      final network = PipingNetwork();
      final controller = PipingInputController(network: network);

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CalloutManagerPanel(controller: controller),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Конструктор шаблонов (ГОСТ / AutoCAD)'));
      await tester.pumpAndSettle();

      // Проверяем наличие селектора формата даты
      expect(find.text('ДД.ММ.ГГГГ (18.09.2026)'), findsOneWidget);

      // Открываем дропдаун формата даты
      await tester.tap(find.text('ДД.ММ.ГГГГ (18.09.2026)'));
      await tester.pumpAndSettle();

      // Выбираем ДД.ММ.ГГ (18.09.26)
      await tester.tap(find.text('ДД.ММ.ГГ (18.09.26)').last);
      await tester.pumpAndSettle();

      // Формат сохранен в проекте
      expect(controller.currentProject.calloutTemplates['date_format'], equals('DD.MM.YY'));

      controller.dispose();
    });

    testWidgets('Category dropdown switches preview and displays accurate category preview without Задвижка', (tester) async {
      final network = PipingNetwork();
      final controller = PipingInputController(network: network);

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CalloutManagerPanel(controller: controller),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Конструктор шаблонов (ГОСТ / AutoCAD)'));
      await tester.pumpAndSettle();

      // Исходно категория Труба
      expect(find.text('ПРЕДПРОСМОТР (ТРУБА)'), findsOneWidget);

      // Переключаем категорию на Сварной стык
      await tester.tap(find.text('Труба'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Сварной стык').last);
      await tester.pumpAndSettle();

      expect(find.text('ПРЕДПРОСМОТР (СВАРНОЙ СТЫК)'), findsOneWidget);
      // Проверяем, что в предпросмотре для стыка отображается С17 и СВ-01, а не Задвижка
      expect(find.textContaining('С17'), findsWidgets);
      expect(find.textContaining('СВ-01'), findsWidgets);
      expect(find.textContaining('Задвижка'), findsNothing);

      controller.dispose();
    });
  });

  group('formatPreviewCalloutText per Category (ГОСТ 2.316 Realistic Previews)', () {
    test('weld preview shows weld type and stamp, never Задвижка or К-1', () {
      final top = formatPreviewCalloutText('Стык №{ID}', CalloutTargetType.weld);
      expect(top, equals('Стык №1'));
      expect(top.contains('К-1'), isFalse);

      final bottom = formatPreviewCalloutText('{TYPE} {STAMP} {DATE}', CalloutTargetType.weld, dateFormat: 'DD.MM.YYYY');
      expect(bottom, equals('С17 СВ-01 18.09.2026'));
      expect(bottom.contains('Задвижка'), isFalse);

      final method = formatPreviewCalloutText('{METHOD}', CalloutTargetType.weld);
      expect(method, equals('ВИК+РК'));
    });

    test('equipment preview shows equipment name, tag and type, never Задвижка', () {
      final top = formatPreviewCalloutText('{NAME}', CalloutTargetType.equipment);
      expect(top, equals('Емкость Е-1'));
      expect(top.contains('Задвижка'), isFalse);

      final bottom = formatPreviewCalloutText('{TYPE}', CalloutTargetType.equipment);
      expect(bottom, equals('Горизонтальный цилиндр'));
      expect(bottom.contains('Задвижка'), isFalse);

      final tag = formatPreviewCalloutText('{TAG}', CalloutTargetType.equipment);
      expect(tag, equals('Е-1'));

      final id = formatPreviewCalloutText('{ID}', CalloutTargetType.equipment);
      expect(id, equals('Е-1'));
      expect(id.contains('К-1'), isFalse);
    });

    test('support preview shows support name, type and code, never Задвижка', () {
      final top = formatPreviewCalloutText('{NAME}', CalloutTargetType.support);
      expect(top, equals('ОП-1'));
      expect(top.contains('Задвижка'), isFalse);

      final bottom = formatPreviewCalloutText('{TYPE}', CalloutTargetType.support);
      expect(bottom, equals('Опора подвижная'));
      expect(bottom.contains('Задвижка'), isFalse);

      final code = formatPreviewCalloutText('{CODE}', CalloutTargetType.support);
      expect(code, equals('ОП'));
    });

    test('node preview shows node number and height mark Z', () {
      final top = formatPreviewCalloutText('Узел {ID}', CalloutTargetType.node);
      expect(top, equals('Узел 1'));
      expect(top.contains('К-1'), isFalse);

      final bottom = formatPreviewCalloutText('Отм. {Z}', CalloutTargetType.node);
      expect(bottom, equals('Отм. 2400'));
      expect(bottom.contains('{Z}'), isFalse);
    });

    test('nozzle preview shows nozzle designation, DN and equipment', () {
      final top = formatPreviewCalloutText('Шт. {NAME} Ду{DN}', CalloutTargetType.nozzle);
      expect(top, equals('Шт. Ш-1 Ду80'));
      expect(top.contains('Задвижка'), isFalse);

      final bottom = formatPreviewCalloutText('{EQUIPMENT}', CalloutTargetType.nozzle);
      expect(bottom, equals('Емкость Е-1'));
    });

    test('fitting preview shows fitting name, type and GOСТ standard', () {
      final top = formatPreviewCalloutText('{NAME}', CalloutTargetType.fitting);
      expect(top, equals('Отвод 90° 89х4'));
      expect(top.contains('Задвижка'), isFalse);

      final type = formatPreviewCalloutText('{TYPE}', CalloutTargetType.fitting);
      expect(type, equals('Отвод 90°'));
      expect(type.contains('Задвижка'), isFalse);

      final standard = formatPreviewCalloutText('{STANDARD}', CalloutTargetType.fitting);
      expect(standard, equals('ГОСТ 17375-2001'));
      expect(standard.contains('ГОСТ 10704-91'), isFalse);
    });

    test('segment preview shows spool mark and dimensions, never Задвижка', () {
      final top = formatPreviewCalloutText('{NAME} Ду{DN} L={L}', CalloutTargetType.segment);
      expect(top, equals('К-1 Ду80 L=2400'));
      expect(top.contains('Задвижка'), isFalse);

      final bottom = formatPreviewCalloutText('{SYSTEM}', CalloutTargetType.segment);
      expect(bottom, equals('В1'));
    });
  });
}

