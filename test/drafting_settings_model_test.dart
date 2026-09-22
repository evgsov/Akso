import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/drafting_settings.dart';
import 'package:akso/domain/models/acquired_tracking_point.dart';
import 'package:akso/domain/models/node_3d.dart';

void main() {
  group('DraftingSettings', () {
    test('default constructor has correct CAD drafting defaults', () {
      const settings = DraftingSettings();
      expect(settings.snapNodes, isTrue);
      expect(settings.snapIntersections, isTrue);
      expect(settings.snapMidpoints, isTrue);
      expect(settings.snapPerpendicular, isTrue);
      expect(settings.snapNearest, isFalse, reason: 'Nearest must be false by default to prevent stickiness');
      expect(settings.enableOtrack, isTrue);
      expect(settings.isZLocked, isTrue);
      expect(settings.showZPlaneGrid, isFalse);
      expect(settings.nodeSnapRadius, equals(20.0));
      expect(settings.nearestSnapRadius, equals(8.0));
    });

    test('copyWith works properly', () {
      const settings = DraftingSettings();
      final updated = settings.copyWith(snapNearest: true, isZLocked: false);
      expect(updated.snapNearest, isTrue);
      expect(updated.isZLocked, isFalse);
      expect(updated.snapNodes, isTrue);
    });
  });

  group('AcquiredTrackingPoint', () {
    test('instantiates with correct fields', () {
      final now = DateTime.now();
      final pt = AcquiredTrackingPoint(
        worldPoint: const Node3D(id: 'n1', x: 100, y: 200, z: 0),
        screenPoint: const Offset(50, 60),
        nodeId: 'n1',
        acquiredAt: now,
      );
      expect(pt.nodeId, equals('n1'));
      expect(pt.worldPoint.x, equals(100));
      expect(pt.screenPoint.dx, equals(50));
    });
  });
}
