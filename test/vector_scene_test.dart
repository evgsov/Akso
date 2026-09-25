import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/vector_scene.dart';

void main() {
  group('VectorScene', () {
    test('creates scene with dimensions and adds primitives', () {
      final scene = VectorScene(widthMm: 420.0, heightMm: 297.0);
      expect(scene.widthMm, equals(420.0));
      expect(scene.heightMm, equals(297.0));
      expect(scene.items, isEmpty);

      scene.addPolyline(
        layer: VectorSceneLayer.pipes,
        points: const [Offset(10, 10), Offset(50, 10)],
        strokeWidthMm: 1.5,
        colorValue: 0xFFFF0000,
        smoothJoin: true,
      );

      scene.addCircle(
        layer: VectorSceneLayer.welds,
        center: const Offset(30, 10),
        radiusMm: 2.0,
        strokeColorValue: 0xFF000000,
      );

      scene.addText(
        layer: VectorSceneLayer.annotations,
        text: 'К-1: Ду50',
        position: const Offset(30, 5),
        fontSizePt: 8.0,
        colorValue: 0xFF333333,
      );

      expect(scene.items.length, equals(3));
    });

    test('getOrderedItems orders by layer enum index then zIndex', () {
      final scene = VectorScene(widthMm: 297.0, heightMm: 210.0);

      // Add in reverse order
      scene.addRect(
        layer: VectorSceneLayer.frameAndStamp,
        rect: const Rect.fromLTWH(0, 0, 100, 100),
      );

      scene.addPolyline(
        layer: VectorSceneLayer.pipes,
        points: const [Offset(0, 0), Offset(10, 10)],
        strokeWidthMm: 1.0,
        colorValue: 0xFF0000FF,
        zIndex: 2,
      );

      scene.addPolyline(
        layer: VectorSceneLayer.pipes,
        points: const [Offset(5, 5), Offset(15, 15)],
        strokeWidthMm: 1.0,
        colorValue: 0xFF0000FF,
        zIndex: 1,
      );

      scene.addLine(
        layer: VectorSceneLayer.axes,
        start: const Offset(0, 50),
        end: const Offset(100, 50),
        strokeWidthMm: 0.35,
        colorValue: 0xFF999999,
      );

      final ordered = scene.getOrderedItems();
      expect(ordered.length, equals(4));

      // Layer ordering: axes (index 0) -> pipes (index 2, zIndex 1) -> pipes (zIndex 2) -> frameAndStamp (index 10)
      expect(ordered[0].layer, equals(VectorSceneLayer.axes));
      expect(ordered[1].layer, equals(VectorSceneLayer.pipes));
      expect(ordered[1].zIndex, equals(1));
      expect(ordered[2].layer, equals(VectorSceneLayer.pipes));
      expect(ordered[2].zIndex, equals(2));
      expect(ordered[3].layer, equals(VectorSceneLayer.frameAndStamp));
    });

    test('ignores polylines with fewer than 2 points or empty text', () {
      final scene = VectorScene(widthMm: 100, heightMm: 100);
      scene.addPolyline(
        layer: VectorSceneLayer.pipes,
        points: const [Offset(0, 0)],
        strokeWidthMm: 1.0,
        colorValue: 0xFF000000,
      );
      scene.addText(
        layer: VectorSceneLayer.annotations,
        text: '',
        position: const Offset(0, 0),
        fontSizePt: 8.0,
        colorValue: 0xFF000000,
      );
      expect(scene.items, isEmpty);
    });
  });
}
