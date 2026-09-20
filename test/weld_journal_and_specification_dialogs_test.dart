import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/weld_journal_dialog.dart';
import 'package:akso/ui/features/editor/widgets/materials_specification_dialog.dart';

void main() {
  group('WeldJournalDialog and MaterialsSpecificationDialog integration tests', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 0, z: 0);

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 150,
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys1',
        dn: 150,
      );

      network.addWeldJoint(segmentId: 'seg1', ratio: 0.9, stamp: 'ИВ-01');
      controller = PipingInputController(network: network);
    });

    testWidgets('WeldJournalDialog displays tabs including template builder and Excel export', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeldJournalDialog(
              network: network,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify tabs
      expect(find.text('Журнал сварных стыков'), findsOneWidget);
      expect(find.text('Ведомость катушек (заготовок)'), findsOneWidget);
      expect(find.text('Конструктор шаблона'), findsOneWidget);

      // Verify Excel export button in weld journal
      expect(find.textContaining('Excel'), findsWidgets);

      // Switch to Template Builder tab
      await tester.tap(find.text('Конструктор шаблона'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify constructor content is rendered
      expect(find.textContaining('Столбцы шаблона'), findsOneWidget);
      expect(find.textContaining('Кликните на чип'), findsOneWidget);
    });

    testWidgets('MaterialsSpecificationDialog displays tabs including template builder and Excel export', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MaterialsSpecificationDialog(
              network: network,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify tabs
      expect(find.text('Спецификация (СО)'), findsOneWidget);
      expect(find.text('Конструктор шаблона'), findsOneWidget);

      // Verify Excel export button
      expect(find.textContaining('Excel'), findsWidgets);

      // Switch to Template Builder tab
      await tester.tap(find.text('Конструктор шаблона'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify constructor content is rendered
      expect(find.textContaining('Столбцы шаблона'), findsOneWidget);
    });
  });
}
