import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/weld_journal_dialog.dart';

void main() {
  group('WeldJournalDialog Widget Tests', () {
    late PipingNetwork network;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );

      network.addWeldJoint(segmentId: 'seg1', ratio: 0.25, stamp: 'ИВ-01');
      network.addWeldJoint(segmentId: 'seg1', ratio: 0.75, stamp: 'ИВ-01');
      controller = PipingInputController(network: network);
    });

    testWidgets('Renders WeldJournalDialog and displays welds in table', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeldJournalDialog(network: network, controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Исполнительная ведомость сети'), findsOneWidget);
      expect(find.text('Журнал сварных стыков'), findsOneWidget);
      expect(find.text('Всего стыков: 2'), findsOneWidget);
      expect(find.text('ИВ-01'), findsNWidgets(2));
      expect(find.text('Выбрать все'), findsOneWidget);
    });

    testWidgets('Selecting welds shows batch toolbar and allows batch stamp update', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeldJournalDialog(network: network, controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Нажимаем «Выбрать все»
      await tester.tap(find.text('Выбрать все'));
      await tester.pumpAndSettle();

      // Появляется панель массовых операций
      expect(find.text('Выбрано: 2'), findsOneWidget);
      expect(find.text('Клеймо'), findsOneWidget);
      expect(find.text('Контроль ▾'), findsOneWidget);
      expect(find.text('Снять выбор'), findsOneWidget);

      // Снимаем выбор
      await tester.tap(find.text('Снять выбор'));
      await tester.pumpAndSettle();

      expect(find.text('Выбрано: 2'), findsNothing);
    });
  });
}
