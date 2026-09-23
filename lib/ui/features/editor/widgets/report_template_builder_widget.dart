import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../data/repositories/report_template_repository.dart';
import '../../../../domain/enums/report_type.dart';
import '../../../../domain/models/piping_network.dart';
import '../../../../domain/models/report_template.dart';
import '../../../../domain/models/report_token_definition.dart';
import '../../../../domain/services/report_engine.dart';
import '../../../canvas/input_controller.dart';

/// Виджет гибкого визуального конструктора шаблонов ведомостей и журналов с чипами и предпросмотром
class ReportTemplateBuilderWidget extends StatefulWidget {
  final ReportType reportType;
  final PipingNetwork network;
  final PipingInputController? controller;
  final ReportTemplate? initialTemplate;
  final ReportTemplateRepository? repository;
  final ValueChanged<ReportTemplate>? onTemplateChanged;

  const ReportTemplateBuilderWidget({
    super.key,
    required this.reportType,
    required this.network,
    this.controller,
    this.repository,
    this.initialTemplate,
    this.onTemplateChanged,
  });

  @override
  State<ReportTemplateBuilderWidget> createState() => _ReportTemplateBuilderWidgetState();
}

class _ReportTemplateBuilderWidgetState extends State<ReportTemplateBuilderWidget> {
  late ReportTemplateRepository _repository;
  List<ReportTemplate> _availableTemplates = [];
  late ReportTemplate _activeTemplate;
  int _activeColumnIndex = 0;
  bool _isLoading = true;
  bool _isPaletteCollapsed = false;
  String _tokenSearchQuery = '';
  bool _showSampleData = false;

  final ScrollController _columnsScrollController = ScrollController();
  final ScrollController _previewVerticalController = ScrollController();
  final ScrollController _previewHorizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? widget.controller?.reportTemplateRepository ?? ReportTemplateRepository();
    if (widget.initialTemplate != null) {
      _activeTemplate = widget.initialTemplate!;
      _availableTemplates = [_activeTemplate];
      _isLoading = false;
    }
    _loadTemplates();
  }

  @override
  void dispose() {
    _columnsScrollController.dispose();
    _previewVerticalController.dispose();
    _previewHorizontalController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    if (widget.initialTemplate == null) {
      setState(() => _isLoading = true);
    }
    final templates = await _repository.getTemplatesForType(
      widget.reportType,
      project: widget.controller?.currentProject,
    );

    ReportTemplate initial = widget.initialTemplate ??
        templates.firstWhere(
          (t) => t.type == widget.reportType,
          orElse: () => ReportTemplate.defaultTemplates.firstWhere((t) => t.type == widget.reportType),
        );

    // Если шаблон уже есть в списке, берем его
    final existing = templates.where((t) => t.id == initial.id).firstOrNull;
    if (existing != null) {
      initial = existing;
    }

    if (mounted) {
      setState(() {
        _availableTemplates = templates;
        _activeTemplate = initial;
        _activeColumnIndex = 0;
        _isLoading = false;
      });
      widget.onTemplateChanged?.call(_activeTemplate);
    }
  }

  void _notifyChange() {
    widget.onTemplateChanged?.call(_activeTemplate);
    setState(() {});
  }

  void _insertTokenToActiveColumn(String tokenCode) {
    if (_activeTemplate.columns.isEmpty) return;
    if (_activeColumnIndex < 0 || _activeColumnIndex >= _activeTemplate.columns.length) {
      _activeColumnIndex = 0;
    }

    final col = _activeTemplate.columns[_activeColumnIndex];
    final newTemplateStr = col.template.isEmpty ? tokenCode : '${col.template} $tokenCode';

    final updatedColumns = List<ReportColumn>.from(_activeTemplate.columns);
    updatedColumns[_activeColumnIndex] = col.copyWith(template: newTemplateStr);

    _activeTemplate = _activeTemplate.copyWith(columns: updatedColumns);
    _notifyChange();
  }

  void _addNewColumn() {
    final newCol = ReportColumn(
      id: 'col_${DateTime.now().millisecondsSinceEpoch}',
      header: 'Новый столбец',
      template: '{num}',
      width: 120,
    );

    final updatedColumns = List<ReportColumn>.from(_activeTemplate.columns)..add(newCol);
    _activeTemplate = _activeTemplate.copyWith(columns: updatedColumns);
    _activeColumnIndex = updatedColumns.length - 1;
    _notifyChange();
  }

  void _addNewColumnFromToken(ReportTokenDefinition token) {
    final newCol = ReportColumn(
      id: 'col_${DateTime.now().millisecondsSinceEpoch}',
      header: token.label,
      template: token.code,
      groupHeader: (token.category == 'Общие' || token.category == 'Геодезия') ? null : token.category,
      width: 120,
      alignment: token.category == 'Контроль' ||
              token.code == '{stamp}' ||
              token.code == '{weld_type}' ||
              token.code == '{num}' ||
              token.code == '{date}'
          ? TextAlign.center
          : TextAlign.left,
    );
    final updatedColumns = List<ReportColumn>.from(_activeTemplate.columns)..add(newCol);
    _activeTemplate = _activeTemplate.copyWith(columns: updatedColumns);
    _activeColumnIndex = updatedColumns.length - 1;
    _notifyChange();
  }

  void _duplicateColumn(int idx) {
    if (idx < 0 || idx >= _activeTemplate.columns.length) return;
    final src = _activeTemplate.columns[idx];
    final copy = src.copyWith(
      id: 'col_${DateTime.now().millisecondsSinceEpoch}',
      header: '${src.header} (копия)',
    );
    final updatedColumns = List<ReportColumn>.from(_activeTemplate.columns)..insert(idx + 1, copy);
    _activeTemplate = _activeTemplate.copyWith(columns: updatedColumns);
    _activeColumnIndex = idx + 1;
    _notifyChange();
  }

  void _moveColumn(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _activeTemplate.columns.length) return;
    if (newIndex < 0 || newIndex >= _activeTemplate.columns.length) return;
    final cols = List<ReportColumn>.from(_activeTemplate.columns);
    final moved = cols.removeAt(oldIndex);
    cols.insert(newIndex, moved);
    _activeTemplate = _activeTemplate.copyWith(columns: cols);
    _activeColumnIndex = newIndex;
    _notifyChange();
  }

  void _insertTokenToColumn(int colIdx, String tokenCode) {
    if (colIdx < 0 || colIdx >= _activeTemplate.columns.length) return;
    final col = _activeTemplate.columns[colIdx];
    final newTemplateStr = col.template.isEmpty ? tokenCode : '${col.template} $tokenCode';
    final cols = List<ReportColumn>.from(_activeTemplate.columns);
    cols[colIdx] = col.copyWith(template: newTemplateStr);
    _activeTemplate = _activeTemplate.copyWith(columns: cols);
    _activeColumnIndex = colIdx;
    _notifyChange();
  }

  void _duplicateTemplate() {
    final copyId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final copyTemplate = _activeTemplate.copyWith(
      id: copyId,
      name: '${_activeTemplate.name} (копия)',
      isBuiltIn: false,
    );

    setState(() {
      _availableTemplates = [..._availableTemplates, copyTemplate];
      _activeTemplate = copyTemplate;
      _activeColumnIndex = 0;
    });
    _notifyChange();
  }

  Future<void> _saveActiveTemplate() async {
    if (widget.controller != null) {
      await widget.controller!.saveReportTemplate(_activeTemplate);
    } else {
      await _repository.saveTemplate(_activeTemplate);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Шаблон "${_activeTemplate.name}" сохранен'),
          backgroundColor: Colors.teal.shade800,
        ),
      );
      _loadTemplates();
    }
  }

  Future<void> _deleteActiveTemplate() async {
    if (_activeTemplate.isBuiltIn) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удаление шаблона'),
        content: Text('Вы действительно хотите удалить шаблон "${_activeTemplate.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (widget.controller != null) {
        await widget.controller!.deleteReportTemplate(_activeTemplate.id);
      } else {
        await _repository.deleteTemplate(_activeTemplate.id);
      }
      await _loadTemplates();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Верхняя панель управления шаблонами
        _buildTemplateHeaderBar(),
        const SizedBox(height: 12),

        // 2. Палитра чипов-токенов
        _buildChipPaletteCard(),
        const SizedBox(height: 12),

        // 3. Столбцы шаблона и живой предпросмотр
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Левая колонка: список столбцов с настройками
              Expanded(
                flex: 4,
                child: _buildColumnsManagerPanel(),
              ),
              const SizedBox(width: 16),

              // Правая колонка: живой интерактивный предпросмотр таблицы
              Expanded(
                flex: 5,
                child: _buildLivePreviewPanel(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateHeaderBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.dashboard_customize_outlined, size: 20, color: Colors.indigo),
              const SizedBox(width: 8),
              const Text('Шаблон: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 4),
              DropdownButton<String>(
                value: _availableTemplates.any((t) => t.id == _activeTemplate.id) ? _activeTemplate.id : null,
                items: _availableTemplates.map((t) {
                  return DropdownMenuItem(
                    value: t.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.name, style: const TextStyle(fontSize: 13)),
                        if (t.isBuiltIn) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('ГОСТ', style: TextStyle(fontSize: 9, color: Colors.indigo, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (id) {
                  if (id != null) {
                    final selected = _availableTemplates.firstWhere((t) => t.id == id);
                    setState(() {
                      _activeTemplate = selected;
                      _activeColumnIndex = 0;
                    });
                    _notifyChange();
                  }
                },
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Дублировать', style: TextStyle(fontSize: 12)),
                onPressed: _duplicateTemplate,
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Сохранить', style: TextStyle(fontSize: 12)),
                onPressed: _saveActiveTemplate,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (!_activeTemplate.isBuiltIn)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  tooltip: 'Удалить шаблон',
                  onPressed: _deleteActiveTemplate,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChipPaletteCard() {
    final groupedTokens = ReportTokenDefinition.getGroupedTokensForType(widget.reportType);
    final activeColName = _activeTemplate.columns.isNotEmpty && _activeColumnIndex < _activeTemplate.columns.length
        ? _activeTemplate.columns[_activeColumnIndex].header
        : '—';

    if (_isPaletteCollapsed) {
      return Card(
        elevation: 0,
        color: Colors.indigo.shade50.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.indigo.shade100),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.touch_app_outlined, size: 16, color: Colors.indigo),
              const SizedBox(width: 8),
              const Text('Палитра токенов', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Активный столбец: $activeColName',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.indigo.shade900),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.expand_more, size: 16),
                label: const Text('Развернуть палитру', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => setState(() => _isPaletteCollapsed = false),
              ),
            ],
          ),
        ),
      );
    }

    final filteredGroups = <String, List<ReportTokenDefinition>>{};
    for (final entry in groupedTokens.entries) {
      final list = entry.value.where((t) {
        if (_tokenSearchQuery.isEmpty) return true;
        final q = _tokenSearchQuery.toLowerCase();
        return t.code.toLowerCase().contains(q) || t.label.toLowerCase().contains(q);
      }).toList();
      if (list.isNotEmpty) {
        filteredGroups[entry.key] = list;
      }
    }

    return Card(
      elevation: 0,
      color: Colors.indigo.shade50.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.indigo.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.touch_app_outlined, size: 18, color: Colors.indigo),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Кликните на чип для вставки в: ',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.indigo),
                  ),
                  child: Text(
                    activeColName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.indigo.shade900),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 180,
                  height: 30,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Поиск токена...',
                      prefixIcon: const Icon(Icons.search, size: 14),
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    style: const TextStyle(fontSize: 11),
                    onChanged: (q) => setState(() => _tokenSearchQuery = q.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.expand_less, size: 16),
                  label: const Text('Свернуть', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() => _isPaletteCollapsed = true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: filteredGroups.entries.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key.toUpperCase(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: entry.value.map((token) {
                            return ActionChip(
                              label: Text('${token.code} (${token.label})'),
                              backgroundColor: Colors.indigo.shade50,
                              side: BorderSide(color: Colors.indigo.shade100),
                              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _insertTokenToActiveColumn(token.code),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnsManagerPanel() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.view_column_outlined, size: 18, color: Colors.indigo),
                    const SizedBox(width: 8),
                    Text(
                      'Столбцы шаблона (${_activeTemplate.columns.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _addNewColumn,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('+ Добавить столбец', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                    ),
                    const SizedBox(width: 6),
                PopupMenuButton<dynamic>(
                  tooltip: 'Добавить поле из каталога',
                  onSelected: (val) {
                    if (val == '__empty__') {
                      _addNewColumn();
                    } else if (val is ReportTokenDefinition) {
                      _addNewColumnFromToken(val);
                    }
                  },
                  itemBuilder: (ctx) {
                    final grouped = ReportTokenDefinition.getGroupedTokensForType(widget.reportType);
                    final items = <PopupMenuEntry<dynamic>>[];

                    for (final entry in grouped.entries) {
                      items.add(PopupMenuItem<dynamic>(
                        enabled: false,
                        height: 24,
                        child: Text(
                          '— ${entry.key.toUpperCase()} —',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo),
                        ),
                      ));
                      for (final token in entry.value) {
                        items.add(PopupMenuItem<dynamic>(
                          value: token,
                          height: 32,
                          child: Row(
                            children: [
                              Text(token.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                              const Spacer(),
                              Text(
                                token.code,
                                style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ));
                      }
                      items.add(const PopupMenuDivider(height: 8));
                    }

                    items.add(const PopupMenuItem<dynamic>(
                      value: '__empty__',
                      height: 34,
                      child: Row(
                        children: [
                          Icon(Icons.add_circle_outline, size: 16, color: Colors.teal),
                          SizedBox(width: 8),
                          Text('+ Пустой произвольный столбец', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
                        ],
                      ),
                    ));

                    return items;
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.playlist_add, size: 16, color: Colors.indigo.shade800),
                        const SizedBox(width: 4),
                        Text(
                          '+ Из каталога ▾',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
          Expanded(
            child: _activeTemplate.columns.isEmpty
                ? const Center(child: Text('Нет столбцов'))
                : ReorderableListView.builder(
                    scrollController: _columnsScrollController,
                    primary: false,
                    padding: const EdgeInsets.all(8),
                    itemCount: _activeTemplate.columns.length,
                    onReorder: (oldIndex, newIndex) {
                      if (oldIndex < newIndex) newIndex -= 1;
                      _moveColumn(oldIndex, newIndex);
                    },
                    itemBuilder: (context, idx) {
                      final col = _activeTemplate.columns[idx];
                      final isSelected = idx == _activeColumnIndex;

                      return Container(
                        key: ValueKey(col.id),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.indigo.shade50.withValues(alpha: 0.6) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? Colors.indigo : Colors.grey.shade300,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: ExpansionTile(
                          key: PageStorageKey(col.id),
                          initiallyExpanded: isSelected,
                          onExpansionChanged: (exp) {
                            if (exp) setState(() => _activeColumnIndex = idx);
                          },
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.drag_indicator, size: 18, color: Colors.grey),
                              const SizedBox(width: 2),
                              Text(
                                '${idx + 1}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(width: 4),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: idx > 0 ? () => _moveColumn(idx, idx - 1) : null,
                                    child: Icon(Icons.arrow_drop_up, size: 18, color: idx > 0 ? Colors.indigo : Colors.grey.shade300),
                                  ),
                                  InkWell(
                                    onTap: idx < _activeTemplate.columns.length - 1 ? () => _moveColumn(idx, idx + 1) : null,
                                    child: Icon(Icons.arrow_drop_down, size: 18, color: idx < _activeTemplate.columns.length - 1 ? Colors.indigo : Colors.grey.shade300),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  col.header,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (col.groupHeader != null && col.groupHeader!.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.blueGrey.shade200),
                                  ),
                                  child: Text(
                                    col.groupHeader!,
                                    style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade800),
                                  ),
                                ),
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Text(
                                  '${col.width.round()} px',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            col.template,
                            style: TextStyle(fontSize: 11, color: Colors.indigo.shade700, fontFamily: 'monospace'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 17, color: Colors.indigo),
                                tooltip: 'Дублировать столбец',
                                onPressed: () => _duplicateColumn(idx),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                tooltip: 'Удалить столбец',
                                onPressed: () {
                                  if (_activeTemplate.columns.length <= 1) return;
                                  final cols = List<ReportColumn>.from(_activeTemplate.columns)..removeAt(idx);
                                  _activeTemplate = _activeTemplate.copyWith(columns: cols);
                                  if (_activeColumnIndex >= cols.length) {
                                    _activeColumnIndex = cols.length - 1;
                                  }
                                  _notifyChange();
                                },
                              ),
                            ],
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          key: ValueKey('header_${col.id}_${col.header}'),
                                          initialValue: col.header,
                                          decoration: const InputDecoration(
                                            labelText: 'Заголовок столбца',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                          style: const TextStyle(fontSize: 12),
                                          onChanged: (val) {
                                            final cols = List<ReportColumn>.from(_activeTemplate.columns);
                                            cols[idx] = col.copyWith(header: val);
                                            _activeTemplate = _activeTemplate.copyWith(columns: cols);
                                            _notifyChange();
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          key: ValueKey('group_${col.id}_${col.groupHeader}'),
                                          initialValue: col.groupHeader ?? '',
                                          decoration: const InputDecoration(
                                            labelText: 'Группа (шапка Excel)',
                                            hintText: 'Элемент №1, Заключения',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                          style: const TextStyle(fontSize: 12),
                                          onChanged: (val) {
                                            final cols = List<ReportColumn>.from(_activeTemplate.columns);
                                            cols[idx] = col.copyWith(
                                              groupHeader: val.trim().isEmpty ? null : val.trim(),
                                              clearGroupHeader: val.trim().isEmpty,
                                            );
                                            _activeTemplate = _activeTemplate.copyWith(columns: cols);
                                            _notifyChange();
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          key: ValueKey('template_${col.id}_${col.template}'),
                                          initialValue: col.template,
                                          decoration: const InputDecoration(
                                            labelText: 'Формула / Токены',
                                            hintText: '{elem1_name} Ду{elem1_dn}',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                                          onChanged: (val) {
                                            final cols = List<ReportColumn>.from(_activeTemplate.columns);
                                            cols[idx] = col.copyWith(template: val);
                                            _activeTemplate = _activeTemplate.copyWith(columns: cols);
                                            _notifyChange();
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      PopupMenuButton<String>(
                                        tooltip: 'Вставить токен в формулу',
                                        onSelected: (code) => _insertTokenToColumn(idx, code),
                                        itemBuilder: (ctx) {
                                          final allTokens = ReportTokenDefinition.getTokensForType(widget.reportType);
                                          return allTokens.map((t) {
                                            return PopupMenuItem<String>(
                                              value: t.code,
                                              height: 32,
                                              child: Row(
                                                children: [
                                                  Text(t.label, style: const TextStyle(fontSize: 12)),
                                                  const Spacer(),
                                                  Text(
                                                    t.code,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontFamily: 'monospace',
                                                      color: Colors.indigo.shade700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList();
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.indigo.shade200),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.add_link, size: 16, color: Colors.indigo),
                                              SizedBox(width: 4),
                                              Text(
                                                '+ Токен',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Text('Ширина:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 75,
                                        height: 32,
                                        child: TextFormField(
                                          key: ValueKey('width_${col.id}_${col.width}'),
                                          initialValue: col.width.round().toString(),
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            suffixText: 'px',
                                          ),
                                          style: const TextStyle(fontSize: 11),
                                          onChanged: (val) {
                                            final w = double.tryParse(val.trim());
                                            if (w != null && w >= 40 && w <= 600) {
                                              final cols = List<ReportColumn>.from(_activeTemplate.columns);
                                              cols[idx] = col.copyWith(width: w);
                                              _activeTemplate = _activeTemplate.copyWith(columns: cols);
                                              _notifyChange();
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Wrap(
                                        spacing: 4,
                                        children: [80, 100, 120, 150, 180, 220].map((presetW) {
                                          final isCurrent = col.width.round() == presetW;
                                          return InkWell(
                                            onTap: () {
                                              final cols = List<ReportColumn>.from(_activeTemplate.columns);
                                              cols[idx] = col.copyWith(width: presetW.toDouble());
                                              _activeTemplate = _activeTemplate.copyWith(columns: cols);
                                              _notifyChange();
                                            },
                                            borderRadius: BorderRadius.circular(4),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: isCurrent ? Colors.indigo : Colors.grey.shade100,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: isCurrent ? Colors.indigo : Colors.grey.shade300),
                                              ),
                                              child: Text(
                                                '$presetW',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isCurrent ? Colors.white : Colors.black87,
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    alignment: WrapAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Checkbox(
                                            value: col.isNumeric,
                                            visualDensity: VisualDensity.compact,
                                            onChanged: (val) {
                                              final cols = List<ReportColumn>.from(_activeTemplate.columns);
                                              cols[idx] = col.copyWith(isNumeric: val ?? false);
                                              _activeTemplate = _activeTemplate.copyWith(columns: cols);
                                              _notifyChange();
                                            },
                                          ),
                                          const Text('Числовой (Excel)', style: TextStyle(fontSize: 11)),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('Выравнивание: ', style: TextStyle(fontSize: 11)),
                                          DropdownButton<TextAlign>(
                                            value: col.alignment,
                                            isDense: true,
                                            items: const [
                                              DropdownMenuItem(value: TextAlign.left, child: Text('По левому', style: TextStyle(fontSize: 11))),
                                              DropdownMenuItem(value: TextAlign.center, child: Text('По центру', style: TextStyle(fontSize: 11))),
                                              DropdownMenuItem(value: TextAlign.right, child: Text('По правому', style: TextStyle(fontSize: 11))),
                                            ],
                                            onChanged: (align) {
                                              if (align != null) {
                                                final cols = List<ReportColumn>.from(_activeTemplate.columns);
                                                cols[idx] = col.copyWith(alignment: align);
                                                _activeTemplate = _activeTemplate.copyWith(columns: cols);
                                                _notifyChange();
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreviewPanel() {
    final realDataRows = ReportEngine.generateTableData(_activeTemplate, widget.network);
    final isUsingSample = _showSampleData || realDataRows.isEmpty;
    final dataRows = isUsingSample ? ReportEngine.generateSampleData(_activeTemplate) : realDataRows;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                const Icon(Icons.table_chart_outlined, size: 18, color: Colors.indigo),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Живой предпросмотр таблицы данных',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _showSampleData = !_showSampleData),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isUsingSample ? Colors.amber.shade50 : Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: isUsingSample ? Colors.amber.shade300 : Colors.indigo.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUsingSample ? Icons.science_outlined : Icons.storage_outlined,
                          size: 13,
                          color: isUsingSample ? Colors.amber.shade900 : Colors.indigo,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isUsingSample ? 'Демо-образцы (${dataRows.length})' : 'Сеть (${dataRows.length})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isUsingSample ? Colors.amber.shade900 : Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isUsingSample && realDataRows.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              color: Colors.amber.shade50,
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 13, color: Colors.amber.shade900),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'В проекте еще нет элементов этого типа — отображаются демо-данные для настройки',
                      style: TextStyle(fontSize: 10, color: Colors.amber.shade900),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: dataRows.isEmpty
                ? Center(
                    child: Text(
                      'В проекте пока нет элементов для этого типа отчета',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  )
                : Scrollbar(
                    controller: _previewVerticalController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _previewVerticalController,
                      primary: false,
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        controller: _previewHorizontalController,
                        primary: false,
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
                          headingRowHeight: 40,
                          dataRowMinHeight: 32,
                          dataRowMaxHeight: 38,
                          columnSpacing: 14,
                          columns: _activeTemplate.columns.map((col) {
                            final w = math.max(65.0, col.width * 0.85);
                            return DataColumn(
                              label: SizedBox(
                                width: w,
                                child: Column(
                                  crossAxisAlignment: col.alignment == TextAlign.center
                                      ? CrossAxisAlignment.center
                                      : (col.alignment == TextAlign.right
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start),
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (col.groupHeader != null && col.groupHeader!.isNotEmpty)
                                      Text(
                                        col.groupHeader!,
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.indigo.shade800,
                                          fontWeight: FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    Text(
                                      col.header,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: col.alignment,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                          rows: dataRows.map((row) {
                            return DataRow(
                              cells: List.generate(row.length, (colIdx) {
                                final cellVal = row[colIdx]?.toString() ?? '';
                                final col = colIdx < _activeTemplate.columns.length
                                    ? _activeTemplate.columns[colIdx]
                                    : null;
                                final align = col?.alignment ?? TextAlign.left;
                                final w = col != null ? math.max(65.0, col.width * 0.85) : 80.0;
                                return DataCell(
                                  SizedBox(
                                    width: w,
                                    child: Text(
                                      cellVal,
                                      textAlign: align,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: col?.isNumeric == true ? 'monospace' : null,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                );
                              }),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
