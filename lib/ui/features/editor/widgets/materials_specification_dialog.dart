import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/dxf/dxf_writer.dart';
import '../../../../data/repositories/report_template_repository.dart';
import '../../../../data/services/excel_export_service.dart';
import '../../../../domain/enums/report_type.dart';
import '../../../../domain/models/piping_network.dart';
import '../../../../domain/models/report_template.dart';
import '../../../canvas/input_controller.dart';
import 'report_template_builder_widget.dart';

class MaterialsSpecificationDialog extends StatefulWidget {
  final PipingNetwork network;
  final PipingInputController? controller;

  const MaterialsSpecificationDialog({
    super.key,
    required this.network,
    this.controller,
  });

  @override
  State<MaterialsSpecificationDialog> createState() => _MaterialsSpecificationDialogState();
}

class _MaterialsSpecificationDialogState extends State<MaterialsSpecificationDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'Все';
  String? _statusMessage;
  ReportTemplate? _activeTemplate;
  List<ReportTemplate> _availableTemplates = [];

  static const List<String> _categories = [
    'Все',
    'Оборудование',
    'Трубы',
    'Фасонные детали',
    'Арматура',
    'Опоры',
    'Фланцы и прокладки',
    'Сварка',
  ];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final templates = widget.controller != null
        ? await widget.controller!.getReportTemplates(ReportType.materialsSpecification)
        : await ReportTemplateRepository().getTemplatesForType(ReportType.materialsSpecification);
    if (mounted) {
      setState(() {
        _availableTemplates = templates;
        if (_activeTemplate == null && templates.isNotEmpty) {
          _activeTemplate = templates.first;
        } else if (_activeTemplate != null) {
          final found = templates.where((t) => t.id == _activeTemplate!.id);
          _activeTemplate = found.isNotEmpty ? found.first : templates.first;
        }
      });
    }
  }

  Future<void> _exportSpecificationExcel() async {
    final template = _activeTemplate ?? ReportTemplate.defaultMtoGostTemplate;
    await ExcelExportService.exportAndSaveExcel(
      context: context,
      template: template,
      network: widget.network,
    );
  }

  bool _matchesCategory(List<String> row, String category) {
    if (category == 'Все') return true;
    final name = row.length > 1 ? row[1] : '';
    final note = row.length > 7 ? row[7] : '';

    switch (category) {
      case 'Оборудование':
        return note.toLowerCase().contains('оборудование');
      case 'Трубы':
        return note.contains('Строительный метраж') || name.startsWith('Труба');
      case 'Фасонные детали':
        return note.contains('Фасонные детали');
      case 'Арматура':
        return note.contains('Запорно-регулирующая');
      case 'Опоры':
        return note.contains('Опоры');
      case 'Фланцы и прокладки':
        return note.contains('Комплект арматуры') || note.contains('Штуцер оборудования');
      case 'Сварка':
        return note.contains('Монтажная сварка');
      default:
        return true;
    }
  }

  Future<void> _exportCsvFile(String csvContent) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(csvContent));
      const fileName = 'specification.csv';

      final Uri? uri = await FilePicker.saveFile(
        dialogTitle: 'Сохранить спецификацию (CSV)',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: bytes,
      );

      if (uri == null) {
        setState(() {
          _statusMessage = 'Экспорт отменен';
        });
        return;
      }

      String targetPath = uri.scheme == 'file'
          ? uri.toFilePath()
          : (uri.path.isNotEmpty ? uri.path : uri.toString());

      if (!targetPath.toLowerCase().endsWith('.csv')) {
        targetPath = '$targetPath.csv';
      }

      if (!kIsWeb) {
        final file = File(targetPath);
        await file.writeAsString(csvContent, flush: true);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Спецификация успешно сохранена: $targetPath'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения файла: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final csv = DxfWriter.generateMtoCsv(widget.network);
    final allRows = _parseCsvRows(csv);

    // Подсчет количества по категориям
    final categoryCounts = <String, int>{};
    categoryCounts['Все'] = allRows.length;
    for (final cat in _categories.skip(1)) {
      categoryCounts[cat] = allRows.where((r) => _matchesCategory(r, cat)).length;
    }

    // Фильтрация по выбранной категории и поисковому запросу
    final filteredRows = allRows.where((r) {
      if (!_matchesCategory(r, _selectedCategory)) return false;
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      return r.any((cell) => cell.toLowerCase().contains(q));
    }).toList();

    return DefaultTabController(
      length: 2,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1100,
            maxHeight: 740,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Шапка диалога
                Row(
                  children: [
                    const Icon(Icons.list_alt, color: Colors.teal, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Спецификация оборудования, изделий и материалов (СО)',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'ГОСТ 21.110-2013 / СП 73.13330 / ГОСТ 21.602',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Табы
                const TabBar(
                  labelColor: Colors.teal,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.teal,
                  tabs: [
                    Tab(icon: Icon(Icons.list_alt), text: 'Спецификация (СО)'),
                    Tab(icon: Icon(Icons.tune), text: 'Конструктор шаблона'),
                  ],
                ),
                const SizedBox(height: 12),

                Expanded(
                  child: TabBarView(
                    children: [
                      // Вкладка 1: Просмотр спецификации и экспорт
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Панель действий: поиск, выбор шаблона, кнопки экспорта
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (_availableTemplates.isNotEmpty) ...[
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Шаблон: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    DropdownButton<String>(
                                      value: _activeTemplate?.id,
                                      isDense: true,
                                      items: _availableTemplates.map((t) {
                                        return DropdownMenuItem(
                                          value: t.id,
                                          child: Text(t.name, style: const TextStyle(fontSize: 12)),
                                        );
                                      }).toList(),
                                      onChanged: (id) {
                                        if (id != null) {
                                          setState(() {
                                            _activeTemplate = _availableTemplates.firstWhere((t) => t.id == id);
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ],
                              FilledButton.icon(
                                icon: const Icon(Icons.table_view, size: 16),
                                label: const Text('Экспорт в Excel (.xlsx)'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.teal.shade700,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: allRows.isEmpty ? null : _exportSpecificationExcel,
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.download, size: 16),
                                label: const Text('Сохранить CSV'),
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: allRows.isEmpty ? null : () => _exportCsvFile(csv),
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Скопировать CSV'),
                                style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: allRows.isEmpty
                                    ? null
                                    : () {
                                        Clipboard.setData(ClipboardData(text: csv));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Спецификация (CSV) скопирована в буфер обмена'),
                                            backgroundColor: Colors.teal,
                                          ),
                                        );
                                      },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Поисковая строка
                          SizedBox(
                            height: 38,
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Поиск по наименованию, марке, ГОСТ или материалу...',
                                hintStyle: const TextStyle(fontSize: 13),
                                prefixIcon: const Icon(Icons.search, size: 18),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 16),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              onChanged: (val) => setState(() => _searchQuery = val),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Фильтр категорий
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _categories.map((cat) {
                                final count = categoryCounts[cat] ?? 0;
                                final isSelected = _selectedCategory == cat;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: FilterChip(
                                    label: Text('$cat ($count)'),
                                    labelStyle: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? Colors.white : Colors.black87,
                                    ),
                                    selected: isSelected,
                                    selectedColor: Colors.teal,
                                    backgroundColor: Colors.grey.shade100,
                                    checkmarkColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                    onSelected: (val) {
                                      setState(() {
                                        _selectedCategory = cat;
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Таблица спецификации
                          Expanded(
                            child: allRows.isEmpty
                                ? const Center(child: Text('Спецификация пуста (на схеме нет элементов)'))
                                : filteredRows.isEmpty
                                    ? const Center(child: Text('По заданным фильтрам ничего не найдено'))
                                    : Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey.shade300),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.vertical,
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: DataTable(
                                              headingRowColor: WidgetStateProperty.all(Colors.teal.shade50),
                                              columnSpacing: 16,
                                              horizontalMargin: 12,
                                              columns: const [
                                                DataColumn(label: Text('Поз.', style: TextStyle(fontWeight: FontWeight.bold))),
                                                DataColumn(label: Text('Наименование и техническая характеристика', style: TextStyle(fontWeight: FontWeight.bold))),
                                                DataColumn(label: Text('Тип, марка', style: TextStyle(fontWeight: FontWeight.bold))),
                                                DataColumn(label: Text('Обозначение документа', style: TextStyle(fontWeight: FontWeight.bold))),
                                                DataColumn(label: Text('Код / Завод', style: TextStyle(fontWeight: FontWeight.bold))),
                                                DataColumn(label: Text('Ед. изм.', style: TextStyle(fontWeight: FontWeight.bold))),
                                                DataColumn(label: Text('Кол-во', style: TextStyle(fontWeight: FontWeight.bold))),
                                                DataColumn(label: Text('Масса ед., кг', style: TextStyle(fontWeight: FontWeight.bold))),
                                                DataColumn(label: Text('Примечание', style: TextStyle(fontWeight: FontWeight.bold))),
                                              ],
                                              rows: filteredRows.map((r) {
                                                return DataRow(
                                                  cells: [
                                                    DataCell(Text(r[0])),
                                                    DataCell(ConstrainedBox(
                                                      constraints: const BoxConstraints(maxWidth: 320),
                                                      child: Text(r[1], overflow: TextOverflow.ellipsis),
                                                    )),
                                                    DataCell(Text(r[2])),
                                                    DataCell(Text(r[3])),
                                                    DataCell(Text(r[4])),
                                                    DataCell(Text(r[5], style: const TextStyle(fontWeight: FontWeight.bold))),
                                                    DataCell(Text(r[6])),
                                                    DataCell(Text(r.length > 8 ? r[7] : '')),
                                                    DataCell(Text(r.length > 8 ? r[8] : (r.length > 7 ? r[7] : ''), style: const TextStyle(color: Colors.black54))),
                                                  ],
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ),
                                      ),
                          ),
                          if (_statusMessage != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _statusMessage!,
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ],
                        ],
                      ),

                      // Вкладка 2: Конструктор шаблона спецификации
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ReportTemplateBuilderWidget(
                          reportType: ReportType.materialsSpecification,
                          network: widget.network,
                          controller: widget.controller,
                          initialTemplate: _activeTemplate ?? ReportTemplate.defaultMtoGostTemplate,
                          onTemplateChanged: (t) {
                            setState(() => _activeTemplate = t);
                            _loadTemplates();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<List<String>> _parseCsvRows(String csv) {
    final lines = csv.trim().split('\n');
    if (lines.length <= 1) return [];

    final result = <List<String>>[];
    // Пропускаем строку заголовка (lines[0])
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = line.split(';');
      while (parts.length < 9) {
        parts.add('');
      }
      result.add(parts);
    }
    return result;
  }
}
