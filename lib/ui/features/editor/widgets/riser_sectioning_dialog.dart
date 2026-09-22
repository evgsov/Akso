import 'package:flutter/material.dart';
import '../../../../domain/enums/inspection_method.dart';
import '../../../../domain/enums/weld_type.dart';
import '../../../../domain/services/segment_positioning_service.dart';
import '../../../canvas/input_controller.dart';

/// Режим нарезки стояка на катушки
enum RiserSectioningMode {
  equalStep,
  lengthsChain,
  elevationsList,
}

/// Диалог нарезки стояка / участка трубы на катушки
class RiserSectioningDialog extends StatefulWidget {
  final PipingInputController controller;
  final String segmentId;

  const RiserSectioningDialog({
    super.key,
    required this.controller,
    required this.segmentId,
  });

  static Future<bool?> show(
    BuildContext context, {
    required PipingInputController controller,
    required String segmentId,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => RiserSectioningDialog(
        controller: controller,
        segmentId: segmentId,
      ),
    );
  }

  @override
  State<RiserSectioningDialog> createState() => _RiserSectioningDialogState();
}

class _RiserSectioningDialogState extends State<RiserSectioningDialog> {
  RiserSectioningMode _mode = RiserSectioningMode.equalStep;

  late TextEditingController _stepController;
  late TextEditingController _lengthsController;
  late TextEditingController _elevationsController;
  late TextEditingController _offsetController;
  late TextEditingController _stampController;

  bool _fromBottom = true;
  WeldType _weldType = WeldType.c17;
  InspectionMethod _inspectionMethod = InspectionMethod.vik;

  @override
  void initState() {
    super.initState();
    _stepController = TextEditingController(text: '2500');
    _lengthsController = TextEditingController(text: '2000, 2500, 2500');
    _elevationsController = TextEditingController(text: '2.800, 5.600, 8.400');
    _offsetController = TextEditingController(text: '0');

    final defaultStamp = widget.controller.currentProject.calloutTemplates['default_weld_stamp'] ?? 'С-01';
    _stampController = TextEditingController(text: defaultStamp);
  }

  @override
  void dispose() {
    _stepController.dispose();
    _lengthsController.dispose();
    _elevationsController.dispose();
    _offsetController.dispose();
    _stampController.dispose();
    super.dispose();
  }

  List<double> _calculateRatios() {
    final net = widget.controller.network;
    switch (_mode) {
      case RiserSectioningMode.equalStep:
        final step = double.tryParse(_stepController.text.replaceAll(',', '.').replaceAll(' ', '')) ?? 0.0;
        if (step <= 50.0) return [];
        return SegmentPositioningService.calculateRiserWeldRatiosByStep(
          net,
          widget.segmentId,
          step,
          fromBottom: _fromBottom,
        );

      case RiserSectioningMode.lengthsChain:
        final raw = _lengthsController.text;
        final parts = raw.split(RegExp(r'[,;\s]+')).where((s) => s.isNotEmpty);
        final lengths = <double>[];
        for (final p in parts) {
          final l = double.tryParse(p.replaceAll(',', '.'));
          if (l != null && l > 0) lengths.add(l);
        }
        if (lengths.isEmpty) return [];
        return SegmentPositioningService.calculateRiserWeldRatiosByLengths(
          net,
          widget.segmentId,
          lengths,
          fromBottom: _fromBottom,
        );

      case RiserSectioningMode.elevationsList:
        final raw = _elevationsController.text;
        final offsetMm = double.tryParse(_offsetController.text.replaceAll(',', '.').replaceAll(' ', '')) ?? 0.0;
        final parts = raw.split(RegExp(r'[,;\s]+')).where((s) => s.isNotEmpty);
        final elevations = <double>[];
        for (final p in parts) {
          final e = double.tryParse(p.replaceAll(',', '.'));
          if (e != null) {
            elevations.add(e + offsetMm / 1000.0);
          }
        }
        if (elevations.isEmpty) return [];
        return SegmentPositioningService.calculateRiserWeldRatiosByElevations(
          net,
          widget.segmentId,
          elevations,
        );
    }
  }

  void _applySectioning(List<double> ratios) {
    if (ratios.isEmpty) return;
    widget.controller.divideRiserIntoSpools(
      widget.segmentId,
      ratios,
      stamp: _stampController.text.trim().isNotEmpty ? _stampController.text.trim() : null,
      weldType: _weldType,
      inspectionMethod: _inspectionMethod,
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final net = widget.controller.network;
    final seg = net.segments[widget.segmentId];
    if (seg == null) {
      return AlertDialog(
        title: const Text('Ошибка'),
        content: const Text('Участок трубы не найден.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть')),
        ],
      );
    }

    final sNode = net.nodes[seg.startNodeId];
    final eNode = net.nodes[seg.endNodeId];
    final totalLen = sNode != null && eNode != null ? sNode.distanceTo(eNode) : 0.0;
    final sElevM = (sNode?.z ?? 0.0) / 1000.0;
    final eElevM = (eNode?.z ?? 0.0) / 1000.0;
    final isVertical = (sNode != null && eNode != null) && (eNode.z - sNode.z).abs() > 10.0;

    final ratios = _calculateRatios();
    final previews = SegmentPositioningService.previewSections(net, widget.segmentId, ratios);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Заголовок
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.content_cut, color: Colors.teal.shade800, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isVertical ? 'Нарезка стояка на катушки' : 'Нарезка трубы на катушки',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Ду ${seg.dn} (⌀${seg.outerDiameterMm.toStringAsFixed(0)} мм) • Длина: ${totalLen.round()} мм • Z: ${sElevM.toStringAsFixed(3)} → ${eElevM.toStringAsFixed(3)} м',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 2. Выбор режима нарезки (SegmentedButton)
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<RiserSectioningMode>(
                  segments: const [
                    ButtonSegment(
                      value: RiserSectioningMode.equalStep,
                      label: Text('Равный шаг', style: TextStyle(fontSize: 11)),
                      icon: Icon(Icons.straighten, size: 14),
                    ),
                    ButtonSegment(
                      value: RiserSectioningMode.lengthsChain,
                      label: Text('Цепочка длин', style: TextStyle(fontSize: 11)),
                      icon: Icon(Icons.format_list_numbered, size: 14),
                    ),
                    ButtonSegment(
                      value: RiserSectioningMode.elevationsList,
                      label: Text('Отметки этажей', style: TextStyle(fontSize: 11)),
                      icon: Icon(Icons.apartment, size: 14),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (set) {
                    setState(() {
                      _mode = set.first;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),

              // 3. Параметры выбранного режима
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    if (_mode == RiserSectioningMode.equalStep) ...[
                      Row(
                        children: [
                          const Text('Шаг катушки (L):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            height: 32,
                            child: TextField(
                              controller: _stepController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              decoration: const InputDecoration(
                                suffixText: 'мм',
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const Spacer(),
                          // Быстрые пресеты шага
                          Wrap(
                            spacing: 4,
                            children: [2000, 2500, 3000].map((preset) {
                              return ActionChip(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                label: Text('$preset', style: const TextStyle(fontSize: 10)),
                                onPressed: () {
                                  _stepController.text = '$preset';
                                  setState(() {});
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Направление отсчета:', style: TextStyle(fontSize: 11, color: Colors.black87)),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Снизу вверх', style: TextStyle(fontSize: 10)),
                            selected: _fromBottom,
                            visualDensity: VisualDensity.compact,
                            onSelected: (val) {
                              if (val) setState(() => _fromBottom = true);
                            },
                          ),
                          const SizedBox(width: 4),
                          ChoiceChip(
                            label: const Text('Сверху вниз', style: TextStyle(fontSize: 10)),
                            selected: !_fromBottom,
                            visualDensity: VisualDensity.compact,
                            onSelected: (val) {
                              if (val) setState(() => _fromBottom = false);
                            },
                          ),
                        ],
                      ),
                    ] else if (_mode == RiserSectioningMode.lengthsChain) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text('Длины катушек:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 32,
                                  child: TextField(
                                    controller: _lengthsController,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    decoration: const InputDecoration(
                                      hintText: 'напр. 1500, 2500, 2500, 2000',
                                      suffixText: 'мм',
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Задайте последовательность длин (мм). Остаток трубы сформирует замыкающую катушку.',
                                  style: TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Направление отсчета:', style: TextStyle(fontSize: 11, color: Colors.black87)),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Снизу вверх', style: TextStyle(fontSize: 10)),
                            selected: _fromBottom,
                            visualDensity: VisualDensity.compact,
                            onSelected: (val) {
                              if (val) setState(() => _fromBottom = true);
                            },
                          ),
                          const SizedBox(width: 4),
                          ChoiceChip(
                            label: const Text('Сверху вниз', style: TextStyle(fontSize: 10)),
                            selected: !_fromBottom,
                            visualDensity: VisualDensity.compact,
                            onSelected: (val) {
                              if (val) setState(() => _fromBottom = false);
                            },
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text('Отметки этажей (Z):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 32,
                                  child: TextField(
                                    controller: _elevationsController,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    decoration: const InputDecoration(
                                      hintText: 'напр. 2.800, 5.600, 8.400',
                                      suffixText: 'м',
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Отметки перекрытий или уровней в метрах (например, чистый пол этажа).',
                                  style: TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          const Text('Смещение стыка от отметки:', style: TextStyle(fontSize: 11, color: Colors.black87)),
                          SizedBox(
                            width: 90,
                            height: 28,
                            child: TextField(
                              controller: _offsetController,
                              keyboardType: const TextInputType.numberWithOptions(signed: true),
                              style: const TextStyle(fontSize: 11),
                              decoration: const InputDecoration(
                                suffixText: 'мм',
                                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const Text('(напр. +500 мм от пола)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 4. Интерактивная таблица предварительного просмотра катушек
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Text(
                      'Предварительный просмотр катушек:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Катушек: ${previews.length} • Стыков: ${ratios.length}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: previews.isEmpty
                      ? const Center(
                          child: Text(
                            'Не заданы стыки или шаг превышает длину трубы',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          itemCount: previews.length,
                          separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1),
                          itemBuilder: (ctx, i) {
                            final p = previews[i];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              color: i.isEven ? Colors.white : Colors.grey.shade50,
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text('${p.spoolNumber}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal.shade900)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Рез: ${p.cutLengthMm.toStringAsFixed(0)} мм',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
                                        ),
                                        Text(
                                          '${p.startLabel} → ${p.endLabel}',
                                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Z: ${p.startElevationString} → ${p.endElevationString}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          'ΔZ: ${(p.endElevationM - p.startElevationM).abs().toStringAsFixed(3)} м',
                                          style: const TextStyle(fontSize: 10, color: Colors.grey),
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
              ),
              const SizedBox(height: 12),

              // 5. Параметры создаваемых сварных стыков
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Клеймо:', style: TextStyle(fontSize: 11, color: Colors.black87)),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 70,
                          height: 28,
                          child: TextField(
                            controller: _stampController,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Тип:', style: TextStyle(fontSize: 11, color: Colors.black87)),
                        const SizedBox(width: 6),
                        DropdownButton<WeldType>(
                          value: _weldType,
                          isDense: true,
                          style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold),
                          items: WeldType.values.map((wt) {
                            return DropdownMenuItem(value: wt, child: Text(wt.shortName));
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _weldType = v);
                          },
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Контроль:', style: TextStyle(fontSize: 11, color: Colors.black87)),
                        const SizedBox(width: 6),
                        DropdownButton<InspectionMethod>(
                          value: _inspectionMethod,
                          isDense: true,
                          style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold),
                          items: InspectionMethod.values.map((im) {
                            return DropdownMenuItem(value: im, child: Text(im.code));
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _inspectionMethod = v);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 6. Кнопки действий
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(
                      ratios.isNotEmpty ? 'Нарезать (создать ${ratios.length} стык.)' : 'Нарезать стояк',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: ratios.isNotEmpty ? () => _applySectioning(ratios) : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
