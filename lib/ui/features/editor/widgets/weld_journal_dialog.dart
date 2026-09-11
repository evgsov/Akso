import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/dxf/dxf_writer.dart';
import '../../../../domain/enums/inspection_method.dart';
import '../../../../domain/enums/weld_type.dart';
import '../../../../domain/models/piping_network.dart';

class WeldJournalDialog extends StatelessWidget {
  final PipingNetwork network;

  const WeldJournalDialog({super.key, required this.network});

  @override
  Widget build(BuildContext context) {
    final welds = network.weldJoints.values.toList()..sort((a, b) => a.number.compareTo(b.number));
    final spools = network.spools.values.toList();

    return DefaultTabController(
      length: 2,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 800,
          height: 600,
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Всего стыков: ${welds.length}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Скопировать CSV'),
                              onPressed: () {
                                final csv = DxfWriter.generateWeldJournalCsv(network);
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
                                      headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
                                       columns: const [
                                        DataColumn(label: Text('№ шва')),
                                        DataColumn(label: Text('Диаметр')),
                                        DataColumn(label: Text('Тип шва')),
                                        DataColumn(label: Text('Марка стали')),
                                        DataColumn(label: Text('Св. материалы')),
                                        DataColumn(label: Text('Клеймо')),
                                        DataColumn(label: Text('Контроль')),
                                        DataColumn(label: Text('Дата')),
                                        DataColumn(label: Text('Результат')),
                                      ],
                                      rows: welds.map((w) {
                                        final seg = network.segments[w.segmentId];
                                        return DataRow(cells: [
                                          DataCell(Text('№${w.number}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                          DataCell(Text(seg != null ? 'Ду${seg.dn}' : '—')),
                                          DataCell(Text(w.weldType.shortName)),
                                          DataCell(Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(w.steelGrade, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          )),
                                          DataCell(Text(w.electrodeGrade, style: const TextStyle(fontSize: 11))),
                                          DataCell(Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(w.stamp, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          )),
                                          DataCell(Text(w.inspectionMethod.displayName)),
                                          DataCell(Text(w.date)),
                                          DataCell(Text(w.notes, style: const TextStyle(color: Colors.green))),
                                        ]);
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
                                final csv = DxfWriter.generateSpoolsCsv(network);
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
