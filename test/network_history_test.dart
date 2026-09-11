import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/network_history_manager.dart';

void main() {
  group('NetworkHistoryManager Tests', () {
    late PipingNetwork network;
    late NetworkHistoryManager history;

    setUp(() {
      network = PipingNetwork();
      history = NetworkHistoryManager(maxSnapshots: 20);
    });

    test('Фиксация состояния, Undo и Redo восстанавливают структуру сети', () {
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);

      // Сохраняем начальное состояние
      history.recordState(network);

      // Добавляем сегмент 1
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 50,
      );
      history.recordState(network);

      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);
      expect(network.segments.length, equals(1));

      // Добавляем сегмент 2
      network.nodes['n3'] = const Node3D(id: 'n3', x: 1000, y: 1000, z: 0);
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys_b1',
        dn: 50,
      );
      history.recordState(network);

      expect(network.segments.length, equals(2));

      // Откат 1: должно остаться 1 сегмент
      final undo1 = history.undo(network);
      expect(undo1, isTrue);
      expect(network.segments.length, equals(1));
      expect(history.canRedo, isTrue);

      // Откат 2: должно стать 0 сегментов
      final undo2 = history.undo(network);
      expect(undo2, isTrue);
      expect(network.segments.isEmpty, isTrue);

      // Повтор (Redo) 1: снова 1 сегмент
      final redo1 = history.redo(network);
      expect(redo1, isTrue);
      expect(network.segments.length, equals(1));

      // Повтор (Redo) 2: снова 2 сегмента
      final redo2 = history.redo(network);
      expect(redo2, isTrue);
      expect(network.segments.length, equals(2));
      expect(history.canRedo, isFalse);
    });
  });
}
