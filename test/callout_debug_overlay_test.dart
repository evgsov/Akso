import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/drawing_sheet.dart';

void main() {
  group('DrawingSheet debugShowObstacles', () {
    test('defaults to false', () {
      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
      );
      expect(sheet.debugShowObstacles, isFalse);
    });

    test('copyWith updates debugShowObstacles', () {
      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
      );
      final updated = sheet.copyWith(debugShowObstacles: true);
      expect(updated.debugShowObstacles, isTrue);

      final reverted = updated.copyWith(debugShowObstacles: false);
      expect(reverted.debugShowObstacles, isFalse);
    });

    test('serializes and deserializes debugShowObstacles', () {
      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
        debugShowObstacles: true,
      );
      final json = sheet.toJson();
      expect(json['debugShowObstacles'], isTrue);

      final restored = DrawingSheet.fromJson(json);
      expect(restored.debugShowObstacles, isTrue);
    });
  });
}
