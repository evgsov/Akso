import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/inspection_method.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/services/report_engine.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/node_3d.dart';

void main() {
  group('Composite inspection methods in WeldJoint', () {
    test('supports multiple inspection methods and formats them as string', () {
      final joint = WeldJoint(
        id: 'wj_1',
        segmentId: 'seg_1',
        ratio: 0.5,
        number: 1,
        stamp: 'СВ-01',
        inspectionMethods: const [
          InspectionMethod.vik,
          InspectionMethod.uzk,
          InspectionMethod.pvk,
        ],
      );
      expect(joint.inspectionMethods.length, equals(3));
      expect(joint.formattedInspectionMethods, equals('ВИК, УЗК, ПВК'));
      // Backward compatibility getter
      expect(joint.inspectionMethod, equals(InspectionMethod.vik));
    });

    test('toJson and fromJson preserves composite inspectionMethods list', () {
      final joint = WeldJoint(
        id: 'wj_2',
        segmentId: 'seg_1',
        ratio: 0.2,
        number: 2,
        stamp: 'СВ-02',
        inspectionMethods: const [
          InspectionMethod.vik,
          InspectionMethod.rk,
          InspectionMethod.mpk,
        ],
      );

      final json = joint.toJson();
      final restored = WeldJoint.fromJson(json);

      expect(restored.inspectionMethods.length, equals(3));
      expect(restored.inspectionMethods, contains(InspectionMethod.vik));
      expect(restored.inspectionMethods, contains(InspectionMethod.rk));
      expect(restored.inspectionMethods, contains(InspectionMethod.mpk));
      expect(restored.formattedInspectionMethods, equals('ВИК, РК, МПК'));
    });

    test('ReportEngine evaluates composite inspection tokens', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = PipeSegment(
        id: 'seg_1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        dn: 50,
        systemId: 'sys_b1',
      );
      network.segments[seg.id] = seg;
      final joint = WeldJoint(
        id: 'wj_3',
        segmentId: 'seg_1',
        ratio: 0.5,
        number: 1,
        stamp: 'ИВ-1',
        inspectionMethods: const [InspectionMethod.vik, InspectionMethod.rk],
      );
      network.weldJoints[joint.id] = joint;

      final ctx = ReportEngine.resolveWeldContext(joint, network, 1);
      expect(ReportEngine.evaluateTemplateString('{weld_inspection}', ctx), equals('ВИК, РК'));
      expect(ReportEngine.evaluateTemplateString('{weld_has_vik}', ctx), equals('Да'));
      expect(ReportEngine.evaluateTemplateString('{weld_has_rk}', ctx), equals('Да'));
      expect(ReportEngine.evaluateTemplateString('{weld_has_uzk}', ctx), equals('Нет'));
    });
  });
}
