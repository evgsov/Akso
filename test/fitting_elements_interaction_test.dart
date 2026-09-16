import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/models/fitting_catalog.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/ui/features/editor/widgets/fitting_catalog_dialog.dart';
import 'package:akso/ui/features/editor/widgets/fitting_properties_sheet.dart';

void main() {
  group('Fitting Elements & Exact Weld Count Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      network.systems['sys1'] = const PipingSystem(id: 'sys1', name: 'Техническая вода', code: 'В3', colorValue: 0xFF0000FF, dxfAciColor: 5);
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      network.recalculateSpools();
    });

    test('Фланец к оборудованию (toEquipment) не создает автоматических стыков', () {
      final initialWelds = network.weldJoints.length;
      expect(initialWelds, 0);

      final flange = network.insertFlange(
        segmentId: 'seg1',
        ratio: 0.5,
        flangeConnectionType: FlangeConnectionType.toEquipment,
        dn: 100,
      );

      expect(flange, isNotNull);
      expect(flange!.flangeConnectionType, FlangeConnectionType.toEquipment);
      expect(flange.effectiveWeldCount, 1);
      expect(flange.isFlangePair, false);

      // Проверяем, что стыки не создаются автоматически
      expect(network.weldJoints.length, 0);
    });

    test('Межтрубное фланцевое соединение (pipeToPipe) не создает автоматических стыков', () {
      final flange = network.insertFlange(
        segmentId: 'seg1',
        ratio: 0.5,
        flangeConnectionType: FlangeConnectionType.pipeToPipe,
        dn: 100,
      );

      expect(flange, isNotNull);
      expect(flange!.flangeConnectionType, FlangeConnectionType.pipeToPipe);
      expect(flange.effectiveWeldCount, 2);
      expect(flange.isFlangePair, true);

      // Проверяем, что автоматические стыки не добавляются
      expect(network.weldJoints.length, 0);
    });

    test('Фланцевая заглушка (blindFlange) не создает автоматических стыков', () {
      final flange = network.insertFlange(
        segmentId: 'seg1',
        ratio: 0.5,
        flangeConnectionType: FlangeConnectionType.blindFlange,
        dn: 100,
      );

      expect(flange, isNotNull);
      expect(flange!.flangeConnectionType, FlangeConnectionType.blindFlange);
      expect(flange.effectiveWeldCount, 1);
      expect(network.weldJoints.length, 0);
    });

    test('Ручное переопределение числа стыков через customWeldCount', () {
      final flange = network.insertFlange(
        segmentId: 'seg1',
        ratio: 0.5,
        flangeConnectionType: FlangeConnectionType.toEquipment,
        customWeldCount: 3,
      );

      expect(flange!.effectiveWeldCount, 3);
    });

    test('Переключение режима фланца через updateFitting сохраняет параметры', () {
      final flange = network.insertFlange(
        segmentId: 'seg1',
        ratio: 0.5,
        flangeConnectionType: FlangeConnectionType.pipeToPipe,
      );
      expect(network.weldJoints.length, 0);

      // Переключаем в режим к оборудованию
      final updated = flange!.copyWith(
        flangeConnectionType: FlangeConnectionType.toEquipment,
        isFlangePair: false,
      );
      network.updateFitting(flange.nodeId, updated);

      expect(network.weldJoints.length, 0);
      expect(network.fittings[flange.nodeId]!.flangeConnectionType, FlangeConnectionType.toEquipment);

      // Возвращаем в межтрубное
      final updated2 = updated.copyWith(
        flangeConnectionType: FlangeConnectionType.pipeToPipe,
        isFlangePair: true,
      );
      network.updateFitting(flange.nodeId, updated2);

      expect(network.weldJoints.length, 0);
      expect(network.fittings[flange.nodeId]!.flangeConnectionType, FlangeConnectionType.pipeToPipe);
    });

    test('Отводы и вычеты: изменение радиуса гиба R корректно пересчитывает катушки', () {
      // Создаем поворот трассы: n1 (0,0) -> n2 (1000, 0) -> n3 (1000, 1000)
      final net = PipingNetwork();
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      net.nodes['n3'] = const Node3D(id: 'n3', x: 1000, y: 1000, z: 0);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      net.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 100);

      // Автодетекция узла n2 создаст отвод 90°
      net.moveNode('n2', 1000, 0, 0); // триггерит автоопределение

      final elbow = net.fittings['n2'];
      expect(elbow, isNotNull);
      expect(elbow!.fittingType, FittingType.elbow90);
      expect(elbow.effectiveRadiusMm, 150.0); // 1.5 * DN100

      // Проверяем вычет катушки: длина 1000 - 150 = 850 мм
      net.recalculateSpools();
      final sp1 = net.spools.values.firstWhere((s) => s.segmentId == 's1');
      expect(sp1.cutLengthMm, 850.0);

      // Меняем отвод на гнутый R=3.0DN (300 мм)
      final elbowBent = elbow.copyWith(customRadiusMm: 300.0, radiusMm: 300.0);
      net.updateFitting('n2', elbowBent);

      final sp1Updated = net.spools.values.firstWhere((s) => s.segmentId == 's1');
      expect(sp1Updated.cutLengthMm, 700.0); // 1000 - 300 = 700 мм
    });

    test('attachCapToNode устанавливает эллиптическое днище без автогенерации стыка', () {
      expect(network.weldJoints.length, 0);
      expect(network.fittings['n2'], isNull);

      final cap = network.attachCapToNode('n2');
      expect(cap, isNotNull);
      expect(cap!.fittingType, FittingType.cap);
      expect(cap.dn, 100);
      expect(network.fittings['n2'], equals(cap));
      expect(network.weldJoints.length, 0);

      // Удаление фитинга через removeFitting убирает заглушку
      network.removeFitting('n2');
      expect(network.fittings['n2'], isNull);
      expect(network.weldJoints.length, 0);
    });

    test('attachEndFlangeToNode устанавливает концевой фланец на открытый конец трубы без автогенерации стыка', () {
      expect(network.weldJoints.length, 0);
      expect(network.fittings['n1'], isNull);

      final flange = network.attachEndFlangeToNode(
        'n1',
        flangeConnectionType: FlangeConnectionType.toEquipment,
        pressurePn: 16,
      );
      expect(flange, isNotNull);
      expect(flange!.fittingType, FittingType.flange);
      expect(flange.dn, 100);
      expect(flange.isFlangePair, isFalse);
      expect(network.fittings['n1'], equals(flange));
      expect(network.weldJoints.length, 0);
    });
  });

  group('FittingCatalog & Collection Tests', () {
    test('Каталог содержит базовые ГОСТ элементы и настройки трассировки', () {
      final catalog = FittingCatalog();
      expect(catalog.definitions.containsKey('elbow_gost_17375'), isTrue);
      expect(catalog.definitions.containsKey('elbow_gost_30753'), isTrue);
      expect(catalog.definitions.containsKey('elbow_bent_gost_24950'), isTrue);
      expect(catalog.definitions.containsKey('tee_gost_17376'), isTrue);
      expect(catalog.definitions.containsKey('direct_branch_u18'), isTrue);
      expect(catalog.definitions.containsKey('flange_weld_neck_11'), isTrue);

      expect(catalog.defaultFlangeConnectionType, FlangeConnectionType.toEquipment);
      expect(catalog.defaultValveIsFlanged, isFalse);
    });

    test('Добавление пользовательского элемента в коллекцию и его сохранение в JSON', () {
      final catalog = FittingCatalog();
      final customElbow = catalog.createFromBase(
        baseDefinitionId: 'elbow_gost_17375',
        newName: 'Отвод ТУ 102-488-05 R=5DN',
        newStandard: 'ТУ 102-488-05',
        newMaterial: '09Г2С',
        newRadiusFactor: 5.0,
      );

      expect(customElbow.isCustom, isTrue);
      expect(catalog.customDefinitions.length, 1);
      expect(catalog.getDefinition(customElbow.id), isNotNull);

      // Сериализация и загрузка
      final json = catalog.toJson();
      final loadedCatalog = FittingCatalog();
      loadedCatalog.loadFromJson(json);

      expect(loadedCatalog.customDefinitions.length, 1);
      final loadedCustom = loadedCatalog.getDefinition(customElbow.id);
      expect(loadedCustom, isNotNull);
      expect(loadedCustom!.name, 'Отвод ТУ 102-488-05 R=5DN');
      expect(loadedCustom.radiusFactor, 5.0);
    });
  });

  group('Fitting UI Interaction Tests', () {
    testWidgets('FittingPropertiesSheet отображает параметры и позволяет менять режим фланца', (tester) async {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      final flange = network.insertFlange(
        segmentId: 'seg1',
        ratio: 0.5,
        flangeConnectionType: FlangeConnectionType.toEquipment,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FittingPropertiesSheet(
            network: network,
            nodeId: flange!.nodeId,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Фланец Ду100'), findsWidgets);
      expect(find.text('К оборудованию\n(1 стык)'), findsOneWidget);
      expect(find.text('Межтрубное\n(2 стыка)'), findsOneWidget);
      expect(find.text('Выбрать из коллекции'), findsOneWidget);
      expect(find.text('В коллекцию'), findsOneWidget);

      // Нажимаем на "Межтрубное (2 стыка)"
      await tester.tap(find.text('Межтрубное\n(2 стыка)'));
      await tester.pumpAndSettle();

      // Проверяем, что режим обновился
      final updated = network.fittings[flange.nodeId]!;
      expect(updated.flangeConnectionType, FlangeConnectionType.pipeToPipe);
      expect(network.weldJoints.length, 0);
    });

    testWidgets('FittingCatalogDialog открывается, переключает вкладки и отображает правила', (tester) async {
      final network = PipingNetwork();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FittingCatalogDialog(network: network),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Элементы и соединения'), findsOneWidget);
      expect(find.text('Коллекция элементов'), findsOneWidget);
      expect(find.text('Правила соединений и трассировки'), findsOneWidget);
      expect(find.text('+ Создать свой элемент'), findsOneWidget);

      // Переключаем на вкладку "Правила соединений и трассировки"
      await tester.tap(find.text('Правила соединений и трассировки'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Отводы при изменении направления трассы'), findsOneWidget);
      expect(find.textContaining('Фланцевые соединения и оборудование'), findsOneWidget);
      expect(find.text('К оборудованию (1 стык)'), findsOneWidget);
      expect(find.text('Межтрубное (2 стыка)'), findsOneWidget);
    });
  });
}

