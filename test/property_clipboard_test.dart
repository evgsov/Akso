import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/inspection_method.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/enums/weld_joint_style.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/property_clipboard.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('ElementPropertySnapshot & PropertyCopyOptions', () {
    test('copies Valve properties to another Valve of the same DN and preserves target ID/position/serial by default', () {
      const source = Valve(
        id: 'v_src',
        segmentId: 'seg_1',
        ratio: 0.3,
        valveType: ValveType.ballValve,
        dn: 50,
        name: 'Кран шаровой 11с67п',
        lengthMm: 210,
        handleAngleDeg: 90,
        isReversed: true,
        isFlanged: true,
        flangePressurePn: 25,
        includeCounterFlanges: true,
        counterFlangeType: 'ГОСТ 33259-2015 тип 11',
        counterFlangeLengthMm: 52,
        counterFlangeMaterial: '09Г2С',
        serialNumber: 'ЗАВ-001',
        mark: 'КШ-1',
      );

      const target = Valve(
        id: 'v_dst',
        segmentId: 'seg_2',
        ratio: 0.7,
        valveType: ValveType.gateValve,
        dn: 50,
        name: 'Задвижка 30с41нж',
        lengthMm: 180,
        isFlanged: false,
        flangePressurePn: 16,
        includeCounterFlanges: false,
        counterFlangeMaterial: 'Сталь 20',
        serialNumber: 'ЗАВ-999',
        mark: 'З-2',
      );

      final snapshot = ElementPropertySnapshot.fromValve(source);
      final updated = snapshot.applyToValve(
        target,
        options: const PropertyCopyOptions(
          copyMaterialAndStandard: true,
          copyDimensionsAndType: true,
          copySerialAndMark: false,
        ),
      );

      expect(updated.id, equals('v_dst'));
      expect(updated.segmentId, equals('seg_2'));
      expect(updated.ratio, equals(0.7));
      expect(updated.valveType, equals(ValveType.ballValve));
      expect(updated.name, equals('Кран шаровой 11с67п'));
      expect(updated.lengthMm, equals(210));
      expect(updated.handleAngleDeg, equals(90));
      expect(updated.isFlanged, isTrue);
      expect(updated.flangePressurePn, equals(25));
      expect(updated.includeCounterFlanges, isTrue);
      expect(updated.counterFlangeLengthMm, equals(52));
      expect(updated.counterFlangeMaterial, equals('09Г2С'));
      // Serial and mark are preserved when copySerialAndMark is false
      expect(updated.serialNumber, equals('ЗАВ-999'));
      expect(updated.mark, equals('З-2'));

      // Now with copySerialAndMark: true
      final updatedWithSerial = snapshot.applyToValve(
        target,
        options: const PropertyCopyOptions(
          copyMaterialAndStandard: true,
          copyDimensionsAndType: true,
          copySerialAndMark: true,
        ),
      );
      expect(updatedWithSerial.serialNumber, equals('ЗАВ-001'));
      expect(updatedWithSerial.mark, equals('КШ-1'));
    });

    test('copies Valve properties to another Valve of different DN without overwriting DN-specific lengths', () {
      const source = Valve(
        id: 'v_src',
        segmentId: 'seg_1',
        ratio: 0.3,
        valveType: ValveType.ballValve,
        dn: 50,
        name: 'Кран шаровой фланцевый',
        lengthMm: 210,
        isFlanged: true,
        flangePressurePn: 40,
        includeCounterFlanges: true,
        counterFlangeMaterial: '09Г2С',
        counterFlangeLengthMm: 52,
      );

      const target = Valve(
        id: 'v_dst',
        segmentId: 'seg_2',
        ratio: 0.5,
        valveType: ValveType.ballValve,
        name: 'Кран шаровой',
        dn: 100,
        lengthMm: 300,
        isFlanged: false,
        flangePressurePn: 16,
      );

      final snapshot = ElementPropertySnapshot.fromValve(source);
      final updated = snapshot.applyToValve(target);

      expect(updated.dn, equals(100));
      expect(updated.lengthMm, equals(300)); // Preserved for DN100
      expect(updated.isFlanged, isTrue);
      expect(updated.flangePressurePn, equals(40));
      expect(updated.includeCounterFlanges, isTrue);
      expect(updated.counterFlangeMaterial, equals('09Г2С'));
    });

    test('copies Fitting properties between elbows and preserves 1.0 DN vs 1.5 DN radius factor across different DNs', () {
      const sourceElbow = Fitting(
        id: 'f_src',
        nodeId: 'n1',
        fittingType: FittingType.elbow90,
        dn: 100,
        name: 'Отвод 90° крутоизогнутый 1D',
        standard: 'ГОСТ 17375-2001 исп. 1',
        material: '09Г2С',
        weldType: WeldType.c17,
        radiusMm: 100.0,
        customRadiusMm: 100.0, // 1.0 DN
      );

      const targetElbowSameDn = Fitting(
        id: 'f_dst_100',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        dn: 100,
        name: 'Отвод 90°',
        standard: 'ГОСТ 17375-2001',
        material: 'Сталь 20',
        radiusMm: 150.0,
      );

      const targetElbowDiffDn = Fitting(
        id: 'f_dst_200',
        nodeId: 'n3',
        fittingType: FittingType.elbow90,
        dn: 200,
        name: 'Отвод 90°',
        standard: 'ГОСТ 17375-2001',
        material: 'Сталь 20',
        radiusMm: 300.0, // 1.5 DN initially
      );

      final snapshot = ElementPropertySnapshot.fromFitting(sourceElbow);

      final updatedSameDn = snapshot.applyToFitting(targetElbowSameDn);
      expect(updatedSameDn.material, equals('09Г2С'));
      expect(updatedSameDn.standard, equals('ГОСТ 17375-2001 исп. 1'));
      expect(updatedSameDn.effectiveRadiusMm, equals(100.0));

      final updatedDiffDn = snapshot.applyToFitting(targetElbowDiffDn);
      expect(updatedDiffDn.material, equals('09Г2С'));
      expect(updatedDiffDn.standard, equals('ГОСТ 17375-2001 исп. 1'));
      expect(updatedDiffDn.effectiveRadiusMm, equals(200.0)); // Scaled 1.0 * DN200!
    });

    test('supports cross-copying common flange properties between Flange Fitting and Flanged Valve', () {
      const sourceFlange = Fitting(
        id: 'fl_1',
        nodeId: 'n1',
        fittingType: FittingType.flange,
        dn: 50,
        radiusMm: 0,
        name: 'Фланец воротниковый',
        standard: 'ГОСТ 33259-2015 тип 11',
        material: '12Х18Н10Т',
        pressurePn: 25,
        buildingLengthMm: 48.0,
      );

      const targetValve = Valve(
        id: 'v_1',
        segmentId: 's1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Задвижка',
        dn: 50,
        lengthMm: 180,
        isFlanged: true,
        flangePressurePn: 16,
        includeCounterFlanges: true,
        counterFlangeMaterial: 'Сталь 20',
      );

      final snapFromFlange = ElementPropertySnapshot.fromFitting(sourceFlange);
      final updatedValve = snapFromFlange.applyToValve(targetValve);
      expect(updatedValve.flangePressurePn, equals(25));
      expect(updatedValve.counterFlangeMaterial, equals('12Х18Н10Т'));
      expect(updatedValve.counterFlangeType, equals('ГОСТ 33259-2015 тип 11'));
      expect(updatedValve.counterFlangeLengthMm, equals(48.0));

      // And reverse: from Flanged Valve to Flange Fitting
      final snapFromValve = ElementPropertySnapshot.fromValve(updatedValve);
      const targetFlange = Fitting(
        id: 'fl_2',
        nodeId: 'n2',
        fittingType: FittingType.flange,
        dn: 50,
        radiusMm: 0,
        name: 'Фланец',
        standard: 'ГОСТ 33259-2015 тип 01',
        material: 'Сталь 20',
        pressurePn: 10,
      );
      final updatedFlange = snapFromValve.applyToFitting(targetFlange);
      expect(updatedFlange.pressurePn, equals(25));
      expect(updatedFlange.material, equals('12Х18Н10Т'));
      expect(updatedFlange.standard, equals('ГОСТ 33259-2015 тип 11'));
      expect(updatedFlange.buildingLengthMm, equals(48.0));
    });

    test('copies PipeSegment, PipeSupport, and WeldJoint properties', () {
      const srcSeg = PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_t3',
        dn: 100,
        outerDiameterMm: 108,
        wallThicknessMm: 4.0,
        material: '09Г2С',
        name: 'Магистраль Т3',
        serialNumber: 'ПЛ-77',
      );
      const dstSeg = PipeSegment(
        id: 's2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys_b1',
        dn: 50,
        wallThicknessMm: 3.5,
        material: 'Сталь 20',
      );
      final segSnap = ElementPropertySnapshot.fromSegment(srcSeg);
      final updatedSeg = segSnap.applyToSegment(
        dstSeg,
        options: const PropertyCopyOptions(copySerialAndMark: true),
      );
      expect(updatedSeg.id, equals('s2'));
      expect(updatedSeg.systemId, equals('sys_t3'));
      expect(updatedSeg.dn, equals(100));
      expect(updatedSeg.wallThicknessMm, equals(4.0));
      expect(updatedSeg.material, equals('09Г2С'));
      expect(updatedSeg.serialNumber, equals('ПЛ-77'));

      const srcSup = PipeSupport(
        id: 'sup1',
        segmentId: 's1',
        distanceRatio: 0.2,
        type: PipeSupportType.fixed,
        name: 'НО-100',
        mark: 'НО-1',
      );
      const dstSup = PipeSupport(
        id: 'sup2',
        segmentId: 's2',
        distanceRatio: 0.8,
        type: PipeSupportType.sliding,
        name: 'ОП-50',
      );
      final supSnap = ElementPropertySnapshot.fromSupport(srcSup);
      final updatedSup = supSnap.applyToSupport(dstSup);
      expect(updatedSup.type, equals(PipeSupportType.fixed));
      expect(updatedSup.name, equals('НО-100'));
      expect(updatedSup.distanceRatio, equals(0.8));

      const srcWeld = WeldJoint(
        id: 'w1',
        segmentId: 's1',
        ratio: 0.5,
        number: 1,
        stamp: 'КЛ-99',
        weldType: WeldType.u18,
        inspectionMethods: [InspectionMethod.vik, InspectionMethod.uzk],
        steelGrade: '09Г2С',
        electrodeGrade: 'LB-52U',
        style: WeldJointStyle.circle,
      );
      const dstWeld = WeldJoint(
        id: 'w2',
        segmentId: 's2',
        ratio: 0.5,
        number: 2,
        stamp: 'ИВ-24',
      );
      final weldSnap = ElementPropertySnapshot.fromWeld(srcWeld);
      final updatedWeld = weldSnap.applyToWeld(dstWeld);
      expect(updatedWeld.number, equals(2));
      expect(updatedWeld.stamp, equals('КЛ-99'));
      expect(updatedWeld.weldType, equals(WeldType.u18));
      expect(updatedWeld.inspectionMethods, equals([InspectionMethod.vik, InspectionMethod.uzk]));
      expect(updatedWeld.steelGrade, equals('09Г2С'));
      expect(updatedWeld.electrodeGrade, equals('LB-52U'));
      expect(updatedWeld.style, equals(WeldJointStyle.circle));
    });

    test('PipingInputController batch applies properties to all similar valves and supports Undo', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      final n3 = Node3D(id: 'n3', x: 3000, y: 3000, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;
      network.addSegment(const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50));
      network.addSegment(const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', dn: 100));

      final v1 = network.addValve(
        segmentId: 's1',
        ratio: 0.3,
        valveType: ValveType.gateValve,
        dn: 50,
        isFlanged: true,
        flangePressurePn: 25,
        includeCounterFlanges: true,
        counterFlangeMaterial: '09Г2С',
      );
      final v2 = network.addValve(
        segmentId: 's1',
        ratio: 0.7,
        valveType: ValveType.gateValve,
        dn: 50,
        isFlanged: false,
        flangePressurePn: 16,
      );
      final v3 = network.addValve(
        segmentId: 's2',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
        isFlanged: false,
        flangePressurePn: 16,
      );

      final controller = PipingInputController(network: network);
      controller.selectedValveId = v1.id;

      // Count targets
      expect(controller.countSimilarTargets(sameDnOnly: true), equals(1)); // Only v2
      expect(controller.countSimilarTargets(sameDnOnly: false), equals(2)); // v2 and v3

      // Apply to same DN only (v2)
      final updatedCountSameDn = controller.applySelectedPropertiesToSimilar(sameDnOnly: true);
      expect(updatedCountSameDn, equals(1));
      expect(network.valves[v2.id]!.isFlanged, isTrue);
      expect(network.valves[v2.id]!.flangePressurePn, equals(25));
      expect(network.valves[v2.id]!.counterFlangeMaterial, equals('09Г2С'));
      expect(network.valves[v3.id]!.isFlanged, isFalse);

      // Undo restores v2
      controller.undo();
      expect(network.valves[v2.id]!.isFlanged, isFalse);

      // Apply to all gate valves of any DN (v2 and v3)
      controller.selectedValveId = v1.id;
      final updatedCountAll = controller.applySelectedPropertiesToSimilar(sameDnOnly: false);
      expect(updatedCountAll, equals(2));
      expect(network.valves[v2.id]!.isFlanged, isTrue);
      expect(network.valves[v3.id]!.isFlanged, isTrue);
      expect(network.valves[v3.id]!.flangePressurePn, equals(25));
      expect(network.valves[v3.id]!.counterFlangeMaterial, equals('09Г2С'));
    });
  });
}
