import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/core/math/snap_engine.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('3D Axis and Reference Line Snapping Tests', () {
    late PipingNetwork network;
    late AxonometryProjector projector;
    late SnapEngine snapEngine;

    setUp(() {
      network = PipingNetwork();
      projector = AxonometryProjector();
      snapEngine = const SnapEngine();
    });

    test('Примагничивание к строительной оси на отметке Z=2800 сохраняет elevation', () {
      // Ось здания "1" расположена на Z=0 от y=-1000 до y=5000 при x=1000
      const axis1 = ConstructionAxis(
        id: 'axis_1',
        label: '1',
        startPoint: Node3D(id: '', x: 1000, y: -1000, z: 0),
        endPoint: Node3D(id: '', x: 1000, y: 5000, z: 0),
        isBuildingGrid: true,
      );
      network.axes['axis_1'] = axis1;

      // Трассировка ведется на отметке Z=2800.0
      const currentElevationZ = 2800.0;
      // Точка на оси на высоте 2800: (1000, 2000, 2800)
      const targetPoint = Node3D(id: '', x: 1000, y: 2000, z: currentElevationZ);
      final screenPos = projector.project(targetPoint);
      // Курсор чуть смещен на 6 пикселей
      final cursor = screenPos.translate(4.0, 4.0);

      final result = snapEngine.findSnap(
        screenPos: cursor,
        network: network,
        projector: projector,
        currentElevationZ: currentElevationZ,
      );

      expect(result.type, equals(SnapType.gridAxis));
      expect(result.snappedSegmentId, equals('axis_1'));
      expect(result.worldPoint.z, equals(currentElevationZ));
      expect(result.worldPoint.x, closeTo(1000.0, 1.0));
      expect(result.worldPoint.y, closeTo(2000.0, 25.0));
      expect(result.label, contains('Ось 1 [∇+2.800]'));
    });

    test('Примагничивание к вспомогательной/опорной линии формирует корректный лейбл', () {
      const refLine = ConstructionAxis(
        id: 'ref_line_1',
        label: '',
        startPoint: Node3D(id: '', x: -2000, y: 0, z: 0),
        endPoint: Node3D(id: '', x: 4000, y: 0, z: 0),
        isBuildingGrid: false,
      );
      network.axes['ref_line_1'] = refLine;

      const currentElevationZ = 0.0;
      const targetPoint = Node3D(id: '', x: 500, y: 0, z: currentElevationZ);
      final screenPos = projector.project(targetPoint);

      final result = snapEngine.findSnap(
        screenPos: screenPos,
        network: network,
        projector: projector,
        currentElevationZ: currentElevationZ,
      );

      expect(result.type, equals(SnapType.gridAxis));
      expect(result.snappedSegmentId, equals('ref_line_1'));
      expect(result.worldPoint.z, equals(0.0));
      expect(result.label, contains('Опорная линия [∇+0.000]'));
    });
  });

  group('PipingInputController Axis Selection and Deletion Tests', () {
    late PipingInputController controller;

    setUp(() {
      controller = PipingInputController();
    });

    test('Переключение режима "Ось здания" / "Опорная линия" и создание оси', () {
      controller.setTool(CanvasTool.drawAxis);
      expect(controller.isBuildingGridAxis, isTrue);

      // Переключаем на опорную линию
      controller.setIsBuildingGridAxis(false);
      expect(controller.isBuildingGridAxis, isFalse);

      // Черчение опорной линии
      controller.handlePointerDown(const Offset(100, 100));
      controller.handlePointerDown(const Offset(300, 100));

      expect(controller.network.axes.length, equals(1));
      final axis = controller.network.axes.values.first;
      expect(axis.isBuildingGrid, isFalse);
      expect(axis.label, isEmpty);
    });

    test('Выделение оси кликом мыши в режиме select и удаление по deleteSelected()', () {
      // Добавляем ось здания
      const axis = ConstructionAxis(
        id: 'test_axis_1',
        label: '1',
        startPoint: Node3D(id: '', x: 0, y: 0, z: 0),
        endPoint: Node3D(id: '', x: 2000, y: 0, z: 0),
        isBuildingGrid: true,
      );
      controller.network.axes[axis.id] = axis;

      controller.setTool(CanvasTool.select);

      // Кликаем по середине оси
      const midWorld = Node3D(id: '', x: 1000, y: 0, z: 0);
      final screenPos = controller.projector.project(midWorld);
      controller.handlePointerDown(screenPos);

      expect(controller.selectedAxisId, equals('test_axis_1'));

      // Удаляем выделенную ось
      controller.deleteSelected();

      expect(controller.network.axes.containsKey('test_axis_1'), isFalse);
      expect(controller.selectedAxisId, isNull);
    });

    test('Отмена операции через cancelCurrentOperation сбрасывает selectedAxisId', () {
      const axis = ConstructionAxis(
        id: 'test_axis_2',
        label: '2',
        startPoint: Node3D(id: '', x: 0, y: 0, z: 0),
        endPoint: Node3D(id: '', x: 0, y: 3000, z: 0),
        isBuildingGrid: true,
      );
      controller.network.axes[axis.id] = axis;
      controller.selectedAxisId = 'test_axis_2';

      controller.cancelCurrentOperation();
      expect(controller.selectedAxisId, isNull);
    });
  });
}
