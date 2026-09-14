import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/domain/models/linear_dimension.dart';
import 'package:akso/domain/models/callout.dart';

void main() {
  test('Verify DXF generation for AutoCAD 2024', () {
    final net = PipingNetwork();
    net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
    net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 2800);
    net.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 3500, z: 2800);
    net.nodes['n4'] = const Node3D(id: 'n4', x: 2000, y: 3500, z: 2800);
    net.nodes['n5'] = const Node3D(id: 'n5', x: 2000, y: 3500, z: 600);

    net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 50);
    net.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_b1', dn: 50);
    net.segments['s3'] = const PipeSegment(id: 's3', startNodeId: 'n3', endNodeId: 'n4', systemId: 'sys_b1', dn: 80);
    net.segments['s4'] = const PipeSegment(id: 's4', startNodeId: 'n4', endNodeId: 'n5', systemId: 'sys_b1', dn: 80);

    net.addValve(segmentId: 's2', ratio: 0.5, valveType: ValveType.gateValve, dn: 50);
    net.recalculateSpools();

    net.axes['a1'] = const ConstructionAxis(id: 'a1', startPoint: Node3D(id: 'p1', x: -500, y: 0, z: 0), endPoint: Node3D(id: 'p2', x: 2500, y: 0, z: 0), label: '1', isBuildingGrid: true);
    net.axes['a2'] = const ConstructionAxis(id: 'a2', startPoint: Node3D(id: 'p3', x: 0, y: -500, z: 0), endPoint: Node3D(id: 'p4', x: 0, y: 4000, z: 0), label: 'А', isBuildingGrid: true);
    net.axes['a3'] = const ConstructionAxis(id: 'a3', startPoint: Node3D(id: 'p5', x: 500, y: -500, z: 0), endPoint: Node3D(id: 'p6', x: 500, y: 4000, z: 0), label: '', isBuildingGrid: false);

    net.dimensions['d1'] = const LinearDimension(id: 'd1', startPoint: Node3D(id: 'dp1', x: 0, y: 0, z: 2800), endPoint: Node3D(id: 'dp2', x: 0, y: 3500, z: 2800));

    net.callouts['c1'] = const Callout(id: 'c1', targetId: 's1', targetType: CalloutTargetType.segment, screenOffsetX: 50.0, screenOffsetY: -50.0);

    final dxf3d = DxfWriter.generate3dDxf(net);
    File('test_generated_3d.dxf').writeAsStringSync(dxf3d);

    final dxf2d = DxfWriter.generate2dGostAxonometryDxf(net);
    File('test_generated_2d.dxf').writeAsStringSync(dxf2d);

    const acadPath = r'C:\Program Files\Autodesk\AutoCAD 2024\accoreconsole.exe';
    if (File(acadPath).existsSync()) {
      final scr2d = File('test_run_2d.scr');
      scr2d.writeAsStringSync('_DXFIN "${File('test_generated_2d.dxf').absolute.path}"\n_QUIT\n_Y\n');
      final res2d = Process.runSync(acadPath, ['/s', scr2d.absolute.path]);
      scr2d.deleteSync();
      expect(res2d.exitCode, equals(0));
      expect(res2d.stdout.toString().contains('DXF -'), isFalse);

      final scr3d = File('test_run_3d.scr');
      scr3d.writeAsStringSync('_DXFIN "${File('test_generated_3d.dxf').absolute.path}"\n_QUIT\n_Y\n');
      final res3d = Process.runSync(acadPath, ['/s', scr3d.absolute.path]);
      scr3d.deleteSync();
      expect(res3d.exitCode, equals(0));
      expect(res3d.stdout.toString().contains('DXF -'), isFalse);
    }
  });
}
