import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout_candidate_slot.dart';
import 'package:akso/domain/services/cascade_spring_aligner.dart';

void main() {
  group('CascadeSpringAligner', () {
    test('aligns shelves with close X coordinates into a neat vertical column with identical X', () {
      final slot1 = CalloutCandidateSlot(
        anchor: const Offset(50.0, 50.0),
        entryShelf: const Offset(68.5, 40.0),
        shelfEnd: const Offset(98.5, 40.0),
        isRight: true,
        boundingBox: const Rect.fromLTWH(68.5, 35.0, 30.0, 8.0),
        radius: 20.0,
        angleRad: 0.5,
        localStaticCost: 10.0,
      );

      final slot2 = CalloutCandidateSlot(
        anchor: const Offset(50.0, 60.0),
        entryShelf: const Offset(70.0, 55.0), // dx = 70.0 (разница всего 1.5 мм с slot1)
        shelfEnd: const Offset(100.0, 55.0),
        isRight: true,
        boundingBox: const Rect.fromLTWH(70.0, 50.0, 30.0, 8.0),
        radius: 20.0,
        angleRad: 0.5,
        localStaticCost: 10.0,
      );

      final slot3 = CalloutCandidateSlot(
        anchor: const Offset(50.0, 70.0),
        entryShelf: const Offset(69.0, 68.0), // dx = 69.0
        shelfEnd: const Offset(99.0, 68.0),
        isRight: true,
        boundingBox: const Rect.fromLTWH(69.0, 63.0, 30.0, 8.0),
        radius: 20.0,
        angleRad: 0.5,
        localStaticCost: 10.0,
      );

      final input = {
        'c1': slot1,
        'c2': slot2,
        'c3': slot3,
      };

      final aligned = CascadeSpringAligner.align(input, pitchMm: 10.0);

      expect(aligned.length, equals(3));
      final a1 = aligned['c1']!;
      final a2 = aligned['c2']!;
      final a3 = aligned['c3']!;

      // Все три полочки должны получить абсолютно одинаковую координату X (каскад!)
      expect(a1.entryShelf.dx, equals(a2.entryShelf.dx));
      expect(a2.entryShelf.dx, equals(a3.entryShelf.dx));

      // Расстояние между строками должно быть не менее заданного pitch
      expect((a2.entryShelf.dy - a1.entryShelf.dy).abs(), greaterThanOrEqualTo(9.9));
      expect((a3.entryShelf.dy - a2.entryShelf.dy).abs(), greaterThanOrEqualTo(9.9));
    });

    test('does not merge callouts with opposite directions or far X distances', () {
      final slotRight = CalloutCandidateSlot(
        anchor: const Offset(50.0, 50.0),
        entryShelf: const Offset(65.0, 40.0),
        shelfEnd: const Offset(95.0, 40.0),
        isRight: true,
        boundingBox: const Rect.fromLTWH(65.0, 35.0, 30.0, 8.0),
        radius: 20.0,
        angleRad: 0.5,
        localStaticCost: 10.0,
      );

      final slotLeft = CalloutCandidateSlot(
        anchor: const Offset(50.0, 50.0),
        entryShelf: const Offset(35.0, 40.0),
        shelfEnd: const Offset(5.0, 40.0),
        isRight: false, // Влево!
        boundingBox: const Rect.fromLTWH(5.0, 35.0, 30.0, 8.0),
        radius: 20.0,
        angleRad: 2.6,
        localStaticCost: 10.0,
      );

      final input = {
        'right': slotRight,
        'left': slotLeft,
      };

      final aligned = CascadeSpringAligner.align(input);

      // Не должны объединяться
      expect(aligned['right']!.entryShelf.dx, equals(65.0));
      expect(aligned['left']!.entryShelf.dx, equals(35.0));
    });
  });
}
