import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Node-to-Pipe Connection and Branching Tests', () {
    test('Dragging vertical riser top node onto upper horizontal pipe splits pipe and creates Tee', () {
      final network = PipingNetwork();
      // Upper horizontal pipe along X axis at Z = 2000
      network.nodes['u1'] = const Node3D(id: 'u1', x: 0, y: 0, z: 2000);
      network.nodes['u2'] = const Node3D(id: 'u2', x: 2000, y: 0, z: 2000);
      network.segments['seg_upper'] = const PipeSegment(
        id: 'seg_upper',
        startNodeId: 'u1',
        endNodeId: 'u2',
        systemId: 'sys1',
        dn: 100,
        outerDiameterMm: 108,
      );

      // Lower vertical riser at (1000, 0, 0) up to (1000, 0, 1000)
      network.nodes['r_bot'] = const Node3D(id: 'r_bot', x: 1000, y: 0, z: 0);
      network.nodes['r_top'] = const Node3D(id: 'r_top', x: 1000, y: 0, z: 1000);
      network.segments['seg_riser'] = const PipeSegment(
        id: 'seg_riser',
        startNodeId: 'r_bot',
        endNodeId: 'r_top',
        systemId: 'sys1',
        dn: 80,
        outerDiameterMm: 89,
      );

      final controller = PipingInputController(initialNetwork: network);
      controller.useDirectBranch = false; // Default: Tee

      // Select and drag the top of the riser
      controller.selectedNodeId = 'r_top';
      controller.isDraggingNode = true;

      // Project target world position (1000, 0, 2000) to screen coordinates
      final targetScreen = controller.projector.project(const Node3D(id: 'target', x: 1000, y: 0, z: 2000));
      controller.handlePointerMove(targetScreen);
      controller.handlePointerUp();

      // Verify that the upper pipe segment is split into 2 segments
      final riserTopNode = controller.network.nodes['r_top']!;
      expect(riserTopNode.z, closeTo(2000.0, 1.0), reason: 'Riser node should elevate to upper pipe at Z=2000');

      final connectedToJunction = controller.network.getConnectedSegments('r_top');
      expect(connectedToJunction.length, equals(3), reason: 'Junction must have 3 connected segments (main left, main right, riser)');

      // Verify a Tee was automatically created
      final fitting = controller.network.fittings['r_top'];
      expect(fitting, isNotNull, reason: 'A fitting should be created at the 3-way junction');
      expect(fitting!.fittingType, equals(FittingType.tee));

      controller.dispose();
    });

    test('Dragging vertical riser top node with useDirectBranch=true creates Direct Branch (Врезка У18)', () {
      final network = PipingNetwork();
      network.nodes['u1'] = const Node3D(id: 'u1', x: 0, y: 0, z: 2000);
      network.nodes['u2'] = const Node3D(id: 'u2', x: 2000, y: 0, z: 2000);
      network.segments['seg_upper'] = const PipeSegment(
        id: 'seg_upper',
        startNodeId: 'u1',
        endNodeId: 'u2',
        systemId: 'sys1',
        dn: 100,
        outerDiameterMm: 108,
      );

      network.nodes['r_bot'] = const Node3D(id: 'r_bot', x: 1000, y: 0, z: 0);
      network.nodes['r_top'] = const Node3D(id: 'r_top', x: 1000, y: 0, z: 1000);
      network.segments['seg_riser'] = const PipeSegment(
        id: 'seg_riser',
        startNodeId: 'r_bot',
        endNodeId: 'r_top',
        systemId: 'sys1',
        dn: 80,
        outerDiameterMm: 89,
      );

      final controller = PipingInputController(initialNetwork: network);
      controller.useDirectBranch = true; // Mode: Direct Branch

      controller.selectedNodeId = 'r_top';
      controller.isDraggingNode = true;

      final targetScreen = controller.projector.project(const Node3D(id: 'target', x: 1000, y: 0, z: 2000));
      controller.handlePointerMove(targetScreen);
      controller.handlePointerUp();

      final riserTopNode = controller.network.nodes['r_top']!;
      expect(riserTopNode.z, closeTo(2000.0, 1.0));

      final connectedToJunction = controller.network.getConnectedSegments('r_top');
      expect(connectedToJunction.length, equals(3));

      final fitting = controller.network.fittings['r_top'];
      expect(fitting, isNotNull);
      expect(fitting!.fittingType, equals(FittingType.directBranch));

      controller.dispose();
    });

    test('Tracing into an existing segment creates fitting (Tee or Direct Branch)', () {
      final network = PipingNetwork();
      network.nodes['m1'] = const Node3D(id: 'm1', x: 0, y: 0, z: 0);
      network.nodes['m2'] = const Node3D(id: 'm2', x: 2000, y: 0, z: 0);
      network.segments['main_seg'] = const PipeSegment(
        id: 'main_seg',
        startNodeId: 'm1',
        endNodeId: 'm2',
        systemId: 'sys1',
        dn: 100,
        outerDiameterMm: 108,
      );

      final controller = PipingInputController(initialNetwork: network);
      controller.useDirectBranch = false;

      // Start tracing from (1000, 1000, 0)
      network.nodes['start'] = const Node3D(id: 'start', x: 1000, y: 1000, z: 0);
      controller.setTool(CanvasTool.trace);
      controller.traceStartNode = network.nodes['start'];

      // Tap on the middle of main_seg at (1000, 0, 0)
      final junctionScreen = controller.projector.project(const Node3D(id: 'j', x: 1000, y: 0, z: 0));
      controller.handlePointerMove(junctionScreen);
      controller.handlePointerDown(junctionScreen);

      // Find junction node
      final junctionNode = controller.network.nodes.values.firstWhere(
        (n) => (n.x - 1000).abs() < 10 && (n.y).abs() < 10 && (n.z).abs() < 10 && n.id != 'start',
      );

      final connected = controller.network.getConnectedSegments(junctionNode.id);
      expect(connected.length, equals(3));

      final fitting = controller.network.fittings[junctionNode.id];
      expect(fitting, isNotNull, reason: 'Tee should be created when tracing into existing pipe');
      expect(fitting!.fittingType, equals(FittingType.tee));

      controller.dispose();
    });

    test('Grip mode moving riser top node to upper horizontal pipe splits pipe and creates Tee', () {
      final network = PipingNetwork();
      network.nodes['u1'] = const Node3D(id: 'u1', x: 0, y: 0, z: 2000);
      network.nodes['u2'] = const Node3D(id: 'u2', x: 2000, y: 0, z: 2000);
      network.segments['seg_upper'] = const PipeSegment(
        id: 'seg_upper',
        startNodeId: 'u1',
        endNodeId: 'u2',
        systemId: 'sys1',
        dn: 100,
        outerDiameterMm: 108,
      );

      network.nodes['r_bot'] = const Node3D(id: 'r_bot', x: 1000, y: 0, z: 0);
      network.nodes['r_top'] = const Node3D(id: 'r_top', x: 1000, y: 0, z: 1000);
      network.segments['seg_riser'] = const PipeSegment(
        id: 'seg_riser',
        startNodeId: 'r_bot',
        endNodeId: 'r_top',
        systemId: 'sys1',
        dn: 80,
        outerDiameterMm: 89,
      );

      final controller = PipingInputController(initialNetwork: network);
      controller.useDirectBranch = false;

      // Activate Grip edit on r_top
      controller.activeGripNodeId = 'r_top';

      final targetScreen = controller.projector.project(const Node3D(id: 'target', x: 1000, y: 0, z: 2000));
      controller.handlePointerMove(targetScreen);
      controller.handlePointerDown(targetScreen); // Click to place grip

      final riserTopNode = controller.network.nodes['r_top']!;
      expect(riserTopNode.z, closeTo(2000.0, 1.0));

      final connectedToJunction = controller.network.getConnectedSegments('r_top');
      expect(connectedToJunction.length, equals(3));

      final fitting = controller.network.fittings['r_top'];
      expect(fitting, isNotNull);
      expect(fitting!.fittingType, equals(FittingType.tee));

      controller.dispose();
    });

    test('Free drag of vertical riser without snap elevates along Z holding X,Y fixed', () {
      final network = PipingNetwork();
      network.nodes['r_bot'] = const Node3D(id: 'r_bot', x: 500, y: 500, z: 0);
      network.nodes['r_top'] = const Node3D(id: 'r_top', x: 500, y: 500, z: 1000);
      network.segments['seg_riser'] = const PipeSegment(
        id: 'seg_riser',
        startNodeId: 'r_bot',
        endNodeId: 'r_top',
        systemId: 'sys1',
        dn: 50,
        outerDiameterMm: 57,
      );

      final controller = PipingInputController(initialNetwork: network);
      controller.isSnapEnabled = false; // Disable snap to test pure unprojectElevation

      controller.selectedNodeId = 'r_top';
      controller.isDraggingNode = true;

      // Project target world at Z = 2500
      final targetScreen = controller.projector.project(const Node3D(id: 't', x: 500, y: 500, z: 2500));
      controller.handlePointerMove(targetScreen);
      controller.handlePointerUp();

      final node = controller.network.nodes['r_top']!;
      expect(node.x, closeTo(500.0, 0.1));
      expect(node.y, closeTo(500.0, 0.1));
      expect(node.z, closeTo(2500.0, 1.0));

      controller.dispose();
    });

    test('Dropping open branch node onto existing 2-pipe node creates 3-way Tee', () {
      final network = PipingNetwork();
      network.nodes['m1'] = const Node3D(id: 'm1', x: 0, y: 0, z: 0);
      network.nodes['m_mid'] = const Node3D(id: 'm_mid', x: 1000, y: 0, z: 0);
      network.nodes['m2'] = const Node3D(id: 'm2', x: 2000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'm1',
        endNodeId: 'm_mid',
        systemId: 'sys1',
        dn: 100,
        outerDiameterMm: 108,
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'm_mid',
        endNodeId: 'm2',
        systemId: 'sys1',
        dn: 100,
        outerDiameterMm: 108,
      );

      // Branch from (1000, 1000, 0) to (1000, 200, 0)
      network.nodes['b_start'] = const Node3D(id: 'b_start', x: 1000, y: 1000, z: 0);
      network.nodes['b_end'] = const Node3D(id: 'b_end', x: 1000, y: 200, z: 0);
      network.segments['seg_branch'] = const PipeSegment(
        id: 'seg_branch',
        startNodeId: 'b_start',
        endNodeId: 'b_end',
        systemId: 'sys1',
        dn: 80,
        outerDiameterMm: 89,
      );

      final controller = PipingInputController(initialNetwork: network);
      controller.useDirectBranch = false;

      controller.selectedNodeId = 'b_end';
      controller.isDraggingNode = true;

      // Drag b_end onto m_mid at (1000, 0, 0)
      final midScreen = controller.projector.project(network.nodes['m_mid']!);
      controller.handlePointerMove(midScreen);
      controller.handlePointerUp();

      // b_end should have merged into m_mid, so m_mid now has 3 connected segments
      final connected = controller.network.getConnectedSegments('m_mid');
      expect(connected.length, equals(3));

      final fitting = controller.network.fittings['m_mid'];
      expect(fitting, isNotNull);
      expect(fitting!.fittingType, equals(FittingType.tee));

      controller.dispose();
    });
  });
}
