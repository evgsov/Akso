import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/weld_joint_style.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/vector_scene.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/services/sheet_geometry_builder.dart';

void main() {
  group('SheetGeometryBuilder', () {
    test('builds scene with frame, pipes and spools without phantom gaps', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = PipeSegment(id: 'seg_1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'sys_1');
      network.segments[seg.id] = seg;

      // Add a weld in the middle
      final weld = WeldJoint(id: 'w1', segmentId: 'seg_1', ratio: 0.5, number: 1, stamp: 'W1');
      network.weldJoints[weld.id] = weld;
      network.recalculateSpools();

      expect(network.spools.length, equals(2));

      final sheet = DrawingSheet.createDefault(id: 'sheet_1', name: 'Лист 1', sheetNumber: 1);
      final scene = SheetGeometryBuilder.buildScene(sheet: sheet, network: network);

      expect(scene.widthMm, equals(sheet.format.widthMm));
      expect(scene.heightMm, equals(sheet.format.heightMm));

      final pipeItems = scene.items.where((it) => it.layer == VectorSceneLayer.pipes).toList();
      // Should have 2 polylines for the 2 spools, both having smoothJoin == true
      expect(pipeItems.length, equals(2));
      for (final it in pipeItems) {
        final poly = it.primitive as VectorPolyline;
        expect(poly.smoothJoin, isTrue);
        expect(poly.points.length, equals(2));
      }

      // Check weld item
      final weldItems = scene.items.where((it) => it.layer == VectorSceneLayer.welds).toList();
      expect(weldItems, isNotEmpty);

      // Check frame and stamp
      final frameItems = scene.items.where((it) => it.layer == VectorSceneLayer.frameAndStamp).toList();
      expect(frameItems, isNotEmpty);
    });

    test('builds elbow as a continuous smooth polyline rather than disconnected segments', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 1000, z: 0);
      final nCenter = Node3D(id: 'nCenter', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[nCenter.id] = nCenter;
      network.nodes[n2.id] = n2;

      final s1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'nCenter', dn: 50, systemId: 'sys_1');
      final s2 = PipeSegment(id: 's2', startNodeId: 'nCenter', endNodeId: 'n2', dn: 50, systemId: 'sys_1');
      network.segments[s1.id] = s1;
      network.segments[s2.id] = s2;

      final elbow = Fitting(id: 'fit_1', nodeId: 'nCenter', fittingType: FittingType.elbow90, dn: 50, radiusMm: 50.0);
      network.fittings[nCenter.id] = elbow;

      final sheet = DrawingSheet.createDefault(id: 'sheet_1', name: 'Лист 1', sheetNumber: 1);
      final scene = SheetGeometryBuilder.buildScene(sheet: sheet, network: network);

      final fittingItems = scene.items.where((it) => it.layer == VectorSceneLayer.fittings).toList();
      expect(fittingItems, isNotEmpty);

      final poly = fittingItems.first.primitive as VectorPolyline;
      expect(poly.smoothJoin, isTrue);
      // Continuous polyline has 9 points (8 segments)
      expect(poly.points.length, greaterThanOrEqualTo(8));
    });

    test('supports 3D ring style for welds', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'sys_1');
      network.segments[seg.id] = seg;

      final weld = WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.5, number: 1, stamp: 'W1', style: WeldJointStyle.ring3d);
      network.weldJoints[weld.id] = weld;

      final sheet = DrawingSheet.createDefault(id: 'sheet_1', name: 'Лист 1', sheetNumber: 1);
      final scene = SheetGeometryBuilder.buildScene(sheet: sheet, network: network);

      final weldItems = scene.items.where((it) => it.layer == VectorSceneLayer.welds).toList();
      // ring3d produces a 16-segment spatial ring
      expect(weldItems.length, equals(16));
      for (final it in weldItems) {
        final poly = it.primitive as VectorPolyline;
        expect(poly.smoothJoin, isTrue);
      }
    });
  });
}
