import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/sheet_format_type.dart';
import 'package:akso/domain/models/sheet_format.dart';
import 'package:akso/domain/models/title_block_data.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/drawing_style_config.dart';
import 'package:akso/domain/models/project_model.dart';

void main() {
  group('DrawingSheet & TitleBlockData Models', () {
    test('SheetFormat calculates correct paper size and 20-5-5-5 frame margins', () {
      final a3 = SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape);
      expect(a3.widthMm, equals(420.0));
      expect(a3.heightMm, equals(297.0));
      expect(a3.frameLeftMm, equals(20.0));
      expect(a3.frameTopMm, equals(5.0));
      expect(a3.frameRightMm, equals(5.0));
      expect(a3.frameBottomMm, equals(5.0));
      expect(a3.printableWidthMm, equals(395.0));
      expect(a3.printableHeightMm, equals(287.0));

      final a4 = SheetFormat(type: SheetFormatType.a4, orientation: SheetOrientation.portrait);
      expect(a4.widthMm, equals(210.0));
      expect(a4.heightMm, equals(297.0));
      expect(a4.printableWidthMm, equals(185.0)); // 210 - 20 - 5 = 185 (ровно ширина штампа 185 мм!)
    });

    test('DrawingSheet JSON serialization roundtrip with all attributes', () {
      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Лист 1: В1',
        sheetNumber: 1,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        titleBlockForm: TitleBlockForm.form3,
        titleBlockData: TitleBlockData(
          projectName: 'Установка подготовки нефти',
          buildingName: 'Блок технологический',
          drawingTitle: 'Схема трубопроводов В1',
          documentCode: '04-2026-ТХ.ИС',
          organization: 'ООО НефтеГазМонтаж',
          stage: 'И',
          scaleText: 'М 1:50',
          topRightCorner: const TopRightCornerBlock(
            mode: TopRightCornerMode.actAttachment,
            text: 'Приложение №1 к Акту освидетельствования скрытых работ №14',
            actNumber: '14',
            actDate: '20.09.2026',
          ),
          approvals: const [
            TitleBlockApproval(role: 'Разраб.', name: 'Петров А.В.', date: '20.09.26'),
            TitleBlockApproval(role: 'Пров.', name: 'Сидоров И.И.', date: '20.09.26'),
            TitleBlockApproval(role: 'ГИП', name: 'Иванов С.П.', date: '20.09.26'),
          ],
        ),
        viewport: const SheetViewport(
          xMm: 25.0,
          yMm: 10.0,
          widthMm: 250.0,
          heightMm: 220.0,
          viewScale: 0.02,
          autoFit: true,
          visibleSystemIds: {'sys_b1'},
          ghostInactiveSystems: true,
        ),
        technicalRequirements: const TechnicalRequirements(
          text: '1. Сварные швы выполнить по ГОСТ 16037-80.\n2. Контроль ВИК 100%, РК 100%.',
          xMm: 230.0,
          yMm: 180.0,
          widthMm: 185.0,
        ),
      );

      final json = sheet.toJson();
      final restored = DrawingSheet.fromJson(json);

      expect(restored.id, equals(sheet.id));
      expect(restored.name, equals('Лист 1: В1'));
      expect(restored.format.widthMm, equals(420.0));
      expect(restored.titleBlockForm, equals(TitleBlockForm.form3));
      expect(restored.titleBlockData.documentCode, equals('04-2026-ТХ.ИС'));
      expect(restored.titleBlockData.topRightCorner.mode, equals(TopRightCornerMode.actAttachment));
      expect(restored.titleBlockData.topRightCorner.actNumber, equals('14'));
      expect(restored.titleBlockData.approvals.length, equals(3));
      expect(restored.viewport.visibleSystemIds, contains('sys_b1'));
      expect(restored.viewport.ghostInactiveSystems, isTrue);
      expect(restored.technicalRequirements?.text, contains('ГОСТ 16037-80'));
    });

    test('DrawingStyleConfig holds configurable line widths and annotative text sizes', () {
      const config = DrawingStyleConfig(
        pipeLineWidthMm: 0.8,
        thinLineWidthMm: 0.25,
        textHeightSmallMm: 2.5,
        textHeightRegularMm: 3.5,
        textHeightLargeMm: 7.0,
      );

      expect(config.pipeLineWidthMm, equals(0.8));
      expect(config.thinLineWidthMm, equals(0.25));
      expect(config.textHeightRegularMm, equals(3.5));

      final json = config.toJson();
      final restored = DrawingStyleConfig.fromJson(json);
      expect(restored.pipeLineWidthMm, equals(0.8));
      expect(restored.textHeightRegularMm, equals(3.5));
    });

    test('ProjectModel manages sheets list, activeSheetId, and styles with backward compatibility', () {
      final defaultSheet = DrawingSheet.createDefault(id: 'sh_1', name: 'Лист 1', sheetNumber: 1);
      final project = ProjectModel(
        id: 'proj_1',
        title: 'Тестовый проект',
        sheets: [defaultSheet],
        activeSheetId: 'sh_1',
      );

      expect(project.sheets.length, equals(1));
      expect(project.activeSheetId, equals('sh_1'));
      expect(project.activeSheet?.name, equals('Лист 1'));
      expect(project.isModelSpaceActive, isFalse);

      final modelSpaceProject = project.copyWith(clearActiveSheet: true);
      expect(modelSpaceProject.activeSheetId, isNull);
      expect(modelSpaceProject.isModelSpaceActive, isTrue);

      // JSON roundtrip
      final json = project.toJson();
      final restored = ProjectModel.fromJson(json);
      expect(restored.sheets.length, equals(1));
      expect(restored.activeSheetId, equals('sh_1'));
      expect(restored.styleConfig.textHeightRegularMm, equals(3.5));
    });
  });
}
