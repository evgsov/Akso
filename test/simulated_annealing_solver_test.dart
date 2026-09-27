import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout_candidate_slot.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';
import 'package:akso/domain/services/simulated_annealing_callout_solver.dart';

void main() {
  group('SimulatedAnnealingCalloutSolver', () {
    test('resolves collision between two overlapping callouts', () {
      final anchor1 = const Offset(100.0, 100.0);
      final anchor2 = const Offset(105.0, 100.0);

      // Обе выноски имеют два слота: один смотрит вправо (конфликтный), другой смотрит влево (свободный)
      final slot1Right = CalloutCandidateSlot(
        anchor: anchor1,
        entryShelf: const Offset(115.0, 95.0),
        shelfEnd: const Offset(145.0, 95.0),
        isRight: true,
        boundingBox: const Rect.fromLTWH(114.0, 90.0, 32.0, 8.0),
        radius: 15.0,
        angleRad: 0.5,
        localStaticCost: 10.0,
      );
      final slot1Left = CalloutCandidateSlot(
        anchor: anchor1,
        entryShelf: const Offset(85.0, 95.0),
        shelfEnd: const Offset(55.0, 95.0),
        isRight: false,
        boundingBox: const Rect.fromLTWH(54.0, 90.0, 32.0, 8.0),
        radius: 15.0,
        angleRad: 2.6,
        localStaticCost: 20.0,
      );

      final slot2Right = CalloutCandidateSlot(
        anchor: anchor2,
        entryShelf: const Offset(120.0, 95.0), // Накладывается на slot1Right!
        shelfEnd: const Offset(150.0, 95.0),
        isRight: true,
        boundingBox: const Rect.fromLTWH(119.0, 90.0, 32.0, 8.0), // Очевидное наложение!
        radius: 15.0,
        angleRad: 0.5,
        localStaticCost: 10.0,
      );
      final slot2Up = CalloutCandidateSlot(
        anchor: anchor2,
        entryShelf: const Offset(110.0, 75.0), // Выше, чистый
        shelfEnd: const Offset(140.0, 75.0),
        isRight: true,
        boundingBox: const Rect.fromLTWH(109.0, 70.0, 32.0, 8.0),
        radius: 25.0,
        angleRad: 1.2,
        localStaticCost: 30.0,
      );

      final pools = {
        'c1': [slot1Right, slot1Left],
        'c2': [slot2Right, slot2Up],
      };

      final obstacleMap = CalloutObstacleMap();

      final solution = SimulatedAnnealingCalloutSolver.solve(
        candidatePools: pools,
        obstacleMap: obstacleMap,
        iterations: 2000,
      );

      expect(solution.length, equals(2));
      final s1 = solution['c1']!;
      final s2 = solution['c2']!;

      // Проверяем, что решатель разрешил конфликт: полки не накладываются друг на друга
      expect(s1.boundingBox.overlaps(s2.boundingBox), isFalse);
      // Проверяем, что стрелки не пересекаются
      expect(
        CalloutObstacleMap.segmentsIntersect(s1.anchor, s1.entryShelf, s2.anchor, s2.entryShelf),
        isFalse,
      );
    });

    test('pairwise conflict evaluation penalizes overlaps and crossings', () {
      final a = CalloutCandidateSlot(
        anchor: const Offset(10.0, 10.0),
        entryShelf: const Offset(20.0, 20.0),
        shelfEnd: const Offset(40.0, 20.0),
        isRight: true,
        boundingBox: const Rect.fromLTWH(20.0, 15.0, 20.0, 10.0),
        radius: 14.0,
        angleRad: 0.78,
        localStaticCost: 10.0,
      );

      // Накладывающийся слот
      final bOverlapping = CalloutCandidateSlot(
        anchor: const Offset(15.0, 12.0),
        entryShelf: const Offset(25.0, 20.0),
        shelfEnd: const Offset(45.0, 20.0),
        isRight: true,
        boundingBox: const Rect.fromLTWH(24.0, 16.0, 20.0, 10.0), // Пересекается с a
        radius: 14.0,
        angleRad: 0.78,
        localStaticCost: 10.0,
      );

      final conflictOverlap = SimulatedAnnealingCalloutSolver.computePairwiseConflict(a, bOverlapping);
      expect(conflictOverlap, greaterThanOrEqualTo(100000000.0));

      // Чистый параллельный слот в каскаде (выравнивание по X)
      final bCascade = CalloutCandidateSlot(
        anchor: const Offset(10.0, 30.0),
        entryShelf: const Offset(20.0, 35.0),
        shelfEnd: const Offset(40.0, 35.0),
        isRight: true,
        boundingBox: const Rect.fromLTWH(20.0, 30.0, 20.0, 10.0), // Ровно под a
        radius: 11.0,
        angleRad: 0.78,
        localStaticCost: 10.0,
      );

      final conflictCascade = SimulatedAnnealingCalloutSolver.computePairwiseConflict(a, bCascade);
      expect(conflictCascade, lessThan(0.0)); // Бонус за каскад!
    });

    test('greedy monotonic initialization resolves dense vertical stack without leader crossings', () {
      // 5 выносок, расположенных вертикально вдоль стояка (X = 100, Y от 50 до 90)
      final pools = <String, List<CalloutCandidateSlot>>{};

      for (int i = 0; i < 5; i++) {
        final y = 50.0 + i * 10.0;
        final anchor = Offset(100.0, y);

        // Каждый имеет выбор: слот в правой колонке на разной высоте
        final slots = <CalloutCandidateSlot>[];
        for (int k = 0; k < 5; k++) {
          final shelfY = 45.0 + k * 12.0;
          final entry = Offset(130.0, shelfY);
          slots.add(CalloutCandidateSlot(
            anchor: anchor,
            entryShelf: entry,
            shelfEnd: Offset(entry.dx + 25.0, entry.dy),
            isRight: true,
            boundingBox: Rect.fromLTWH(entry.dx, entry.dy - 4.0, 25.0, 8.0),
            radius: (entry - anchor).distance,
            angleRad: 0.3,
            localStaticCost: (entry - anchor).distance,
          ));
        }
        pools['c$i'] = slots;
      }

      final solution = SimulatedAnnealingCalloutSolver.solve(
        candidatePools: pools,
        iterations: 1000,
      );

      expect(solution.length, equals(5));

      // Проверяем, что ни одна пара стрелок не пересекается
      final entries = solution.values.toList();
      for (int i = 0; i < entries.length; i++) {
        for (int j = i + 1; j < entries.length; j++) {
          final a = entries[i];
          final b = entries[j];
          final crosses = CalloutObstacleMap.segmentsIntersect(
            a.anchor,
            a.entryShelf,
            b.anchor,
            b.entryShelf,
          );
          expect(crosses, isFalse, reason: 'Callouts $i and $j crossed leader lines!');
          expect(a.boundingBox.overlaps(b.boundingBox), isFalse, reason: 'Callouts $i and $j overlap!');
        }
      }
    });
  });
}
