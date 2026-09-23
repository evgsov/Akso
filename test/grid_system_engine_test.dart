import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/services/grid_system_engine.dart';

void main() {
  group('GridSystemEngine - ГОСТ Auto-Increment Labels', () {
    test('increments digits correctly', () {
      expect(GridSystemEngine.generateNextLabel('1'), '2');
      expect(GridSystemEngine.generateNextLabel('9'), '10');
      expect(GridSystemEngine.generateNextLabel('15'), '16');
    });

    test('increments Russian letters according to ГОСТ 21.101-2020 skipping prohibited letters', () {
      // А -> Б -> В -> Г -> Д -> Е -> Ж -> И (skip Ё, З)
      expect(GridSystemEngine.generateNextLabel('А'), 'Б');
      expect(GridSystemEngine.generateNextLabel('Б'), 'В');
      expect(GridSystemEngine.generateNextLabel('Е'), 'Ж');
      expect(GridSystemEngine.generateNextLabel('Ж'), 'И'); // skips З
      expect(GridSystemEngine.generateNextLabel('И'), 'К'); // skips Й
      expect(GridSystemEngine.generateNextLabel('Н'), 'П'); // skips О
      expect(GridSystemEngine.generateNextLabel('Ф'), 'Ш'); // skips Х, Ц, Ч
      expect(GridSystemEngine.generateNextLabel('Ш'), 'Э'); // skips Щ, Ъ, Ы, Ь
      expect(GridSystemEngine.generateNextLabel('Ю'), 'Я');
      expect(GridSystemEngine.generateNextLabel('Я'), 'А1');
    });

    test('increments Latin letters skipping I and O', () {
      expect(GridSystemEngine.generateNextLabel('A'), 'B');
      expect(GridSystemEngine.generateNextLabel('H'), 'J'); // skips I
      expect(GridSystemEngine.generateNextLabel('N'), 'P'); // skips O
      expect(GridSystemEngine.generateNextLabel('Z'), 'A1');
    });

    test('handles empty or default strings', () {
      expect(GridSystemEngine.generateNextLabel(''), '1');
      expect(GridSystemEngine.generateNextLabel('Grid-1'), 'Grid-2');
    });
  });

  group('GridSystemEngine - Alignment Chains', () {
    test('detects alignment chains for parallel axes with aligned endpoints', () {
      final axes = {
        'ax1': const ConstructionAxis(
          id: 'ax1',
          label: '1',
          startPoint: Node3D(id: 'n1', x: 0, y: 0, z: 0),
          endPoint: Node3D(id: 'n2', x: 0, y: 10000, z: 0),
        ),
        'ax2': const ConstructionAxis(
          id: 'ax2',
          label: '2',
          startPoint: Node3D(id: 'n3', x: 6000, y: 0, z: 0),
          endPoint: Node3D(id: 'n4', x: 6000, y: 10000, z: 0),
        ),
        'ax3': const ConstructionAxis(
          id: 'ax3',
          label: '3',
          startPoint: Node3D(id: 'n5', x: 12000, y: 1500, z: 0), // Not aligned at start
          endPoint: Node3D(id: 'n6', x: 12000, y: 10000, z: 0), // Aligned at end
        ),
      };

      final chains = GridSystemEngine.findAlignmentChains(axes);

      // Start chain should group ax1 and ax2
      final startChain = chains.firstWhere((c) => c.isStart && c.axisIds.contains('ax1'));
      expect(startChain.axisIds, containsAll(['ax1', 'ax2']));
      expect(startChain.axisIds.contains('ax3'), isFalse);

      // End chain should group ax1, ax2, and ax3
      final endChain = chains.firstWhere((c) => !c.isStart && c.axisIds.contains('ax1'));
      expect(endChain.axisIds, containsAll(['ax1', 'ax2', 'ax3']));
    });

    test('stretches chained endpoints when locked', () {
      final axes = {
        'ax1': const ConstructionAxis(
          id: 'ax1',
          label: '1',
          startPoint: Node3D(id: 'n1', x: 0, y: 0, z: 0),
          endPoint: Node3D(id: 'n2', x: 0, y: 10000, z: 0),
          isEndLocked: true,
        ),
        'ax2': const ConstructionAxis(
          id: 'ax2',
          label: '2',
          startPoint: Node3D(id: 'n3', x: 6000, y: 0, z: 0),
          endPoint: Node3D(id: 'n4', x: 6000, y: 10000, z: 0),
          isEndLocked: true,
        ),
      };

      // Drag ax1 end from Y=10000 to Y=12000 (+2000 mm)
      final updated = GridSystemEngine.stretchChainedEndpoints(
        draggedAxisId: 'ax1',
        isStart: false,
        newPoint: const Node3D(id: 'drag', x: 0, y: 12000, z: 0),
        axes: axes,
      );

      expect(updated['ax1']!.endPoint.y, 12000);
      expect(updated['ax2']!.endPoint.y, 12000); // ax2 stretched synchronously!
    });

    test('unlocked axis does not stretch with chain', () {
      final axes = {
        'ax1': const ConstructionAxis(
          id: 'ax1',
          label: '1',
          startPoint: Node3D(id: 'n1', x: 0, y: 0, z: 0),
          endPoint: Node3D(id: 'n2', x: 0, y: 10000, z: 0),
          isEndLocked: true,
        ),
        'ax2': const ConstructionAxis(
          id: 'ax2',
          label: '2',
          startPoint: Node3D(id: 'n3', x: 6000, y: 0, z: 0),
          endPoint: Node3D(id: 'n4', x: 6000, y: 10000, z: 0),
          isEndLocked: false, // UNLOCKED
        ),
      };

      final updated = GridSystemEngine.stretchChainedEndpoints(
        draggedAxisId: 'ax1',
        isStart: false,
        newPoint: const Node3D(id: 'drag', x: 0, y: 12000, z: 0),
        axes: axes,
      );

      expect(updated['ax1']!.endPoint.y, 12000);
      expect(updated['ax2']!.endPoint.y, 10000); // ax2 stayed at 10000
    });
  });

  group('GridSystemEngine - Temporary Dimensions & Moving by Distance', () {
    test('calculates temporary dimensions to adjacent parallel axes', () {
      final axes = {
        'ax1': const ConstructionAxis(
          id: 'ax1',
          label: '1',
          startPoint: Node3D(id: 'n1', x: 0, y: 0, z: 0),
          endPoint: Node3D(id: 'n2', x: 0, y: 10000, z: 0),
        ),
        'ax2': const ConstructionAxis(
          id: 'ax2',
          label: '2',
          startPoint: Node3D(id: 'n3', x: 6000, y: 0, z: 0),
          endPoint: Node3D(id: 'n4', x: 6000, y: 10000, z: 0),
        ),
        'ax3': const ConstructionAxis(
          id: 'ax3',
          label: '3',
          startPoint: Node3D(id: 'n5', x: 15000, y: 0, z: 0),
          endPoint: Node3D(id: 'n6', x: 15000, y: 10000, z: 0),
        ),
      };

      // Select ax2: predecessor is ax1 (distance 6000), successor is ax3 (distance 9000)
      final dims = GridSystemEngine.calculateTemporaryDimensions('ax2', axes);
      expect(dims.length, 2);

      final toAx1 = dims.firstWhere((d) => d.referenceAxisId == 'ax1');
      expect(toAx1.distanceMm, 6000);

      final toAx3 = dims.firstWhere((d) => d.referenceAxisId == 'ax3');
      expect(toAx3.distanceMm, 9000);
    });

    test('moves axis to exact distance from reference axis', () {
      final ax1 = const ConstructionAxis(
        id: 'ax1',
        label: '1',
        startPoint: Node3D(id: 'n1', x: 0, y: 0, z: 0),
        endPoint: Node3D(id: 'n2', x: 0, y: 10000, z: 0),
      );
      final ax2 = const ConstructionAxis(
        id: 'ax2',
        label: '2',
        startPoint: Node3D(id: 'n3', x: 6000, y: 0, z: 0),
        endPoint: Node3D(id: 'n4', x: 6000, y: 10000, z: 0),
      );

      // Move ax2 to be 7500 mm from ax1
      final moved = GridSystemEngine.moveAxisByDistance(
        axisToMove: ax2,
        referenceAxis: ax1,
        targetDistanceMm: 7500,
      );

      expect(moved.startPoint.x, 7500);
      expect(moved.endPoint.x, 7500);
      expect(moved.startPoint.y, 0);
      expect(moved.endPoint.y, 10000);
    });

    test('creates offset axis with incremented label', () {
      final ax1 = const ConstructionAxis(
        id: 'ax1',
        label: '1',
        startPoint: Node3D(id: 'n1', x: 0, y: 0, z: 0),
        endPoint: Node3D(id: 'n2', x: 0, y: 10000, z: 0),
      );

      final offsetAxis = GridSystemEngine.createOffsetAxis(
        sourceAxis: ax1,
        offsetDistanceMm: 6000,
        positiveSide: true,
      );

      expect(offsetAxis.label, '2');
      expect(offsetAxis.startPoint.x, 6000);
      expect(offsetAxis.endPoint.x, 6000);
      expect(offsetAxis.startPoint.y, 0);
      expect(offsetAxis.endPoint.y, 10000);
    });
  });
}
