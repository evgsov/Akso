import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/dxf/dxf_writer.dart';
import '../../../../domain/enums/inspection_method.dart';
import '../../../../domain/enums/weld_type.dart';
import '../../../../domain/models/piping_network.dart';
import '../../../canvas/input_controller.dart';

/// Диалог «Исполнительная ведомость сети» с интерактивным массовым и инлайн-редактированием сварных стыков
class WeldJournalDialog extends StatefulWidget {
  final PipingNetwork network;
  final PipingInputController? controller;
  final VoidCallback? onModified;

  const WeldJournalDialog({
    super.key,
    required this.network,
    this.controller,
    this.onModified,
  });

  @override
  State<WeldJournalDialog> createState() => _WeldJournalDialogState();
}

class _WeldJournalDialogState extends State<WeldJournalDialog> {
  final Set<String> _selectedWeldIds = {};

  static const List<String> _standardSteelGrades = [
    'Сталь 20',
    '09Г2С',
    '12Х18Н10Т',
    '10ХСНД',
    '15Х5М',
    '12Х1МФ',
  ];

  static const List<String> _standardElectrodeGrades = [
    'УОНИ 13/55',
    'ЦЛ-11',
    'МТГ-01К',
    'Э-42А',
    'Св-08Г2С',
    'LB-52U',
  ];

  void _commitChange() {
    if (widget.controller != null) {
      widget.controller!.history.recordState(widget.network);
      widget.controller!.refresh();
    }
    widget.onModified?.call();
    setState(() {});
  }

  Future<String?> _showTextPromptDialog(BuildContext context, {required String title, required String initialValue, required String hint}) async {
    final tc = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: tc,
          autofocus: true,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(tc.text.trim()), child: const Text('Применить')),
        ],
      ),
    );
  }

  Future<void> _batchSetStamp() async {
    final stamp = await _showTextPromptDialog(
      context,
      title: 'Клеймо для ${_selectedWeldIds.length} стыков',
      initialValue: 'ИВ-01',
      hint: 'Например: ИВ-02, 12-А',
    );
    if (stamp != null && stamp.isNotEmpty) {
      widget.network.bulkUpdateWeldJoints(_selectedWeldIds, stamp: stamp);
      _commitChange();
    }
  }

  Future<void> _batchSetDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      final dateStr = picked.toIso8601String().substring(0, 10);
      widget.network.bulkUpdateWeldJoints(_selectedWeldIds, date: dateStr);
      _commitChange();
    }
  }

  void _batchSetMethod(InspectionMethod method) {
    widget.network.bulkUpdateWeldJoints(_selectedWeldIds, inspectionMethod: method);
    _commitChange();
  }

  void _batchSetWeldType(WeldType type) {
    widget.network.bulkUpdateWeldJoints(_selectedWeldIds, weldType: type);
    _commitChange();
  }

  void _batchSetSteelGrade(String grade) {
    widget.network.bulkUpdateWeldJoints(_selectedWeldIds, steelGrade: grade);
    _commitChange();
  }

  void _batchSetElectrode(String electrode) {
    widget.network.bulkUpdateWeldJoints(_selectedWeldIds, electrodeGrade: electrode);
    _commitChange();
  }

  Widget _buildBatchToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.checklist, size: 18, color: Colors.amber),
              const SizedBox(width: 6),
              Text(
                'Выбрано: ${_selectedWeldIds.length}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),

          // Клеймо
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.badge, size: 15),
            label: const Text('Клеймо', style: TextStyle(fontSize: 12)),
            onPressed: _batchSetStamp,
          ),

          // Контроль
          PopupMenuButton<InspectionMethod>(
            tooltip: 'Задать метод контроля',
            onSelected: _batchSetMethod,
            itemBuilder: (ctx) => InspectionMethod.values.map((m) {
              return PopupMenuItem(value: m, child: Text(m.displayName));
            }).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search, size: 14),
                  SizedBox(width: 4),
                  Text('Контроль ▾', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),

          // Тип шва
          PopupMenuButton<WeldType>(
            tooltip: 'Задать тип шва по ГОСТ',
            onSelected: _batchSetWeldType,
            itemBuilder: (ctx) => WeldType.values.map((t) {
              return PopupMenuItem(value: t, child: Text('${t.shortName} (${t.gostCode})'));
            }).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.architecture, size: 14),
                  SizedBox(width: 4),
                  Text('Тип шва ▾', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),

          // Дата
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.calendar_today, size: 14),
            label: const Text('Дата', style: TextStyle(fontSize: 12)),
            onPressed: _batchSetDate,
          ),

          // Сталь
          PopupMenuButton<String>(
            tooltip: 'Задать марку стали',
            onSelected: _batchSetSteelGrade,
            itemBuilder: (ctx) => _standardSteelGrades.map((g) {
              return PopupMenuItem(value: g, child: Text(g));
            }).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers, size: 14),
                  SizedBox(width: 4),
                  Text('Сталь ▾', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),

          // Материалы
          PopupMenuButton<String>(
            tooltip: 'Задать сварочные материалы',
            onSelected: _batchSetElectrode,
            itemBuilder: (ctx) => _standardElectrodeGrades.map((e) {
              return PopupMenuItem(value: e, child: Text(e));
            }).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hardware, size: 14),
                  SizedBox(width: 4),
                  Text('Материалы ▾', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),

          // Снять выделение
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => setState(() => _selectedWeldIds.clear()),
            child: const Text('Снять выбор', style: TextStyle(fontSize: 12, color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final welds = widget.network.weldJoints.values.toList()..sort((a, b) => a.number.compareTo(b.number));
    final spools = widget.network.spools.values.toList();
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = math.min(980.0, screenSize.width * 0.95);
    final dialogHeight = math.min(680.0, screenSize.height * 0.90);

    return DefaultTabController(
      length: 2,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.table_chart, color: Colors.indigo),
                  const SizedBox(width: 12),
                  const Text(
                    'Исполнительная ведомость сети',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const TabBar(
                labelColor: Colors.indigo,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.indigo,
                tabs: [
                  Tab(icon: Icon(Icons.hardware), text: 'Журнал сварных стыков'),
                  Tab(icon: Icon(Icons.straighten), text: 'Ведомость катушек (заготовок)'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    // Вкладка 1: Сварные соединения
                    Column(
                      children: [
                        if (_selectedWeldIds.isNotEmpty) _buildBatchToolbar(),
                        Row(
                          children: [
                            Text(
                              'Всего стыков: ${welds.length}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (welds.isNotEmpty) ...[
                              const SizedBox(width: 16),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    if (_selectedWeldIds.length == welds.length) {
                                      _selectedWeldIds.clear();
                                    } else {
                                      _selectedWeldIds.addAll(welds.map((w) => w.id));
                                    }
                                  });
                                },
                                child: Text(
                                  _selectedWeldIds.length == welds.length ? 'Снять все' : 'Выбрать все',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                            const Spacer(),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Скопировать CSV'),
                              onPressed: () {
                                final csv = DxfWriter.generateWeldJournalCsv(widget.network);
                                Clipboard.setData(ClipboardData(text: csv));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Журнал сварки скопирован в буфер обмена')),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: welds.isEmpty
                              ? const Center(child: Text('На схеме пока нет сварных стыков'))
                              : SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      showCheckboxColumn: true,
                                      onSelectAll: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedWeldIds.addAll(welds.map((w) => w.id));
                                          } else {
                                            _selectedWeldIds.clear();
                                          }
                                        });
                                      },
                                      headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
                                      columns: const [
                                        DataColumn(label: Text('№ шва')),
                                        DataColumn(label: Text('Диаметр')),
                                        DataColumn(label: Text('Тип шва ✎')),
                                        DataColumn(label: Text('Марка стали ✎')),
                                        DataColumn(label: Text('Св. материалы ✎')),
                                        DataColumn(label: Text('Клеймо ✎')),
                                        DataColumn(label: Text('Контроль ✎')),
                                        DataColumn(label: Text('Дата ✎')),
                                        DataColumn(label: Text('Результат ✎')),
                                      ],
                                      rows: welds.map((w) {
                                        final seg = widget.network.segments[w.segmentId];
                                        final isSelected = _selectedWeldIds.contains(w.id);

                                        return DataRow(
                                          selected: isSelected,
                                          onSelectChanged: (selected) {
                                            setState(() {
                                              if (selected == true) {
                                                _selectedWeldIds.add(w.id);
                                              } else {
                                                _selectedWeldIds.remove(w.id);
                                              }
                                            });
                                          },
                                          cells: [
                                            // Номер шва
                                            DataCell(Text('№${w.number}', style: const TextStyle(fontWeight: FontWeight.bold))),

                                            // Диаметр
                                            DataCell(Text(seg != null ? 'Ду${seg.dn}' : '—')),

                                            // Тип шва (инлайн Popup)
                                            DataCell(
                                              PopupMenuButton<WeldType>(
                                                tooltip: 'Изменить тип шва',
                                                initialValue: w.weldType,
                                                onSelected: (wt) {
                                                  widget.network.updateWeldJoint(w.id, (old) => old.copyWith(weldType: wt));
                                                  _commitChange();
                                                },
                                                itemBuilder: (ctx) => WeldType.values.map((t) {
                                                  return PopupMenuItem(value: t, child: Text('${t.shortName} (${t.gostCode})'));
                                                }).toList(),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(w.weldType.shortName),
                                                    const Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey),
                                                  ],
                                                ),
                                              ),
                                            ),

                                            // Марка стали (инлайн Popup)
                                            DataCell(
                                              PopupMenuButton<String>(
                                                tooltip: 'Изменить марку стали',
                                                initialValue: w.steelGrade,
                                                onSelected: (grade) {
                                                  widget.network.updateWeldJoint(w.id, (old) => old.copyWith(steelGrade: grade));
                                                  _commitChange();
                                                },
                                                itemBuilder: (ctx) => _standardSteelGrades.map((g) {
                                                  return PopupMenuItem(value: g, child: Text(g));
                                                }).toList(),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade200,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(w.steelGrade, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                      const Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Сварочные материалы (инлайн Popup + ввод)
                                            DataCell(
                                              PopupMenuButton<String>(
                                                tooltip: 'Изменить материалы',
                                                initialValue: w.electrodeGrade,
                                                onSelected: (val) {
                                                  widget.network.updateWeldJoint(w.id, (old) => old.copyWith(electrodeGrade: val));
                                                  _commitChange();
                                                },
                                                itemBuilder: (ctx) => _standardElectrodeGrades.map((e) {
                                                  return PopupMenuItem(value: e, child: Text(e));
                                                }).toList(),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(w.electrodeGrade, style: const TextStyle(fontSize: 11)),
                                                    const Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey),
                                                  ],
                                                ),
                                              ),
                                            ),

                                            // Клеймо (инлайн ввод)
                                            DataCell(
                                              InkWell(
                                                borderRadius: BorderRadius.circular(4),
                                                onTap: () async {
                                                  final newStamp = await _showTextPromptDialog(
                                                    context,
                                                    title: 'Клеймо стыка №${w.number}',
                                                    initialValue: w.stamp,
                                                    hint: 'Например: ИВ-01',
                                                  );
                                                  if (newStamp != null && newStamp.isNotEmpty) {
                                                    widget.network.updateWeldJoint(w.id, (old) => old.copyWith(stamp: newStamp));
                                                    _commitChange();
                                                  }
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.shade100,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(w.stamp, style: const TextStyle(fontWeight: FontWeight.bold)),
                                                      const SizedBox(width: 4),
                                                      const Icon(Icons.edit, size: 12, color: Colors.brown),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Метод контроля (инлайн Popup)
                                            DataCell(
                                              PopupMenuButton<InspectionMethod>(
                                                tooltip: 'Изменить метод контроля',
                                                initialValue: w.inspectionMethod,
                                                onSelected: (m) {
                                                  widget.network.updateWeldJoint(w.id, (old) => old.copyWith(inspectionMethod: m));
                                                  _commitChange();
                                                },
                                                itemBuilder: (ctx) => InspectionMethod.values.map((m) {
                                                  return PopupMenuItem(value: m, child: Text(m.displayName));
                                                }).toList(),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(w.inspectionMethod.displayName),
                                                    const Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey),
                                                  ],
                                                ),
                                              ),
                                            ),

                                            // Дата (инлайн DatePicker)
                                            DataCell(
                                              InkWell(
                                                borderRadius: BorderRadius.circular(4),
                                                onTap: () async {
                                                  DateTime initial = DateTime.now();
                                                  try {
                                                    if (w.date.isNotEmpty) initial = DateTime.parse(w.date);
                                                  } catch (_) {}
                                                  final picked = await showDatePicker(
                                                    context: context,
                                                    initialDate: initial,
                                                    firstDate: DateTime(2020),
                                                    lastDate: DateTime(2035),
                                                  );
                                                  if (picked != null) {
                                                    final dStr = picked.toIso8601String().substring(0, 10);
                                                    widget.network.updateWeldJoint(w.id, (old) => old.copyWith(date: dStr));
                                                    _commitChange();
                                                  }
                                                },
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(w.date.isEmpty ? '—' : w.date),
                                                    const SizedBox(width: 4),
                                                    const Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                                                  ],
                                                ),
                                              ),
                                            ),

                                            // Результат / примечание
                                            DataCell(
                                              InkWell(
                                                borderRadius: BorderRadius.circular(4),
                                                onTap: () async {
                                                  final res = await _showTextPromptDialog(
                                                    context,
                                                    title: 'Примечание к стыку №${w.number}',
                                                    initialValue: w.notes,
                                                    hint: 'Например: Годен, РК-100%, Ремонт',
                                                  );
                                                  if (res != null) {
                                                    widget.network.updateWeldJoint(w.id, (old) => old.copyWith(notes: res));
                                                    _commitChange();
                                                  }
                                                },
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(w.notes, style: const TextStyle(color: Colors.green)),
                                                    const SizedBox(width: 4),
                                                    const Icon(Icons.edit, size: 12, color: Colors.grey),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),

                    // Вкладка 2: Катушки
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Всего катушек: ${spools.length}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Скопировать CSV'),
                              onPressed: () {
                                final csv = DxfWriter.generateSpoolsCsv(widget.network);
                                Clipboard.setData(ClipboardData(text: csv));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Ведомость катушек скопирована в буфер обмена')),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: spools.isEmpty
                              ? const Center(child: Text('На схеме пока нет катушек'))
                              : SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      headingRowColor: WidgetStateProperty.all(Colors.teal.shade50),
                                      columns: const [
                                        DataColumn(label: Text('Позиция')),
                                        DataColumn(label: Text('Диаметр DN')),
                                        DataColumn(label: Text('Стенка S (мм)')),
                                        DataColumn(label: Text('Длина реза (мм)')),
                                        DataColumn(label: Text('Материал')),
                                      ],
                                      rows: spools.map((sp) {
                                        return DataRow(cells: [
                                          DataCell(Text(sp.number, style: const TextStyle(fontWeight: FontWeight.bold))),
                                          DataCell(Text('Ду${sp.dn}')),
                                          DataCell(Text('${sp.wallThickness} мм')),
                                          DataCell(Text(
                                            '${sp.cutLengthMm.toStringAsFixed(0)} мм',
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                                          )),
                                          DataCell(Text(sp.material)),
                                        ]);
                                      }).toList(),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
