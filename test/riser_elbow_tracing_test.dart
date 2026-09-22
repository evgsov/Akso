import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/services/fitting_detector.dart';

void main() {
  group('Riser & Elbow Tracing Tests', () {
    test('1. Vertical transition with elbow creates clean welds and spools', () {
      final network = PipingNetwork();

      // n1: (0, 0, 2800) -> n2: (2000, 0, 2800) -> n3: (2000, 0, 600)
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 2800);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 2800);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 600);

      network.addSegment(const PipeSegment(id: 'seg_h', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50));
      network.addSegment(const PipeSegment(id: 'seg_v', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50));

      FittingDetector.autoDetectAllFittings(network);
      expect(network.fittings['n2']?.fittingType, equals(FittingType.elbow90));

      network.generateElementWeldJoints();
      network.recalculateSpools();

      // Должно быть ровно 2 шва отвода: на горизонтальной трубе и на стояке
      expect(network.weldJoints.length, equals(2));
      final hWeld = network.weldJoints.values.firstWhere((w) => w.segmentId == 'seg_h');
      final vWeld = network.weldJoints.values.firstWhere((w) => w.segmentId == 'seg_v');

      expect(hWeld.sourceElementId, equals('fit_n2_seg_h'));
      expect(vWeld.sourceElementId, equals('fit_n2_seg_v'));

      // Тангенс отвода Ду50 = 75 мм.
      // seg_h: длина 2000, шов на 1925 мм (r = 0.9625)
      expect((hWeld.ratio - 0.9625).abs(), lessThan(0.001));
      // seg_v: длина 2200, шов на 75 мм от начала (r = 75 / 2200 = 0.03409)
      expect((vWeld.ratio - (75.0 / 2200.0)).abs(), lessThan(0.001));

      // Катушки: на каждой трубе ровно по одной катушке, начинающейся/заканчивающейся строго у стыка отвода
      expect(network.spools.length, equals(2));
      final hSpool = network.spools.values.firstWhere((s) => s.segmentId == 'seg_h');
      final vSpool = network.spools.values.firstWhere((s) => s.segmentId == 'seg_v');

      expect(hSpool.cutLengthMm, equals(1925.0));
      expect(hSpool.endPoint?.x, equals(1925.0));

      expect(vSpool.cutLengthMm, equals(2125.0));
      expect(vSpool.startPoint?.z, equals(2725.0)); // 2800 - 75 = 2725
      expect(vSpool.endPoint?.z, equals(600.0));
    });

    test('2. Step 3 ignores non-collinear pipes and does not generate coaxial weld at 90 deg', () {
      final network = PipingNetwork();

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 2800);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 2800);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 600);

      // Добавляем сегменты напрямую без детектора фитингов
      network.segments['seg_h'] = const PipeSegment(id: 'seg_h', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50);
      network.segments['seg_v'] = const PipeSegment(id: 'seg_v', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50);

      // Даже если фитинг в n2 еще не создан, Step 3 не должен создавать соосный шов
      final added = network.generateElementWeldJoints();
      expect(added, equals(0));
      expect(network.weldJoints.isEmpty, isTrue);
    });

    test('3. Step 3 creates coaxial weld only for truly collinear straight pipes', () {
      final network = PipingNetwork();

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 2800);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 2800);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 4000, y: 0, z: 2800);

      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50);

      final added = network.generateElementWeldJoints();
      expect(added, equals(1));
      expect(network.weldJoints.length, equals(1));
      final weld = network.weldJoints.values.first;
      expect(weld.sourceElementId, equals('coaxial_n2'));
    });

    test('4. Obsolete coaxial weld is cleaned up when pipe turns', () {
      final network = PipingNetwork();

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 2800);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 2800);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 4000, y: 0, z: 2800);

      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50);

      network.generateElementWeldJoints();
      expect(network.weldJoints.length, equals(1));

      // Теперь поворачиваем n3 вниз, превращая трубу в стояк
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 600);

      // Вызываем очистку и генерацию
      network.generateElementWeldJoints();
      FittingDetector.autoDetectAllFittings(network);
      network.generateElementWeldJoints();

      // Старый coaxial_n2 должен быть удален, а вместо него созданы швы отвода
      expect(network.weldJoints.values.any((w) => w.sourceElementId == 'coaxial_n2'), isFalse);
    });

    test('5. SpoolCalculator prevents ghost pipe spool inside fitting deduction zone', () {
      final network = PipingNetwork();

      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 2800);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 2800);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 600);

      network.addSegment(const PipeSegment(id: 'seg_h', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 50));
      network.addSegment(const PipeSegment(id: 'seg_v', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 50));

      FittingDetector.autoDetectAllFittings(network);
      network.generateElementWeldJoints();

      // Принудительно вставляем шов на отметке 20 мм (внутри 75-мм тангенса отвода)
      network.addWeldJoint(segmentId: 'seg_v', ratio: 20.0 / 2200.0, weldType: WeldType.c17, sourceElementId: 'test_inner');

      network.recalculateSpools();

      // Никакой катушки внутри зоны [0, 75] мм не должно быть создано!
      for (final sp in network.spools.values.where((s) => s.segmentId == 'seg_v')) {
        expect(sp.startPoint!.z, lessThanOrEqualTo(2725.01)); // Не выше стыка отвода (2725)
      }
    });
  });
}
