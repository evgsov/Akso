import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  test('Генерация реальных демонстрационных файлов DXF и журналов', () {
    final net = PipingNetwork();

    // Стояк В1
    net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
    net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 2800);
    net.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 80);

    // Магистраль вдоль Y
    net.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 3500, z: 2800);
    net.segments['seg2'] = const PipeSegment(id: 'seg2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_b1', dn: 80);

    // Врезка задвижки и затвора «баттерфляй»
    net.addValve(segmentId: 'seg2', ratio: 0.3, valveType: ValveType.gateValve, dn: 80);
    net.addValve(segmentId: 'seg2', ratio: 0.7, valveType: ValveType.butterflyValve, dn: 80);

    // Отвод 90° вглубь X
    net.nodes['n4'] = const Node3D(id: 'n4', x: 2000, y: 3500, z: 2800);
    net.segments['seg3'] = const PipeSegment(id: 'seg3', startNodeId: 'n3', endNodeId: 'n4', systemId: 'sys_b1', dn: 50);

    // Опуск к прибору
    net.nodes['n5'] = const Node3D(id: 'n5', x: 2000, y: 3500, z: 600);
    net.segments['seg4'] = const PipeSegment(id: 'seg4', startNodeId: 'n4', endNodeId: 'n5', systemId: 'sys_b1', dn: 50);

    net.addValve(segmentId: 'seg4', ratio: 0.5, valveType: ValveType.ballValve, dn: 50);

    // Врезка концентрического перехода Ду50 -> Ду32 на участке seg3
    net.insertReducer(segmentId: 'seg3', ratio: 0.5, newDn: 32, isEccentric: false);

    net.recalculateSpools();

    final dir = Directory('d:/Git/Akso/samples');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final dxf2d = DxfWriter.generate2dGostAxonometryDxf(net, projection: ProjectionType.gostFrontal45);
    File('d:/Git/Akso/samples/demo_gost_2d.dxf').writeAsStringSync(dxf2d);

    final dxf3d = DxfWriter.generate3dDxf(net);
    File('d:/Git/Akso/samples/demo_3d.dxf').writeAsStringSync(dxf3d);

    final weldCsv = DxfWriter.generateWeldJournalCsv(net);
    File('d:/Git/Akso/samples/weld_journal.csv').writeAsStringSync(weldCsv);

    final spoolsCsv = DxfWriter.generateSpoolsCsv(net);
    File('d:/Git/Akso/samples/spools_list.csv').writeAsStringSync(spoolsCsv);

    expect(File('d:/Git/Akso/samples/demo_gost_2d.dxf').existsSync(), isTrue);
    expect(File('d:/Git/Akso/samples/demo_3d.dxf').existsSync(), isTrue);
  });
}
