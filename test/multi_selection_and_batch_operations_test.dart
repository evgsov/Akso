import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/desktop_cad_layout.dart';

void main() {
  group('CAD Milestone 2: Multi-selection & Batch Operations Tests', () {
    late PipingNetwork network;
    late AxonometryProjector projector;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      projector = AxonometryProjector();
      controller = PipingInputController(network: network, projector: projector);
    });

    tearDown(() {
      controller.dispose();
    });

    test('1. Рамочный выбор (слева направо) синхронизирует selectedSegmentIds и selectedSpoolIds', () {
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = const Node3D(id: 'n3', x: 5000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      final s1 = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      final s2 = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_1', dn: 50);
      network.addSegment(s1);
      network.addSegment(s2);
      network.recalculateSpools();

      final p1 = projector.project(n1);
      final p2 = projector.project(n2);

      // Рамка слева направо вокруг s1 (охватывает n1 и n2, но не n3)
      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(Offset(p1.dx - 20, p1.dy - 20));
      controller.handlePointerMove(Offset(p2.dx + 20, p2.dy + 20));
      controller.handlePointerUp();

      expect(controller.selectedSegmentIds.contains('s1'), isTrue);
      expect(controller.selectedSegmentIds.contains('s2'), isFalse);
      expect(controller.selectedSegmentId, equals('s1'));

      // Катушка s1 также должна быть автоматически выбрана в selectedSpoolIds
      final spool1 = network.spools.values.firstWhere((sp) => sp.segmentId == 's1');
      expect(controller.selectedSpoolIds.contains(spool1.id), isTrue);
      expect(controller.selectedSpoolId, equals(spool1.id));
    });

    test('2. Секущая рамка (справа налево) выделяет пересекаемые трубы и узлы с катушками', () {
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;

      final s1 = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      network.addSegment(s1);
      network.recalculateSpools();

      final p1 = projector.project(n1);
      final p2 = projector.project(n2);
      final mid = (p1 + p2) / 2;

      // Рамка справа налево через середину трубы
      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(Offset(mid.dx + 25, mid.dy + 25));
      controller.handlePointerMove(Offset(mid.dx - 25, mid.dy - 25));
      controller.handlePointerUp();

      expect(controller.selectedSegmentIds.contains('s1'), isTrue);
      final spool1 = network.spools.values.firstWhere((sp) => sp.segmentId == 's1');
      expect(controller.selectedSpoolIds.contains(spool1.id), isTrue);
    });

    test('3. Ctrl+click синхронно добавляет и удаляет сегменты и катушки', () {
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      final s1 = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      final s2 = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_1', dn: 50);
      network.addSegment(s1);
      network.addSegment(s2);
      network.recalculateSpools();

      final pMid1 = (projector.project(n1) + projector.project(n2)) / 2;
      final pMid2 = (projector.project(n2) + projector.project(n3)) / 2;

      controller.setTool(CanvasTool.select);

      // Клик по первой трубе
      controller.handlePointerDown(pMid1);
      controller.handlePointerUp();
      expect(controller.selectedSegmentIds, equals({'s1'}));

      // Ctrl+клик по второй трубе -> добавляет в выделение
      controller.handlePointerDown(pMid2, isCtrl: true);
      controller.handlePointerUp();
      expect(controller.selectedSegmentIds, equals({'s1', 's2'}));

      final spool1 = network.spools.values.firstWhere((sp) => sp.segmentId == 's1');
      final spool2 = network.spools.values.firstWhere((sp) => sp.segmentId == 's2');
      expect(controller.selectedSpoolIds.contains(spool1.id), isTrue);
      expect(controller.selectedSpoolIds.contains(spool2.id), isTrue);

      // Ctrl+клик по первой трубе -> снимает выделение с s1, остается s2
      controller.handlePointerDown(pMid1, isCtrl: true);
      controller.handlePointerUp();
      expect(controller.selectedSegmentIds, equals({'s2'}));
      expect(controller.selectedSegmentId, equals('s2'));
      expect(controller.selectedSpoolIds.contains(spool1.id), isFalse);
      expect(controller.selectedSpoolIds.contains(spool2.id), isTrue);
    });

    test('4. Пакетная смена диаметра DN обновляет все трубы, Dн, стенку S и пересчитывает катушки в 1 Undo шаг', () {
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      final s1 = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      final s2 = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_1', dn: 50);
      network.addSegment(s1);
      network.addSegment(s2);
      network.recalculateSpools();
      controller.history.recordState(network);

      controller.selectedSegmentIds.addAll(['s1', 's2']);
      controller.selectedSegmentId = 's1';

      // Пакетно меняем на DN 100
      controller.changeSelectedSegmentDn(100);

      expect(network.segments['s1']!.dn, equals(100));
      expect(network.segments['s2']!.dn, equals(100));
      expect(network.segments['s1']!.outerDiameterMm, equals(108.0));
      expect(network.segments['s2']!.outerDiameterMm, equals(108.0));

      final spool1 = network.spools.values.firstWhere((sp) => sp.segmentId == 's1');
      final spool2 = network.spools.values.firstWhere((sp) => sp.segmentId == 's2');
      expect(spool1.dn, equals(100));
      expect(spool2.dn, equals(100));

      // Проверяем откат в 1 шаг Undo
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(network.segments['s1']!.dn, equals(50));
      expect(network.segments['s2']!.dn, equals(50));
    });

    test('5. Пакетная смена марки стали обновляет сегменты и привязанные сварные стыки в 1 Undo шаг', () {
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      final s1 = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50, material: 'Сталь 20');
      final s2 = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_1', dn: 50, material: 'Сталь 20');
      network.addSegment(s1);
      network.addSegment(s2);

      final w1 = const WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.5, number: 1, stamp: 'A1', steelGrade: 'Сталь 20');
      final w2 = const WeldJoint(id: 'w2', segmentId: 's2', ratio: 0.5, number: 2, stamp: 'A2', steelGrade: 'Сталь 20');
      network.weldJoints['w1'] = w1;
      network.weldJoints['w2'] = w2;
      network.recalculateSpools();
      controller.history.recordState(network);

      controller.selectedSegmentIds.addAll(['s1', 's2']);
      controller.changeSelectedSegmentMaterial('12Х18Н10Т');

      expect(network.segments['s1']!.material, equals('12Х18Н10Т'));
      expect(network.segments['s2']!.material, equals('12Х18Н10Т'));
      expect(network.weldJoints['w1']!.steelGrade, equals('12Х18Н10Т'));
      expect(network.weldJoints['w2']!.steelGrade, equals('12Х18Н10Т'));

      // Undo
      controller.undo();
      expect(network.segments['s1']!.material, equals('Сталь 20'));
      expect(network.weldJoints['w1']!.steelGrade, equals('Сталь 20'));
    });

    test('6. Пакетное назначение уклона i выставляет уклон на выбранных трубах', () {
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      final n3 = const Node3D(id: 'n3', x: 4000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      final s1 = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50, slope: 0.0);
      final s2 = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_1', dn: 50, slope: 0.0);
      network.addSegment(s1);
      network.addSegment(s2);
      network.recalculateSpools();
      controller.history.recordState(network);

      controller.selectedSegmentIds.addAll(['s1', 's2']);
      controller.changeSelectedSegmentsSlope(0.003);

      expect(network.segments['s1']!.slope, closeTo(0.003, 0.0001));
      expect(network.segments['s2']!.slope, closeTo(0.003, 0.0001));

      // Undo
      controller.undo();
      expect(network.segments['s1']!.slope, closeTo(0.0, 0.0001));
    });

    test('7. Пакетный сдвиг высотной отметки (shiftSelectedSegmentsElevation) сдвигает узлы группы', () {
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      final s1 = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      final s2 = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_1', dn: 50);
      network.addSegment(s1);
      network.addSegment(s2);
      network.recalculateSpools();
      controller.history.recordState(network);

      controller.selectedSegmentIds.addAll(['s1', 's2']);
      controller.shiftSelectedSegmentsElevation(0.500); // +0.5 м = +500 мм

      expect(network.nodes['n1']!.z, closeTo(500.0, 0.1));
      expect(network.nodes['n2']!.z, closeTo(500.0, 0.1));
      expect(network.nodes['n3']!.z, closeTo(500.0, 0.1));

      // Undo
      controller.undo();
      expect(network.nodes['n1']!.z, closeTo(0.0, 0.1));
      expect(network.nodes['n2']!.z, closeTo(0.0, 0.1));
      expect(network.nodes['n3']!.z, closeTo(0.0, 0.1));
    });

    test('8. Групповое удаление очищает сеть и восстанавливается через Undo в 1 шаг', () {
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      final s1 = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      final s2 = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_1', dn: 50);
      network.addSegment(s1);
      network.addSegment(s2);
      network.recalculateSpools();
      controller.history.recordState(network);

      controller.selectedSegmentIds.addAll(['s1', 's2']);
      controller.selectedNodeIds.addAll(['n1', 'n2', 'n3']);

      controller.deleteSelected();

      expect(network.segments.isEmpty, isTrue);
      expect(network.nodes.isEmpty, isTrue);
      expect(controller.selectedSegmentIds.isEmpty, isTrue);
      expect(controller.selectedSpoolIds.isEmpty, isTrue);

      // Undo
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(network.segments.length, equals(2));
      expect(network.nodes.length, equals(3));
    });

    testWidgets('9. Виджет инспектора группы рендерится в DesktopCadLayout без RenderFlex overflow на 800x600', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 1500, y: 0, z: 0);
      final n3 = const Node3D(id: 'n3', x: 3000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      final s1 = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);
      final s2 = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_1', dn: 50);
      network.addSegment(s1);
      network.addSegment(s2);
      network.recalculateSpools();

      controller.enableDragDelay = false;
      controller.selectedSegmentIds.addAll(['s1', 's2']);
      controller.selectedSegmentId = 's1';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopCadLayout(
              controller: controller,
              canvasWidget: const SizedBox(width: 800, height: 600),
            ),
          ),
        ),
      );
      await tester.pump();

      // Находим карточку инспектора группы
      final cardFinder = find.ancestor(
        of: find.textContaining('Выделено'),
        matching: find.byType(Card),
      );
      expect(cardFinder, findsOneWidget);

      // Проверяем наличие заголовка группы в карточке инспектора
      expect(find.descendant(of: cardFinder, matching: find.textContaining('Выделено')), findsOneWidget);
      // Проверяем наличие сводки по трубам
      expect(find.descendant(of: cardFinder, matching: find.textContaining('Выбрано: 2 труб')), findsOneWidget);
      // Проверяем элементы управления внутри карточки
      expect(find.descendant(of: cardFinder, matching: find.text('Ду:')), findsOneWidget);
      expect(find.descendant(of: cardFinder, matching: find.text('Сталь:')), findsOneWidget);
      expect(find.descendant(of: cardFinder, matching: find.text('Система:')), findsOneWidget);
      expect(find.descendant(of: cardFinder, matching: find.text('Уклон i:')), findsOneWidget);
      expect(find.descendant(of: cardFinder, matching: find.text('Сдвиг Z:')), findsOneWidget);
      expect(find.descendant(of: cardFinder, matching: find.text('Сдвинуть')), findsOneWidget);
      expect(find.descendant(of: cardFinder, matching: find.text('Удалить группу (Del)')), findsOneWidget);

      // Проверяем, что нет RenderFlex overflow ошибок
      expect(tester.takeException(), isNull);
    });
  });
}
