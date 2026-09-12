import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Viewport Navigation & Controller Tests', () {
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

    test('Отмена операции через cancelCurrentOperation очищает начальный узел трассировки', () {
      controller.setTool(CanvasTool.trace);
      controller.traceStartNode = const Node3D(id: 'n_start', x: 0, y: 0, z: 0);
      controller.currentCursorScreenPos = const Offset(100, 100);

      expect(controller.traceStartNode, isNotNull);

      controller.cancelCurrentOperation();

      expect(controller.traceStartNode, isNull);
      expect(controller.currentCursorScreenPos, isNull);
    });

    test('Панорамирование через контроллер смещает panOffset проектора', () {
      final initialPan = controller.projector.panOffset;
      controller.pan(const Offset(50, -30));

      expect(controller.projector.panOffset, equals(initialPan + const Offset(50, -30)));
    });

    test('Undo и Redo в контроллере отменяют и восстанавливают добавленные элементы', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 50);

      controller.recordSnapshot();
      expect(controller.canUndo, isTrue);

      // Врезка задвижки
      network.addValve(segmentId: 'seg1', ratio: 0.5, valveType: ValveType.gateValve, dn: 50);
      controller.recordSnapshot();
      expect(network.valves.length, equals(1));

      // Откат (Undo)
      controller.undo();
      expect(network.valves.isEmpty, isTrue);
      expect(controller.canRedo, isTrue);

      // Повтор (Redo)
      controller.redo();
      expect(network.valves.length, equals(1));
    });

    test('Смена системы в контроллере обновляет активную сталь и диаметр из свойств системы', () {
      controller.setActiveSystem('sys_o1'); // Отопление, сталь 09Г2С, Ду32
      expect(controller.activeSystemId, equals('sys_o1'));
      expect(controller.activeMaterial, equals('09Г2С'));
      expect(controller.activeDn, equals(32));
    });

    test('Вращение через orbit переключает проекцию в orbit3d и изменяет углы', () {
      final initialAzimuth = controller.projector.orbitAzimuth;
      controller.orbit(const Offset(20, 10));

      expect(controller.projector.projectionType, equals(ProjectionType.orbit3d));
      expect(controller.projector.orbitAzimuth, greaterThan(initialAzimuth));
    });

    test('Жест Drag-to-Draw завершает трассировку сегмента при отпускании стилуса', () {
      controller.setTool(CanvasTool.trace);
      expect(network.segments.isEmpty, isTrue);

      // Касание (Start point)
      controller.handlePointerDown(const Offset(100, 100));
      expect(controller.traceStartNode, isNotNull);

      // Протягивание стилусом
      controller.handlePointerMove(const Offset(300, 100));

      // Отпускание (Pointer Up)
      controller.handlePointerUp();

      // Сегмент должен быть успешно создан и добавлен в сеть!
      expect(network.segments.length, equals(1));
    });

    test('Выбор сегмента, редактирование длины, диаметра и марки стали', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 25);
      controller.recordSnapshot();

      // Исходный сегмент seg1
      controller.selectedSegmentId = 'seg1';
      expect(controller.selectedSegmentLength, closeTo(1000.0, 0.1));

      // 1. Изменение длины с 1000 до 1500 мм
      controller.changeSelectedSegmentLength(1500.0);
      expect(controller.selectedSegmentLength, closeTo(1500.0, 0.1));

      // 2. Изменение диаметра DN с 25 на 50
      expect(network.segments['seg1']!.dn, equals(25));
      controller.changeSelectedSegmentDn(50);
      expect(network.segments['seg1']!.dn, equals(50));

      // 3. Изменение марки стали
      controller.changeSelectedSegmentMaterial('12Х18Н10Т');
      expect(network.segments['seg1']!.material, equals('12Х18Н10Т'));

      // Undo восстанавливает прежние свойства
      controller.undo();
      expect(network.segments['seg1']!.material, equals('Сталь 20'));
    });

    test('Удаление выбранного сегмента очищает привязанную арматуру и стыки', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 25);
      controller.recordSnapshot();

      // Врезаем задвижку в seg1
      network.addValve(segmentId: 'seg1', ratio: 0.5, valveType: ValveType.gateValve, dn: 25);
      controller.recordSnapshot();
      expect(network.valves.length, equals(1));
      expect(network.segments.containsKey('seg1'), isTrue);

      // Выбираем seg1 и удаляем
      controller.selectedSegmentId = 'seg1';
      controller.deleteSelected();

      expect(network.segments.containsKey('seg1'), isFalse);
      expect(network.valves.isEmpty, isTrue);
      expect(controller.selectedSegmentId, isNull);

      // Откат через Undo восстанавливает сегмент и задвижку
      controller.undo();
      expect(network.segments.containsKey('seg1'), isTrue);
      expect(network.valves.length, equals(1));
    });

    test('Масштабирование zoom сохраняет неподвижной точку focalPoint под курсором', () {
      // Исходная точка в мировых координатах
      const worldTarget = Node3D(id: 'target', x: 2500, y: 1500, z: 500);
      final screenPosBefore = controller.projector.project(worldTarget);

      // Масштабируем относительно экранного положения целевой точки с увеличением 1.75x
      controller.zoom(1.75, screenPosBefore);

      final screenPosAfter = controller.projector.project(worldTarget);

      // Точка под курсором осталась ровно в тех же пикселях экрана!
      expect(screenPosAfter.dx, closeTo(screenPosBefore.dx, 1e-4));
      expect(screenPosAfter.dy, closeTo(screenPosBefore.dy, 1e-4));

      // Масштабируем с уменьшением 0.4x
      controller.zoom(0.4, screenPosBefore);
      final screenPosAfterZoomOut = controller.projector.project(worldTarget);
      expect(screenPosAfterZoomOut.dx, closeTo(screenPosBefore.dx, 1e-4));
      expect(screenPosAfterZoomOut.dy, closeTo(screenPosBefore.dy, 1e-4));
    });

    test('zoomToFit вписывает и центрирует геометрию сети в заданный размер экрана', () {
      // Создаем разнесенную сеть труб (например, 10 метров в длину)
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 10000, y: 5000, z: 1000);
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 100);

      const viewport = Size(1920, 1080);
      controller.zoomToFit(viewportSize: viewport);

      final p1 = controller.projector.project(network.nodes['n1']!);
      final p2 = controller.projector.project(network.nodes['n2']!);

      // Обе точки должны находиться внутри viewport с безопасным отступом
      expect(p1.dx, greaterThan(0.0));
      expect(p1.dx, lessThan(viewport.width));
      expect(p1.dy, greaterThan(0.0));
      expect(p1.dy, lessThan(viewport.height));

      expect(p2.dx, greaterThan(0.0));
      expect(p2.dx, lessThan(viewport.width));
      expect(p2.dy, greaterThan(0.0));
      expect(p2.dy, lessThan(viewport.height));

      // Центр между двумя точками должен быть приблизительно в центре экрана (960, 540)
      final midX = (p1.dx + p2.dx) / 2;
      final midY = (p1.dy + p2.dy) / 2;
      expect(midX, closeTo(viewport.width / 2, 50.0));
      expect(midY, closeTo(viewport.height / 2, 50.0));
    });

    test('zoomIn, zoomOut и zoom100 изменяют масштаб с корректным процентом', () {
      controller.zoom100();
      expect(controller.projector.scale, equals(0.25));
      expect(controller.zoomPercentage, equals(100));

      controller.zoomIn();
      expect(controller.projector.scale, closeTo(0.25 * 1.25, 1e-4));
      expect(controller.zoomPercentage, equals(125));

      controller.zoomOut();
      expect(controller.projector.scale, closeTo(0.25, 1e-4));
      expect(controller.zoomPercentage, equals(100));
    });
  });
}
