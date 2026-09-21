import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';

void main() {
  group('CalloutObstacleMap', () {
    test('detects shelf overlap with existing callout rects', () {
      final map = CalloutObstacleMap();
      map.addRect(const Rect.fromLTWH(100, 100, 80, 20));

      // Overlapping rect
      expect(map.testShelfCollision(const Rect.fromLTWH(120, 110, 80, 20)), isTrue);
      // Disjoint rect
      expect(map.testShelfCollision(const Rect.fromLTWH(250, 100, 80, 20)), isFalse);
    });

    test('detects shelf collision with pipe corridor', () {
      final map = CalloutObstacleMap();
      map.addPipe(const Offset(0, 50), const Offset(200, 50), 10.0);

      // Shelf intersecting pipe
      expect(map.testShelfCollision(const Rect.fromLTWH(50, 45, 60, 20)), isTrue);
      // Shelf clearly outside pipe corridor
      expect(map.testShelfCollision(const Rect.fromLTWH(50, 80, 60, 20)), isFalse);
    });

    test('counts leader line intersections with pipes and other leader lines', () {
      final map = CalloutObstacleMap();
      // Pipe across Y=100
      map.addPipe(const Offset(0, 100), const Offset(200, 100), 5.0);

      // Leader crossing the pipe
      final count1 = map.countLeaderLineIntersections(const Offset(50, 50), const Offset(50, 150));
      expect(count1, equals(1));

      // Leader not crossing the pipe
      final count2 = map.countLeaderLineIntersections(const Offset(50, 110), const Offset(50, 150));
      expect(count2, equals(0));
    });
  });

  group('CalloutLayoutEngine', () {
    test('findBestCandidate avoids obstacles and chooses clear quadrant', () {
      final map = CalloutObstacleMap();
      // Block top-right quadrant with a pipe and obstacle
      map.addRect(const Rect.fromLTWH(110, 80, 100, 40));
      map.addPipe(const Offset(100, 100), const Offset(200, 50), 8.0);

      const anchor = Offset(100, 100);
      const textWidth = 60.0;
      const textHeight = 12.0;

      final best = CalloutLayoutEngine.evaluateBestOffset(
        anchor: anchor,
        textWidth: textWidth,
        textHeight: textHeight,
        obstacleMap: map,
      );

      expect(best, isNotNull);
      // The chosen shelf rect must not collide with the obstacle
      final chosenBounds = Rect.fromLTWH(
        anchor.dx + best!.dx,
        anchor.dy + best.dy - textHeight - 4.0,
        textWidth + 10.0,
        textHeight + 8.0,
      );
      expect(map.testShelfCollision(chosenBounds), isFalse);
    });
  });
}

