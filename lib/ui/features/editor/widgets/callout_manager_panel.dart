import 'package:flutter/material.dart';
import '../../../../domain/enums/fitting_type.dart';
import '../../../../domain/models/callout.dart';
import '../../../canvas/input_controller.dart';

/// Модальная панель управления умными выносками (Smart Callouts Manager)
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

  @override
  Widget build(BuildContext context) {
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
            final text = widget.controller.getCalloutText(c).toLowerCase();
            final targetId = c.targetId.toLowerCase();
            if (!text.contains(query) && !targetId.contains(query)) {
              return false;
            }
          }
          return true;
        }).toList();

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 960,
            height: 650,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, allCallouts.length),
                const SizedBox(height: 16),
                _buildToolbar(context),
                const SizedBox(height: 12),
                Expanded(
                  child: filteredCallouts.isEmpty
                      ? _buildEmptyState(allCallouts.isEmpty)
                      : _buildCalloutsTable(filteredCallouts),
                ),
              ],
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
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Закрыть',
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Row(
      children: [
        FilledButton.icon(
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
        const SizedBox(width: 16),
        // Фильтр по типам
        DropdownButton<CalloutTargetType?>(
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
        ),
        const SizedBox(width: 16),
        // Поиск
        Expanded(
          child: TextField(
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
          ),
        ),
      ],
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
              dataRowMaxHeight: 56,
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('Тип', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Объект', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Режим', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Текст выноски', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Смещение', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Удалить', style: TextStyle(fontWeight: FontWeight.bold))),
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
    final renderedText = widget.controller.getCalloutText(callout);

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
            width: 140,
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
        // 4. Текст выноски
        DataCell(
          SizedBox(
            width: 320,
            child: callout.isCustom
                ? TextFormField(
                    initialValue: callout.customText ?? renderedText,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onFieldSubmitted: (newText) {
                      widget.controller.updateCalloutCustomText(callout.id, newText);
                    },
                  )
                : Tooltip(
                    message: 'Генерируется динамически по шаблону проекта',
                    child: Text(
                      renderedText,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                      overflow: TextOverflow.ellipsis,
                    ),
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
        // 6. Удалить
        DataCell(
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
            tooltip: 'Удалить выноску',
            onPressed: () {
              widget.controller.removeCallout(callout.id);
            },
          ),
        ),
      ],
    );
  }

  String _getTargetDescription(Callout callout) {
    final net = widget.controller.network;
    switch (callout.targetType) {
      case CalloutTargetType.segment:
        final s = net.segments[callout.targetId];
        return s != null ? 'DN${s.dn} (${s.id})' : callout.targetId;
      case CalloutTargetType.valve:
        final v = net.valves[callout.targetId];
        return v != null ? '${v.name} Ду${v.dn}' : callout.targetId;
      case CalloutTargetType.weld:
        final w = net.weldJoints[callout.targetId];
        return w != null ? 'Стык №${w.number > 0 ? w.number : w.id}' : callout.targetId;
      case CalloutTargetType.equipment:
        final eq = net.equipments[callout.targetId];
        return eq != null ? eq.name : callout.targetId;
      case CalloutTargetType.fitting:
        final f = net.fittings[callout.targetId] ??
            net.fittings.values.where((fit) => fit.id == callout.targetId).firstOrNull;
        return f != null ? (f.name ?? f.fittingType.displayName) : callout.targetId;
      case CalloutTargetType.support:
        final sup = net.supports[callout.targetId];
        return sup != null ? sup.name : callout.targetId;
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
      case CalloutTargetType.support:
        return Colors.orange.shade800;
      case CalloutTargetType.node:
        return Colors.blueGrey.shade700;
    }
  }
}
