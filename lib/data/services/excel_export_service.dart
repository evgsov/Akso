import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../domain/models/piping_network.dart';
import '../../domain/models/report_template.dart';
import '../../domain/services/report_engine.dart';

/// Сервис профессионального экспорта спецификаций и ведомостей в Microsoft Excel (.xlsx) и CSV
class ExcelExportService {
  /// Генерация бинарного содержимого файла .xlsx со стилизацией, шапками и автошириной
  static List<int> generateExcelBytes(
    ReportTemplate template,
    PipingNetwork network,
  ) {
    final excel = Excel.createExcel();

    // Excel ограничивает имя листа 31 символом и запрещает символы / \ ? * : [ ]
    String cleanSheetName = template.name
        .replaceAll(RegExp(r'[/\\?*:[\]]'), ' ')
        .trim();
    if (cleanSheetName.length > 28) {
      cleanSheetName = '${cleanSheetName.substring(0, 28)}...';
    }
    if (cleanSheetName.isEmpty) cleanSheetName = 'Ведомость';

    final defaultSheet = excel.getDefaultSheet();
    final sheet = excel[cleanSheetName];
    if (defaultSheet != null && defaultSheet != cleanSheetName) {
      excel.delete(defaultSheet);
    }
    excel.setDefaultSheet(cleanSheetName);

    // Получаем матрицу данных от движка
    final dataRows = ReportEngine.generateTableData(template, network);

    // Проверяем, есть ли двухуровневая шапка (groupHeader)
    final hasGroupHeaders = template.columns.any((c) => c.groupHeader != null && c.groupHeader!.trim().isNotEmpty);

    int dataStartRow = 0;

    final headerGroupStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final headerColStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    if (hasGroupHeaders) {
      dataStartRow = 2;

      // 1. Строка 0: Групповые заголовки (объединяем смежные одинаковые)
      int colIdx = 0;
      while (colIdx < template.columns.length) {
        final gTitle = template.columns[colIdx].groupHeader?.trim() ?? '';
        int endCol = colIdx;
        while (endCol + 1 < template.columns.length &&
            (template.columns[endCol + 1].groupHeader?.trim() ?? '') == gTitle) {
          endCol++;
        }

        if (gTitle.isNotEmpty) {
          if (endCol > colIdx) {
            sheet.merge(
              CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: 0),
              CellIndex.indexByColumnRow(columnIndex: endCol, rowIndex: 0),
              customValue: TextCellValue(gTitle),
            );
          } else {
            final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: 0));
            cell.value = TextCellValue(gTitle);
            cell.cellStyle = headerGroupStyle;
          }
        }
        colIdx = endCol + 1;
      }

      // 2. Строка 1: Подзаголовки столбцов
      for (int c = 0; c < template.columns.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1));
        cell.value = TextCellValue(template.columns[c].header);
        cell.cellStyle = headerColStyle;
      }
    } else {
      dataStartRow = 1;
      // 1. Строка 0: Обычные заголовки столбцов
      for (int c = 0; c < template.columns.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
        cell.value = TextCellValue(template.columns[c].header);
        cell.cellStyle = headerColStyle;
      }
    }

    // 3. Данные
    for (int r = 0; r < dataRows.length; r++) {
      final rowData = dataRows[r];
      final targetRow = dataStartRow + r;

      for (int c = 0; c < template.columns.length; c++) {
        if (c >= rowData.length) continue;
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: targetRow));
        final val = rowData[c];

        if (val is int) {
          cell.value = IntCellValue(val);
          cell.cellStyle = CellStyle(
            horizontalAlign: HorizontalAlign.Right,
          );
        } else if (val is double) {
          cell.value = DoubleCellValue(val);
          cell.cellStyle = CellStyle(
            horizontalAlign: HorizontalAlign.Right,
          );
        } else {
          cell.value = TextCellValue(val?.toString() ?? '');
          final align = template.columns[c].alignment == TextAlign.center
              ? HorizontalAlign.Center
              : (template.columns[c].alignment == TextAlign.right
                  ? HorizontalAlign.Right
                  : HorizontalAlign.Left);
          cell.cellStyle = CellStyle(horizontalAlign: align);
        }
      }
    }

    // 4. Настройка ширины колонок
    for (int c = 0; c < template.columns.length; c++) {
      double maxLen = template.columns[c].header.length.toDouble();
      final gLen = template.columns[c].groupHeader?.length.toDouble() ?? 0.0;
      if (gLen > maxLen) maxLen = gLen;

      for (final r in dataRows) {
        if (c < r.length) {
          final sLen = (r[c]?.toString() ?? '').length.toDouble();
          if (sLen > maxLen) maxLen = sLen;
        }
      }
      final width = (maxLen + 4.0).clamp(10.0, 50.0);
      sheet.setColumnWidth(c, width);
    }

    return excel.encode() ?? [];
  }

  /// Генерация CSV текста с разделителем точка с запятой (;) для буфера обмена
  static String generateCsvString(
    ReportTemplate template,
    PipingNetwork network,
  ) {
    final buffer = StringBuffer();
    final dataRows = ReportEngine.generateTableData(template, network);

    // Заголовки столбцов
    buffer.writeln(template.columns.map((c) => _escapeCsv(c.header)).join(';'));

    // Данные
    for (final row in dataRows) {
      buffer.writeln(row.map((val) => _escapeCsv(val?.toString() ?? '')).join(';'));
    }

    return buffer.toString();
  }

  static String _escapeCsv(String val) {
    if (val.contains(';') || val.contains('"') || val.contains('\n')) {
      return '"${val.replaceAll('"', '""')}"';
    }
    return val;
  }

  /// Сохранение Excel файла с диалогом выбора пути и уведомлением
  static Future<bool> exportAndSaveExcel({
    required BuildContext context,
    required ReportTemplate template,
    required PipingNetwork network,
    String? customFileName,
  }) async {
    try {
      final bytes = generateExcelBytes(template, network);
      if (bytes.isEmpty) return false;

      final now = DateTime.now();
      final dateSuffix = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final fileName = customFileName ?? '${template.type.defaultFileName}_$dateSuffix.xlsx';

      final u8Bytes = Uint8List.fromList(bytes);

      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        final uri = await FilePicker.saveFile(
          dialogTitle: 'Сохранить ${template.name} (.xlsx)',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          bytes: u8Bytes,
        );

        if (uri == null) return false;

        String targetPath = uri.scheme == 'file'
            ? uri.toFilePath()
            : (uri.path.isNotEmpty ? uri.path : uri.toString());
        if (!targetPath.toLowerCase().endsWith('.xlsx')) {
          targetPath = '$targetPath.xlsx';
        }

        final file = File(targetPath);
        await file.writeAsBytes(bytes, flush: true);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Файл Excel успешно сохранен: ${file.path}'),
              backgroundColor: Colors.teal.shade800,
            ),
          );
        }
        return true;
      } else {
        // Mobile / Web шеринг
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                u8Bytes,
                name: fileName,
                mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              ),
            ],
            text: 'Экспорт ${template.name}',
          ),
        );
        return true;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка экспорта в Excel: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
      return false;
    }
  }
}
