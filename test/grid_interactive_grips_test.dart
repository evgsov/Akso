import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Grid interactive grips & controller mechanics', () {
    late PipingInputController controller;
    late PipingNetwork net;

    setUp(() {
      net = PipingNetwork();
      net.axes['ax1'] = const ConstructionAxis(
        id: 'ax1',
        label: '1',
        startPoint: Node3D(id: 'n1', x: 0, y: 0, z: 0),
        endPoint: Node3D(id: 'n2', x: 0, y: 10000, z: 0),
        showStartBubble: true,
        showEndBubble: false,
        isStartLocked: true,
        isEndLocked: true,
      );
      net.axes['ax2'] = const ConstructionAxis(
        id: 'ax2',
        label: '2',
        startPoint: Node3D(id: 'n3', x: 6000, y: 0, z: 0),
        endPoint: Node3D(id: 'n4', x: 6000, y: 10000, z: 0),
        showStartBubble: true,
        showEndBubble: false,
        isStartLocked: true,
        isEndLocked: true,
      );

      controller = PipingInputController(
        network: net,
        projector: const AxonometryProjector(scale: 0.1),
      );
      controller.selectedAxisId = 'ax1';
    });

    test('toggling bubble visibility at start and end', () {
      controller.toggleAxisBubbleVisibility('ax1', isStart: true);
      expect(controller.network.axes['ax1']!.showStartBubble, isFalse);

      controller.toggleAxisBubbleVisibility('ax1', isStart: false);
      expect(controller.network.axes['ax1']!.showEndBubble, isTrue);
    });

    test('toggling alignment lock at start and end', () {
      controller.toggleAxisAlignmentLock('ax1', isStart: true);
      expect(controller.network.axes['ax1']!.isStartLocked, isFalse);

      controller.toggleAxisAlignmentLock('ax1', isStart: false);
      expect(controller.network.axes['ax1']!.isEndLocked, isFalse);
    });

    test('dragging chained endpoint stretches both aligned axes', () {
      // Initiate drag on ax1 end
      controller.startAxisGripDrag('ax1', isStart: false);
      // Move pointer
      final newEnd = const Node3D(id: 'drag', x: 0, y: 14000, z: 0);
      controller.updateAxisGripDrag(newEnd);
      controller.endAxisGripDrag();

      expect(controller.network.axes['ax1']!.endPoint.y, 14000);
      expect(controller.network.axes['ax2']!.endPoint.y, 14000); // Chained!
    });

    test('applying temporary dimension moves axis by exact distance', () {
      controller.applyTemporaryDimension('ax2', 'ax1', 8000.0);
      expect(controller.network.axes['ax2']!.startPoint.x, 8000.0);
      expect(controller.network.axes['ax2']!.endPoint.x, 8000.0);
    });

    test('setting and clearing elbow break offset', () {
      controller.setAxisElbowOffset('ax1', isStart: true, offset: const Offset(25, -30));
      expect(controller.network.axes['ax1']!.startElbowOffset, const Offset(25, -30));

      controller.clearAxisElbowOffset('ax1', isStart: true);
      expect(controller.network.axes['ax1']!.startElbowOffset, isNull);
    });

    test('creating offset axis duplicates with next GOST label', () {
      final newAxis = controller.createOffsetAxis('ax2', 6000.0, positiveSide: true);
      expect(newAxis.label, '3');
      expect(newAxis.startPoint.x, 12000.0);
      expect(newAxis.endPoint.x, 12000.0);
      expect(controller.network.axes.containsKey(newAxis.id), isTrue);
    });
  });
}
