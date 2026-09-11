import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/piping_canvas.dart';

void main() {
  group('Fittings and Elevation Workflow Tests', () {
    late PipingNetwork network;
    late AxonometryProjector projector;

    setUp(() {
      network = PipingNetwork();
      projector = AxonometryProjector(projectionType: ProjectionType.iso30);
    });

    test('Изменение уровня при отсутствии активного черчения не создает фантомную трубу', () {
      final controller = PipingInputController(network: network, projector: projector);

      // Пользователь меняет высотную отметку в режиме ожидания
      controller.addVerticalRiser(2500.0);

      // Никаких сегментов или стояков не должно появиться
      expect(network.segments.isEmpty, isTrue);
      expect(network.nodes.isEmpty, isTrue);
      expect(controller.currentElevationZ, 2500.0);
    });

    test('Изменение уровня во время активной трассировки создает вертикальный стояк и отвод', () {
      final controller = PipingInputController(network: network, projector: projector);

      // Создаем начальный горизонтальный сегмент
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.addSegment(const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_t1',
        dn: 50,
      ));

      // Пользователь чертит от узла n2 и меняет уровень на +1500 мм
      controller.traceStartNode = n2;
      controller.addVerticalRiser(1500.0);

      // Должен создаться вертикальный стояк
      expect(network.segments.length, 2);
      final riser = network.segments.values.firstWhere((s) => s.id != 's1');
      final topNode = network.nodes[riser.endNodeId]!;
      expect(topNode.z, 1500.0);
      expect(topNode.x, 2000.0);
      expect(topNode.y, 0.0);

      // В узле n2 должен автоматически определиться отвод 90°
      expect(network.fittings.containsKey('n2'), isTrue);
      expect(network.fittings['n2']!.fittingType, FittingType.elbow90);

      // Точка продолжения трассировки перемещается на верхний узел стояка
      expect(controller.traceStartNode?.id, topNode.id);
      expect(controller.currentElevationZ, 1500.0);
    });

    test('Автоопределение отводов и тройников при соединении сегментов', () {
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = const Node3D(id: 'n3', x: 1000, y: 1000, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      network.addSegment(const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_1',
        dn: 80,
      ));
      network.addSegment(const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys_1',
        dn: 80,
      ));

      // В повороте n2 автоматически распознан отвод 90°
      expect(network.fittings.containsKey('n2'), isTrue);
      expect(network.fittings['n2']!.fittingType, FittingType.elbow90);

      // Добавляем третий сегмент от n2 в направлении X (образуя т-образное соединение)
      final n4 = const Node3D(id: 'n4', x: 2000, y: 0, z: 0);
      network.nodes['n4'] = n4;
      network.addSegment(const PipeSegment(
        id: 'seg3',
        startNodeId: 'n2',
        endNodeId: 'n4',
        systemId: 'sys_1',
        dn: 80,
      ));

      // Фитинг в n2 автоматически обновлен до тройника (Tee)
      expect(network.fittings['n2']!.fittingType, FittingType.tee);
    });

    test('PipingCanvasPainter корректно отрисовывает отводы и тройники без исключений', () {
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = const Node3D(id: 'n3', x: 1000, y: 1000, z: 0);
      final n4 = const Node3D(id: 'n4', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;
      network.nodes['n4'] = n4;

      network.addSegment(const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50));
      network.addSegment(const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_1', dn: 50));
      network.addSegment(const PipeSegment(id: 's3', startNodeId: 'n2', endNodeId: 'n4', systemId: 'sys_1', dn: 50));

      final painter = PipingCanvasPainter(
        network: network,
        projector: projector,
        showWelds: true,
        showCallouts: true,
        showGrid: true,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(1000, 800));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });
  });
}
