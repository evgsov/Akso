import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/dxf/dxf_writer.dart';
import '../../../../domain/models/piping_network.dart';

class MaterialsSpecificationDialog extends StatelessWidget {
  final PipingNetwork network;

  const MaterialsSpecificationDialog({super.key, required this.network});

  @override
  Widget build(BuildContext context) {
    final csv = DxfWriter.generateMtoCsv(network);
    final rows = _parseCsvRows(csv);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 960,
        height: 640,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.list_alt, color: Colors.teal),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Спецификация оборудования, изделий и материалов (СО)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'ГОСТ 21.110-2013 / СП 73.13330 / ГОСТ 21.602',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Скопировать CSV'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: csv));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Спецификация (CSV) скопирована в буфер обмена'),
                        backgroundColor: Colors.teal,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text(
                        'В проекте пока нет элементов для спецификации',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(Colors.teal.shade50),
                          columns: const [
                            DataColumn(label: Text('Поз.')),
                            DataColumn(label: Text('Наименование и тех. характеристика')),
                            DataColumn(label: Text('Тип, марка')),
                            DataColumn(label: Text('ГОСТ / ТУ')),
                            DataColumn(label: Text('Материал')),
                            DataColumn(label: Text('Кол-во')),
                            DataColumn(label: Text('Ед.')),
                            DataColumn(label: Text('Примечание')),
                          ],
                          rows: rows.map((r) {
                            return DataRow(
                              cells: [
                                DataCell(Text(r[0], style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(r[1])),
                                DataCell(Text(r[2])),
                                DataCell(Text(r[3])),
                                DataCell(Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Text(r[4], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                )),
                                DataCell(Text(r[5], style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(r[6])),
                                DataCell(Text(r[7], style: const TextStyle(color: Colors.black54))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
            ),
          ],
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
      while (parts.length < 8) {
        parts.add('');
      }
      result.add(parts);
    }
    return result;
  }
}
