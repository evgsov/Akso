import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/inspection_method.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Copy Tool & Distance Entry Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;
    late PipingSystem sys;
    late PipeSegment seg;

    setUp(() {
      network = PipingNetwork();
      sys = PipingSystem(
        id: 'sys_v1',
        name: 'Холодное водоснабжение',
        code: 'В1',
        colorValue: Colors.blue.toARGB32(),
        dxfAciColor: 5,
      );
      network.systems[sys.id] = sys;

      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      seg = PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_v1',
        dn: 50,
        outerDiameterMm: 57.0,
      );
      network.segments[seg.id] = seg;

      controller = PipingInputController(network: network);
    });

    tearDown(() {
      controller.dispose();
    });

    test('commitTraceWithLength on CanvasTool.copy places copy at exact distance, resets tool to select, clears base point, and allows 1-step undo', () {
      // Select segment
      controller.selectedSegmentId = seg.id;
      controller.selectedSegmentIds.add(seg.id);
      expect(controller.selectedSegmentIds, contains(seg.id));

      // Switch to copy tool and set base point at (0, 0, 0)
      controller.setTool(CanvasTool.copy);
      controller.modifyBasePointWorld = Node3D(id: 'base', x: 0, y: 0, z: 0);

      // Commit distance 1500 mm in direction X (+1, 0, 0)
      controller.commitTraceWithLength(1500, dirX: 1.0, dirY: 0.0, dirZ: 0.0);

      // 1. Check that a new segment is created with nodes at x=1500 and x=2500
      expect(network.segments.length, equals(2));
      final copiedSeg = network.segments.values.firstWhere((s) => s.id != seg.id);
      final cStart = network.nodes[copiedSeg.startNodeId]!;
      final cEnd = network.nodes[copiedSeg.endNodeId]!;
      expect(cStart.x, closeTo(1500.0, 0.1));
      expect(cEnd.x, closeTo(2500.0, 0.1));

      // 2. Check that tool is finished and returned to CanvasTool.select
      expect(controller.currentTool, equals(CanvasTool.select));
      expect(controller.modifyBasePointWorld, isNull);
      expect(controller.modifyBasePointScreen, isNull);

      // 3. Check that the copied segment is selected
      expect(controller.selectedSegmentIds, contains(copiedSeg.id));

      // 4. Check that 1 call to undo() removes the copy and returns to original 1 segment
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(network.segments.length, equals(1));
      expect(network.segments.containsKey(seg.id), isTrue);
      expect(network.segments.containsKey(copiedSeg.id), isFalse);
    });

    test('duplicateSelection does not record double state in history', () {
      controller.selectedSegmentId = seg.id;
      controller.selectedSegmentIds.add(seg.id);
      final initialCanUndo = controller.history.canUndo;

      // Duplicate
      final success = controller.duplicateSelection(dx: 500, dy: 0, dz: 0);
      expect(success, isTrue);

      // Verify exactly 1 undo restores the previous state
      expect(network.segments.length, equals(2));
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(network.segments.length, equals(1));
      // After 1 undo, we should be back at the initial state
      expect(controller.canUndo, equals(initialCanUndo));
    });

    test('Mouse clicks in CanvasTool.copy do not accumulate offset when updateSelection is false', () {
      controller.selectedSegmentId = seg.id;
      controller.selectedSegmentIds.add(seg.id);
      controller.setTool(CanvasTool.copy);
      controller.modifyBasePointWorld = Node3D(id: 'base', x: 0, y: 0, z: 0);

      // First click at (500, 0, 0)
      controller.handlePointerDown(controller.projector.project(Node3D(id: 'p1', x: 500, y: 0, z: 0)));
      expect(network.segments.length, equals(2));

      // Second click at (1000, 0, 0) - should create copy at 1000, NOT 1500
      controller.handlePointerDown(controller.projector.project(Node3D(id: 'p2', x: 1000, y: 0, z: 0)));
      expect(network.segments.length, equals(3));

      // Verify coordinates of the two created copies
      final copies = network.segments.values.where((s) => s.id != seg.id).toList();
      final starts = copies.map((s) => network.nodes[s.startNodeId]!.x).toList()..sort();
      expect(starts[0], closeTo(500.0, 1.0));
      expect(starts[1], closeTo(1000.0, 1.0));
    });
  });

  group('Single Step Undo Tests for Element Insertions & Edits', () {
    late PipingNetwork network;
    late PipingInputController controller;
    late PipingSystem sys;
    late PipeSegment seg;

    setUp(() {
      network = PipingNetwork();
      sys = PipingSystem(
        id: 'sys_v1',
        name: 'Холодное водоснабжение',
        code: 'В1',
        colorValue: Colors.blue.toARGB32(),
        dxfAciColor: 5,
      );
      network.systems[sys.id] = sys;

      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      seg = PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_v1',
        dn: 50,
        outerDiameterMm: 57.0,
      );
      network.segments[seg.id] = seg;

      controller = PipingInputController(network: network);
    });

    tearDown(() {
      controller.dispose();
    });

    test('insertValve is undone in exactly 1 step without deleting the pipe', () {
      controller.setTool(CanvasTool.insertValve);
      final midScreen = controller.projector.project(Node3D(id: 'mid', x: 1000, y: 0, z: 0));
      controller.handlePointerDown(midScreen);

      expect(network.valves.length, equals(1));
      expect(network.segments.length, equals(1));

      // 1 single undo must remove the valve and preserve the segment
      controller.undo();
      expect(network.valves.length, equals(0));
      expect(network.segments.length, equals(1));
    });

    test('insertSupport is undone in exactly 1 step without deleting the pipe', () {
      controller.setTool(CanvasTool.insertSupport);
      final midScreen = controller.projector.project(Node3D(id: 'mid', x: 1000, y: 0, z: 0));
      controller.handlePointerDown(midScreen);

      expect(network.supports.length, equals(1));
      expect(network.segments.length, equals(1));

      controller.undo();
      expect(network.supports.length, equals(0));
      expect(network.segments.length, equals(1));
    });

    test('insertWeld is undone in exactly 1 step without deleting the pipe', () {
      controller.setTool(CanvasTool.insertWeld);
      final midScreen = controller.projector.project(Node3D(id: 'mid', x: 1000, y: 0, z: 0));
      controller.handlePointerDown(midScreen);

      expect(network.weldJoints.length, equals(1));
      expect(network.segments.length, equals(1));

      controller.undo();
      expect(network.weldJoints.length, equals(0));
      expect(network.segments.length, equals(1));
    });

    test('insertReducer is undone in exactly 1 step', () {
      controller.setTool(CanvasTool.insertReducer);
      controller.targetReducerDn = 32;
      final midScreen = controller.projector.project(Node3D(id: 'mid', x: 1000, y: 0, z: 0));
      controller.handlePointerDown(midScreen);

      // Inserting reducer splits segment into 2 segments with reducer fitting
      expect(network.segments.length, equals(2));

      controller.undo();
      expect(network.segments.length, equals(1));
    });

    test('addVerticalRiser is undone in exactly 1 step', () {
      controller.setTool(CanvasTool.select);
      controller.selectedNodeId = 'n2';
      controller.addVerticalRiser(1500.0);

      expect(network.segments.length, equals(2));
      expect(network.nodes.length, equals(3));

      controller.undo();
      expect(network.segments.length, equals(1));
      expect(network.nodes.length, equals(2));
    });

    test('editing valve properties records state after modification so 1 undo restores previous value', () {
      // Add valve
      final v = network.addValve(
        segmentId: seg.id,
        ratio: 0.5,
        valveType: ValveType.ballValve,
        dn: 50,
      );
      expect(v, isNotNull);
      final valveId = v.id;

      // Ensure history has state with valve
      controller.history.recordState(controller.network);

      // Modify name and record state after
      controller.network.updateValve(valveId, v.copyWith(name: 'Кран Изменен'));
      controller.history.recordState(controller.network);

      expect(network.valves[valveId]!.name, equals('Кран Изменен'));

      // 1 undo restores original name
      controller.undo();
      expect(network.valves[valveId]!.name, isNot(equals('Кран Изменен')));
      expect(network.segments.length, equals(1));
    });

    test('editing support type records state after modification so 1 undo restores previous type', () {
      final sup = network.addSupport(
        segmentId: seg.id,
        distanceRatio: 0.5,
        type: PipeSupportType.sliding,
      );
      expect(sup, isNotNull);
      final supId = sup.id;
      controller.history.recordState(controller.network);

      controller.network.updateSupport(supId, sup.copyWith(type: PipeSupportType.fixed));
      controller.history.recordState(controller.network);

      expect(network.supports[supId]!.type, equals(PipeSupportType.fixed));

      controller.undo();
      expect(network.supports[supId]!.type, equals(PipeSupportType.sliding));
      expect(network.segments.length, equals(1));
    });

    test('editing weld inspection method records state after modification so 1 undo restores previous method', () {
      final w = network.addWeldJoint(
        segmentId: seg.id,
        ratio: 0.3,
        inspectionMethod: InspectionMethod.vik,
      );
      expect(w, isNotNull);
      final weldId = w.id;
      controller.history.recordState(controller.network);

      controller.network.updateWeldJoint(weldId, (weld) => weld.copyWith(inspectionMethod: InspectionMethod.uzk));
      controller.history.recordState(controller.network);

      expect(network.weldJoints[weldId]!.inspectionMethod, equals(InspectionMethod.uzk));

      controller.undo();
      expect(network.weldJoints[weldId]!.inspectionMethod, equals(InspectionMethod.vik));
      expect(network.segments.length, equals(1));
    });

    test('attaching cap to end node is undone in exactly 1 step', () {
      controller.history.recordState(controller.network);

      controller.network.attachCapToNode('n2');
      controller.history.recordState(controller.network);

      expect(network.fittings.values.any((f) => f.fittingType == FittingType.cap), isTrue);

      controller.undo();
      expect(network.fittings.values.any((f) => f.fittingType == FittingType.cap), isFalse);
      expect(network.segments.length, equals(1));
    });
  });
}
