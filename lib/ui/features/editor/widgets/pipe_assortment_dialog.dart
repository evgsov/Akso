import 'package:flutter/material.dart';
import '../../../../domain/models/pipe_dimension.dart';
import '../../../../domain/models/piping_network.dart';
import '../../../canvas/input_controller.dart';
import 'custom_pipe_dimension_dialog.dart';

/// Диалог просмотра и управления сортаментом труб (ГОСТ 8732, ГОСТ 10704, ГОСТ 20295)
class PipeAssortmentDialog extends StatefulWidget {
  final PipingNetwork network;
  final PipingInputController? controller;
  final VoidCallback? onCatalogChanged;

  const PipeAssortmentDialog({
    super.key,
    required this.network,
    this.controller,
    this.onCatalogChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required PipingNetwork network,
    PipingInputController? controller,
    VoidCallback? onCatalogChanged,
  }) {
    return showDialog(
      context: context,
      builder: (_) => PipeAssortmentDialog(
        network: network,
        controller: controller,
        onCatalogChanged: onCatalogChanged,
      ),
    );
  }

  @override
  State<PipeAssortmentDialog> createState() => _PipeAssortmentDialogState();
}

class _PipeAssortmentDialogState extends State<PipeAssortmentDialog> {
  String _filter = 'all'; // 'all', 'building', 'industrial', 'custom'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.network.pipeCatalog;
    final allDimensions = catalog.dimensions.values.toList()
      ..sort((a, b) => a.dn.compareTo(b.dn));

    final filtered = allDimensions.where((dim) {
      if (_filter == 'building' && dim.dn > 200) return false;
      if (_filter == 'industrial' && (dim.dn <= 200 || dim.isCustom)) return false;
      if (_filter == 'custom' && !dim.isCustom) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchDn = dim.dn.toString().contains(q);
        final matchOuter = dim.outerDiameterMm.toString().contains(q);
        final matchStd = dim.standard.toLowerCase().contains(q);
        final matchWalls = dim.wallThicknesses.any((w) => w.toString().contains(q));
        if (!matchDn && !matchOuter && !matchStd && !matchWalls) return false;
      }
      return true;
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 920,
        height: 680,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.95,
          maxHeight: MediaQuery.sizeOf(context).height * 0.95,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Шапка диалога
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.line_weight, color: Colors.indigo, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Сортамент труб и толщины стенок',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'ГОСТ 8732-78, ГОСТ 10704-91, ГОСТ 20295-85 и пользовательские типоразмеры',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Свой размер'),
                  onPressed: () async {
                    final newDim = await CustomPipeDimensionDialog.show(context);
                    if (newDim != null) {
                      widget.network.pipeCatalog.addCustomDimension(newDim);
                      widget.onCatalogChanged?.call();
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
            const SizedBox(height: 12),

            // Поиск и фильтры категорий
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Поиск по Ду, ⌀, стенке...',
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
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
                SegmentedButton<String>(
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('Все (15–1420)')),
                    ButtonSegment(value: 'building', label: Text('ЖКХ (15–200)')),
                    ButtonSegment(value: 'industrial', label: Text('Пром. (250–1400)')),
                    ButtonSegment(value: 'custom', label: Text('Свои')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (set) => setState(() => _filter = set.first),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Таблица сортамента
            Expanded(
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'Типоразмеры не найдены',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final dim = filtered[index];
                          final isCurrentActive = widget.controller != null &&
                              widget.controller!.activeDn == dim.dn;

                          return Container(
                            color: isCurrentActive ? Colors.indigo.shade50.withValues(alpha: 0.5) : null,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Бейдж Ду
                                Container(
                                  width: 72,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: dim.isCustom
                                        ? Colors.purple.shade50
                                        : (dim.dn > 200 ? Colors.orange.shade50 : Colors.blue.shade50),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: dim.isCustom
                                          ? Colors.purple.shade200
                                          : (dim.dn > 200 ? Colors.orange.shade200 : Colors.blue.shade200),
                                    ),
                                  ),
                                  child: Text(
                                    'Ду ${dim.dn}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: dim.isCustom
                                          ? Colors.purple.shade900
                                          : (dim.dn > 200 ? Colors.orange.shade900 : Colors.blue.shade900),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Наружный диаметр и стандарт
                                SizedBox(
                                  width: 160,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '⌀ ${dim.outerDiameterMm.truncateToDouble() == dim.outerDiameterMm ? dim.outerDiameterMm.toStringAsFixed(0) : dim.outerDiameterMm.toStringAsFixed(1)} мм',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      Text(
                                        dim.standard,
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Ряд толщин стенок S
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            'Толщины стенок (S, мм):',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                          InkWell(
                                            onTap: () => _showAddWallThicknessDialog(dim),
                                            child: Text(
                                              '+ добавить стенку',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.indigo.shade700,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: dim.wallThicknesses.map((w) {
                                          final isDefault = (w - dim.defaultWallThicknessMm).abs() < 0.05;
                                          final isCurrentWall = isCurrentActive &&
                                              (widget.controller!.activeWallThicknessMm - w).abs() < 0.05;

                                          return InkWell(
                                            onTap: widget.controller != null
                                                ? () {
                                                    widget.controller!.setActiveDn(dim.dn);
                                                    widget.controller!.setActiveWallThickness(w);
                                                    Navigator.of(context).pop();
                                                  }
                                                : null,
                                            borderRadius: BorderRadius.circular(4),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isCurrentWall
                                                    ? Colors.indigo
                                                    : (isDefault ? Colors.indigo.shade100 : Colors.grey.shade100),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: isCurrentWall
                                                      ? Colors.indigo
                                                      : (isDefault ? Colors.indigo.shade300 : Colors.grey.shade300),
                                                ),
                                              ),
                                              child: Text(
                                                '${w.truncateToDouble() == w ? w.toStringAsFixed(0) : w.toStringAsFixed(1)}${isDefault ? ' (осн.)' : ''}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: isDefault || isCurrentWall ? FontWeight.bold : FontWeight.normal,
                                                  color: isCurrentWall
                                                      ? Colors.white
                                                      : (isDefault ? Colors.indigo.shade900 : Colors.black87),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 12),

                                // Кнопка применить / выбрать для черчения
                                if (widget.controller != null) ...[
                                  if (isCurrentActive)
                                    const Chip(
                                      avatar: Icon(Icons.check, size: 14, color: Colors.green),
                                      label: Text('Активный', style: TextStyle(fontSize: 11, color: Colors.green)),
                                      backgroundColor: Color(0xFFE8F5E9),
                                      visualDensity: VisualDensity.compact,
                                    )
                                  else
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                      ),
                                      onPressed: () {
                                        widget.controller!.setActiveDn(dim.dn);
                                        widget.controller!.setActiveWallThickness(dim.defaultWallThicknessMm);
                                        Navigator.of(context).pop();
                                      },
                                      child: const Text('Выбрать', style: TextStyle(fontSize: 12)),
                                    ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),

            const SizedBox(height: 12),
            // Подвал с подсказками
            Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Нажмите на толщину стенки или «Выбрать» для установки диаметра в активный инструмент черчения.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddWallThicknessDialog(PipeDimension dim) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Добавить толщину стенки для Ду ${dim.dn}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Текущие стенки: ${dim.wallThicknesses.map((w) => '$w мм').join(', ')}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Новая толщина стенки S',
                suffixText: 'мм',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(textController.text.replaceAll(',', '.'));
              if (val != null && val > 0) {
                widget.network.pipeCatalog.addWallThickness(dim.dn, val);
                widget.onCatalogChanged?.call();
                setState(() {});
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }
}
