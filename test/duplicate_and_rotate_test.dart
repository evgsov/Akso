import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Duplicate and Rotate Selection Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      controller = PipingInputController(network: network);
    });

    test('Дублирование выделенных узлов и сегментов со смещением (duplicateSelection)', () {
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 100);

      controller.selectedNodeIds.addAll(['n1', 'n2']);
      controller.selectedSegmentIds.add('seg1');

      expect(network.nodes.length, equals(2));
      expect(network.segments.length, equals(1));

      // Дублируем со смещением (dx: 500, dy: 1000, dz: 0)
      controller.duplicateSelection(dx: 500, dy: 1000, dz: 0);

      // В сети теперь 4 узла и 2 сегмента
      expect(network.nodes.length, equals(4));
      expect(network.segments.length, equals(2));

      // Выделение переключилось на новые элементы
      expect(controller.selectedNodeIds.length, equals(2));
      expect(controller.selectedSegmentIds.length, equals(1));
      expect(controller.selectedNodeIds.contains('n1'), isFalse);
      expect(controller.selectedNodeIds.contains('n2'), isFalse);

      // Проверяем координаты новых узлов
      final newNodes = controller.selectedNodeIds.map((id) => network.nodes[id]!).toList();
      final newN1 = newNodes.firstWhere((n) => n.x == 500);
      final newN2 = newNodes.firstWhere((n) => n.x == 2500);

      expect(newN1.y, equals(1000));
      expect(newN2.y, equals(1000));

      // Проверяем новый сегмент между новыми узлами
      final newSegId = controller.selectedSegmentIds.first;
      final newSeg = network.segments[newSegId]!;
      expect(
        (newSeg.startNodeId == newN1.id && newSeg.endNodeId == newN2.id) ||
            (newSeg.startNodeId == newN2.id && newSeg.endNodeId == newN1.id),
        isTrue,
      );
      expect(newSeg.dn, equals(100));
    });

    test('Поворот выделения вокруг оси Z на 90 градусов (rotateSelectionAroundZ)', () {
      // Создаем отрезок вдоль оси X: от (0, 0, 0) до (2000, 0, 0)
      // Центр: (1000, 0, 0)
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 100);

      controller.selectedNodeIds.addAll(['n1', 'n2']);
      controller.selectedSegmentIds.add('seg1');

      // Поворачиваем на +90° вокруг центра
      controller.rotateSelectionAroundZ(90);

      final rotN1 = network.nodes['n1']!;
      final rotN2 = network.nodes['n2']!;

      // Исходный вектор (2000, 0) поворачивается на 90° и становится вертикальным (0, 2000)
      // Центр остался (1000, 0)
      expect(rotN1.x, closeTo(1000.0, 0.01));
      expect(rotN2.x, closeTo(1000.0, 0.01));
      expect((rotN1.y - rotN2.y).abs(), closeTo(2000.0, 0.01));

      // Длина сегмента инвариантна
      final len = network.segments['seg1']!.calculateLength(rotN1, rotN2);
      expect(len, closeTo(2000.0, 0.01));
    });

    test('Групповое удаление выделения (deleteSelected)', () {
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      const n3 = Node3D(id: 'n3', x: 1000, y: 1000, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 100);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_1', dn: 100);

      controller.selectedNodeIds.addAll(['n1', 'n2']);
      controller.selectedSegmentIds.add('s1');

      controller.deleteSelected();

      // n1 и n2 удалены, сегмент s1 удален, сегмент s2 тоже удален (так как n2 удален)
      expect(network.nodes.containsKey('n1'), isFalse);
      expect(network.nodes.containsKey('n2'), isFalse);
      expect(network.nodes.containsKey('n3'), isTrue);
      expect(network.segments.containsKey('s1'), isFalse);
      expect(network.segments.containsKey('s2'), isFalse);

      expect(controller.selectedNodeIds, isEmpty);
      expect(controller.selectedSegmentIds, isEmpty);
    });

    test('Отмена и повтор операции дублирования (Undo/Redo)', () {
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 100);
      controller.history.recordState(network);

      controller.selectedNodeIds.addAll(['n1', 'n2']);
      controller.selectedSegmentIds.add('seg1');

      controller.duplicateSelection(dx: 500, dy: 0, dz: 0);
      expect(network.nodes.length, equals(4));

      // Отмена
      controller.undo();
      expect(network.nodes.length, equals(2));

      // Повтор
      controller.redo();
      expect(network.nodes.length, equals(4));
    });
  });
}
