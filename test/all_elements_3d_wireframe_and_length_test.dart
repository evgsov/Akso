import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/services/element_3d_geometry.dart';
import 'package:akso/ui/canvas/painters/pipe_painter.dart';

void main() {
  group('All Elements 3D Wireframe and Geometry Tests', () {
    test('generateReducerWireframe creates axial triangle pointing to smaller diameter', () {
      // Horizontal pipe along X axis: from (0,0,0) to (2000,0,0), reducer at (1000,0,0)
      // Large DN=100 (inlet from n1), Small DN=50 (outlet to n2)
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const nCenter = Node3D(id: 'nc', x: 1000, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);

      const reducer = Fitting(
        id: 'red1',
        nodeId: 'nc',
        fittingType: FittingType.reducerConcentric,
        name: 'Переход концентрический',
        dn: 100,
        dnSecondary: 50,
        radiusMm: 60.0,
        buildingLengthMm: 120.0,
      );



      final segments = Element3dGeometry.generateReducerWireframe(
        reducer,
        nCenter,
        n1,
        n2,
      );

      expect(segments, isNotEmpty);
      expect(segments.length, greaterThanOrEqualTo(4));

      // Check that the wireframe extends across building length (120 mm => +- 60 mm from center x=1000)
      final allX = segments.expand((s) => [s.x1, s.x2]).toList();
      final minX = allX.reduce((a, b) => math.min(a, b));
      final maxX = allX.reduce((a, b) => math.max(a, b));

      expect(minX, closeTo(940.0, 1.0));
      expect(maxX, closeTo(1060.0, 1.0));
    });

    test('generateReducerWireframe on vertical pipe orients along Z axis', () {
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const nCenter = Node3D(id: 'nc', x: 0, y: 0, z: 1000);
      const n2 = Node3D(id: 'n2', x: 0, y: 0, z: 2000);

      const reducer = Fitting(
        id: 'red1',
        nodeId: 'nc',
        fittingType: FittingType.reducerConcentric,
        name: 'Переход концентрический вертикальный',
        dn: 80,
        dnSecondary: 40,
        radiusMm: 50.0,
        buildingLengthMm: 100.0,
      );



      final segments = Element3dGeometry.generateReducerWireframe(
        reducer,
        nCenter,
        n1,
        n2,
      );

      expect(segments, isNotEmpty);
      final allZ = segments.expand((s) => [s.z1, s.z2]).toList();
      final minZ = allZ.reduce((a, b) => math.min(a, b));
      final maxZ = allZ.reduce((a, b) => math.max(a, b));

      expect(minZ, closeTo(950.0, 1.0));
      expect(maxZ, closeTo(1050.0, 1.0));
    });

    test('Reducer rotation around pipe axis modifies 3D wireframe points', () {
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const nCenter = Node3D(id: 'nc', x: 1000, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);



      const red0 = Fitting(
        id: 'red1',
        nodeId: 'nc',
        fittingType: FittingType.reducerEccentric,
        name: 'Переход эксцентрический',
        dn: 100,
        dnSecondary: 50,
        radiusMm: 50.0,
        buildingLengthMm: 100.0,
        rotationAngleDeg: 0.0,
      );

      const red90 = Fitting(
        id: 'red1',
        nodeId: 'nc',
        fittingType: FittingType.reducerEccentric,
        name: 'Переход эксцентрический 90',
        dn: 100,
        dnSecondary: 50,
        radiusMm: 50.0,
        buildingLengthMm: 100.0,
        rotationAngleDeg: 90.0,
      );

      final segs0 = Element3dGeometry.generateReducerWireframe(
        red0,
        nCenter,
        n1,
        n2,
      );

      final segs90 = Element3dGeometry.generateReducerWireframe(
        red90,
        nCenter,
        n1,
        n2,
      );

      // Rotating eccentric reducer by 90 degrees rotates the flat side from vertical to horizontal
      final allY0 = segs0.expand((s) => [s.y1, s.y2]).toList();
      final allY90 = segs90.expand((s) => [s.y1, s.y2]).toList();

      expect(allY0.reduce((a, b) => math.max(a, b)), isNot(closeTo(allY90.reduce((a, b) => math.max(a, b)), 1.0)));
    });

    test('generateValveWireframe supports all valve types with opposing triangles and controls', () {
      const p1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const p2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);

      for (final type in ValveType.values) {
        final v = Valve(
          id: 'v_${type.name}',
          segmentId: 's1',
          ratio: 0.5,
          valveType: type,
          name: type.displayName,
          dn: 80,
          lengthMm: 150.0,
          isFlanged: true,
        );

        final wireframe = Element3dGeometry.generateValveWireframe(
          v,
          p1,
          p2,
        );

        expect(wireframe, isNotEmpty, reason: 'Valve type ${type.name} wireframe should not be empty');
        expect(wireframe.length, greaterThanOrEqualTo(8));
      }
    });

    test('generateCapWireframe and generateFlangeWireframe generate true 3D vector geometry', () {
      const p1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const p2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);

      const cap = Fitting(
        id: 'cap1',
        nodeId: 'n2',
        fittingType: FittingType.cap,
        name: 'Заглушка',
        dn: 100,
        radiusMm: 25.0,
        buildingLengthMm: 50.0,
      );

      final capWire = Element3dGeometry.generateCapWireframe(
        cap,
        p2,
        p1,
      );
      expect(capWire, isNotEmpty);
      expect(capWire.length, greaterThanOrEqualTo(8));

      const flange = Fitting(
        id: 'fl1',
        nodeId: 'n2',
        fittingType: FittingType.flange,
        name: 'Фланец',
        dn: 100,
        radiusMm: 22.5,
        buildingLengthMm: 45.0,
      );

      final flangeWire = Element3dGeometry.generateFlangeWireframe(
        flange,
        p2,
        p1,
      );
      expect(flangeWire, isNotEmpty);
      expect(flangeWire.length, greaterThanOrEqualTo(4));
    });
  });

  group('Element Exact Length, Pipe Trimming and Spool Deductions', () {
    test('Reducer length updates properly recalculate spool cut lengths', () {
      final net = PipingNetwork();
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_1',
        dn: 100,
      );

      // Insert reducer at 1000 mm with new DN=50
      final reducerFit = net.insertReducer(
        segmentId: 's1',
        ratio: 0.5,
        newDn: 50,
      );
      expect(reducerFit, isNotNull);
      final reducerNodeId = reducerFit!.nodeId;

      // Reducer default length is max(80, 100*1.5) = 150 mm
      final redFit = net.fittings[reducerNodeId];
      expect(redFit, isNotNull);
      expect(redFit!.effectiveBuildingLengthMm, 150.0);

      // Initial spool deductions: each segment is 1000 mm center-to-center.
      // Deduction from reducer is L/2 = 75 mm each.
      final spoolsBefore = net.spools.values.toList();
      expect(spoolsBefore.length, 2);
      expect(spoolsBefore[0].cutLengthMm, closeTo(1000.0 - 75.0, 1.0));
      expect(spoolsBefore[1].cutLengthMm, closeTo(1000.0 - 75.0, 1.0));

      // Now user changes building length L to 200 mm ("чтобы катушки все бились")
      net.updateFittingLength(reducerNodeId, 200.0);

      expect(net.fittings[reducerNodeId]!.buildingLengthMm, 200.0);
      expect(net.fittings[reducerNodeId]!.effectiveBuildingLengthMm, 200.0);

      // Recalculated spools: deduction should now be 200/2 = 100 mm each
      final spoolsAfter = net.spools.values.toList();
      expect(spoolsAfter[0].cutLengthMm, closeTo(1000.0 - 100.0, 1.0));
      expect(spoolsAfter[1].cutLengthMm, closeTo(1000.0 - 100.0, 1.0));
    });

    test('Valve length updates properly recalculate spool cut lengths', () {
      final net = PipingNetwork();
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_1',
        dn: 100,
      );

      final v = net.addValve(
        segmentId: 's1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
      );

      // Default length for gate valve DN 100 is max(140, 100*2) = 200 mm
      expect(v.lengthMm, 200.0);

      // Initial cut length for 2000 mm pipe with valve in middle:
      // SpoolCalculator splits pipe at valve and deducts half valve length (100 mm) each
      final spoolsBefore = net.spools.values.toList();
      expect(spoolsBefore.length, 2);
      expect(spoolsBefore[0].cutLengthMm, closeTo(900.0, 1.0));
      expect(spoolsBefore[1].cutLengthMm, closeTo(900.0, 1.0));

      // User modifies valve length to 350 mm
      net.updateValveLength(v.id, 350.0);
      expect(net.valves[v.id]!.lengthMm, 350.0);

      final spoolsAfter = net.spools.values.toList();
      expect(spoolsAfter.length, 2);
      expect(spoolsAfter[0].cutLengthMm, closeTo(825.0, 1.0));
      expect(spoolsAfter[1].cutLengthMm, closeTo(825.0, 1.0));
    });

    test('calcPipeTrimmedPoint trims pipe line at reducer boundary', () {
      final net = PipingNetwork();
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_1',
        dn: 100,
      );

      net.fittings['n2'] = const Fitting(
        id: 'red1',
        nodeId: 'n2',
        fittingType: FittingType.reducerConcentric,
        name: 'Переход',
        dn: 100,
        dnSecondary: 50,
        radiusMm: 60.0,
        buildingLengthMm: 120.0,
      );

      final trimmed = PipePainter.calcPipeTrimmedPoint(
        network: net,
        nodeId: 'n2',
        otherNodeId: 'n1',
        nodeScreen: const Offset(1000, 0),
        otherScreen: const Offset(0, 0),
        seg: net.segments['s1']!,
      );

      // The point should be retracted from x=1000 by L/2 = 60 px towards x=0 => x=940
      expect(trimmed.dx, closeTo(940.0, 0.1));
      expect(trimmed.dy, closeTo(0.0, 0.1));
    });
  });
}
