import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/domain/models/node_3d.dart';

void main() {
  group('ConstructionAxis Revit properties & serialization', () {
    test('default values match expected Revit configuration', () {
      final axis = ConstructionAxis(
        id: 'ax1',
        label: '1',
        startPoint: const Node3D(id: 'n1', x: 0, y: 0, z: 0),
        endPoint: const Node3D(id: 'n2', x: 6000, y: 0, z: 0),
      );
      expect(axis.showStartBubble, isTrue);
      expect(axis.showEndBubble, isFalse);
      expect(axis.elevationZ, 0.0);
      expect(axis.isPinned, isFalse);
      expect(axis.is3dPlaneOriented, isTrue);
      expect(axis.isStartLocked, isTrue);
      expect(axis.isEndLocked, isTrue);
      expect(axis.startElbowOffset, isNull);
      expect(axis.endElbowOffset, isNull);
    });

    test('serialization round-trip with all fields', () {
      final axis = ConstructionAxis(
        id: 'ax2',
        label: 'А',
        startPoint: const Node3D(id: 'n1', x: 0, y: 0, z: 1000),
        endPoint: const Node3D(id: 'n2', x: 0, y: 6000, z: 1000),
        showStartBubble: true,
        showEndBubble: true,
        elevationZ: 1000.0,
        startElbowOffset: const Offset(15.0, -20.0),
        endElbowOffset: const Offset(-10.0, 25.0),
        isPinned: true,
        is3dPlaneOriented: true,
        isStartLocked: false,
        isEndLocked: true,
      );
      final json = axis.toJson();
      final restored = ConstructionAxis.fromJson(json);
      expect(restored.id, 'ax2');
      expect(restored.label, 'А');
      expect(restored.showStartBubble, isTrue);
      expect(restored.showEndBubble, isTrue);
      expect(restored.elevationZ, 1000.0);
      expect(restored.startElbowOffset?.dx, 15.0);
      expect(restored.startElbowOffset?.dy, -20.0);
      expect(restored.endElbowOffset?.dx, -10.0);
      expect(restored.endElbowOffset?.dy, 25.0);
      expect(restored.isPinned, isTrue);
      expect(restored.is3dPlaneOriented, isTrue);
      expect(restored.isStartLocked, isFalse);
      expect(restored.isEndLocked, isTrue);
    });

    test('backward compatibility for legacy json without new fields', () {
      final legacyJson = {
        'id': 'legacy1',
        'label': 'Б',
        'startPoint': {'id': 'n1', 'x': 0.0, 'y': 0.0, 'z': 0.0},
        'endPoint': {'id': 'n2', 'x': 5000.0, 'y': 0.0, 'z': 0.0},
        'isBuildingGrid': true,
      };
      final restored = ConstructionAxis.fromJson(legacyJson);
      expect(restored.id, 'legacy1');
      expect(restored.label, 'Б');
      expect(restored.showStartBubble, isTrue);
      expect(restored.showEndBubble, isFalse);
      expect(restored.elevationZ, 0.0);
      expect(restored.isPinned, isFalse);
      expect(restored.is3dPlaneOriented, isTrue);
      expect(restored.isStartLocked, isTrue);
      expect(restored.isEndLocked, isTrue);
      expect(restored.startElbowOffset, isNull);
      expect(restored.endElbowOffset, isNull);
    });

    test('copyWith updates properties correctly', () {
      final axis = ConstructionAxis(
        id: 'ax3',
        label: '1',
        startPoint: const Node3D(id: 'n1', x: 0, y: 0, z: 0),
        endPoint: const Node3D(id: 'n2', x: 3000, y: 0, z: 0),
      );
      final updated = axis.copyWith(
        showEndBubble: true,
        isPinned: true,
        elevationZ: 500.0,
        startElbowOffset: const Offset(5, 5),
      );
      expect(updated.showEndBubble, isTrue);
      expect(updated.isPinned, isTrue);
      expect(updated.elevationZ, 500.0);
      expect(updated.startElbowOffset, const Offset(5, 5));
      expect(updated.showStartBubble, isTrue); // preserved
    });
  });
}
