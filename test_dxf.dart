import 'dart:io';
import 'lib/domain/models/piping_network.dart';
import 'lib/domain/models/node_3d.dart';
import 'lib/domain/models/pipe_segment.dart';
import 'lib/data/dxf/dxf_writer.dart';

void main() {
  final net = PipingNetwork();
  net.nodes['1'] = Node3D(id: '1', x: 0, y: 0, z: 0);
  net.nodes['2'] = Node3D(id: '2', x: 100, y: 0, z: 0);
  net.segments['s1'] = PipeSegment(id: 's1', startNodeId: '1', endNodeId: '2', systemId: 'sys1', dn: 50, material: 'Steel', wallThicknessMm: 3.0);
  final dxf = DxfWriter.generate3dDxf(net);
  File('output_test.dxf').writeAsStringSync(dxf);
}
