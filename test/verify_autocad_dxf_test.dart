import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/enums/valve_type.dart';

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

    final dxf3d = DxfWriter.generate3dDxf(net);
    File('test_generated_3d.dxf').writeAsStringSync(dxf3d);

    final dxf2d = DxfWriter.generate2dGostAxonometryDxf(net);
    File('test_generated_2d.dxf').writeAsStringSync(dxf2d);
  });
}
