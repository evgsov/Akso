import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/report_type.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/report_template.dart';
import 'package:akso/ui/features/editor/widgets/report_template_builder_widget.dart';

void main() {
  group('ReportTemplateBuilderWidget tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    testWidgets('renders template builder with chips and column list', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportTemplateBuilderWidget(
              reportType: ReportType.weldJournal,
              network: network,
              initialTemplate: ReportTemplate.defaultWeldJournalTransneftTemplate,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Check template name dropdown or title
      expect(find.text('Реестр стыков Транснефть (СП14/15)'), findsWidgets);

      // Check chips palette presence
      expect(find.textContaining('Кликните на чип'), findsOneWidget);
      expect(find.textContaining('{elem1_name}'), findsWidgets);
      expect(find.textContaining('{connection_type}'), findsWidgets);

      // Check column list header and items
      expect(find.textContaining('Столбцы шаблона'), findsOneWidget);
      expect(find.text('Номер стыка'), findsWidgets);
      expect(find.text('Раздел'), findsWidgets);
    });

    testWidgets('adds a new column to template', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      ReportTemplate? updatedTemplate;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportTemplateBuilderWidget(
              reportType: ReportType.materialsSpecification,
              network: network,
              initialTemplate: ReportTemplate.defaultMtoGostTemplate,
              onTemplateChanged: (t) => updatedTemplate = t,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final initialColCount = ReportTemplate.defaultMtoGostTemplate.columns.length;

      // Find "+ Добавить столбец" button
      final addBtn = find.text('+ Добавить столбец');
      expect(addBtn, findsOneWidget);

      await tester.tap(addBtn);
      await tester.pump();

      expect(updatedTemplate, isNotNull);
      expect(updatedTemplate!.columns.length, initialColCount + 1);
    });

    testWidgets('duplicates a column in template', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      ReportTemplate? updatedTemplate;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportTemplateBuilderWidget(
              reportType: ReportType.weldJournal,
              network: network,
              initialTemplate: ReportTemplate.defaultWeldJournalTransneftTemplate,
              onTemplateChanged: (t) => updatedTemplate = t,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final initialColCount = ReportTemplate.defaultWeldJournalTransneftTemplate.columns.length;

      // Tap duplicate on the first column
      final dupBtn = find.byTooltip('Дублировать столбец').first;
      expect(dupBtn, findsOneWidget);

      await tester.tap(dupBtn);
      await tester.pump();

      expect(updatedTemplate, isNotNull);
      expect(updatedTemplate!.columns.length, initialColCount + 1);
    });

    testWidgets('toggles demo sample data in preview panel', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportTemplateBuilderWidget(
              reportType: ReportType.weldJournal,
              network: network,
              initialTemplate: ReportTemplate.defaultWeldJournalTransneftTemplate,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Check demo data badge exists
      expect(find.textContaining('Демо-образцы'), findsOneWidget);

      // Banner for sample data on empty network
      expect(find.textContaining('отображаются демо-данные'), findsOneWidget);
    });
  });
}
