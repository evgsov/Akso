import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/enums/dxf_callout_options.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/callout.dart';

void main() {
  group('DxfCalloutOptions Enums & Math', () {
    test('DxfCalloutType has 3 options with non-empty descriptions', () {
      expect(DxfCalloutType.values.length, equals(3));
      for (final type in DxfCalloutType.values) {
        expect(type.displayName.isNotEmpty, isTrue);
        expect(type.description.isNotEmpty, isTrue);
      }
    });

    test('DxfCalloutOrientation has 8 orientations with valid extrusion vectors', () {
      expect(DxfCalloutOrientation.values.length, equals(8));
      for (final ori in DxfCalloutOrientation.values) {
        expect(ori.displayName.isNotEmpty, isTrue);
        final vec = ori.getExtrusionVector();
        final len = math.sqrt(vec.nx * vec.nx + vec.ny * vec.ny + vec.nz * vec.nz);
        expect(len, closeTo(1.0, 1e-4));
      }
    });

    test('DxfCalloutOrientation cameraFacing responds to projector orbitAzimuth', () {
      final projFront = const AxonometryProjector(orbitAzimuth: 0.0);
      final vecFront = DxfCalloutOrientation.cameraFacing.getExtrusionVector(projFront);
      expect(vecFront.nx, closeTo(0.0, 1e-4));
      expect(vecFront.ny, closeTo(-1.0, 1e-4));
      expect(vecFront.nz, closeTo(0.0, 1e-4));

      final projSide = const AxonometryProjector(orbitAzimuth: -math.pi / 2);
      final vecSide = DxfCalloutOrientation.cameraFacing.getExtrusionVector(projSide);
      expect(vecSide.nx, closeTo(1.0, 1e-4));
      expect(vecSide.ny, closeTo(0.0, 1e-4));
      expect(vecSide.nz, closeTo(0.0, 1e-4));
    });
  });

  group('DxfWriter 3D Callout Generation', () {
    late PipingNetwork net;

    setUp(() {
      net = PipingNetwork();
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 2000);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 50);
      net.callouts['c1'] = const Callout(
        id: 'c1',
        targetId: 's1',
        targetType: CalloutTargetType.segment,
        screenOffsetX: 60.0,
        screenOffsetY: -60.0,
      );
    });

    test('generate3dDxf with monolithicBlock creates BLOCK and INSERT with extrusion vector', () {
      final dxf = DxfWriter.generate3dDxf(
        net,
        calloutType: DxfCalloutType.monolithicBlock,
        calloutOrientation: DxfCalloutOrientation.isoSouthEast,
      );

      expect(dxf.contains('CALLOUT_SHELF_1'), isTrue);
      expect(dxf.contains('INSERT'), isTrue);
      // Check extrusion vector 210, 220, 230
      expect(dxf.contains('210\n'), isTrue);
      expect(dxf.contains('220\n'), isTrue);
      expect(dxf.contains('230\n'), isTrue);
    });

    test('generate3dDxf with nativeLeader creates LINE shelf and TEXT with extrusion vector', () {
      final dxf = DxfWriter.generate3dDxf(
        net,
        calloutType: DxfCalloutType.nativeLeader,
        calloutOrientation: DxfCalloutOrientation.viewFront,
      );

      expect(dxf.contains(DxfWriter.toAutoCadString('АКСО_ВЫНОСКИ')), isTrue);
      expect(dxf.contains(DxfWriter.toAutoCadString('АКСО_ВЫНОСКИ_ТЕКСТ')), isTrue);
      expect(dxf.contains('210\n'), isTrue);
      expect(dxf.contains('220\n'), isTrue);
    });

    test('generateMleaderScript creates valid AutoCAD script commands', () {
      final scr = DxfWriter.generateMleaderScript(net);
      expect(scr.contains('(command "_.MLEADER"'), isTrue);
      expect(scr.contains('_non'), isTrue);
      expect(scr.contains('50'), isTrue);
    });

    test('AutoCAD 2024 accoreconsole audits both DXF modes and MLEADER script', () {
      const acadPath = r'C:\Program Files\Autodesk\AutoCAD 2024\accoreconsole.exe';
      if (!File(acadPath).existsSync()) return;

      // 1. Audit monolithicBlock DXF
      final dxfMono = DxfWriter.generate3dDxf(
        net,
        calloutType: DxfCalloutType.monolithicBlock,
        calloutOrientation: DxfCalloutOrientation.isoSouthEast,
      );
      final monoDxfFile = File('test_mono.dxf');
      monoDxfFile.writeAsStringSync(dxfMono);

      final scrMono = File('test_mono.scr');
      scrMono.writeAsStringSync('_DXFIN "${monoDxfFile.absolute.path}"\n_AUDIT\n_Y\n_QUIT\n_Y\n');
      final resMono = Process.runSync(acadPath, ['/s', scrMono.absolute.path]);
      monoDxfFile.deleteSync();
      scrMono.deleteSync();

      expect(resMono.exitCode, equals(0));
      expect(resMono.stdout.toString().contains('DXF -'), isFalse);

      // 2. Audit nativeLeader DXF
      final dxfNative = DxfWriter.generate3dDxf(
        net,
        calloutType: DxfCalloutType.nativeLeader,
        calloutOrientation: DxfCalloutOrientation.viewFront,
      );
      final nativeDxfFile = File('test_native.dxf');
      nativeDxfFile.writeAsStringSync(dxfNative);

      final scrNative = File('test_native.scr');
      scrNative.writeAsStringSync('_DXFIN "${nativeDxfFile.absolute.path}"\n_AUDIT\n_Y\n_QUIT\n_Y\n');
      final resNative = Process.runSync(acadPath, ['/s', scrNative.absolute.path]);
      nativeDxfFile.deleteSync();
      scrNative.deleteSync();

      expect(resNative.exitCode, equals(0));
      expect(resNative.stdout.toString().contains('DXF -'), isFalse);
    });
  });
}
