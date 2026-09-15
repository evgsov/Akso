import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/services/element_3d_geometry.dart';

void main() {
  group('Element3dGeometry Tests', () {
    test('generateValve3d creates 3D wireframe lines for gate valve', () {
      final p1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final p2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      const valve = Valve(
        id: 'v1',
        segmentId: 's1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Задвижка',
        dn: 100,
        lengthMm: 200,
        isFlanged: true,
      );

      final lines = Element3dGeometry.generateValve3d(
        valve,
        p1,
        p2,
        pipeOuterDiameter: 114.0,
      );

      expect(lines, isNotEmpty);
      expect(lines.every((l) => l.x1 != l.x2 || l.y1 != l.y2 || l.z1 != l.z2), isTrue);
      expect(lines.length, greaterThan(20));
    });

    test('generateWeld3d creates circular seam and ticks', () {
      final p1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final p2 = const Node3D(id: 'n2', x: 0, y: 1000, z: 0);
      const weld = WeldJoint(
        id: 'w1',
        segmentId: 's1',
        ratio: 0.3,
        number: 1,
        stamp: 'ИВ-01',
      );

      final lines = Element3dGeometry.generateWeld3d(
        weld,
        p1,
        p2,
        pipeOuterDiameter: 89.0,
      );

      expect(lines, isNotEmpty);
      expect(lines.length, greaterThanOrEqualTo(16));
    });

    test('generateSupport3d creates clamp and footplate lines', () {
      final p1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final p2 = const Node3D(id: 'n2', x: 0, y: 0, z: 1000);
      const support = PipeSupport(
        id: 'sup1',
        segmentId: 's1',
        distanceRatio: 0.5,
        type: PipeSupportType.sliding,
        name: 'ОП-1',
      );

      final lines = Element3dGeometry.generateSupport3d(
        support,
        p1,
        p2,
        pipeOuterDiameter: 159.0,
      );

      expect(lines, isNotEmpty);
      expect(lines.length, greaterThanOrEqualTo(8));
    });

    test('generateFlange3d and generateCap3d create geometry', () {
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 500, y: 0, z: 0);

      const flange = Fitting(
        id: 'f1',
        nodeId: 'n1',
        dn: 50,
        radiusMm: 0,
        fittingType: FittingType.flange,
        name: 'Фланец',
      );
      final flangeLines = Element3dGeometry.generateFlange3d(
        flange,
        n1,
        n2,
        pipeOuterDiameter: 57.0,
      );
      expect(flangeLines, isNotEmpty);

      const cap = Fitting(
        id: 'f2',
        nodeId: 'n1',
        dn: 50,
        radiusMm: 0,
        fittingType: FittingType.cap,
        name: 'Заглушка',
      );
      final capLines = Element3dGeometry.generateCap3d(
        cap,
        n1,
        n2,
        pipeOuterDiameter: 57.0,
      );
      expect(capLines, isNotEmpty);
    });

    test('generateAllElements3d collects all elements across network', () {
      final net = PipingNetwork();
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50);

      net.addValve(
        segmentId: 's1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
      );
      net.addWeldJoint(
        segmentId: 's1',
        ratio: 0.2,
      );
      net.supports['sup1'] = const PipeSupport(
        id: 'sup1',
        segmentId: 's1',
        distanceRatio: 0.8,
        type: PipeSupportType.fixed,
      );

      final allLines = Element3dGeometry.generateAllElements3d(net);
      expect(allLines, isNotEmpty);
      expect(allLines.length, greaterThan(30));
    });
  });

  group('3D DXF Export with 3D Wireframe Elements', () {
    test('generate3dDxf includes 3D layers and wireframe entities for elements', () {
      final net = PipingNetwork();
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 80);

      net.addValve(
        segmentId: 's1',
        ratio: 0.4,
        valveType: ValveType.ballValve,
        isFlanged: true,
      );
      net.addWeldJoint(
        segmentId: 's1',
        ratio: 0.1,
        stamp: 'АК-01',
      );
      net.supports['sup1'] = const PipeSupport(
        id: 'sup1',
        segmentId: 's1',
        distanceRatio: 0.7,
        type: PipeSupportType.sliding,
      );

      final dxf = DxfWriter.generate3dDxf(net);

      final valveLayer = DxfWriter.toAutoCadString(Element3dGeometry.layerValves);
      final weldLayer = DxfWriter.toAutoCadString(Element3dGeometry.layerWelds);
      final supportLayer = DxfWriter.toAutoCadString(Element3dGeometry.layerSupports);

      // Verify layer headers
      expect(dxf.contains(valveLayer), isTrue);
      expect(dxf.contains(weldLayer), isTrue);
      expect(dxf.contains(supportLayer), isTrue);

      // Verify ENTITIES section has 3D LINEs on element layers
      expect(dxf.contains('8\n$valveLayer') || dxf.contains('8\r\n$valveLayer'), isTrue);
      expect(dxf.contains('8\n$weldLayer') || dxf.contains('8\r\n$weldLayer'), isTrue);
      expect(dxf.contains('8\n$supportLayer') || dxf.contains('8\r\n$supportLayer'), isTrue);

      // Verify EOF
      expect(dxf.contains('EOF'), isTrue);
    });
  });
}
