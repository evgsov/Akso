import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../domain/models/custom_valve_definition.dart';
import '../../../../domain/services/custom_valve_catalog.dart';
import '../../../canvas/valve_symbol_painter.dart';
import 'custom_valve_editor_dialog.dart';

/// Диалог управления каталогом семейств арматуры:
/// выбор, создание, редактирование и удаление параметрических УГО и 3D тел.
class CustomValveCatalogDialog extends StatefulWidget {
  final Map<String, CustomValveDefinition>? projectValves;

  const CustomValveCatalogDialog({
    super.key,
    this.projectValves,
  });

  static Future<CustomValveDefinition?> show(
    BuildContext context, {
    Map<String, CustomValveDefinition>? projectValves,
  }) {
    return showDialog<CustomValveDefinition>(
      context: context,
      builder: (_) => CustomValveCatalogDialog(projectValves: projectValves),
    );
  }

  @override
  State<CustomValveCatalogDialog> createState() => _CustomValveCatalogDialogState();
}

class _CustomValveCatalogDialogState extends State<CustomValveCatalogDialog> {
  String _searchQuery = '';
  String _filter = 'all'; // 'all', 'builtin', 'user'

  List<CustomValveDefinition> _getFilteredDefinitions() {
    final catalog = CustomValveCatalog.instance;
    final all = <String, CustomValveDefinition>{};

    for (final d in catalog.allDefinitions) {
      all[d.id] = d;
    }
    if (widget.projectValves != null) {
      for (final entry in widget.projectValves!.entries) {
        all[entry.key] = entry.value;
      }
    }

    return all.values.where((def) {
      if (_filter == 'builtin' && !def.isBuiltin) return false;
      if (_filter == 'user' && def.isBuiltin) return false;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchName = def.name.toLowerCase().contains(query);
        final matchDesc = def.description.toLowerCase().contains(query);
        final matchText = def.symbol2d.stemText.toLowerCase().contains(query);
        if (!matchName && !matchDesc && !matchText) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _getFilteredDefinitions();

    final screenSize = MediaQuery.of(context).size;
    final dialogW = math.min(780.0, screenSize.width - 32.0);
    final dialogH = math.min(600.0, screenSize.height - 32.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogW,
        height: dialogH,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Заголовок
            Row(
              children: [
                const Icon(Icons.settings_suggest, color: Colors.indigo, size: 24),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Каталог семейств арматуры',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Создать (+)', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onPressed: () async {
                    final created = await showDialog<CustomValveDefinition>(
                      context: context,
                      builder: (_) => const CustomValveEditorDialog(),
                    );
                    if (created != null && mounted) {
                      setState(() {});
                    }
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),

            // Фильтры и поиск
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Поиск по наименованию, описанию или буквам привода...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (q) => setState(() => _searchQuery = q.trim()),
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('Все')),
                    ButtonSegment(value: 'builtin', label: Text('ГОСТ')),
                    ButtonSegment(value: 'user', label: Text('Мои')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (set) {
                    setState(() => _filter = set.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Список семейств
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text('Семейства арматуры не найдены',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final def = items[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          leading: Container(
                            width: 64,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Center(
                              child: CustomPaint(
                                size: const Size(48, 30),
                                painter: _ValveThumbnailPainter(symbolConfig: def.symbol2d),
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  def.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (def.isBuiltin)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.indigo.shade200),
                                  ),
                                  child: const Text('ГОСТ',
                                      style: TextStyle(fontSize: 10, color: Colors.indigo, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (def.description.isNotEmpty)
                                Text(
                                  def.description,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 3),
                              Text(
                                '3D: ${def.geometry3d.bodyShape.displayName}, привод: ${def.geometry3d.actuatorType.displayName}'
                                '${def.symbol2d.stemText.isNotEmpty ? " • Обозначение: «${def.symbol2d.stemText}»" : ""}',
                                style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: def.isBuiltin ? 'Клонировать / настроить' : 'Редактировать',
                                onPressed: () async {
                                  final edited = await showDialog<CustomValveDefinition>(
                                    context: context,
                                    builder: (_) => CustomValveEditorDialog(initialDefinition: def),
                                  );
                                  if (edited != null && mounted) {
                                    setState(() {});
                                  }
                                },
                              ),
                              if (!def.isBuiltin)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  tooltip: 'Удалить',
                                  onPressed: () async {
                                    await CustomValveCatalog.instance.deleteDefinition(def.id);
                                    if (mounted) setState(() {});
                                  },
                                ),
                              const SizedBox(width: 4),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () => Navigator.of(context).pop(def),
                                child: const Text('Выбрать', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Миниатюрный предпросмотр УГО для карточки в списке
class _ValveThumbnailPainter extends CustomPainter {
  final ValveSymbolConfig symbolConfig;

  const _ValveThumbnailPainter({required this.symbolConfig});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 3);

    ValveSymbolPainter.drawCustomValve(
      canvas,
      center: center,
      angleRad: 0.0,
      symbolConfig: symbolConfig,
      color: Colors.black87,
      size: 18.0,
    );
  }

  @override
  bool shouldRepaint(covariant _ValveThumbnailPainter oldDelegate) {
    return oldDelegate.symbolConfig != symbolConfig;
  }
}
