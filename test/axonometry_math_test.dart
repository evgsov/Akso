import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/models/node_3d.dart';

void main() {
  group('AxonometryProjector Tests', () {
    test('ГОСТ 45° проекция вертикального стояка и горизонтальной трубы', () {
      const projector = AxonometryProjector(
        projectionType: ProjectionType.gostFrontal45,
        scale: 1.0,
        panOffset: Offset.zero,
      );

      // 1. Вертикальный стояк (Z меняется от 0 до 2000 мм)
      final pBottom = const Node3D(id: 'b', x: 0, y: 0, z: 0);
      final pTop = const Node3D(id: 't', x: 0, y: 0, z: 2000);

      final screenBottom = projector.project(pBottom);
      final screenTop = projector.project(pTop);

      // В ГОСТ проекции X не меняется, значит экранный X одинаковый
      expect(screenBottom.dx, closeTo(screenTop.dx, 0.001));
      // Экранный Y должен уменьшиться ровно на 2000 (так как во Flutter экранный Y направлен вниз)
      expect(screenTop.dy, closeTo(screenBottom.dy - 2000.0, 0.001));

      // 2. Горизонтальная труба вдоль оси Y (0 до 1500 мм)
      final pY1 = const Node3D(id: 'y1', x: 0, y: 0, z: 0);
      final pY2 = const Node3D(id: 'y2', x: 0, y: 1500, z: 0);

      final screenY1 = projector.project(pY1);
      final screenY2 = projector.project(pY2);

      // Вдоль оси Y труба строго горизонтальна на экране
      expect(screenY1.dy, closeTo(screenY2.dy, 0.001));
      expect(screenY2.dx, closeTo(screenY1.dx + 1500.0, 0.001));
    });

    test('ISO 30° обратное преобразование (unproject)', () {
      const projector = AxonometryProjector(
        projectionType: ProjectionType.iso30,
        scale: 0.5,
        panOffset: Offset(400, 300),
      );

      const testZ = 1200.0;
      final originalNode = const Node3D(id: 'orig', x: 1000, y: 2500, z: testZ);
      final screenPos = projector.project(originalNode);

      final reconstructedNode = projector.unproject(screenPos, testZ);

      expect(reconstructedNode.x, closeTo(originalNode.x, 0.1));
      expect(reconstructedNode.y, closeTo(originalNode.y, 0.1));
      expect(reconstructedNode.z, closeTo(testZ, 0.001));
    });

    test('ГОСТ 45° обратное преобразование (unproject)', () {
      const projector = AxonometryProjector(
        projectionType: ProjectionType.gostFrontal45,
        scale: 0.25,
        panOffset: Offset(500, 500),
      );

      const testZ = 500.0;
      final originalNode = const Node3D(id: 'orig', x: 800, y: 1600, z: testZ);
      final screenPos = projector.project(originalNode);

      final reconstructedNode = projector.unproject(screenPos, testZ);

      expect(reconstructedNode.x, closeTo(originalNode.x, 0.1));
      expect(reconstructedNode.y, closeTo(originalNode.y, 0.1));
    });

    test('3D Orbit обратное преобразование (unproject)', () {
      const projector = AxonometryProjector(
        projectionType: ProjectionType.orbit3d,
        scale: 0.35,
        panOffset: Offset(600, 400),
        orbitAzimuth: -0.65,
        orbitElevation: 0.55,
      );

      const testZ = 1500.0;
      final originalNode = const Node3D(id: 'orig', x: 2400, y: 3200, z: testZ);
      final screenPos = projector.project(originalNode);

      final reconstructedNode = projector.unproject(screenPos, testZ);

      expect(reconstructedNode.x, closeTo(originalNode.x, 0.1));
      expect(reconstructedNode.y, closeTo(originalNode.y, 0.1));
      expect(reconstructedNode.z, closeTo(testZ, 0.001));
    });

    test('2D План (topPlan2d) прямое и обратное преобразование', () {
      const projector = AxonometryProjector(
        projectionType: ProjectionType.topPlan2d,
        scale: 0.5,
        panOffset: Offset(200, 200),
      );

      const testZ = 0.0;
      final originalNode = const Node3D(id: 'orig', x: 1200, y: 1800, z: testZ);
      final screenPos = projector.project(originalNode);

      // В 2D плане X горизонтально, Y вертикально
      expect(screenPos.dx, closeTo(200 + 1200 * 0.5, 0.001));
      expect(screenPos.dy, closeTo(200 - 1800 * 0.5, 0.001));

      final reconstructedNode = projector.unproject(screenPos, testZ);
      expect(reconstructedNode.x, closeTo(originalNode.x, 0.1));
      expect(reconstructedNode.y, closeTo(originalNode.y, 0.1));
    });
  });
}
