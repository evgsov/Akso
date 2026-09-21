import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  test('PipingInputController.autoLayoutCallouts updates callouts and records history', () {
    final network = PipingNetwork();
    network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
    network.nodes['n2'] = const Node3D(id: 'n2', x: 4000, y: 0, z: 0);
    network.segments['seg'] = const PipeSegment(
      id: 'seg',
      startNodeId: 'n1',
      endNodeId: 'n2',
      outerDiameterMm: 108,
      systemId: 'sys1',
      dn: 100,
    );
    final c1 = Callout(id: 'c1', targetId: 'seg', targetType: CalloutTargetType.segment);
    network.callouts[c1.id] = c1;

    final controller = PipingInputController(initialNetwork: network);
    expect(controller.canUndo, isFalse);

    final updated = controller.autoLayoutCallouts();
    expect(updated, greaterThanOrEqualTo(1));
    expect(controller.canUndo, isTrue);

    // Undo restores previous state
    controller.undo();
    expect(controller.network.callouts['c1']?.screenOffsetX, equals(c1.screenOffsetX));
  });

  test('PipingInputController pin methods toggle and unpin callouts', () {
    final network = PipingNetwork();
    network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
    network.nodes['n2'] = const Node3D(id: 'n2', x: 4000, y: 0, z: 0);
    network.segments['seg'] = const PipeSegment(
      id: 'seg',
      startNodeId: 'n1',
      endNodeId: 'n2',
      outerDiameterMm: 108,
      systemId: 'sys1',
      dn: 100,
    );
    final c1 = Callout(id: 'c1', targetId: 'seg', targetType: CalloutTargetType.segment);
    network.callouts[c1.id] = c1;

    final controller = PipingInputController(initialNetwork: network);
    expect(controller.network.callouts['c1']?.isPinned, isFalse);

    controller.toggleCalloutPinning('c1');
    expect(controller.network.callouts['c1']?.isPinned, isTrue);

    controller.unpinAllCallouts();
    expect(controller.network.callouts['c1']?.isPinned, isFalse);
  });
}
