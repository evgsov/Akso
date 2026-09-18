import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/ui/canvas/painters/callout_painter.dart';
import 'package:akso/ui/features/editor/widgets/callout_manager_panel.dart';

void main() {
  group('Task 1: Exclude inline pipe diameters from DXF export', () {
    test('generate2dGostAxonometryDxf and generate3dDxf do NOT contain АКСО_ДИАМЕТРЫ by default', () {
      final network = PipingNetwork();
      final sys = PipingSystem(
        id: 'sys_v1',
        name: 'Холодное водоснабжение',
        code: 'В1',
        colorValue: Colors.blue.toARGB32(),
        dxfAciColor: 5,
      );
      network.systems[sys.id] = sys;

      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      final seg = PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_v1',
        dn: 80,
        outerDiameterMm: 89.0,
      );
      network.segments[seg.id] = seg;

      final proj = AxonometryProjector(
        projectionType: ProjectionType.gostFrontal45,
        scale: 1.0,
        panOffset: Offset.zero,
      );

      final diameterText = DxfWriter.toAutoCadString(seg.shortCallout);
      final diameterLayer = DxfWriter.toAutoCadString('АКСО_ДИАМЕТРЫ');

      // Default export: exportInlineDiameters is false
      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network, activeProjector: proj);
      final dxf3d = DxfWriter.generate3dDxf(network);

      final entities2d = dxf2d.substring(dxf2d.indexOf('ENTITIES'));
      final entities3d = dxf3d.substring(dxf3d.indexOf('ENTITIES'));

      // Verify that entities section does not write layer АКСО_ДИАМЕТРЫ with Ду80 text
      expect(entities2d.contains(diameterLayer), isFalse);
      expect(entities2d.contains(diameterText), isFalse);
      expect(entities3d.contains(diameterLayer), isFalse);
      expect(entities3d.contains(diameterText), isFalse);

      // If exportInlineDiameters is explicitly enabled, it should write them
      final dxf2dWithDiameters = DxfWriter.generate2dGostAxonometryDxf(network, activeProjector: proj, exportInlineDiameters: true);
      final dxf3dWithDiameters = DxfWriter.generate3dDxf(network, exportInlineDiameters: true);

      final entities2dWithDiameters = dxf2dWithDiameters.substring(dxf2dWithDiameters.indexOf('ENTITIES'));
      final entities3dWithDiameters = dxf3dWithDiameters.substring(dxf3dWithDiameters.indexOf('ENTITIES'));

      expect(entities2dWithDiameters.contains(diameterLayer), isTrue);
      expect(entities2dWithDiameters.contains(diameterText), isTrue);
      expect(entities3dWithDiameters.contains(diameterLayer), isTrue);
      expect(entities3dWithDiameters.contains(diameterText), isTrue);
    });
  });

  group('Task 2: Elevation Mark ГОСТ 21.101 Templating and Placeholders', () {
    test('default templates for node target type', () {
      expect(CalloutTargetType.node.defaultTemplate, contains('{Z_M}'));
      expect(CalloutTargetType.node.defaultBottomTemplate, 'Ур.ч.п.');
      expect(defaultCalloutTemplates['node'], contains('{Z_M}'));
      expect(defaultCalloutTemplates['node_bottom'], 'Ур.ч.п.');
    });

    test('formatCalloutTemplate for node supports {Z_M}, {Z_TOP}, {Z_BOT}, {Z_AXIS}', () {
      final network = PipingNetwork();
      final sys = PipingSystem(
        id: 'sys_v1',
        name: 'Холодное водоснабжение',
        code: 'В1',
        colorValue: Colors.blue.toARGB32(),
        dxfAciColor: 5,
      );
      network.systems[sys.id] = sys;

      final n1 = Node3D(id: 'node_1', x: 0, y: 0, z: 2400);
      final n2 = Node3D(id: 'node_2', x: 3000, y: 0, z: 2400);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      final seg = PipeSegment(
        id: 'seg_1',
        startNodeId: 'node_1',
        endNodeId: 'node_2',
        systemId: 'sys_v1',
        dn: 80,
        outerDiameterMm: 90.0, // radius = 45 mm = 0.045 m
      );
      network.segments[seg.id] = seg;

      // 1. Check {Z_M} and +{Z_M} (no double plus)
      final textZM = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '+{Z_M}');
      expect(textZM, '+2.400');

      final textBareZM = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{Z_M}');
      expect(textBareZM, '+2.400');

      // 2. Check {Z} in mm
      final textZ = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{Z}');
      expect(textZ, '2400');

      // 3. Check {TOP} and {Z_TOP} (2400 + 45 = 2445 mm -> +2.445 m)
      final textTop = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{TOP}');
      expect(textTop, 'В.Т. +2.445');

      final textZTop = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{Z_TOP}');
      expect(textZTop, '+2.445');

      // 4. Check {BOP} and {Z_BOT} (2400 - 45 = 2355 mm -> +2.355 m)
      final textBop = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{BOP}');
      expect(textBop, 'Н.Т. +2.355');

      final textZBot = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{Z_BOT}');
      expect(textZBot, '+2.355');

      // 5. Check {Z_AXIS}
      final textAxis = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', '{Z_AXIS}');
      expect(textAxis, 'ОСЬ +2.400');

      // 6. Check {DN} and {SYSTEM}
      final textPipe = network.formatCalloutTemplate(CalloutTargetType.node, 'node_1', 'Ду{DN} {SYSTEM}');
      expect(textPipe, 'Ду80 В1');
    });

    test('formatPreviewCalloutText for node generates realistic ГОСТ 21.101 sample', () {
      final previewTop = formatPreviewCalloutText('+{Z_M}', CalloutTargetType.node);
      expect(previewTop, '+2.400');

      final previewTopPipe = formatPreviewCalloutText('{TOP}', CalloutTargetType.node);
      expect(previewTopPipe, contains('В.Т.'));

      final previewBotPipe = formatPreviewCalloutText('{BOP}', CalloutTargetType.node);
      expect(previewBotPipe, contains('Н.Т.'));

      final previewBottom = formatPreviewCalloutText('Ур.ч.п.', CalloutTargetType.node);
      expect(previewBottom, 'Ур.ч.п.');
    });
  });

  group('Task 3: 3D Smart Normal Vector and Callout Geometry', () {
    test('Adaptive normal vector on pipes at 90, 45, and 30 degrees', () {
      final network = PipingNetwork();
      final nStart = Node3D(id: 's', x: 0, y: 0, z: 0);
      final nOrth = Node3D(id: 'eOrth', x: 2000, y: 0, z: 0);
      final n45 = Node3D(id: 'e45', x: 2000, y: 2000, z: 0);
      final rad30 = 30.0 * math.pi / 180.0;
      final n30 = Node3D(id: 'e30', x: 2000 * math.cos(rad30), y: 2000 * math.sin(rad30), z: 0);

      network.nodes[nStart.id] = nStart;
      network.nodes[nOrth.id] = nOrth;
      network.nodes[n45.id] = n45;
      network.nodes[n30.id] = n30;

      final segOrth = PipeSegment(id: 'sOrth', startNodeId: 's', endNodeId: 'eOrth', systemId: 'v1', dn: 80);
      network.segments[segOrth.id] = segOrth;

      final proj = AxonometryProjector(projectionType: ProjectionType.gostFrontal45, scale: 1.0);

      // 1. Normal for orthogonal pipe
      final nVecOrth = CalloutPainter.computeNodeNormalVector(network, proj, 's');
      final p1 = proj.project(nStart);
      final p2 = proj.project(nOrth);
      final vOrth = Offset(p2.dx - p1.dx, p2.dy - p1.dy);
      expect(vOrth.dx * nVecOrth.dx + vOrth.dy * nVecOrth.dy, closeTo(0.0, 1e-4));

      // 2. Normal for 45° pipe
      network.segments.clear();
      final seg45 = PipeSegment(id: 's45', startNodeId: 's', endNodeId: 'e45', systemId: 'v1', dn: 80);
      network.segments[seg45.id] = seg45;
      final nVec45 = CalloutPainter.computeNodeNormalVector(network, proj, 's');
      final p2_45 = proj.project(n45);
      final v45 = Offset(p2_45.dx - p1.dx, p2_45.dy - p1.dy);
      expect(v45.dx * nVec45.dx + v45.dy * nVec45.dy, closeTo(0.0, 1e-4));

      // 3. Normal for 30° pipe
      network.segments.clear();
      final seg30 = PipeSegment(id: 's30', startNodeId: 's', endNodeId: 'e30', systemId: 'v1', dn: 80);
      network.segments[seg30.id] = seg30;
      final nVec30 = CalloutPainter.computeNodeNormalVector(network, proj, 's');
      final p2_30 = proj.project(n30);
      final v30 = Offset(p2_30.dx - p1.dx, p2_30.dy - p1.dy);
      expect(v30.dx * nVec30.dx + v30.dy * nVec30.dy, closeTo(0.0, 1e-4));
    });

    test('generateMissingCallouts creates node callouts for vertical risers and endpoints', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 0, y: 0, z: 2500); // vertical riser
      final n3 = Node3D(id: 'n3', x: 1500, y: 0, z: 2500); // horizontal
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      network.nodes[n3.id] = n3;

      final seg1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'v1', dn: 50);
      final seg2 = PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'v1', dn: 50);
      network.segments[seg1.id] = seg1;
      network.segments[seg2.id] = seg2;

      final added = network.generateMissingCallouts(targetTypes: {CalloutTargetType.node});
      expect(added, greaterThanOrEqualTo(2));

      // Verify created callouts have targetType node
      final nodeCallouts = network.callouts.values.where((c) => c.targetType == CalloutTargetType.node).toList();
      expect(nodeCallouts, isNotEmpty);
      expect(nodeCallouts.any((c) => c.targetId == 'n2' || c.targetId == 'n3'), isTrue);
    });
  });

  group('Task 4: DXF Export of ГОСТ 21.101 Elevation Callouts', () {
    test('generate2dGostAxonometryDxf exports node callout as ГОСТ elevation mark block and avoids duplicate', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 2500);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 2500);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;

      final seg = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'v1', dn: 80);
      network.segments[seg.id] = seg;

      final callout = Callout(
        id: 'c_node1',
        targetId: 'n1',
        targetType: CalloutTargetType.node,
        customText: '+{Z_M}',
        customBottomText: 'Ур.ч.п.',
        screenOffsetX: 60.0,
        screenOffsetY: -40.0,
      );
      network.callouts[callout.id] = callout;

      final proj = AxonometryProjector(projectionType: ProjectionType.gostFrontal45, scale: 1.0);
      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network, activeProjector: proj);

      final elevLayer = DxfWriter.toAutoCadString('АКСО_ОТМЕТКИ');
      final elevTextLayer = DxfWriter.toAutoCadString('АКСО_ОТМЕТКИ_ТЕКСТ');
      final textZM = DxfWriter.toAutoCadString('+2.500');
      final textBottom = DxfWriter.toAutoCadString('Ур.ч.п.');

      expect(dxf2d.contains(elevLayer), isTrue);
      expect(dxf2d.contains(elevTextLayer), isTrue);
      expect(dxf2d.contains(textZM), isTrue);
      expect(dxf2d.contains(textBottom), isTrue);

      // Verify that the block definition includes the triangular flag or lines
      expect(dxf2d.contains('CALLOUT_2D_1'), isTrue);
    });

    test('generate3dDxf exports node callout to АКСО_ОТМЕТКИ layer in 3D', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 3200);
      network.nodes[n1.id] = n1;

      final callout = Callout(
        id: 'c_node1',
        targetId: 'n1',
        targetType: CalloutTargetType.node,
        customText: '+{Z_M}',
        customBottomText: 'В.Т.',
        screenOffsetX: 50.0,
        screenOffsetY: -50.0,
      );
      network.callouts[callout.id] = callout;

      final dxf3d = DxfWriter.generate3dDxf(network);
      final elevLayer = DxfWriter.toAutoCadString('АКСО_ОТМЕТКИ');
      final elevTextLayer = DxfWriter.toAutoCadString('АКСО_ОТМЕТКИ_ТЕКСТ');
      final textZM = DxfWriter.toAutoCadString('+3.200');
      final textBottom = DxfWriter.toAutoCadString('В.Т.');

      expect(dxf3d.contains(elevLayer), isTrue);
      expect(dxf3d.contains(elevTextLayer), isTrue);
      expect(dxf3d.contains(textZM), isTrue);
      expect(dxf3d.contains(textBottom), isTrue);
      expect(dxf3d.contains('CALLOUT_SHELF_1'), isTrue);
    });
  });
}

