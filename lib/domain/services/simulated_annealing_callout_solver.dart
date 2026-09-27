import 'dart:math' as math;
import '../models/callout_candidate_slot.dart';
import 'callout_layout_engine.dart';

/// Глобальный оптимизатор расстановки выносок на основе метода имитации отжига (Simulated Annealing)
class SimulatedAnnealingCalloutSolver {
  /// Оценка парного конфликта между двумя выносками (слотами):
  /// - Наложение полочек: +100 000 000
  /// - Пересечение стрелок: +50 000 000
  /// - Стрелка рассекает чужую полочку: +30 000 000
  /// - Бонус за ровный каскад (друг под другом): -50.0
  static double computePairwiseConflict(CalloutCandidateSlot a, CalloutCandidateSlot b) {
    // 1. Абсолютный запрет: наложение полок и текстов друг на друга
    if (a.boundingBox.overlaps(b.boundingBox)) {
      return 100000000.0;
    }

    // 2. Абсолютный запрет: взаимное пересечение наклонных стрелок (ножек)
    if (CalloutObstacleMap.segmentsIntersect(a.anchor, a.entryShelf, b.anchor, b.entryShelf)) {
      return 50000000.0;
    }

    // 3. Стрелка одной выноски рассекает горизонтальную полочку другой
    if (CalloutObstacleMap.segmentsIntersect(a.anchor, a.entryShelf, b.entryShelf, b.shelfEnd) ||
        CalloutObstacleMap.segmentsIntersect(b.anchor, b.entryShelf, a.entryShelf, a.shelfEnd)) {
      return 30000000.0;
    }

    // 4. Прямоугольник текста полочки пересекает наклонную стрелку другой выноски
    if (CalloutObstacleMap.rectCollidesWithSegment(a.boundingBox, b.anchor, b.entryShelf, 0.3) ||
        CalloutObstacleMap.rectCollidesWithSegment(b.boundingBox, a.anchor, a.entryShelf, 0.3)) {
      return 30000000.0;
    }

    // 5. Поощрительный бонус за аккуратный каскад (выравнивание по одной вертикальной линии X)
    if (a.isRight == b.isRight &&
        (a.entryShelf.dx - b.entryShelf.dx).abs() <= 1.8) {
      final dy = (a.entryShelf.dy - b.entryShelf.dy).abs();
      if (dy >= 4.5 && dy <= 80.0) {
        // Дополнительный бонус за идеальное совпадение направляющей X
        final exactXBonus = (a.entryShelf.dx - b.entryShelf.dx).abs() <= 0.05 ? -40.0 : 0.0;
        return -100.0 + exactXBonus;
      } else if (dy < 4.5) {
        // Слишком тесно по вертикали в одной колонке
        return 10000.0;
      }
    }

    return 0.0;
  }

  /// Выполняет глобальный поиск оптимальной комбинации слотов выносок
  static Map<String, CalloutCandidateSlot> solve({
    required Map<String, List<CalloutCandidateSlot>> candidatePools,
    CalloutObstacleMap? obstacleMap,
    int iterations = 30000,
    double initialTemperature = 500.0,
    double minTemperature = 0.05,
    void Function(Map<String, CalloutCandidateSlot> currentSolution)? onStep,
    int stepInterval = 1000,
  }) {
    final result = <String, CalloutCandidateSlot>{};
    if (candidatePools.isEmpty) return result;

    final calloutIds = candidatePools.keys.toList();
    final pools = calloutIds.map((id) => candidatePools[id]!).toList();
    final n = calloutIds.length;

    // Жадная монотонная инициализация сверху вниз:
    // Сортируем выноски по вертикальной координате анкера (Y).
    // Верхние выноски первыми занимают верхние слоты без пересечений и коллизий.
    final sortedIndices = List<int>.generate(n, (idx) => idx);
    sortedIndices.sort((a, b) => pools[a].first.anchor.dy.compareTo(pools[b].first.anchor.dy));

    final state = List<int>.filled(n, 0);
    final placed = <int>[];

    for (final i in sortedIndices) {
      final pool = pools[i];
      int bestIdx = 0;
      double minCost = double.infinity;

      for (int s = 0; s < pool.length; s++) {
        final cand = pool[s];
        double cost = cand.localStaticCost;

        for (final p in placed) {
          cost += computePairwiseConflict(cand, pools[p][state[p]]);
        }

        if (cost < minCost) {
          minCost = cost;
          bestIdx = s;
        }
      }

      state[i] = bestIdx;
      placed.add(i);
    }

    // Расчет начальной энергии системы
    double currentEnergy = 0.0;
    for (int i = 0; i < n; i++) {
      currentEnergy += pools[i][state[i]].localStaticCost;
      for (int j = i + 1; j < n; j++) {
        currentEnergy += computePairwiseConflict(pools[i][state[i]], pools[j][state[j]]);
      }
    }

    double bestEnergy = currentEnergy;
    final bestState = List<int>.from(state);

    final random = math.Random(42);
    double temperature = initialTemperature;
    final coolingFactor = math.pow(minTemperature / initialTemperature, 1.0 / math.max(1, iterations)).toDouble();

    for (int iter = 0; iter < iterations; iter++) {
      // Выбираем случайную выноску, у которой есть альтернативные слоты
      final i = random.nextInt(n);
      final pool = pools[i];
      if (pool.length <= 1) continue;

      final oldIdx = state[i];
      int newIdx = random.nextInt(pool.length);
      if (newIdx == oldIdx) {
        newIdx = (oldIdx + 1) % pool.length;
      }

      final oldSlot = pool[oldIdx];
      final newSlot = pool[newIdx];

      // Быстрое инкрементальное вычисление изменения энергии (Delta E) за O(N)
      double deltaE = newSlot.localStaticCost - oldSlot.localStaticCost;
      for (int j = 0; j < n; j++) {
        if (j == i) continue;
        final otherSlot = pools[j][state[j]];
        final oldConflict = computePairwiseConflict(oldSlot, otherSlot);
        final newConflict = computePairwiseConflict(newSlot, otherSlot);
        deltaE += (newConflict - oldConflict);
      }

      // Критерий Метрополиса для принятия изменений
      bool accept = false;
      if (deltaE < 0) {
        accept = true;
      } else {
        final prob = math.exp(-deltaE / temperature);
        if (random.nextDouble() < prob) {
          accept = true;
        }
      }

      if (accept) {
        state[i] = newIdx;
        currentEnergy += deltaE;
        if (currentEnergy < bestEnergy) {
          bestEnergy = currentEnergy;
          for (int k = 0; k < n; k++) {
            bestState[k] = state[k];
          }
        }
      }

      temperature *= coolingFactor;

      if (onStep != null && (iter % stepInterval == 0 || iter == iterations - 1)) {
        final intermediate = <String, CalloutCandidateSlot>{};
        for (int k = 0; k < n; k++) {
          intermediate[calloutIds[k]] = pools[k][state[k]];
        }
        onStep(intermediate);
      }
    }

    // Формируем результат на основе наилучшего зафиксированного состояния
    for (int k = 0; k < n; k++) {
      result[calloutIds[k]] = pools[k][bestState[k]];
    }

    return result;
  }

  /// Асинхронная глобальная оптимизация с периодическим возвратом управления в event loop
  /// для плавной анимации процесса отжига в интерфейсе Flutter
  static Future<Map<String, CalloutCandidateSlot>> solveAsync({
    required Map<String, List<CalloutCandidateSlot>> candidatePools,
    CalloutObstacleMap? obstacleMap,
    int iterations = 30000,
    double initialTemperature = 500.0,
    double minTemperature = 0.05,
    Future<void> Function(Map<String, CalloutCandidateSlot> currentSolution, double progress)? onStep,
    int stepInterval = 1000,
    Duration stepDelay = const Duration(milliseconds: 20),
  }) async {
    final result = <String, CalloutCandidateSlot>{};
    if (candidatePools.isEmpty) return result;

    final calloutIds = candidatePools.keys.toList();
    final pools = calloutIds.map((id) => candidatePools[id]!).toList();
    final n = calloutIds.length;

    // Жадная монотонная инициализация сверху вниз:
    // Сортируем выноски по вертикальной координате анкера (Y).
    final sortedIndices = List<int>.generate(n, (idx) => idx);
    sortedIndices.sort((a, b) => pools[a].first.anchor.dy.compareTo(pools[b].first.anchor.dy));

    final state = List<int>.filled(n, 0);
    final placed = <int>[];

    for (final i in sortedIndices) {
      final pool = pools[i];
      int bestIdx = 0;
      double minCost = double.infinity;

      for (int s = 0; s < pool.length; s++) {
        final cand = pool[s];
        double cost = cand.localStaticCost;

        for (final p in placed) {
          cost += computePairwiseConflict(cand, pools[p][state[p]]);
        }

        if (cost < minCost) {
          minCost = cost;
          bestIdx = s;
        }
      }

      state[i] = bestIdx;
      placed.add(i);
    }

    // Расчет начальной энергии системы
    double currentEnergy = 0.0;
    for (int i = 0; i < n; i++) {
      currentEnergy += pools[i][state[i]].localStaticCost;
      for (int j = i + 1; j < n; j++) {
        currentEnergy += computePairwiseConflict(pools[i][state[i]], pools[j][state[j]]);
      }
    }

    double bestEnergy = currentEnergy;
    final bestState = List<int>.from(state);

    if (onStep != null) {
      final initialMap = <String, CalloutCandidateSlot>{};
      for (int k = 0; k < n; k++) {
        initialMap[calloutIds[k]] = pools[k][state[k]];
      }
      await onStep(initialMap, 0.0);
    }

    final random = math.Random(42);
    double temperature = initialTemperature;
    final coolingFactor = math.pow(minTemperature / initialTemperature, 1.0 / math.max(1, iterations)).toDouble();

    for (int iter = 0; iter < iterations; iter++) {
      final i = random.nextInt(n);
      final pool = pools[i];
      if (pool.length <= 1) continue;

      final oldIdx = state[i];
      int newIdx = random.nextInt(pool.length);
      if (newIdx == oldIdx) {
        newIdx = (oldIdx + 1) % pool.length;
      }

      final oldSlot = pool[oldIdx];
      final newSlot = pool[newIdx];

      double deltaE = newSlot.localStaticCost - oldSlot.localStaticCost;
      for (int j = 0; j < n; j++) {
        if (j == i) continue;
        final otherSlot = pools[j][state[j]];
        final oldConflict = computePairwiseConflict(oldSlot, otherSlot);
        final newConflict = computePairwiseConflict(newSlot, otherSlot);
        deltaE += (newConflict - oldConflict);
      }

      bool accept = false;
      if (deltaE < 0) {
        accept = true;
      } else {
        final prob = math.exp(-deltaE / temperature);
        if (random.nextDouble() < prob) {
          accept = true;
        }
      }

      if (accept) {
        state[i] = newIdx;
        currentEnergy += deltaE;
        if (currentEnergy < bestEnergy) {
          bestEnergy = currentEnergy;
          for (int k = 0; k < n; k++) {
            bestState[k] = state[k];
          }
        }
      }

      temperature *= coolingFactor;

      if (onStep != null && (iter % stepInterval == 0 || iter == iterations - 1)) {
        final intermediate = <String, CalloutCandidateSlot>{};
        for (int k = 0; k < n; k++) {
          intermediate[calloutIds[k]] = pools[k][state[k]];
        }
        await onStep(intermediate, iter / iterations);
        if (stepDelay > Duration.zero) {
          await Future.delayed(stepDelay);
        }
      }
    }

    for (int k = 0; k < n; k++) {
      result[calloutIds[k]] = pools[k][bestState[k]];
    }

    return result;
  }
}
