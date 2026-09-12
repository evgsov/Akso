import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/core/math/snap_engine.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/piping_canvas.dart';

void main() {
  group('Trace HUD Math and Formatting', () {
    test('computeTraceHudInfo accurately calculates 3D length and orthogonal angles', () {
      final origin = const Node3D(id: '0', x: 0, y: 0, z: 0);

      // +X направление (0°)
      final pX = const Node3D(id: 'px', x: 1250, y: 0, z: 0);
      final hudX = PipingCanvasPainter.computeTraceHudInfo(origin, pX);
      expect(hudX.lengthMm, closeTo(1250, 0.01));
      expect(hudX.angleDegrees, equals(0));
      expect(hudX.text, equals('L: 1250 мм | ∠: 0°'));

      // +Y направление (90°)
      final pY = const Node3D(id: 'py', x: 0, y: 2000, z: 0);
      final hudY = PipingCanvasPainter.computeTraceHudInfo(origin, pY);
      expect(hudY.lengthMm, closeTo(2000, 0.01));
      expect(hudY.angleDegrees, equals(90));
      expect(hudY.text, equals('L: 2000 мм | ∠: 90°'));

      // -X направление (180°)
      final pNegX = const Node3D(id: 'negx', x: -1500, y: 0, z: 0);
      final hudNegX = PipingCanvasPainter.computeTraceHudInfo(origin, pNegX);
      expect(hudNegX.lengthMm, closeTo(1500, 0.01));
      expect(hudNegX.angleDegrees, equals(180));
      expect(hudNegX.text, equals('L: 1500 мм | ∠: 180°'));

      // -Y направление (270°)
      final pNegY = const Node3D(id: 'negy', x: 0, y: -800, z: 0);
      final hudNegY = PipingCanvasPainter.computeTraceHudInfo(origin, pNegY);
      expect(hudNegY.lengthMm, closeTo(800, 0.01));
      expect(hudNegY.angleDegrees, equals(270));
      expect(hudNegY.text, equals('L: 800 мм | ∠: 270°'));
    });

    test('computeTraceHudInfo calculates 45 degree angle and 3D diagonal distance', () {
      final p1 = const Node3D(id: 'p1', x: 100, y: 100, z: 0);
      final p2 = const Node3D(id: 'p2', x: 200, y: 200, z: 0);
      final hud45 = PipingCanvasPainter.computeTraceHudInfo(p1, p2);
      expect(hud45.angleDegrees, equals(45));
      expect(hud45.lengthMm, closeTo(141.42, 0.1));
      expect(hud45.text, equals('L: 141 мм | ∠: 45°'));

      // 3D длина со смещением по Z: sqrt(300^2 + 400^2 + 1200^2) = 1300
      final p3 = const Node3D(id: 'p3', x: 0, y: 0, z: 0);
      final p4 = const Node3D(id: 'p4', x: 300, y: 400, z: 1200);
      final hud3d = PipingCanvasPainter.computeTraceHudInfo(p3, p4);
      expect(hud3d.lengthMm, closeTo(1300.0, 0.01));
      expect(hud3d.angleDegrees, equals(53)); // atan2(400, 300) = ~53.13°
      expect(hud3d.text, equals('L: 1300 мм | ∠: 53°'));
    });

    test('Angle is always in [0, 360) range', () {
      final origin = const Node3D(id: '0', x: 0, y: 0, z: 0);
      final almost360 = const Node3D(id: 'a', x: 1000, y: -0.001, z: 0);
      final hud = PipingCanvasPainter.computeTraceHudInfo(origin, almost360);
      expect(hud.angleDegrees, inInclusiveRange(0, 359));
    });
  });

  group('Trace HUD Badge Positioning', () {
    test('computeBadgePosition offsets badge from cursor so it does not overlap', () {
      const cursor = Offset(100, 100);
      const badgeSize = Size(120, 24);
      const canvasSize = Size(800, 600);

      final pos = PipingCanvasPainter.computeBadgePosition(
        cursorOffset: cursor,
        badgeSize: badgeSize,
        canvasSize: canvasSize,
        offsetDistance: 16.0,
      );

      // Смещен вправо-вниз
      expect(pos.dx, equals(116.0));
      expect(pos.dy, equals(116.0));

      // Проверяем, что точка курсора находится вне прямоугольника бейджа
      final badgeRect = Rect.fromLTWH(pos.dx, pos.dy, badgeSize.width, badgeSize.height);
      expect(badgeRect.contains(cursor), isFalse);
    });

    test('computeBadgePosition flips position to avoid going off-screen', () {
      const badgeSize = Size(120, 24);
      const canvasSize = Size(800, 600);

      // Курсор близко к правому краю
      const cursorRight = Offset(750, 100);
      final posRight = PipingCanvasPainter.computeBadgePosition(
        cursorOffset: cursorRight,
        badgeSize: badgeSize,
        canvasSize: canvasSize,
        offsetDistance: 16.0,
      );
      // Смещается влево от курсора: 750 - 16 - 120 = 614
      expect(posRight.dx, equals(614.0));
      final rectRight = Rect.fromLTWH(posRight.dx, posRight.dy, badgeSize.width, badgeSize.height);
      expect(rectRight.contains(cursorRight), isFalse);
      expect(rectRight.right, lessThanOrEqualTo(canvasSize.width));

      // Курсор близко к нижнему краю
      const cursorBottom = Offset(100, 580);
      final posBottom = PipingCanvasPainter.computeBadgePosition(
        cursorOffset: cursorBottom,
        badgeSize: badgeSize,
        canvasSize: canvasSize,
        offsetDistance: 16.0,
      );
      // Смещается вверх от курсора: 580 - 16 - 24 = 540
      expect(posBottom.dy, equals(540.0));
      final rectBottom = Rect.fromLTWH(posBottom.dx, posBottom.dy, badgeSize.width, badgeSize.height);
      expect(rectBottom.contains(cursorBottom), isFalse);
      expect(rectBottom.bottom, lessThanOrEqualTo(canvasSize.height));
    });
  });

  group('PipingCanvasPainter HUD Rendering', () {
    test('Renders trace HUD for pipe tracing without exceptions', () {
      final network = PipingNetwork();
      const projector = AxonometryProjector();
      final startNode = const Node3D(id: 'start', x: 0, y: 0, z: 0);
      network.nodes['start'] = startNode;

      final painter = PipingCanvasPainter(
        network: network,
        projector: projector,
        activeTraceStart: startNode,
        activeTraceEnd: const Offset(200, 200),
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(800, 600));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('Renders trace HUD for construction axis tracing without exceptions', () {
      final network = PipingNetwork();
      const projector = AxonometryProjector();
      final axisStart = const Node3D(id: 'axis_start', x: 500, y: 500, z: 0);

      final painter = PipingCanvasPainter(
        network: network,
        projector: projector,
        activeAxisStart: axisStart,
        activeTraceEnd: const Offset(300, 250),
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(800, 600));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('Renders trace HUD with snapResult accurately', () {
      final network = PipingNetwork();
      const projector = AxonometryProjector();
      final startNode = const Node3D(id: 'start', x: 0, y: 0, z: 0);
      final snappedWorld = const Node3D(id: 'snap', x: 1000, y: 0, z: 0);

      final painter = PipingCanvasPainter(
        network: network,
        projector: projector,
        activeTraceStart: startNode,
        activeTraceEnd: const Offset(200, 200),
        snapResult: SnapResult(
          type: SnapType.polarAngle,
          screenPoint: const Offset(200, 200),
          worldPoint: snappedWorld,
          snappedAngleDegrees: 0,
        ),
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(800, 600));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('Paints safely with boundary sizes (zero and large screens)', () {
      final network = PipingNetwork();
      const projector = AxonometryProjector();
      final startNode = const Node3D(id: 'start', x: 0, y: 0, z: 0);

      final painter = PipingCanvasPainter(
        network: network,
        projector: projector,
        activeTraceStart: startNode,
        activeTraceEnd: const Offset(150, 150),
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, Size.zero);
      painter.paint(canvas, const Size(1920, 1080));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });
  });
}
