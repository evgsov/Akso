import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_dimension.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/pipe_assortment_dialog.dart';

void main() {
  group('Pipe Dimension & Industrial Assortment Tests', () {
    test('Стандартный каталог содержит промышленный ряд диаметров до Ду 1420', () {
      final catalog = PipeAssortmentCatalog();
      final dns = catalog.getAllDns();

      expect(dns.contains(15), isTrue);
      expect(dns.contains(50), isTrue);
      expect(dns.contains(150), isTrue);
      expect(dns.contains(200), isTrue);
      expect(dns.contains(250), isTrue);
      expect(dns.contains(300), isTrue);
      expect(dns.contains(400), isTrue);
      expect(dns.contains(500), isTrue);
      expect(dns.contains(600), isTrue);
      expect(dns.contains(800), isTrue);
      expect(dns.contains(1000), isTrue);
      expect(dns.contains(1400), isTrue);

      // Проверка Dн и стенок для промышленных диаметров
      final dim150 = catalog.getDimension(150);
      expect(dim150, isNotNull);
      expect(dim150!.outerDiameterMm, 159.0);
      expect(dim150.wallThicknesses.contains(4.5), isTrue);
      expect(dim150.wallThicknesses.contains(8.0), isTrue);

      final dim500 = catalog.getDimension(500);
      expect(dim500, isNotNull);
      expect(dim500!.outerDiameterMm, 530.0);
      expect(dim500.wallThicknesses.contains(8.0), isTrue);
      expect(dim500.wallThicknesses.contains(12.0), isTrue);
    });

    test('Форматирование обозначения и выноски диаметра трубы', () {
      const dim = PipeDimension(
        dn: 150,
        outerDiameterMm: 159.0,
        wallThicknesses: [4.5, 6.0, 8.0],
        defaultWallThicknessMm: 4.5,
      );

      expect(dim.formatLabel(), '⌀159×4.5 (Ду150)');
      expect(dim.formatLabel(8.0), '⌀159×8 (Ду150)');
      expect(dim.shortCallout(), '⌀159×4.5');
      expect(dim.shortCallout(6.0), '⌀159×6');

      const seg = PipeSegment(
        id: 'seg_1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 200,
        outerDiameterMm: 219.0,
        wallThicknessMm: 6.0,
      );

      expect(seg.formattedSize, '⌀219×6 (Ду200)');
      expect(seg.shortCallout, '⌀219×6');
    });

    test('Добавление пользовательского типоразмера и сохранение в каталоге сети', () {
      final network = PipingNetwork();
      const customDim = PipeDimension(
        dn: 175,
        outerDiameterMm: 180.0,
        wallThicknesses: [5.0, 6.5, 8.0],
        defaultWallThicknessMm: 6.5,
        standard: 'ТУ 14-3Р-55',
        isCustom: true,
      );

      network.pipeCatalog.addCustomDimension(customDim);
      expect(network.pipeCatalog.getDimension(175), isNotNull);
      expect(network.pipeCatalog.getDimension(175)!.outerDiameterMm, 180.0);
      expect(network.pipeCatalog.getDimension(175)!.defaultWallThicknessMm, 6.5);

      // Сериализация и восстановление сети
      final json = network.toJson();
      final restored = PipingNetwork.fromJson(json);

      expect(restored.pipeCatalog.getDimension(175), isNotNull);
      expect(restored.pipeCatalog.getDimension(175)!.outerDiameterMm, 180.0);
      expect(restored.pipeCatalog.getDimension(175)!.wallThicknesses, [5.0, 6.5, 8.0]);
    });

    test('Добавление дополнительной толщины стенки к существующему диаметру', () {
      final catalog = PipeAssortmentCatalog();
      final initialCount = catalog.getDimension(150)!.wallThicknesses.length;

      catalog.addWallThickness(150, 5.6);
      final updatedDim = catalog.getDimension(150)!;

      expect(updatedDim.wallThicknesses.length, initialCount + 1);
      expect(updatedDim.wallThicknesses.contains(5.6), isTrue);
    });

    test('Обновление диаметра сегмента трубы автоматически подтягивает Dн и S из каталога', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;

      final seg = PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 50,
      );
      network.segments['seg1'] = seg;
      network.recalculateSpools();

      // Исходно: Ду 50, Dн 57, стенка 3.5
      expect(network.segments['seg1']!.outerDiameterMm, 57.0);

      // Меняем Ду на 250 (промышленный диаметр)
      network.updateSegmentProperties('seg1', dn: 250);

      final updatedSeg = network.segments['seg1']!;
      expect(updatedSeg.dn, 250);
      expect(updatedSeg.outerDiameterMm, 273.0);
      expect(updatedSeg.wallThicknessMm, 7.0);
      expect(updatedSeg.formattedSize, '⌀273×7 (Ду250)');

      // Меняем толщину стенки на 10.0 мм
      network.updateSegmentProperties('seg1', wallThicknessMm: 10.0);
      expect(network.segments['seg1']!.wallThicknessMm, 10.0);
      expect(network.segments['seg1']!.formattedSize, '⌀273×10 (Ду250)');

      // Проверяем, что катушка пересчиталась с новой толщиной стенки
      final spool = network.spools.values.first;
      expect(spool.wallThickness, 10.0);
      expect(spool.dn, 250);
    });

    test('Спецификация материалов и DXF отражают реальный наружный диаметр и толщину стенки', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 150,
        outerDiameterMm: 159.0,
        wallThicknessMm: 4.5,
        material: '09Г2С',
      );

      final csv = DxfWriter.generateMtoCsv(network);
      expect(csv.contains('⌀159×4.5 (Ду150)'), isTrue);
      expect(csv.contains('ГОСТ 8732-78'), isTrue);
      expect(csv.contains('09Г2С'), isTrue);

      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network);
      expect(dxf2d.contains(DxfWriter.toAutoCadString('⌀159×4.5')), isTrue);

      final dxf3d = DxfWriter.generate3dDxf(network);
      expect(dxf3d.contains(DxfWriter.toAutoCadString('⌀159×4.5')), isTrue);
    });

    testWidgets('PipeAssortmentDialog отображает сортамент и позволяет выбрать диаметр и стенку для черчения', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final network = PipingNetwork();
      final controller = PipingInputController(
        network: network,
        projector: const AxonometryProjector(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PipeAssortmentDialog(
              network: network,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Проверяем наличие заголовка и ГОСТов
      expect(find.text('Сортамент труб и толщины стенок'), findsOneWidget);
      expect(find.text('Свой размер'), findsOneWidget);
      expect(find.text('Ду 15'), findsWidgets);

      // Фильтруем по категории «Пром. (250–1400)»
      await tester.tap(find.text('Пром. (250–1400)'));
      await tester.pumpAndSettle();

      expect(find.text('Ду 500'), findsOneWidget);
      expect(find.text('⌀ 530 мм'), findsOneWidget);
      expect(find.text('ГОСТ 10704-91'), findsWidgets);

      // Выбираем первый промышленный диаметр (Ду 250) для трассировки
      await tester.tap(find.widgetWithText(OutlinedButton, 'Выбрать').first);
      await tester.pumpAndSettle();

      expect(controller.activeDn, 250);
      expect(controller.activeWallThicknessMm, 7.0);

      controller.dispose();
    });
  });
}
