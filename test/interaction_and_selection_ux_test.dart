import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/core/math/axonometry_projector.dart';

void main() {
  group('Milestone 1: Pointer, Interaction & Selection UX Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;
    late AxonometryProjector projector;

    setUp(() {
      network = PipingNetwork();
      projector = const AxonometryProjector(scale: 0.1, panOffset: Offset(400, 300));
      controller = PipingInputController(
        network: network,
        projector: projector,
      );
      controller.setTool(CanvasTool.select);
    });

    test('1.2: Node selection does not drag immediately (Drag threshold 6px)', () {
      final n1 = Node3D(id: 'node_1', x: 0, y: 0, z: 0);
      network.nodes[n1.id] = n1;

      final p1 = projector.project(n1);

      // Клик по узлу
      controller.handlePointerDown(p1);
      expect(controller.selectedNodeId, equals('node_1'));
      expect(controller.isDraggingNode, isFalse);

      // Микродвижение (3px) не активирует перетаскивание узла
      controller.handlePointerMove(p1 + const Offset(3, 0));
      expect(controller.isDraggingNode, isFalse);
      expect(network.nodes['node_1']!.x, equals(0.0));

      // Движение более 6px активирует перетаскивание
      controller.handlePointerMove(p1 + const Offset(10, 0));
      expect(controller.isDraggingNode, isTrue);

      controller.handlePointerUp();
      expect(controller.isDraggingNode, isFalse);
    });

    test('1.3: Grip Edit: clicking selected node activates grip mode, next LMB commits', () {
      final n1 = Node3D(id: 'node_1', x: 0, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      final p1 = projector.project(n1);

      // Первый клик — просто выделяет узел
      controller.handlePointerDown(p1);
      controller.handlePointerUp();
      expect(controller.selectedNodeId, equals('node_1'));
      expect(controller.activeGripNodeId, isNull);

      // Второй клик по уже выделенному узлу — активирует Grip Mode
      controller.handlePointerDown(p1);
      expect(controller.activeGripNodeId, equals('node_1'));

      // Перемещение курсора без зажатия кнопки мыши тянет узел за курсором
      final pTarget = projector.projectCoordinates(1000, 500, 0);
      controller.handlePointerMove(pTarget);
      expect(network.nodes['node_1']!.x, equals(1000.0));
      expect(network.nodes['node_1']!.y, equals(500.0));

      // Следующий клик ЛКМ подтверждает и фиксирует положение
      controller.handlePointerDown(pTarget);
      expect(controller.activeGripNodeId, isNull);
      expect(network.nodes['node_1']!.x, equals(1000.0));
      expect(network.nodes['node_1']!.y, equals(500.0));
    });

    test('1.4: Empty canvas click deselects cleanly', () {
      final n1 = Node3D(id: 'node_1', x: 0, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      final p1 = projector.project(n1);

      controller.handlePointerDown(p1);
      controller.handlePointerUp();
      expect(controller.selectedNodeIds, contains('node_1'));

      // Клик по пустому месту (100, 100)
      controller.handlePointerDown(const Offset(100, 100));
      controller.handlePointerUp();
      expect(controller.selectedNodeIds, isEmpty);
      expect(controller.selectedNodeId, isNull);
    });

    test('1.4: Selection modifiers: Ctrl to toggle/add, Shift to subtract', () {
      final n1 = Node3D(id: 'node_1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'node_2', x: 500, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      final p1 = projector.project(n1);
      final p2 = projector.project(n2);

      // Клик по node_1
      controller.handlePointerDown(p1);
      controller.handlePointerUp();
      expect(controller.selectedNodeIds, equals({'node_1'}));

      // Клик с Ctrl по node_2 добавляет node_2 к выбранному
      controller.handlePointerDown(p2, isCtrl: true);
      controller.handlePointerUp();
      expect(controller.selectedNodeIds, equals({'node_1', 'node_2'}));

      // Клик с Shift по node_1 удаляет node_1 из выбранного
      controller.handlePointerDown(p1, isShift: true);
      controller.handlePointerUp();
      expect(controller.selectedNodeIds, equals({'node_2'}));
    });

    test('1.5: Construction axis endpoint grip handle detection and stretching', () {
      final axis = ConstructionAxis(
        id: 'axis_1',
        startPoint: Node3D(id: 'p1', x: 0, y: 0, z: 0),
        endPoint: Node3D(id: 'p2', x: 2000, y: 0, z: 0),
        label: 'A',
      );
      network.axes[axis.id] = axis;

      // Выделяем ось кликом по середине отрезка
      final midScreen = projector.projectCoordinates(1000, 0, 0);
      controller.handlePointerDown(midScreen);
      controller.handlePointerUp();
      expect(controller.selectedAxisId, equals('axis_1'));

      // Кликаем по ручке конечной точки p2 (2000, 0, 0)
      final endScreen = projector.project(axis.endPoint);
      controller.handlePointerDown(endScreen);
      expect(controller.activeGripAxisId, equals('axis_1'));
      expect(controller.isGripAxisStart, isFalse);

      // Перемещаем ручку на X=3000
      final newEndScreen = projector.projectCoordinates(3000, 0, 0);
      controller.handlePointerMove(newEndScreen);
      expect(network.axes['axis_1']!.endPoint.x, equals(3000.0));

      // Клик ЛКМ фиксирует новую длину оси
      controller.handlePointerDown(newEndScreen);
      expect(controller.activeGripAxisId, isNull);
      expect(network.axes['axis_1']!.endPoint.x, equals(3000.0));
    });
  });
}
