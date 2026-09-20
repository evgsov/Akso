# Система динамических листов, видовых экранов, штампов по ГОСТ 21.101 и печати исполнительных схем (СПДС) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Создать масштабируемую подсистему динамических листов (А4–А0), видовых экранов (Viewport), оформления по ГОСТ 21.101-2020 (основная надпись 185х55 мм, рамка 20-5-5-5 мм, архивные графы, настраиваемый блок приложения к акту), составных методов неразрушающего контроля стыков (ВИК, РК, УЗК, ПВК, МПК), аннотативной типографики с настраиваемыми весами линий и прямого экспорта в векторный PDF и AutoCAD DXF (вкладки Layouts / Paper Space).

**Architecture:** 
- Доменный слой: модели `DrawingSheet`, `SheetFormat`, `TitleBlockData`, `SheetViewport`, `SheetTableItem`, `TechnicalRequirements`, `DrawingStyleConfig`, расширение `WeldJoint` (составные методы контроля).
- Сервисный слой: `ViewportTransformService` (координатный конвейер 3D -> 2D -> Viewport мм -> Screen px, аннотативность текста), `PdfExportService` (векторная генерация PDF 1:1), расширение `DxfWriter` (секции LAYOUTS и объекты VIEWPORT в Paper Space).
- UI слой: `SheetTabBar` (вкладки внизу в стиле AutoCAD/СПДС), `SheetToolbar` (чипы систем, масштаб, таблицы, ТТ, печать), `SheetCanvasPainter` (рендеринг листа, рамки, штампа, ТТ и клиппированного видового экрана), диалоги `TitleBlockEditorDialog` и `TechnicalRequirementsDialog`.
- Интеграция: сохранение листов в `ProjectModel` (.akso), синхронизация таблиц спецификаций и стыков с Этапом 8.

**Tech Stack:** Flutter, Dart, `pdf: ^3.11.1`, `printing: ^5.13.2`, `vector_math`, `file_picker`, `share_plus`.

**Spec:** `docs/superpowers/specs/2026-09-20-sheet-layout-and-spds-gost-21-101-design.md`

## Global Constraints
- Сохранение 100% прохождения всех существующих 581+ тестов и `flutter analyze` 0 замечаний.
- Код должен работать на всех платформах: Windows, Android, Web.
- Совместимость со старыми файлами проектов `.akso` (fallback-десериализация при отсутствии полей `sheets`).
- Обратная совместимость для `WeldJoint` (автоматическая конвертация одиночного `inspectionMethod` в `inspectionMethods`).

---

### Task 1: Составные методы контроля сварных стыков и токены отчетов

**Files:**
- Modify: `lib/domain/enums/inspection_method.dart`
- Modify: `lib/domain/models/weld_joint.dart`
- Modify: `lib/domain/services/report_engine.dart`
- Create: `test/weld_composite_inspection_test.dart`

**Interfaces:**
- Consumes: `WeldJoint`, `InspectionMethod`, `ReportEngine`
- Produces: `WeldJoint.inspectionMethods: List<InspectionMethod>`, `WeldJoint.formattedInspectionMethods: String`, токены `{weld_inspection}`, `{weld_has_vik}`, `{weld_has_rk}`, `{weld_has_uzk}`, `{weld_has_pvk}`

- [ ] **Step 1: Write the failing test**

```dart
// test/weld_composite_inspection_test.dart
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

    test('ReportEngine evaluates composite inspection tokens', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.addNode(n1);
      network.addNode(n2);
      final seg = PipeSegment(id: 'seg_1', startNodeId: 'n1', endNodeId: 'n2', dn: 50);
      network.addSegment(seg);
      final joint = WeldJoint(
        id: 'wj_1',
        segmentId: 'seg_1',
        ratio: 0.5,
        number: 1,
        stamp: 'ИВ-1',
        inspectionMethods: const [InspectionMethod.vik, InspectionMethod.rk],
      );
      network.weldJoints[joint.id] = joint;

      final ctx = ReportEngine.resolveWeldContext(network, joint);
      expect(ReportEngine.evaluateTemplateString('{weld_inspection}', ctx), equals('ВИК, РК'));
      expect(ReportEngine.evaluateTemplateString('{weld_has_vik}', ctx), equals('Да'));
      expect(ReportEngine.evaluateTemplateString('{weld_has_rk}', ctx), equals('Да'));
      expect(ReportEngine.evaluateTemplateString('{weld_has_uzk}', ctx), equals('Нет'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement minimal code**
  - Расширить `InspectionMethod` (добавить `pvk`, `mpk`, `pvt`, `styloscopy`).
  - В `WeldJoint` добавить `List<InspectionMethod> inspectionMethods`, сериализацию/десериализацию в JSON с fallback.
  - В `ReportEngine` добавить обработку токенов `{weld_inspection}`, `{weld_has_vik}`, `{weld_has_rk}`, `{weld_has_uzk}`, `{weld_has_pvk}`.
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 2: Доменные модели листов, штампа ГОСТ 21.101 и стилей оформления

**Files:**
- Create: `lib/domain/enums/sheet_format_type.dart`
- Create: `lib/domain/models/sheet_format.dart`
- Create: `lib/domain/models/title_block_data.dart`
- Create: `lib/domain/models/drawing_sheet.dart`
- Create: `lib/domain/models/drawing_style_config.dart`
- Modify: `lib/domain/models/project_model.dart`
- Create: `test/drawing_sheet_model_test.dart`

**Interfaces:**
- Consumes: `ProjectModel`, `SheetFormat`, `TitleBlockData`
- Produces: `DrawingSheet`, `SheetViewport`, `SheetTableItem`, `TechnicalRequirements`, `DrawingStyleConfig`

- [ ] **Step 1: Write the failing test**

```dart
// test/drawing_sheet_model_test.dart
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
    });

    test('DrawingSheet JSON serialization roundtrip', () {
      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Лист 1: В1',
        sheetNumber: 1,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
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
          ),
        ),
        viewport: const SheetViewport(
          xMm: 25.0,
          yMm: 10.0,
          widthMm: 250.0,
          heightMm: 220.0,
          viewScale: 0.02,
          visibleSystemIds: {'sys_b1'},
          ghostInactiveSystems: true,
        ),
      );

      final json = sheet.toJson();
      final restored = DrawingSheet.fromJson(json);

      expect(restored.id, equals(sheet.id));
      expect(restored.name, equals('Лист 1: В1'));
      expect(restored.format.widthMm, equals(420.0));
      expect(restored.titleBlockData.documentCode, equals('04-2026-ТХ.ИС'));
      expect(restored.titleBlockData.topRightCorner.mode, equals(TopRightCornerMode.actAttachment));
      expect(restored.viewport.visibleSystemIds, contains('sys_b1'));
      expect(restored.viewport.ghostInactiveSystems, isTrue);
    });

    test('ProjectModel manages sheets and activeSheetId', () {
      final project = ProjectModel(
        id: 'proj_1',
        title: 'Тестовый проект',
        sheets: [
          DrawingSheet.createDefault(id: 'sh_1', name: 'Лист 1', sheetNumber: 1),
        ],
        activeSheetId: 'sh_1',
      );

      expect(project.sheets.length, equals(1));
      expect(project.activeSheetId, equals('sh_1'));
      expect(project.activeSheet?.name, equals('Лист 1'));

      final json = project.toJson();
      final restored = ProjectModel.fromJson(json);
      expect(restored.sheets.length, equals(1));
      expect(restored.activeSheetId, equals('sh_1'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement minimal code**
  - Реализовать `SheetFormatType`, `SheetOrientation`, `SheetFormat`.
  - Реализовать `TitleBlockData`, `TitleBlockApproval`, `TopRightCornerBlock`, `TopRightCornerMode`.
  - Реализовать `SheetViewport`, `SheetTableItem`, `TechnicalRequirements`, `DrawingSheet`.
  - Реализовать `DrawingStyleConfig` (веса линий и аннотативные размеры текста).
  - Модифицировать `ProjectModel` (добавить `sheets`, `activeSheetId`, `styleConfig`).
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 3: Математический сервис видового экрана и аннотативности (`ViewportTransformService`)

**Files:**
- Create: `lib/domain/services/viewport_transform_service.dart`
- Create: `test/viewport_transform_service_test.dart`

**Interfaces:**
- Consumes: `SheetViewport`, `SheetFormat`, `ProjectionEngine`, `PipingNetwork`
- Produces: `ViewportTransformService.calculateAutoFit`, `ViewportTransformService.modelToSheetMm`, `ViewportTransformService.calculateEffectiveAnnotationScale`

- [ ] **Step 1: Write the failing test**

```dart
// test/viewport_transform_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/services/viewport_transform_service.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'dart:ui';

void main() {
  group('ViewportTransformService', () {
    test('calculateAutoFit calculates correct scale and center for network', () {
      final network = PipingNetwork();
      network.addNode(Node3D(id: 'n1', x: 0, y: 0, z: 0));
      network.addNode(Node3D(id: 'n2', x: 4000, y: 2000, z: 1000));
      network.addSegment(PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50));

      final viewportRectMm = const Rect.fromLTWH(25, 10, 250, 200);
      final result = ViewportTransformService.calculateAutoFit(
        network: network,
        projectionType: ProjectionType.gostFrontal45,
        viewportRectMm: viewportRectMm,
        marginMm: 15.0,
      );

      expect(result.scale, greaterThan(0.0));
      expect(result.scale, lessThan(0.1)); // ~ 1:50 or 1:100 scale
      expect(result.center, isNotNull);
    });

    test('annotative text scaling keeps constant paper height across zoom levels', () {
      // 3.5 mm target text height on paper
      const targetHeightMm = 3.5;
      final scale1to50 = 1.0 / 50.0;
      final scale1to100 = 1.0 / 100.0;

      final textScale50 = ViewportTransformService.calculateAnnotationScale(scale1to50);
      final textScale100 = ViewportTransformService.calculateAnnotationScale(scale1to100);

      expect(textScale100, equals(textScale50 * 2.0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement minimal code**
  - Реализовать расчет 2D-габарита проецируемой сети с учетом фильтра систем `visibleSystemIds`.
  - Реализовать масштабирование в стандартные масштабы (1:10, 1:20, 1:25, 1:50, 1:100, 1:200) или точный автоподбор.
  - Реализовать функции преобразования координат `modelToSheetMm` и клиппирования `viewportClipRect`.
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 4: Интерактивный рендерер листа и штампа (`SheetCanvasPainter`)

**Files:**
- Create: `lib/ui/canvas/sheet_canvas_painter.dart`
- Modify: `lib/ui/canvas/piping_canvas.dart`
- Modify: `lib/ui/canvas/input_controller.dart`
- Create: `test/sheet_canvas_painter_test.dart`

**Interfaces:**
- Consumes: `DrawingSheet`, `SheetFormat`, `TitleBlockData`, `PipingNetwork`, `InputController`
- Produces: `SheetCanvasPainter.paint`, режимы `isPaperMode` vs `isViewportFocused`

- [ ] **Step 1: Write the failing test**

```dart
// test/sheet_canvas_painter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/sheet_format.dart';
import 'package:akso/domain/enums/sheet_format_type.dart';
import 'package:akso/domain/models/title_block_data.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/sheet_canvas_painter.dart';

void main() {
  test('SheetCanvasPainter renders paper sheet, frame, and title block without errors', () {
    final sheet = DrawingSheet.createDefault(id: 's1', name: 'Лист 1', sheetNumber: 1);
    final network = PipingNetwork();
    final painter = SheetCanvasPainter(
      sheet: sheet,
      network: network,
      sheetZoom: 1.0,
      sheetPan: Offset.zero,
      isViewportFocused: false,
    );

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1000, 800));
    painter.paint(canvas, const Size(1000, 800));
    final picture = recorder.endRecording();
    expect(picture, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement minimal code**
  - Отрисовка бумажного листа с белым фоном и тенью (`BoxShadow`).
  - Отрисовка рамки по ГОСТ 21.101 (20 мм поле подшивки, 5 мм остальные поля).
  - Отрисовка основной надписи (штампа $185 \times 55$ мм) со всеми графами, линиями $0.8$ и $0.35$ мм и шрифтом.
  - Отрисовка архивных граф подшивки слева и блока приложения к акту справа вверху.
  - Отрисовка видового экрана с клиппированием, фильтрацией систем и подсветкой при фокусе (`isViewportFocused`).
  - В `InputController` добавить методы переключения листов и управления видовым экраном.
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 5: Пользовательский интерфейс: вкладки листов, панель листа и диалог штампа

**Files:**
- Create: `lib/ui/features/editor/widgets/sheet_tab_bar.dart`
- Create: `lib/ui/features/editor/widgets/sheet_toolbar.dart`
- Create: `lib/ui/features/editor/widgets/title_block_editor_dialog.dart`
- Create: `lib/ui/features/editor/widgets/technical_requirements_dialog.dart`
- Modify: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`
- Create: `test/sheet_ui_widgets_test.dart`

**Interfaces:**
- Consumes: `InputController`, `DrawingSheet`, `TitleBlockData`
- Produces: Вкладки `[Пространство модели] | [Лист 1 (А3)] | [+]`, панель параметров листа, диалог штампа ГОСТ

- [ ] **Step 1: Write widget test for SheetTabBar and TitleBlockEditorDialog**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement minimal code**
  - `SheetTabBar`: отображение вкладок модели и листов, кнопка добавления листа, выбор формата А4–А0.
  - `SheetToolbar`: чипы фильтрации систем листа, выбор масштаба видового экрана, кнопки «+ Таблица», «ТТ», «Печать PDF».
  - `TitleBlockEditorDialog`: табовый диалог со всеми полями штампа, согласованиями, приложением к акту и архивом.
  - `TechnicalRequirementsDialog`: редактор примечаний с библиотекой готовых шаблонов.
  - Интеграция в `DesktopCadLayout`.
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 6: Векторный генератор PDF для печати листов

**Files:**
- Modify: `pubspec.yaml` (добавить `pdf: ^3.11.1` и `printing: ^5.13.2`)
- Create: `lib/data/services/pdf_export_service.dart`
- Create: `test/pdf_export_service_test.dart`

**Interfaces:**
- Consumes: `DrawingSheet`, `PipingNetwork`, `DrawingStyleConfig`
- Produces: `PdfExportService.generateSheetPdf`, `PdfExportService.savePdfFile`, `PdfExportService.printSheet`

- [ ] **Step 1: Write the failing test**

```dart
// test/pdf_export_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/data/services/pdf_export_service.dart';

void main() {
  test('PdfExportService generates valid PDF bytes with A3 dimensions', () async {
    final sheet = DrawingSheet.createDefault(id: 's1', name: 'Лист 1: В1', sheetNumber: 1);
    final network = PipingNetwork();
    final bytes = await PdfExportService.generateSheetPdf(sheet: sheet, network: network);
    expect(bytes, isNotEmpty);
    expect(bytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46])); // %PDF
  });
}
```

- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement minimal code**
  - Подключить `package:pdf/pdf.dart` и `package:pdf/widgets.dart`.
  - Векторная отрисовка страницы точного размера формата (А4: 210х297, А3: 420х297 мм).
  - Рамка 20-5-5-5 мм, таблица штампа 185х55 мм, шрифты ГОСТ, векторные линии сети и выноски.
  - Метод сохранения файла через `FilePicker.saveFile` на ПК и `share_plus` на смартфонах/планшетах.
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 7: Экспорт в AutoCAD DXF с вкладками листов (Layouts / Paper Space)

**Files:**
- Modify: `lib/data/dxf/dxf_writer.dart`
- Create: `test/dxf_layouts_export_test.dart`

**Interfaces:**
- Consumes: `PipingNetwork`, `List<DrawingSheet>`
- Produces: `DxfWriter.generate2dGostAxonometryWithLayoutsDxf`

- [ ] **Step 1: Write the failing test**

```dart
// test/dxf_layouts_export_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/data/dxf/dxf_writer.dart';

void main() {
  test('DxfWriter generates DXF with LAYOUT entities and Paper Space frame', () {
    final network = PipingNetwork();
    final sheet = DrawingSheet.createDefault(id: 'sh_1', name: 'Лист 1 (В1)', sheetNumber: 1);
    final dxf = DxfWriter.generate2dGostAxonometryWithLayoutsDxf(
      network: network,
      sheets: [sheet],
    );

    expect(dxf, contains('LAYOUT'));
    expect(dxf, contains('Лист 1 (В1)'));
    expect(dxf, contains('АКСО_ЛИСТ_РАМКА'));
    expect(dxf, contains('АКСО_ЛИСТ_ШТАМП'));
    expect(dxf, contains('VIEWPORT'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement minimal code**
  - Добавить в `DxfWriter` секции `LAYOUTS`, привязку к пространству листа (код 67: 1 для Paper Space).
  - Генерация рамки, штампа, текста ТТ и объекта `VIEWPORT` в пространстве листа.
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 8: Комплексная верификация, регрессионное тестирование и актуализация базы знаний

**Files:**
- Modify: `PROJECT_MEMORY.md`
- Graphify: `graphify update .`

- [ ] **Step 1: Run all unit, widget, and integration tests (`flutter test`)**
- [ ] **Step 2: Run static analysis (`flutter analyze`)**
- [ ] **Step 3: Update `PROJECT_MEMORY.md` with Milestone 9 documentation**
- [ ] **Step 4: Update knowledge graph (`graphify update .`)**
- [ ] **Step 5: Commit and verify clean working tree**
