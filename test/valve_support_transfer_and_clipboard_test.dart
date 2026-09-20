import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/desktop_cad_layout.dart';

void main() {
  group('Milestone 4: Valve and Support Transfer, Full-range & Clipboard Tests', () {
    late PipingNetwork network;
    late AxonometryProjector projector;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      projector = AxonometryProjector();
      controller = PipingInputController(network: network, projector: projector);

      // Создаем две параллельные трубы: seg1 (DN 100) и seg2 (DN 50)
      // seg1: (0, 0, 0) -> (1000, 0, 0)
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      final seg1 = PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'T1');
      network.segments['seg1'] = seg1;

      // seg2: (0, 500, 0) -> (1000, 500, 0)
      final n3 = Node3D(id: 'n3', x: 0, y: 500, z: 0);
      final n4 = Node3D(id: 'n4', x: 1000, y: 500, z: 0);
      network.nodes['n3'] = n3;
      network.nodes['n4'] = n4;
      final seg2 = PipeSegment(id: 'seg2', startNodeId: 'n3', endNodeId: 'n4', dn: 50, systemId: 'T1');
      network.segments['seg2'] = seg2;

      network.recalculateSpools();
      controller.history.recordState(network);
    });

    test('1. Full range valve positioning: reaches 0.0 and 1.0 without 0.05 clamp', () {
      final v = network.addValve(segmentId: 'seg1', ratio: 0.5, valveType: ValveType.ballValve);
      expect(v.ratio, equals(0.5));

      // Сдвиг в крайнее начало (0.0)
      network.slideValve(v.id, 0.0);
      expect(network.valves[v.id]!.ratio, equals(0.0));

      // Сдвиг в крайний конец (1.0)
      network.slideValve(v.id, 1.0);
      expect(network.valves[v.id]!.ratio, equals(1.0));

      // Попытка за пределами [0.0, 1.0] аккуратно зажимается в [0.0, 1.0]
      network.slideValve(v.id, -0.2);
      expect(network.valves[v.id]!.ratio, equals(0.0));

      network.slideValve(v.id, 1.5);
      expect(network.valves[v.id]!.ratio, equals(1.0));
    });

    test('2. Full range support positioning: reaches 0.0 and 1.0', () {
      final s = network.addSupport(segmentId: 'seg1', distanceRatio: 0.5, type: PipeSupportType.sliding);
      expect(s.distanceRatio, equals(0.5));

      network.transferSupportToSegment(s.id, 'seg1', 0.0);
      expect(network.supports[s.id]!.distanceRatio, equals(0.0));

      network.transferSupportToSegment(s.id, 'seg1', 1.0);
      expect(network.supports[s.id]!.distanceRatio, equals(1.0));
    });

    test('3. Drag-and-drop cross-pipe transfer for valve with DN adaptation', () {
      final v = network.addValve(segmentId: 'seg1', ratio: 0.5, valveType: ValveType.gateValve);
      expect(v.segmentId, equals('seg1'));
      expect(v.dn, equals(100));

      controller.selectedValveId = v.id;
      controller.isDraggingValve = true;

      // Симулируем курсор около seg2: координаты точки (500, 500, 0)
      final ptOnSeg2 = projector.project(Node3D(id: 'tmp', x: 500, y: 500, z: 0));
      controller.handlePointerMove(ptOnSeg2);

      // Кран должен перепрыгнуть на seg2 и адаптировать диаметр под DN 50
      final draggedValve = network.valves[v.id]!;
      expect(draggedValve.segmentId, equals('seg2'));
      expect(draggedValve.dn, equals(50));
      expect(draggedValve.ratio, closeTo(0.5, 0.05));

      // Отпускание мыши фиксирует состояние
      controller.handlePointerUp();
      expect(controller.isDraggingValve, isFalse);
      expect(network.valves[v.id]!.segmentId, equals('seg2'));
    });

    test('4. Drag-and-drop cross-pipe transfer for support', () {
      final s = network.addSupport(segmentId: 'seg1', distanceRatio: 0.3, type: PipeSupportType.fixed);
      expect(s.segmentId, equals('seg1'));

      controller.selectedSupportId = s.id;
      controller.isDraggingSupport = true;

      // Симулируем курсор около seg2: координаты (800, 500, 0)
      final ptOnSeg2 = projector.project(Node3D(id: 'tmp', x: 800, y: 500, z: 0));
      controller.handlePointerMove(ptOnSeg2);

      final draggedSupport = network.supports[s.id]!;
      expect(draggedSupport.segmentId, equals('seg2'));
      expect(draggedSupport.distanceRatio, closeTo(0.8, 0.05));

      controller.handlePointerUp();
      expect(controller.isDraggingSupport, isFalse);
      expect(network.supports[s.id]!.segmentId, equals('seg2'));
    });

    test('5. Single valve duplicate via duplicateSelection (Ctrl+D)', () {
      final v = network.addValve(segmentId: 'seg1', ratio: 0.4, valveType: ValveType.checkValve, name: 'КО-1');
      controller.selectedValveId = v.id;

      final result = controller.duplicateSelection();
      expect(result, isTrue);

      // Должен появиться второй кран на seg1 со смещением
      expect(network.valves.length, equals(2));
      final duplicate = network.valves[controller.selectedValveId!];
      expect(duplicate, isNotNull);
      expect(duplicate!.id, isNot(equals(v.id)));
      expect(duplicate.segmentId, equals('seg1'));
      expect(duplicate.ratio, closeTo(0.5, 0.02));
      expect(duplicate.name, equals('КО-1'));
    });

    test('6. Single support duplicate via duplicateSelection (Ctrl+D)', () {
      final s = network.addSupport(segmentId: 'seg1', distanceRatio: 0.2, type: PipeSupportType.spring, name: 'ОП-1');
      controller.selectedSupportId = s.id;

      final result = controller.duplicateSelection();
      expect(result, isTrue);

      expect(network.supports.length, equals(2));
      final duplicate = network.supports[controller.selectedSupportId!];
      expect(duplicate, isNotNull);
      expect(duplicate!.id, isNot(equals(s.id)));
      expect(duplicate.segmentId, equals('seg1'));
      expect(duplicate.distanceRatio, closeTo(0.3, 0.02));
      expect(duplicate.type, equals(PipeSupportType.spring));
    });

    test('7. Valve copySelection (Ctrl+C) and pasteSelection (Ctrl+V) onto another pipe', () {
      final v = network.addValve(segmentId: 'seg1', ratio: 0.3, valveType: ValveType.butterflyValve, name: 'Затвор ДУ100');
      controller.selectedValveId = v.id;

      expect(controller.canCopy, isTrue);
      expect(controller.canPaste, isFalse);

      final copySuccess = controller.copySelection();
      expect(copySuccess, isTrue);
      expect(controller.canPaste, isTrue);
      expect(controller.clipboardValve?.name, equals('Затвор ДУ100'));

      // Выбираем вторую трубу seg2 и вставляем
      controller.clearSelection();
      controller.selectedSegmentId = 'seg2';
      controller.selectedSegmentIds.add('seg2');

      final pasteSuccess = controller.pasteSelection(ratio: 0.7);
      expect(pasteSuccess, isTrue);
      expect(network.valves.length, equals(2));

      final pastedValve = network.valves[controller.selectedValveId!];
      expect(pastedValve, isNotNull);
      expect(pastedValve!.segmentId, equals('seg2'));
      expect(pastedValve.ratio, equals(0.7));
      expect(pastedValve.dn, equals(50)); // Адаптирован под DN второй трубы
      expect(pastedValve.name, equals('Затвор ДУ100'));
    });

    test('8. Support copySelection (Ctrl+C) and pasteSelection (Ctrl+V) onto another pipe', () {
      final s = network.addSupport(segmentId: 'seg1', distanceRatio: 0.4, type: PipeSupportType.guide, name: 'ОН-1');
      controller.selectedSupportId = s.id;

      final copySuccess = controller.copySelection();
      expect(copySuccess, isTrue);
      expect(controller.clipboardSupport?.type, equals(PipeSupportType.guide));

      controller.clearSelection();
      controller.selectedSegmentId = 'seg2';
      controller.selectedSegmentIds.add('seg2');

      final pasteSuccess = controller.pasteSelection(ratio: 0.85);
      expect(pasteSuccess, isTrue);
      expect(network.supports.length, equals(2));

      final pastedSupport = network.supports[controller.selectedSupportId!];
      expect(pastedSupport, isNotNull);
      expect(pastedSupport!.segmentId, equals('seg2'));
      expect(pastedSupport.distanceRatio, equals(0.85));
      expect(pastedSupport.type, equals(PipeSupportType.guide));
    });

    test('9. Undo/Redo integrity after transfer and duplication', () {
      // 1. Добавляем кран
      final v = network.addValve(segmentId: 'seg1', ratio: 0.5, valveType: ValveType.ballValve);
      controller.history.recordState(network);

      // 2. Дублируем кран
      controller.selectedValveId = v.id;
      controller.duplicateSelection();
      expect(network.valves.length, equals(2));

      // 3. Откатываем назад (Undo)
      controller.undo();
      expect(network.valves.length, equals(1));
      expect(network.valves.containsKey(v.id), isTrue);

      // 4. Повторяем (Redo)
      controller.redo();
      expect(network.valves.length, equals(2));
    });

    testWidgets('10. DesktopCadLayout renders Copy and Duplicate buttons for valve and support', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final v = network.addValve(segmentId: 'seg1', ratio: 0.5, valveType: ValveType.gateValve);
      controller.selectedValveId = v.id;

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
      await tester.pumpAndSettle();

      // Проверяем кнопки в инспекторе арматуры
      expect(find.text('Копировать (Ctrl+C)'), findsOneWidget);
      expect(find.text('Дублировать (Ctrl+D)'), findsOneWidget);

      // Нажимаем «Копировать (Ctrl+C)»
      await tester.tap(find.text('Копировать (Ctrl+C)'));
      await tester.pumpAndSettle();
      expect(controller.clipboardValve?.id, equals(v.id));

      // Переключаемся на опору
      final s = network.addSupport(segmentId: 'seg1', distanceRatio: 0.5, type: PipeSupportType.sliding);
      controller.clearSelection();
      controller.selectedSupportId = s.id;
      controller.refresh();

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
      await tester.pumpAndSettle();

      // Проверяем кнопки в инспекторе опоры
      expect(find.text('Копировать (Ctrl+C)'), findsOneWidget);
      expect(find.text('Дублировать (Ctrl+D)'), findsOneWidget);

      // Нажимаем «Дублировать (Ctrl+D)»
      await tester.tap(find.text('Дублировать (Ctrl+D)'));
      await tester.pumpAndSettle();
      expect(network.supports.length, equals(2));
    });
  });
}
