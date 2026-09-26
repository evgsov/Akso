import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/sheet_format.dart';
import 'package:akso/domain/enums/sheet_format_type.dart';

void main() {
  test('DrawingSheet defaults groupMultiLevelCallouts to true', () {
    final sheet = DrawingSheet(
      id: 'sheet_1',
      name: 'Монтажная схема',
      sheetNumber: 1,
      format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
      viewport: const SheetViewport(),
    );
    expect(sheet.groupMultiLevelCallouts, isTrue);
  });

  test('DrawingSheet serialization preserves groupMultiLevelCallouts', () {
    final sheet = DrawingSheet(
      id: 'sheet_1',
      name: 'Монтажная схема',
      sheetNumber: 1,
      format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
      viewport: const SheetViewport(),
      groupMultiLevelCallouts: false,
    );
    final json = sheet.toJson();
    expect(json['groupMultiLevelCallouts'], isFalse);

    final restored = DrawingSheet.fromJson(json);
    expect(restored.groupMultiLevelCallouts, isFalse);
  });
}
