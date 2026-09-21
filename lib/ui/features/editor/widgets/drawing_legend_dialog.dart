import 'package:flutter/material.dart';
import '../../../../domain/models/drawing_legend.dart';

/// Диалог настройки и редактирования блока «Условные обозначения»
class DrawingLegendDialog extends StatefulWidget {
  final DrawingLegend legend;
  final ValueChanged<DrawingLegend> onSave;

  const DrawingLegendDialog({
    super.key,
    required this.legend,
    required this.onSave,
  });

  @override
  State<DrawingLegendDialog> createState() => _DrawingLegendDialogState();
}

class _DrawingLegendDialogState extends State<DrawingLegendDialog> {
  late bool _isVisible;
  late TextEditingController _titleController;
  late bool _hasBorder;
  late List<LegendItem> _items;

  @override
  void initState() {
    super.initState();
    _isVisible = widget.legend.isVisible;
    _titleController = TextEditingController(text: widget.legend.title);
    _hasBorder = widget.legend.hasBorder;
    _items = List<LegendItem>.from(widget.legend.items);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _addNewItem() {
    setState(() {
      _items.add(
        LegendItem(
          id: 'leg_${DateTime.now().millisecondsSinceEpoch}',
          type: LegendItemType.custom,
          label: '- новое обозначение',
        ),
      );
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.list_alt, color: Color(0xFF1976D2)),
          SizedBox(width: 8),
          Text('Условные обозначения чертежа', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                title: const Text('Отображать условные обозначения на листе'),
                value: _isVisible,
                onChanged: (val) => setState(() => _isVisible = val),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Заголовок блока',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Рамка вокруг блока'),
                value: _hasBorder,
                onChanged: (val) => setState(() => _hasBorder = val),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Элементы условных обозначений:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить пункт'),
                    onPressed: _addNewItem,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Список условных обозначений пуст')),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  onReorder: (oldIdx, newIdx) {
                    setState(() {
                      if (oldIdx < newIdx) newIdx -= 1;
                      final item = _items.removeAt(oldIdx);
                      _items.insert(newIdx, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      key: ValueKey(item.id),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Checkbox(
                              value: item.isVisible,
                              onChanged: (val) {
                                setState(() {
                                  _items[index] = item.copyWith(isVisible: val ?? true);
                                });
                              },
                            ),
                            _buildItemIcon(item.type),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                children: [
                                  TextFormField(
                                    initialValue: item.label,
                                    decoration: const InputDecoration(
                                      labelText: 'Основная подпись',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) {
                                      _items[index] = item.copyWith(label: val);
                                    },
                                  ),
                                  if (item.type == LegendItemType.dimension) ...[
                                    const SizedBox(height: 6),
                                    TextFormField(
                                      initialValue: item.subLabel ?? '',
                                      decoration: const InputDecoration(
                                        labelText: 'Вторая строка (фактический размер)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) {
                                        _items[index] = item.copyWith(subLabel: val);
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              tooltip: 'Удалить',
                              onPressed: () => _removeItem(index),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final updated = widget.legend.copyWith(
              isVisible: _isVisible,
              title: _titleController.text.trim(),
              hasBorder: _hasBorder,
              items: _items,
            );
            widget.onSave(updated);
            Navigator.of(context).pop();
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _buildItemIcon(LegendItemType type) {
    switch (type) {
      case LegendItemType.dimension:
        return const Icon(Icons.straighten, color: Color(0xFF1976D2), size: 24);
      case LegendItemType.elevation:
        return const Icon(Icons.arrow_drop_up, color: Color(0xFF00897B), size: 28);
      case LegendItemType.pipeSystem:
        return const Icon(Icons.horizontal_rule, color: Color(0xFF0288D1), size: 24);
      case LegendItemType.weldJoint:
        return const Icon(Icons.lens, color: Colors.redAccent, size: 16);
      case LegendItemType.valve:
        return const Icon(Icons.tune, color: Color(0xFF6D4C41), size: 20);
      case LegendItemType.fitting:
        return const Icon(Icons.rounded_corner, color: Color(0xFF5E35B1), size: 20);
      case LegendItemType.custom:
        return const Icon(Icons.label_outline, color: Colors.blueGrey, size: 20);
    }
  }
}
