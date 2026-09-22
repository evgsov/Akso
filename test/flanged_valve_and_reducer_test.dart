import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/services/element_3d_geometry.dart';
import 'package:akso/domain/services/segment_positioning_service.dart';
import 'package:akso/domain/services/spool_calculator.dart';
import 'package:akso/domain/services/report_engine.dart';
import 'package:akso/domain/models/report_template.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/core/math/axonometry_projector.dart';

void main() {
  group('Flanged and Welded Valves Adaptation Tests', () {
    test('1. Insertion of plain (welded) vs flanged valve via PipingInputController', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      final seg = PipeSegment(
        id: 'seg1',
        startNodeId: n1.id,
        endNodeId: n2.id,
        dn: 50,
        systemId: 'sys1',
      );
      network.segments[seg.id] = seg;

      final controller = PipingInputController(
        network: network,
        projector: const AxonometryProjector(),
      );

      // Default is plain welded valve
      expect(controller.isValveFlanged, isFalse);
      expect(controller.valveFlangePressurePn, equals(16));
      expect(controller.valveIncludeCounterFlanges, isTrue);

      // Add welded check valve
      controller.setSelectedValveType(ValveType.checkValve);
      final weldedValve = network.addValve(
        segmentId: seg.id,
        ratio: 0.3,
        valveType: controller.selectedValveType,
        isFlanged: controller.isValveFlanged,
      );

      expect(weldedValve.isFlanged, isFalse);
      expect(weldedValve.valveType, equals(ValveType.checkValve));

      // Switch controller to flanged
      controller.setIsValveFlanged(true);
      controller.setValveFlangePressurePn(25);
      controller.setValveCounterFlangeType('ГОСТ 33259-2015 тип 11');

      final flangedValve = network.addValve(
        segmentId: seg.id,
        ratio: 0.7,
        valveType: controller.selectedValveType,
        isFlanged: controller.isValveFlanged,
        flangePressurePn: controller.valveFlangePressurePn,
        includeCounterFlanges: controller.valveIncludeCounterFlanges,
        counterFlangeType: controller.valveCounterFlangeType,
      );

      expect(flangedValve.isFlanged, isTrue);
      expect(flangedValve.flangePressurePn, equals(25));
      expect(flangedValve.includeCounterFlanges, isTrue);
      expect(flangedValve.counterFlangeType, equals('ГОСТ 33259-2015 тип 11'));
    });

    test('2. Check valve wireframe has NO stem, and flanges align with basis.u', () {
      final start = Node3D(id: 's', x: 0, y: 0, z: 0);
      final end = Node3D(id: 'e', x: 1000, y: 0, z: 0);

      final plainCheckValve = Valve(
        id: 'v1',
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.checkValve,
        name: 'Обратный клапан под приварку',
        dn: 50,
        lengthMm: 120.0,
        isFlanged: false,
      );

      final plainWires = Element3dGeometry.generateValveWireframe(
        plainCheckValve,
        start,
        end,
        pipeOuterDiameter: 57.0,
      );

      // Verify that NO wireframe segment goes from center straight up to stem height
      final center = plainCheckValve.calculatePosition(start, end);
      final hasVerticalStem = plainWires.any((w) =>
          (w.x1 == center.x && w.y1 == center.y && w.z1 == center.z) &&
          (w.z2 > center.z + 10.0 || w.y2 > center.y + 10.0));
      expect(hasVerticalStem, isFalse, reason: 'Check valve should not have a stem or handwheel');

      // Check flanged check valve
      final flangedCheckValve = plainCheckValve.copyWith(
        id: 'v2',
        isFlanged: true,
        includeCounterFlanges: true,
      );

      final flangedWires = Element3dGeometry.generateValveWireframe(
        flangedCheckValve,
        start,
        end,
        pipeOuterDiameter: 57.0,
      );

      // Flanged wireframe must have more segments due to flanges and counter-flanges
      expect(flangedWires.length, greaterThan(plainWires.length));

      // Flange bars must be drawn
      expect(flangedWires.any((w) => w.layer == Element3dGeometry.layerValves), isTrue);
    });

    test('3. Flow reversal (isReversed) flips directional check valve arrow in wireframe', () {
      final start = Node3D(id: 's', x: 0, y: 0, z: 0);
      final end = Node3D(id: 'e', x: 1000, y: 0, z: 0);

      final forwardValve = Valve(
        id: 'vf',
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.checkValve,
        name: 'КОП прямой',
        dn: 50,
        lengthMm: 120.0,
        isReversed: false,
      );

      final reverseValve = forwardValve.copyWith(isReversed: true);

      final wiresFwd = Element3dGeometry.generateValveWireframe(forwardValve, start, end);
      final wiresRev = Element3dGeometry.generateValveWireframe(reverseValve, start, end);

      // Arrow tip x-coordinate in forward should be > center.x, in reverse < center.x
      final center = forwardValve.calculatePosition(start, end);
      final fwdArrow = wiresFwd.firstWhere((w) => (w.x1 - center.x).abs() < 30.0 && w.x2 > center.x + 30.0);
      final revArrow = wiresRev.firstWhere((w) => (w.x1 - center.x).abs() < 30.0 && w.x2 < center.x - 30.0);

      expect(fwdArrow.x2, greaterThan(center.x));
      expect(revArrow.x2, lessThan(center.x));
    });

    test('4. Eccentric reducer followed immediately by flanged check valve with L1 = 0', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 200, y: 0, z: 0);
      final n3 = Node3D(id: 'n3', x: 1200, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      network.nodes[n3.id] = n3;

      // Seg 1 (DN80) before reducer
      final segIn = PipeSegment(id: 'seg_in', startNodeId: n1.id, endNodeId: n2.id, dn: 80, systemId: 'sys1');
      network.segments[segIn.id] = segIn;

      // Reducer at n2: DN80 -> DN50 eccentric
      network.fittings[n2.id] = Fitting(
        id: 'red1',
        nodeId: n2.id,
        fittingType: FittingType.reducerEccentric,
        dn: 80,
        dnSecondary: 50,
        radiusMm: 0,
        buildingLengthMm: 100.0, // 50mm deduction into seg_out
      );

      // Seg 2 (DN50) after reducer: total length 1000mm
      final segOut = PipeSegment(
        id: 'seg_out',
        startNodeId: n2.id,
        endNodeId: n3.id,
        dn: 50,
        systemId: 'sys1',
      );
      network.segments[segOut.id] = segOut;

      // Flanged check valve on seg_out, length 120mm
      final checkValve = network.addValve(
        segmentId: segOut.id,
        ratio: 0.5,
        valveType: ValveType.checkValve,
        dn: 50,
        customLengthMm: 120.0,
        isFlanged: true,
        flangePressurePn: 16,
        includeCounterFlanges: true,
      );

      // The reducer deduction at n2 for seg_out is 50mm (100 / 2)
      final deduction = SpoolCalculator.getFittingDeduction(network, n2.id, segmentId: segOut.id);
      expect(deduction, closeTo(50.0, 0.1));

      // Dock flush inстык: L1 = 0
      // Assembly length = 120 + 2 * 45 = 210 mm, half-length = 105 mm
      final flushRatio = SegmentPositioningService.calculateRatioFromLengthToPrev(
        network,
        segOut.id,
        0.0, // 0 mm to reducer
        elementLengthMm: checkValve.effectiveTotalLengthMm,
        currentElementId: checkValve.id,
        currentRatio: checkValve.ratio,
      );

      // Valve upstream collar should be exactly at 50mm:
      // ratio * 1000 - 105 == 50 => ratio * 1000 == 155 => ratio == 0.155
      expect(flushRatio, closeTo(0.155, 0.001));

      // Update valve with flush ratio
      network.updateValve(checkValve.id, checkValve.copyWith(ratio: flushRatio));

      // Check position info
      final posInfo = SegmentPositioningService.getPositionInfo(
        network,
        segOut.id,
        flushRatio,
        elementLengthMm: checkValve.effectiveTotalLengthMm,
        currentElementId: checkValve.id,
      );

      expect(posInfo.lengthToPrevMm, closeTo(0.0, 0.01));
      expect(posInfo.prevItemLabel, contains('Переход'));

      // Check SpoolCalculator: no fake 0-mm spool should be created between reducer and valve!
      network.recalculateSpools();

      // Only 1 spool after the valve to the end should exist on seg_out:
      // 1000 - 50 - 210 = 740 mm
      final segOutSpools = network.spools.values.where((sp) => sp.segmentId == segOut.id).toList();
      expect(segOutSpools.length, equals(1));
      expect(segOutSpools.first.cutLengthMm, closeTo(1000.0 - 50.0 - 210.0, 1.0));
    });

    test('5. Automatic collapseSegmentToButtJoint on Reducer + Flanged Valve', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 200, y: 0, z: 0);
      final n3 = Node3D(id: 'n3', x: 800, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      network.nodes[n3.id] = n3;

      final segIn = PipeSegment(id: 'seg_in', startNodeId: n1.id, endNodeId: n2.id, dn: 80, systemId: 'sys1');
      network.segments[segIn.id] = segIn;

      network.fittings[n2.id] = Fitting(
        id: 'red1',
        nodeId: n2.id,
        fittingType: FittingType.reducerEccentric,
        dn: 80,
        dnSecondary: 50,
        radiusMm: 0,
        buildingLengthMm: 100.0, // 50mm deduction into seg_out
      );

      final segOut = PipeSegment(
        id: 'seg_out',
        startNodeId: n2.id,
        endNodeId: n3.id,
        dn: 50,
        systemId: 'sys1',
      );
      network.segments[segOut.id] = segOut;

      final valve = network.addValve(
        segmentId: segOut.id,
        ratio: 0.5,
        valveType: ValveType.checkValve,
        dn: 50,
        customLengthMm: 140.0,
        isFlanged: true,
        flangePressurePn: 16,
        includeCounterFlanges: true,
      );

      expect(network.isConnectingFittingsSegment(segOut.id), isTrue);
      // Target length = d1 (50) + d2 (0) + valve.effectiveTotalLengthMm (140 + 90 = 230) = 280 mm
      final targetLen = network.getButtJointTargetLength(segOut.id);
      expect(targetLen, closeTo(280.0, 0.1));
      expect(network.getButtJointLabel(segOut.id), contains('Переход'));
      expect(network.getButtJointLabel(segOut.id), contains('обратный'));

      // Collapse to butt joint
      final collapsed = network.collapseSegmentToButtJoint(segOut.id);
      expect(collapsed, isTrue);

      final n2Updated = network.nodes[n2.id]!;
      final n3Updated = network.nodes[n3.id]!;
      expect(n2Updated.distanceTo(n3Updated), closeTo(280.0, 0.5));
      expect(network.isButtJoint(segOut.id), isTrue);

      // Valve should be centered at (50 + 115) / 280 = 165 / 280
      final updatedValve = network.valves[valve.id]!;
      expect(updatedValve.ratio * 280.0, closeTo(165.0, 0.5));

      // No spools on segOut because both sides are butt joints (length 0 <= 1.0 mm)
      final spools = network.spools.values.where((sp) => sp.segmentId == segOut.id).toList();
      expect(spools.isEmpty, isTrue);

      // Verify weld joints: weld at collar contact with reducer (C17)
      final welds = network.weldJoints.values.where((w) => w.segmentId == segOut.id).toList();
      expect(welds.isNotEmpty, isTrue);
      expect(welds.every((w) => w.weldType == WeldType.c17), isTrue);
    });

    test('6. Flexible counter flange parameters (custom collar length and flat welded flange type 01)', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      final seg = PipeSegment(id: 'seg1', startNodeId: n1.id, endNodeId: n2.id, dn: 100, systemId: 'sys1');
      network.segments[seg.id] = seg;

      // Valve with customized collar length 55 mm and material 09Г2С
      final valve1 = network.addValve(
        segmentId: seg.id,
        ratio: 0.3,
        valveType: ValveType.gateValve,
        dn: 100,
        customLengthMm: 200.0,
        isFlanged: true,
        includeCounterFlanges: true,
        counterFlangeType: 'ГОСТ 33259-2015 тип 11',
        counterFlangeLengthMm: 55.0,
        counterFlangeMaterial: '09Г2С',
      );

      expect(valve1.effectiveCounterFlangeLengthMm, equals(55.0));
      expect(valve1.effectiveTotalLengthMm, equals(310.0)); // 200 + 2 * 55
      expect(valve1.effectiveHalfLengthMm, equals(155.0));
      expect(valve1.effectiveCounterFlangeMaterial, equals('09Г2С'));

      // Valve with flat welded flanges (type 01)
      final valve2 = network.addValve(
        segmentId: seg.id,
        ratio: 0.7,
        valveType: ValveType.ballValve,
        dn: 100,
        customLengthMm: 150.0,
        isFlanged: true,
        includeCounterFlanges: true,
        counterFlangeType: 'ГОСТ 33259-2015 тип 01',
      );

      expect(valve2.effectiveCounterFlangeLengthMm, equals(35.0)); // default for type 01
      expect(valve2.effectiveTotalLengthMm, equals(220.0)); // 150 + 2 * 35
      expect(valve2.counterFlangeWeldType, equals(WeldType.c2));
    });

    test('7. ReportEngine adds flanged valve counter-flanges to specification', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      final seg = PipeSegment(id: 'seg1', startNodeId: n1.id, endNodeId: n2.id, dn: 50, systemId: 'sys1');
      network.segments[seg.id] = seg;

      network.addValve(
        segmentId: seg.id,
        ratio: 0.5,
        valveType: ValveType.checkValve,
        dn: 50,
        isFlanged: true,
        includeCounterFlanges: true,
        flangePressurePn: 16,
        counterFlangeType: 'ГОСТ 33259-2015 тип 11',
        counterFlangeMaterial: 'Сталь 20',
      );

      final rows = ReportEngine.generateTableData(
        ReportTemplate.defaultMtoGostTemplate,
        network,
      );

      // Find flange row in report
      final flangeRow = rows.firstWhere(
        (row) => row.any((cell) => cell.toString().contains('Фланец') && cell.toString().contains('50')),
        orElse: () => [],
      );

      expect(flangeRow, isNotEmpty);
      // Qty should be 2 (pair of counter flanges)
      expect(flangeRow.any((cell) => cell == 2 || cell == '2' || cell == 2.0), isTrue);
    });
  });
}
