import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../domain/models/piping_network.dart';
import '../../../../domain/models/piping_system.dart';

const _uuid = Uuid();

class PipingSystemsDialog extends StatefulWidget {
  final PipingNetwork network;
  final String activeSystemId;
  final ValueChanged<String>? onSystemSelected;
  final VoidCallback? onSystemsChanged;

  const PipingSystemsDialog({
    super.key,
    required this.network,
    required this.activeSystemId,
    this.onSystemSelected,
    this.onSystemsChanged,
  });

  @override
  State<PipingSystemsDialog> createState() => _PipingSystemsDialogState();
}

class _PipingSystemsDialogState extends State<PipingSystemsDialog> {
  static const List<Color> _palette = [
    Color(0xFF1E88E5), // Blue
    Color(0xFFE53935), // Red
    Color(0xFFFB8C00), // Orange
    Color(0xFF43A047), // Green
    Color(0xFFD81B60), // Magenta
    Color(0xFF00ACC1), // Cyan
    Color(0xFF6D4C41), // Brown
    Color(0xFF5E35B1), // Purple
    Color(0xFF00897B), // Teal
    Color(0xFF3949AB), // Indigo
  ];

  static const List<String> _steels = ['Сталь 20', '09Г2С', '12Х18Н10Т', '10Г2', 'Ст3сп', '15Х5М'];

  @override
  Widget build(BuildContext context) {
    final systems = widget.network.systems.values.toList();
    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.95).clamp(320.0, 780.0);
    final dialogHeight = (size.height * 0.9).clamp(400.0, 600.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.alt_route, color: Colors.indigo, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Диспетчер систем трубопроводов',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Настройка типов систем, сталей, диаметров и цветов слоев AutoCAD',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Восстановить удаленные стандартные системы',
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('Сброс к ГОСТ', style: TextStyle(fontSize: 12)),
                    onPressed: _restoreDefaultSystems,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Добавить систему'),
                  onPressed: () => _showEditSystemDialog(context, null),
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
              child: ListView.separated(
                itemCount: systems.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final sys = systems[index];
                  final isActive = sys.id == widget.activeSystemId;
                  final color = Color(sys.colorValue);
                  final canDelete = widget.network.systems.length > 1;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: color,
                      radius: 18,
                      child: Text(
                        sys.code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${sys.code} — ${sys.name}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.indigo.shade200),
                            ),
                            child: const Text('АКТИВНАЯ', style: TextStyle(fontSize: 10, color: Colors.indigo, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      'Сталь: ${sys.defaultMaterial} • Ду по умолч.: Ду${sys.defaultDn} • Допустимые: ${sys.availableDns.map((d) => 'Ду$d').join(', ')}',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isActive)
                          OutlinedButton(
                            onPressed: () {
                              widget.onSystemSelected?.call(sys.id);
                              Navigator.of(context).pop();
                            },
                            child: const Text('Выбрать'),
                          ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: 'Редактировать',
                          onPressed: () => _showEditSystemDialog(context, sys),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: canDelete ? Colors.red : Colors.grey.shade400,
                          ),
                          tooltip: canDelete ? 'Удалить систему' : 'Нельзя удалить единственную систему',
                          onPressed: canDelete ? () => _confirmDeleteSystem(context, sys) : null,
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

  void _confirmDeleteSystem(BuildContext context, PipingSystem sys) {
    final affectedSegments = widget.network.segments.values.where((s) => s.systemId == sys.id).length;
    final remainingSystems = widget.network.systems.values.where((s) => s.id != sys.id).toList();
    if (remainingSystems.isEmpty) return;
    final fallbackSys = remainingSystems.first;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить систему ${sys.code}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Вы действительно хотите удалить систему «${sys.code} — ${sys.name}»?'),
            if (affectedSegments > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'В сети есть $affectedSegments уч. с этой системой. Они будут переведены в систему «${fallbackSys.code} — ${fallbackSys.name}».',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                for (final entry in widget.network.segments.entries) {
                  if (entry.value.systemId == sys.id) {
                    widget.network.segments[entry.key] = entry.value.copyWith(systemId: fallbackSys.id);
                  }
                }
                widget.network.systems.remove(sys.id);
                if (sys.id == widget.activeSystemId) {
                  widget.onSystemSelected?.call(fallbackSys.id);
                }
              });
              widget.onSystemsChanged?.call();
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _restoreDefaultSystems() {
    setState(() {
      for (final defaultSys in PipingSystem.defaults) {
        if (!widget.network.systems.containsKey(defaultSys.id)) {
          widget.network.systems[defaultSys.id] = defaultSys;
        }
      }
    });
    widget.onSystemsChanged?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Стандартные системы ГОСТ восстановлены'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showEditSystemDialog(BuildContext context, PipingSystem? existing) {
    final isNew = existing == null;
    final codeCtrl = TextEditingController(text: existing?.code ?? 'ТХ1');
    final nameCtrl = TextEditingController(text: existing?.name ?? 'Технологический трубопровод');
    Color selectedColor = existing != null ? Color(existing.colorValue) : _palette[4];
    String defaultSteel = existing?.defaultMaterial ?? 'Сталь 20';
    int defaultDn = existing?.defaultDn ?? 50;
    List<int> availableDns = List<int>.from(existing?.availableDns ?? [25, 32, 40, 50, 65, 80, 100]);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Text(isNew ? 'Новая система' : 'Редактирование системы ${existing.code}'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 580,
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: codeCtrl,
                              decoration: const InputDecoration(labelText: 'Код (В1, ТХ1, П1...)', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: nameCtrl,
                              decoration: const InputDecoration(labelText: 'Наименование', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Цвет отображения и слоя DXF:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: _palette.map((c) {
                          final isSel = selectedColor.toARGB32() == c.toARGB32();
                          return InkWell(
                            onTap: () => setDlgState(() => selectedColor = c),
                            borderRadius: BorderRadius.circular(16),
                            child: CircleAvatar(
                              backgroundColor: c,
                              radius: 14,
                              child: isSel ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: defaultSteel,
                              decoration: const InputDecoration(labelText: 'Марка стали по умолчанию', border: OutlineInputBorder()),
                              items: _steels.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                              onChanged: (val) {
                                if (val != null) setDlgState(() => defaultSteel = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: availableDns.contains(defaultDn) ? defaultDn : availableDns.first,
                              decoration: const InputDecoration(labelText: 'Диаметр по умолчанию', border: OutlineInputBorder()),
                              items: availableDns.map((dn) => DropdownMenuItem(value: dn, child: Text('Ду$dn'))).toList(),
                              onChanged: (val) {
                                if (val != null) setDlgState(() => defaultDn = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Разрешенный сортамент диаметров (DN):',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.select_all, size: 14),
                                label: const Text('Все (Ду 15–1420)', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                                onPressed: () {
                                  setDlgState(() {
                                    availableDns = List<int>.from(widget.network.pipeCatalog.getAllDns());
                                  });
                                },
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.apartment, size: 14),
                                label: const Text('ЖКХ (15–200)', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                                onPressed: () {
                                  setDlgState(() {
                                    availableDns = widget.network.pipeCatalog.getAllDns().where((d) => d <= 200).toList();
                                  });
                                },
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.factory, size: 14),
                                label: const Text('Пром. (200–1400)', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                                onPressed: () {
                                  setDlgState(() {
                                    availableDns = widget.network.pipeCatalog.getAllDns().where((d) => d >= 200).toList();
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: widget.network.pipeCatalog.getAllDns().map((dn) {
                          final isChecked = availableDns.contains(dn);
                          final dim = widget.network.pipeCatalog.getDimension(dn);
                          final outerStr = dim != null
                              ? ' (⌀${dim.outerDiameterMm.truncateToDouble() == dim.outerDiameterMm ? dim.outerDiameterMm.toStringAsFixed(0) : dim.outerDiameterMm.toStringAsFixed(1)})'
                              : '';
                          return FilterChip(
                            label: Text('Ду$dn$outerStr', style: const TextStyle(fontSize: 11)),
                            selected: isChecked,
                            onSelected: (selected) {
                              setDlgState(() {
                                if (selected) {
                                  availableDns.add(dn);
                                  availableDns.sort();
                                } else if (availableDns.length > 1) {
                                  availableDns.remove(dn);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () {
                    final code = codeCtrl.text.trim().toUpperCase();
                    final name = nameCtrl.text.trim();
                    if (code.isEmpty || name.isEmpty) return;

                    final id = existing?.id ?? 'sys_${_uuid.v4()}';
                    final newSys = PipingSystem(
                      id: id,
                      code: code,
                      name: name,
                      colorValue: selectedColor.toARGB32(),
                      dxfAciColor: _getAciColor(selectedColor),
                      defaultDn: defaultDn,
                      defaultMaterial: defaultSteel,
                      availableDns: availableDns,
                      isCustom: true,
                    );

                    setState(() {
                      widget.network.systems[id] = newSys;
                    });
                    widget.onSystemsChanged?.call();
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  int _getAciColor(Color color) {
    if (color == const Color(0xFF1E88E5)) return 5; // Blue
    if (color == const Color(0xFFE53935)) return 1; // Red
    if (color == const Color(0xFFFB8C00)) return 30; // Orange
    if (color == const Color(0xFF43A047)) return 3; // Green
    if (color == const Color(0xFFD81B60)) return 6; // Magenta
    if (color == const Color(0xFF00ACC1)) return 4; // Cyan
    return 7;
  }
}
