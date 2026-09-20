import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/sheet_tab_bar.dart';
import 'package:akso/ui/features/editor/widgets/sheet_toolbar.dart';
import 'package:akso/ui/features/editor/widgets/title_block_editor_dialog.dart';
import 'package:akso/ui/features/editor/widgets/technical_requirements_dialog.dart';

void main() {
  group('Sheet UI Widgets', () {
    testWidgets('SheetTabBar switches between Model and Sheets and adds new sheets', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = PipingInputController();
      controller.addSheet(name: 'Лист 1: В1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SheetTabBar(controller: controller),
          ),
        ),
      );

      // Model and sheet tabs should be visible
      expect(find.text('Модель'), findsOneWidget);
      expect(find.text('Лист 1: В1'), findsOneWidget);
      expect(find.byKey(const Key('add_sheet_button')), findsOneWidget);

      // Tap model tab
      await tester.tap(find.byKey(const Key('tab_model_space')));
      await tester.pumpAndSettle();
      expect(controller.isModelSpaceActive, isTrue);

      // Tap sheet tab
      await tester.tap(find.text('Лист 1: В1'));
      await tester.pumpAndSettle();
      expect(controller.isModelSpaceActive, isFalse);
      expect(controller.activeSheet?.name, equals('Лист 1: В1'));

      controller.dispose();
    });

    testWidgets('SheetToolbar toggles focus and triggers autofit', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = PipingInputController();
      controller.addSheet(name: 'Лист 1: В1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SheetToolbar(controller: controller),
              ],
            ),
          ),
        ),
      );

      // Expect sheet mode indicator
      expect(find.text('Пространство листа'), findsOneWidget);

      // Toggle focus
      await tester.tap(find.byKey(const Key('sheet_viewport_focus_toggle')));
      await tester.pumpAndSettle();
      expect(controller.isViewportFocused, isTrue);
      expect(find.text('Фокус ВЭ (Модель)'), findsOneWidget);

      // Autofit button
      await tester.tap(find.byKey(const Key('viewport_autofit_button')));
      await tester.pumpAndSettle();

      controller.dispose();
    });

    testWidgets('TitleBlockEditorDialog modifies title block data', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = PipingInputController();
      final sheet = controller.addSheet(name: 'Лист 1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TitleBlockEditorDialog(controller: controller, sheet: sheet),
          ),
        ),
      );

      // Expect tabs
      expect(find.text('Основные графы'), findsOneWidget);
      expect(find.text('Согласования'), findsOneWidget);
      expect(find.text('Приложение к акту'), findsOneWidget);
      expect(find.text('Архив и подшивка'), findsOneWidget);

      // Fill in object name
      final objFinder = find.widgetWithText(TextField, 'Наименование объекта строительства (Графа 1)');
      expect(objFinder, findsOneWidget);
      await tester.enterText(objFinder, 'УПН Северная');

      // Click Apply
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();

      expect(controller.activeSheet?.titleBlockData.projectName, equals('УПН Северная'));

      controller.dispose();
    });

    testWidgets('TechnicalRequirementsDialog appends templates and updates sheet', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = PipingInputController();
      final sheet = controller.addSheet(name: 'Лист 1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TechnicalRequirementsDialog(controller: controller, sheet: sheet),
          ),
        ),
      );

      expect(find.text('Технические требования (ТТ)'), findsOneWidget);
      expect(find.text('Пункт 1'), findsOneWidget);

      // Click template 1
      await tester.tap(find.text('Пункт 1'));
      await tester.pumpAndSettle();

      // Click Apply
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();

      expect(controller.activeSheet?.technicalRequirements?.text, contains('ГОСТ 16037-80'));

      controller.dispose();
    });
  });
}
