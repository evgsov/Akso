import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';

void main() {
  group('Callout isPinned property', () {
    test('defaults to false', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
      );
      expect(callout.isPinned, isFalse);
    });

    test('copyWith updates isPinned', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
      );
      final pinned = callout.copyWith(isPinned: true);
      expect(pinned.isPinned, isTrue);
      final unpinned = pinned.copyWith(isPinned: false);
      expect(unpinned.isPinned, isFalse);
    });

    test('JSON serialization preserves isPinned', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
        isPinned: true,
      );
      final json = callout.toJson();
      expect(json['isPinned'], isTrue);

      final restored = Callout.fromJson(json);
      expect(restored.isPinned, isTrue);

      final legacy = Callout.fromJson({
        'id': 'c2',
        'targetId': 'seg2',
        'targetType': 'segment',
      });
      expect(legacy.isPinned, isFalse);
    });
  });
}
