import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../domain/enums/fitting_type.dart';
import '../../../../domain/models/callout.dart';
import '../../../canvas/input_controller.dart';

/// Модальная панель управления умными выносками (Smart Callouts Manager)
/// с поддержкой адаптивного размера, двухполочных выносок по ГОСТ и конструктора шаблонов
class CalloutManagerPanel extends StatefulWidget {
  final PipingInputController controller;

  const CalloutManagerPanel({super.key, required this.controller});

  static Future<void> show(
    BuildContext context, {
    required PipingInputController controller,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CalloutManagerPanel(controller: controller),
    );
  }

  @override
  State<CalloutManagerPanel> createState() => _CalloutManagerPanelState();
}

class _CalloutManagerPanelState extends State<CalloutManagerPanel> {
  CalloutTargetType? _selectedFilterType;
  String _searchQuery = '';
  bool _isMaximized = false;

  // Состояние конструктора шаблонов
  CalloutTargetType _templateType = CalloutTargetType.segment;
  final TextEditingController _topTemplateController = TextEditingController();
  final TextEditingController _bottomTemplateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTemplateForType(_templateType);
  }

  @override
  void dispose() {
    _topTemplateController.dispose();
    _bottomTemplateController.dispose();
    super.dispose();
  }

  void _loadTemplateForType(CalloutTargetType type) {
    final templates = widget.controller.currentProject.calloutTemplates;
    final top = templates[type.name] ?? type.defaultTemplate;
    final bottom = templates['${type.name}_bottom'] ?? '';
    _topTemplateController.text = top;
    _bottomTemplateController.text = bottom;
  }

  void _saveCurrentTemplate() {
    widget.controller.updateCalloutTemplate(_templateType.name, _topTemplateController.text);
    widget.controller.updateCalloutTemplate('${_templateType.name}_bottom', _bottomTemplateController.text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Шаблон для ${_templateType.displayName} успешно сохранен'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _resetTemplateToDefault() {
    _topTemplateController.text = _templateType.defaultTemplate;
    _bottomTemplateController.text = '';
    _saveCurrentTemplate();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = _isMaximized ? screenSize.width * 0.98 : math.min(1150.0, screenSize.width * 0.92);
    final dialogHeight = _isMaximized ? screenSize.height * 0.96 : math.min(780.0, screenSize.height * 0.88);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final network = widget.controller.network;
        final allCallouts = network.callouts.values.toList();

        final filteredCallouts = allCallouts.where((c) {
          if (_selectedFilterType != null && c.targetType != _selectedFilterType) {
            return false;
          }
          if (_searchQuery.trim().isNotEmpty) {
            final query = _searchQuery.trim().toLowerCase();
            final topText = widget.controller.getCalloutText(c).toLowerCase();
            final bottomText = (widget.controller.getCalloutBottomText(c) ?? '').toLowerCase();
            final targetId = c.targetId.toLowerCase();
            if (!topText.contains(query) && !bottomText.contains(query) && !targetId.contains(query)) {
              return false;
            }
          }
          return true;
        }).toList();

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: dialogWidth,
            height: dialogHeight,
            padding: const EdgeInsets.all(20),
            child: DefaultTabController(
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context, allCallouts.length),
                  const SizedBox(height: 12),
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: Colors.indigo,
                    indicatorColor: Colors.indigo,
                    tabs: [
                      Tab(
                        icon: Icon(Icons.table_chart_outlined, size: 18),
                        text: 'Выноски в проекте',
                      ),
                      Tab(
                        icon: Icon(Icons.tune_outlined, size: 18),
                        text: 'Конструктор шаблонов (ГОСТ / AutoCAD)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Вкладка 1: Таблица выносок
                        Column(
                          children: [
                            _buildToolbar(context),
                            const SizedBox(height: 12),
                            Expanded(
                              child: filteredCallouts.isEmpty
                                  ? _buildEmptyState(allCallouts.isEmpty)
                                  : _buildCalloutsTable(filteredCallouts),
                            ),
                          ],
                        ),
                        // Вкладка 2: Конструктор шаблонов
                        _buildTemplateBuilderTab(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int totalCount) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.label_important_outline, color: Colors.indigo),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Менеджер выносок и аннотаций',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Всего выносок в проекте: $totalCount',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          icon: Icon(_isMaximized ? Icons.fullscreen_exit : Icons.fullscreen),
          tooltip: _isMaximized ? 'Восстановить размер' : 'Развернуть на весь экран',
          onPressed: () {
            setState(() {
              _isMaximized = !_isMaximized;
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Закрыть',
        ),
      ],
    );
  }

  Widget _buildGenerateAllButton(BuildContext context) {
    return Tooltip(
      message: 'Сгенерировать все недостающие выноски проекта',
      child: FilledButton.icon(
        onPressed: () {
          final added = widget.controller.generateMissingCallouts();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                added > 0
                    ? 'Создано $added новых выносок'
                    : 'Все объекты уже имеют выноски',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: const Text('Сгенерировать недостающие'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.indigo,
        ),
      ),
    );
  }

  Widget _buildWeldsButton(BuildContext context) {
    return Tooltip(
      message: 'Сгенерировать технологические стыки на элементах и выноски для них',
      child: FilledButton.tonalIcon(
        onPressed: () {
          final res = widget.controller.generateWeldsAndCallouts();
          final welds = res['welds'] ?? 0;
          final callouts = res['callouts'] ?? 0;
          String msg;
          if (welds > 0 && callouts > 0) {
            msg = 'Сгенерировано стыков: $welds, выносок: $callouts';
          } else if (callouts > 0) {
            msg = 'Создано $callouts выносок для стыков';
          } else if (welds > 0) {
            msg = 'Сгенерировано $welds сварных стыков';
          } else {
            msg = 'Все стыки и их выноски уже созданы';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
          );
        },
        icon: const Icon(Icons.adjust, size: 18),
        label: const Text('Стыки'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }

  Widget _buildElementsButton(BuildContext context) {
    return Tooltip(
      message: 'Сгенерировать выноски для арматуры, деталей и оборудования',
      child: FilledButton.tonalIcon(
        onPressed: () {
          final added = widget.controller.generateElementCallouts();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                added > 0
                    ? 'Создано $added выносок для элементов'
                    : 'Все элементы уже имеют выноски',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        icon: const Icon(Icons.category_outlined, size: 18),
        label: const Text('Элементы'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return DropdownButton<CalloutTargetType?>(
      value: _selectedFilterType,
      hint: const Text('Все типы'),
      underline: const SizedBox(),
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('Все типы'),
        ),
        ...CalloutTargetType.values.map(
          (type) => DropdownMenuItem(
            value: type,
            child: Text(type.displayName),
          ),
        ),
      ],
      onChanged: (val) {
        setState(() {
          _selectedFilterType = val;
        });
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Поиск по тексту или ID объекта...',
        prefixIcon: const Icon(Icons.search, size: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onChanged: (val) {
        setState(() {
          _searchQuery = val;
        });
      },
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 850;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildGenerateAllButton(context),
                  _buildWeldsButton(context),
                  _buildElementsButton(context),
                  _buildFilterDropdown(),
                ],
              ),
              const SizedBox(height: 8),
              _buildSearchField(),
            ],
          );
        }
        return Row(
          children: [
            _buildGenerateAllButton(context),
            const SizedBox(width: 8),
            _buildWeldsButton(context),
            const SizedBox(width: 8),
            _buildElementsButton(context),
            const SizedBox(width: 12),
            _buildFilterDropdown(),
            const SizedBox(width: 12),
            Expanded(child: _buildSearchField()),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(bool isCompletelyEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isCompletelyEmpty ? Icons.post_add_outlined : Icons.filter_alt_off_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            isCompletelyEmpty
                ? 'В проекте пока нет выносок'
                : 'Нет выносок, соответствующих фильтру',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            isCompletelyEmpty
                ? 'Нажмите «Сгенерировать недостающие», чтобы создать выноски по умолчанию для труб, арматуры и стыков'
                : 'Попробуйте сбросить фильтры или строку поиска',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCalloutsTable(List<Callout> callouts) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
              dataRowMinHeight: 48,
              dataRowMaxHeight: 64,
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('Тип', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Объект', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Режим', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Текст над/под полкой', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Смещение', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Действия', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: callouts.map((callout) {
                return _buildDataRow(callout);
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildDataRow(Callout callout) {
    final targetDescription = _getTargetDescription(callout);
    final topText = widget.controller.getCalloutText(callout);
    final bottomText = widget.controller.getCalloutBottomText(callout);

    return DataRow(
      key: ValueKey(callout.id),
      cells: [
        // 1. Тип
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getTypeColor(callout.targetType).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _getTypeColor(callout.targetType).withValues(alpha: 0.4)),
            ),
            child: Text(
              callout.targetType.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _getTypeColor(callout.targetType),
              ),
            ),
          ),
        ),
        // 2. Объект
        DataCell(
          SizedBox(
            width: 150,
            child: Text(
              targetDescription,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        // 3. Режим (по шаблону / свой)
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                callout.isCustom ? 'Свой' : 'Шаблон',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: callout.isCustom ? Colors.orange.shade800 : Colors.indigo.shade700,
                ),
              ),
              const SizedBox(width: 4),
              Switch(
                value: callout.isCustom,
                activeThumbColor: Colors.orange,
                onChanged: (isCustom) {
                  widget.controller.toggleCalloutMode(callout.id, isCustom);
                },
              ),
            ],
          ),
        ),
        // 4. Текст выноски (двухполочный)
        DataCell(
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Text('Над: ', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        topText,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (bottomText != null && bottomText.isNotEmpty)
                  Row(
                    children: [
                      const Text('Под: ', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(
                          bottomText,
                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        // 5. Смещение
        DataCell(
          Text(
            '${callout.screenOffsetX.round()}, ${callout.screenOffsetY.round()}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        // 6. Действия
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (callout.isCustom)
                IconButton(
                  icon: const Icon(Icons.edit_note, size: 20, color: Colors.indigo),
                  tooltip: 'Редактировать текст над и под полкой',
                  onPressed: () => _showEditCalloutDialog(context, callout),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                tooltip: 'Удалить выноску',
                onPressed: () {
                  widget.controller.removeCallout(callout.id);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showEditCalloutDialog(BuildContext context, Callout callout) {
    final topCtrl = TextEditingController(text: callout.customText ?? widget.controller.getCalloutText(callout));
    final bottomCtrl = TextEditingController(text: callout.customBottomText ?? widget.controller.getCalloutBottomText(callout) ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Редактирование выноски (${callout.targetType.displayName})'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: topCtrl,
                decoration: const InputDecoration(
                  labelText: 'Текст над полкой (основной)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: bottomCtrl,
                decoration: const InputDecoration(
                  labelText: 'Текст под полкой (дополнительный)',
                  hintText: 'Оставьте пустым, если не требуется',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              widget.controller.updateCalloutCustomText(callout.id, topCtrl.text);
              widget.controller.updateCalloutCustomBottomText(
                callout.id,
                bottomCtrl.text.trim().isEmpty ? null : bottomCtrl.text,
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateBuilderTab(BuildContext context) {
    final availablePlaceholders = _getPlaceholdersForType(_templateType);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Выбор типа объекта
          Row(
            children: [
              const Text('Категория элементов:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 16),
              DropdownButton<CalloutTargetType>(
                value: _templateType,
                items: CalloutTargetType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.displayName),
                  );
                }).toList(),
                onChanged: (newType) {
                  if (newType != null) {
                    setState(() {
                      _templateType = newType;
                      _loadTemplateForType(newType);
                    });
                  }
                },
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Сбросить к стандарту ГОСТ'),
                onPressed: _resetTemplateToDefault,
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Сохранить шаблон'),
                style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: _saveCurrentTemplate,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Доступные плейсхолдеры (чипы)
          Card(
            color: Colors.blue.shade50.withValues(alpha: 0.5),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.blue.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.touch_app_outlined, size: 18, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'Кликните на чип для вставки плейсхолдера в шаблон:',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: availablePlaceholders.entries.map((entry) {
                      return ActionChip(
                        label: Text('${entry.key} — ${entry.value}'),
                        backgroundColor: Colors.white,
                        side: BorderSide(color: Colors.indigo.shade200),
                        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        onPressed: () {
                          _insertChip(entry.key);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. Поля редактирования текста над и под полкой
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _topTemplateController,
                      decoration: const InputDecoration(
                        labelText: 'Текст над полкой (основной)',
                        hintText: 'например: Ø{DN}x{WALL} {MATERIAL}',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.arrow_upward, size: 18),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bottomTemplateController,
                      decoration: const InputDecoration(
                        labelText: 'Текст под полкой (дополнительный)',
                        hintText: 'например: {STANDARD} или оставьте пустым',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.arrow_downward, size: 18),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // 4. Интерактивный предпросмотр выноски
              Expanded(
                child: Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Stack(
                    children: [
                      const Positioned(
                        top: 8,
                        left: 12,
                        child: Text(
                          'ПРЕДПРОСМОТР ВЫНОСКИ (ГОСТ 2.316)',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                      ),
                      Center(
                        child: _buildCalloutPreview(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _insertChip(String placeholder) {
    // Вставляем в верхнее поле, если активно или по умолчанию
    final text = _topTemplateController.text;
    final selection = _topTemplateController.selection;
    if (selection.start >= 0 && selection.end >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, placeholder);
      _topTemplateController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + placeholder.length),
      );
    } else {
      _topTemplateController.text = text + placeholder;
    }
    setState(() {});
  }

  Widget _buildCalloutPreview() {
    final previewTop = _formatPreviewText(_topTemplateController.text);
    final previewBottom = _formatPreviewText(_bottomTemplateController.text);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Точка на объекте
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            shape: BoxShape.circle,
          ),
        ),
        // Линия-ножка
        Container(
          width: 30,
          height: 1.5,
          color: const Color(0xFF1E293B),
        ),
        // Полочка с текстом
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              previewTop.isNotEmpty ? previewTop : 'Текст над полкой',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF1E293B),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              height: 1.5,
              width: math.max(140.0, math.max(previewTop.length, previewBottom.length) * 8.5),
              color: const Color(0xFF1E293B),
            ),
            if (previewBottom.isNotEmpty)
              Text(
                previewBottom,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF475569),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _formatPreviewText(String template) {
    if (template.isEmpty) return '';
    return template
        .replaceAll('{DN}', '80')
        .replaceAll('{DN2}', '50')
        .replaceAll('{WALL}', '4.0')
        .replaceAll('{S}', '4.0')
        .replaceAll('{D_OUT}', '89')
        .replaceAll('{OD}', '89')
        .replaceAll('{OUTER_DIAMETER}', '89')
        .replaceAll('{MATERIAL}', 'Сталь 20')
        .replaceAll('{STANDARD}', 'ГОСТ 10704-91')
        .replaceAll('{SYSTEM}', 'В1')
        .replaceAll('{ID}', 'К-1')
        .replaceAll('{NUM}', '1')
        .replaceAll('{NUMBER}', '1')
        .replaceAll('{STAMP}', 'СВ-01')
        .replaceAll('{DATE}', '18.09.2024')
        .replaceAll('{TYPE}', 'Задвижка')
        .replaceAll('{NAME}', 'Задвижка 30с41нж')
        .replaceAll('{TAG}', 'Е-1')
        .replaceAll('{DIMENSIONS}', '1200x3000x1500')
        .replaceAll('{EQUIPMENT}', 'Емкость Е-1')
        .replaceAll('{EQUIPMENT_TAG}', 'Е-1')
        .replaceAll('{FACE}', 'top')
        .replaceAll('{SERIAL}', '48219')
        .replaceAll('{SERIAL_NUMBER}', '48219')
        .replaceAll('{BATCH}', 'ПЛ-530')
        .replaceAll('{SPOOL}', 'К-1')
        .replaceAll('{LENGTH}', '2400')
        .replaceAll('{L}', '2400')
        .replaceAll('{L_CUT}', '2400')
        .replaceAll('{CUT_LENGTH}', '2400')
        .replaceAll('{STEEL}', 'Сталь 20')
        .replaceAll('{ELECTRODE}', 'УОНИ-13/55');
  }

  Map<String, String> _getPlaceholdersForType(CalloutTargetType type) {
    switch (type) {
      case CalloutTargetType.segment:
        return {
          '{SPOOL}': 'Марка катушки из ведомости (напр. К-1)',
          '{NUM}': 'Номер катушки или трубы (К-1)',
          '{DN}': 'Диаметр условный (напр. 80)',
          '{WALL}': 'Толщина стенки (напр. 4.0)',
          '{D_OUT}': 'Наружный диаметр (напр. 89)',
          '{CUT_LENGTH}': 'Длина заготовки реза (мм)',
          '{MATERIAL}': 'Марка стали (напр. Сталь 20)',
          '{NAME}': 'Маркировка / наименование (напр. К-1)',
          '{SERIAL}': 'Зав. № / партия (актуально Ду≥500)',
          '{SYSTEM}': 'Код системы (напр. В1)',
          '{ID}': 'Марка катушки / трубы',
        };
      case CalloutTargetType.valve:
        return {
          '{NAME}': 'Наименование арматуры',
          '{TAG}': 'Позиция арматуры',
          '{SERIAL}': 'Заводской номер арматуры',
          '{DN}': 'Диаметр условный',
          '{TYPE}': 'Тип арматуры (задвижка/кран/клапан)',
          '{LENGTH}': 'Строительная длина (мм)',
          '{ID}': 'Наименование / позиция',
        };
      case CalloutTargetType.weld:
        return {
          '{NUM}': 'Номер шва в журнале (напр. 1)',
          '{DATE}': 'Дата выполнения шва (напр. 18.09.2024)',
          '{STAMP}': 'Клеймо сварщика (напр. СВ-01)',
          '{TYPE}': 'Тип сварного шва (С17/У18)',
          '{STEEL}': 'Марка стали стыкуемых труб',
          '{ELECTRODE}': 'Марка электрода',
          '{METHOD}': 'Метод контроля (ВИК/РК/УЗК)',
          '{ID}': 'Номер шва (напр. 1)',
        };
      case CalloutTargetType.fitting:
        return {
          '{NAME}': 'Наименование детали',
          '{TAG}': 'Марка детали',
          '{SERIAL}': 'Зав. № / партия детали',
          '{TYPE}': 'Тип фитинга (отвод/тройник/переход)',
          '{STANDARD}': 'Стандарт ГОСТ',
          '{MATERIAL}': 'Материал детали',
          '{DN}': 'Основной диаметр',
          '{DN2}': 'Вторичный диаметр (для переходов)',
          '{ID}': 'Наименование детали',
        };
      case CalloutTargetType.equipment:
        return {
          '{TAG}': 'Короткая позиция/тег (напр. Е-1, Н-1)',
          '{NAME}': 'Полное наименование оборудования',
          '{TYPE}': 'Тип (насос/бак/емкость)',
          '{DIMENSIONS}': 'Габариты ШхДхВ (мм)',
          '{SERIAL}': 'Заводской номер оборудования',
          '{ID}': 'Позиция аппарата (Е-1)',
        };
      case CalloutTargetType.nozzle:
        return {
          '{NAME}': 'Обозначение штуцера (напр. Ш-1, А1)',
          '{DN}': 'Диаметр условный (напр. 80)',
          '{EQUIPMENT}': 'Наименование аппарата (Емкость Е-1)',
          '{EQUIPMENT_TAG}': 'Позиция аппарата (Е-1)',
          '{FACE}': 'Грань оборудования',
          '{ID}': 'Обозначение штуцера',
        };
      case CalloutTargetType.support:
        return {
          '{NAME}': 'Наименование / марка опоры (напр. ОП-1)',
          '{TYPE}': 'Тип опоры (скользящая/неподвижная)',
          '{CODE}': 'Код типа (ОП/НО/ПП)',
          '{ID}': 'Марка опоры',
        };
      case CalloutTargetType.node:
        return {
          '{NUM}': 'Номер узла',
          '{Z}': 'Отметка высоты Z (мм)',
          '{X}': 'Координата X (мм)',
          '{Y}': 'Координата Y (мм)',
          '{ID}': 'Номер узла',
        };
    }
  }

  String _getTargetDescription(Callout callout) {
    final net = widget.controller.network;
    switch (callout.targetType) {
      case CalloutTargetType.segment:
        final s = net.segments[callout.targetId];
        final spool = net.spools.values.where((sp) => sp.segmentId == callout.targetId).firstOrNull;
        final mark = spool?.number ?? s?.id ?? callout.targetId;
        return s != null ? '$mark (DN${s.dn})' : callout.targetId;
      case CalloutTargetType.valve:
        final v = net.valves[callout.targetId];
        return v != null ? '${v.name} Ду${v.dn}' : callout.targetId;
      case CalloutTargetType.weld:
        final w = net.weldJoints[callout.targetId];
        return w != null ? 'Стык №${w.number > 0 ? w.number : w.id}' : callout.targetId;
      case CalloutTargetType.equipment:
        final eq = net.equipments[callout.targetId];
        return eq != null ? eq.name : callout.targetId;
      case CalloutTargetType.nozzle:
        for (final eq in net.equipments.values) {
          for (final n in eq.nozzles) {
            if (n.id == callout.targetId) {
              return '${n.name} Ду${n.dn} (${eq.name})';
            }
          }
        }
        return 'Штуцер ${callout.targetId}';
      case CalloutTargetType.fitting:
        final f = net.fittings[callout.targetId] ??
            net.fittings.values.where((fit) => fit.id == callout.targetId).firstOrNull;
        return f != null ? (f.name ?? f.fittingType.displayName) : callout.targetId;
      case CalloutTargetType.support:
        final sup = net.supports[callout.targetId];
        return sup != null ? (sup.name.isNotEmpty ? sup.name : sup.type.displayName) : callout.targetId;
      case CalloutTargetType.node:
        return 'Узел ${callout.targetId}';
    }
  }

  Color _getTypeColor(CalloutTargetType type) {
    switch (type) {
      case CalloutTargetType.segment:
        return Colors.blue.shade700;
      case CalloutTargetType.valve:
        return Colors.amber.shade900;
      case CalloutTargetType.weld:
        return Colors.deepPurple.shade700;
      case CalloutTargetType.fitting:
        return Colors.indigo.shade700;
      case CalloutTargetType.equipment:
        return Colors.teal.shade700;
      case CalloutTargetType.nozzle:
        return Colors.cyan.shade800;
      case CalloutTargetType.support:
        return Colors.orange.shade800;
      case CalloutTargetType.node:
        return Colors.blueGrey.shade700;
    }
  }
}

