import 'package:flutter/material.dart';
import '../../../../domain/enums/valve_type.dart';
import '../../../../domain/enums/weld_type.dart';
import '../../../../domain/models/pipe_support.dart';
import '../../../canvas/input_controller.dart';
import 'custom_pipe_dimension_dialog.dart';
import 'pipe_assortment_dialog.dart';

class EditorToolsPanel extends StatelessWidget {
  final PipingInputController controller;

  const EditorToolsPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Строка 1: Инструменты стилуса + Системы + Диаметры
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Выбор основного инструмента
                SegmentedButton<CanvasTool>(
                  segments: const [
                    ButtonSegment(
                      value: CanvasTool.trace,
                      icon: Icon(Icons.edit, size: 18),
                      label: Text('Трассировка'),
                    ),
                    ButtonSegment(
                      value: CanvasTool.select,
                      icon: Icon(Icons.open_with, size: 18),
                      label: Text('Сдвиг/Выбор'),
                    ),
                    ButtonSegment(
                      value: CanvasTool.insertValve,
                      icon: Icon(Icons.tune, size: 18),
                      label: Text('Арматура'),
                    ),
                    ButtonSegment(
                      value: CanvasTool.insertWeld,
                      icon: Icon(Icons.flare, size: 18),
                      label: Text('Сварка'),
                    ),
                    ButtonSegment(
                      value: CanvasTool.insertReducer,
                      icon: Icon(Icons.call_split, size: 18),
                      label: Text('Переход'),
                    ),
                    ButtonSegment(
                      value: CanvasTool.insertFlange,
                      icon: Icon(Icons.radio_button_checked, size: 18),
                      label: Text('Фланец'),
                    ),
                    ButtonSegment(
                      value: CanvasTool.insertSupport,
                      icon: Icon(Icons.format_underlined, size: 18),
                      label: Text('Опора'),
                    ),
                  ],
                  selected: {controller.currentTool},
                  onSelectionChanged: (set) => controller.setTool(set.first),
                ),

                const SizedBox(width: 16),
                const Text('Система:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(width: 8),

                // Чипы выбора систем
                Row(
                  children: controller.network.systems.values.map((sys) {
                    final isSelected = controller.activeSystemId == sys.id;
                    final color = Color(sys.colorValue);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        selected: isSelected,
                        avatar: CircleAvatar(backgroundColor: color, radius: 6),
                        label: Text(sys.code, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                        selectedColor: color,
                        onSelected: (_) => controller.setActiveSystem(sys.id),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(width: 16),
                const Text('DN:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(width: 6),

                // Динамический выбор диаметров (Ду 15 – Ду 1420)
                () {
                  final allDns = controller.network.pipeCatalog.getAllDns();
                  final curVal = allDns.contains(controller.activeDn) ? controller.activeDn : allDns.first;
                  return DropdownButton<int>(
                    value: curVal,
                    items: allDns.map((dn) {
                      final dim = controller.network.pipeCatalog.getDimension(dn);
                      final outerStr = dim != null
                          ? '⌀${dim.outerDiameterMm.truncateToDouble() == dim.outerDiameterMm ? dim.outerDiameterMm.toStringAsFixed(0) : dim.outerDiameterMm.toStringAsFixed(1)}'
                          : '$dn мм';
                      return DropdownMenuItem(
                        value: dn,
                        child: Text(
                          'Ду $dn ($outerStr)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: dn > 200 ? FontWeight.bold : FontWeight.normal,
                            color: dn > 200 ? Colors.indigo.shade800 : Colors.black87,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (dn) {
                      if (dn != null) {
                        controller.setActiveDn(dn);
                        final dim = controller.network.pipeCatalog.getDimension(dn);
                        if (dim != null && !dim.wallThicknesses.any((w) => (w - controller.activeWallThicknessMm).abs() < 0.05)) {
                          controller.setActiveWallThickness(dim.defaultWallThicknessMm);
                        }
                      }
                    },
                  );
                }(),

                const SizedBox(width: 12),
                const Text('S:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(width: 4),

                // Толщина стенки S
                () {
                  final dim = controller.network.pipeCatalog.getDimension(controller.activeDn);
                  final wallOpts = List<double>.from(dim?.wallThicknesses ?? [controller.activeWallThicknessMm]);
                  if (!wallOpts.any((w) => (w - controller.activeWallThicknessMm).abs() < 0.05)) {
                    wallOpts.add(controller.activeWallThicknessMm);
                    wallOpts.sort();
                  }
                  final selectedVal = wallOpts.firstWhere(
                    (w) => (w - controller.activeWallThicknessMm).abs() < 0.05,
                    orElse: () => wallOpts.first,
                  );
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<double>(
                        value: selectedVal,
                        items: wallOpts.map((s) => DropdownMenuItem(
                          value: s,
                          child: Text('${s.truncateToDouble() == s ? s.toStringAsFixed(0) : s.toStringAsFixed(1)} мм'),
                        )).toList(),
                        onChanged: (s) {
                          if (s != null) controller.setActiveWallThickness(s);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.indigo),
                        tooltip: 'Добавить свой типоразмер трубы...',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () async {
                          final newDim = await CustomPipeDimensionDialog.show(
                            context,
                            initialDn: controller.activeDn,
                            initialOuterD: dim?.outerDiameterMm,
                            initialWallS: controller.activeWallThicknessMm,
                          );
                          if (newDim != null) {
                            controller.addCustomPipeDimension(newDim);
                            controller.setActiveDn(newDim.dn);
                            controller.setActiveWallThickness(newDim.defaultWallThicknessMm);
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.line_weight, size: 20, color: Colors.indigo),
                        tooltip: 'Таблица сортамента труб (ГОСТ 8732/10704/20295)...',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => PipeAssortmentDialog.show(
                          context,
                          network: controller.network,
                          controller: controller,
                          onCatalogChanged: () => controller.refresh(),
                        ),
                      ),
                    ],
                  );
                }(),

                const SizedBox(width: 16),
                const Text('Сталь:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(width: 8),

                DropdownButton<String>(
                  value: controller.activeMaterial,
                  items: const [
                    DropdownMenuItem(value: 'Сталь 20', child: Text('Сталь 20')),
                    DropdownMenuItem(value: '09Г2С', child: Text('09Г2С')),
                    DropdownMenuItem(value: '12Х18Н10Т', child: Text('12Х18Н10Т')),
                    DropdownMenuItem(value: '10Г2', child: Text('10Г2')),
                    DropdownMenuItem(value: 'Ст3сп', child: Text('Ст3сп')),
                  ],
                  onChanged: (m) {
                    if (m != null) controller.setActiveMaterial(m);
                  },
                ),
              ],
            ),
          ),

          // Строка 2 (динамическая): Панель выбора опций активного инструмента
          if (controller.currentTool == CanvasTool.trace) ...[
            const Divider(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('Авто-ответвление: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.call_split, size: 16),
                        label: Text('Тройник ГОСТ 17376'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.merge_type, size: 16),
                        label: Text('Прямая врезка У18'),
                      ),
                    ],
                    selected: {controller.useDirectBranch},
                    onSelectionChanged: (set) => controller.setUseDirectBranch(set.first),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'При черчении от или к существующей трубе узел формируется автоматически',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ] else if (controller.currentTool == CanvasTool.insertFlange) ...[
            const Divider(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('Соединение: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  FilterChip(
                    selected: controller.isFlangePair,
                    label: const Text('Фланцевая пара'),
                    onSelected: (val) => controller.setIsFlangePair(val),
                  ),
                  const SizedBox(width: 12),
                  const Text('Давление: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  DropdownButton<int>(
                    value: controller.flangePressurePn,
                    items: const [
                      DropdownMenuItem(value: 10, child: Text('Ру 10')),
                      DropdownMenuItem(value: 16, child: Text('Ру 16')),
                      DropdownMenuItem(value: 25, child: Text('Ру 25')),
                      DropdownMenuItem(value: 40, child: Text('Ру 40')),
                    ],
                    onChanged: (pn) {
                      if (pn != null) controller.setFlangePressurePn(pn);
                    },
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Нажмите на участок трубы на холсте для врезки фланцев (ГОСТ 33259)',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ] else if (controller.currentTool == CanvasTool.insertSupport) ...[
            const Divider(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: PipeSupportType.values.map((st) {
                  final isSelected = controller.selectedSupportType == st;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(st.displayName),
                      selectedColor: Colors.lightBlue.shade100,
                      onSelected: (_) => controller.setSelectedSupportType(st),
                    ),
                  );
                }).toList(),
              ),
            ),
          ] else if (controller.currentTool == CanvasTool.insertValve) ...[
            const Divider(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ValveType.values.map((vt) {
                  final isSelected = controller.selectedValveType == vt;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(vt.displayName),
                      selectedColor: Colors.amber.shade200,
                      onSelected: (_) => controller.setSelectedValveType(vt),
                    ),
                  );
                }).toList(),
              ),
            ),
          ] else if (controller.currentTool == CanvasTool.insertWeld) ...[
            const Divider(height: 12),
            Row(
              children: [
                const Text('Клеймо сварщика: ', style: TextStyle(fontSize: 12)),
                SizedBox(
                  width: 100,
                  height: 32,
                  child: TextField(
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: controller.currentWelderStamp),
                    onChanged: (val) => controller.setCurrentWelderStamp(val),
                  ),
                ),
                const SizedBox(width: 16),
                const Text('Тип шва: ', style: TextStyle(fontSize: 12)),
                DropdownButton<WeldType>(
                  value: controller.currentWeldType,
                  items: WeldType.values.map((wt) {
                    return DropdownMenuItem(value: wt, child: Text(wt.gostCode));
                  }).toList(),
                  onChanged: (wt) {
                    if (wt != null) {
                      controller.setCurrentWeldType(wt);
                    }
                  },
                ),
                const SizedBox(width: 16),
                const Text('Нажмите на участок трубы на холсте для врезки шва', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ] else if (controller.currentTool == CanvasTool.insertReducer) ...[
            const Divider(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('Новый диаметр (после перехода): ', style: TextStyle(fontSize: 12)),
                  DropdownButton<int>(
                    value: controller.targetReducerDn,
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('Ду 15')),
                      DropdownMenuItem(value: 20, child: Text('Ду 20')),
                      DropdownMenuItem(value: 25, child: Text('Ду 25')),
                      DropdownMenuItem(value: 32, child: Text('Ду 32')),
                      DropdownMenuItem(value: 40, child: Text('Ду 40')),
                      DropdownMenuItem(value: 50, child: Text('Ду 50')),
                      DropdownMenuItem(value: 65, child: Text('Ду 65')),
                      DropdownMenuItem(value: 80, child: Text('Ду 80')),
                      DropdownMenuItem(value: 100, child: Text('Ду 100')),
                      DropdownMenuItem(value: 150, child: Text('Ду 150')),
                      DropdownMenuItem(value: 200, child: Text('Ду 200')),
                    ],
                    onChanged: (dn) {
                      if (dn != null) controller.setTargetReducerDn(dn);
                    },
                  ),
                  const SizedBox(width: 16),
                  FilterChip(
                    selected: controller.isEccentricReducer,
                    label: const Text('Эксцентрический'),
                    onSelected: (val) => controller.setIsEccentricReducer(val),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Нажмите на трубу на холсте для врезки перехода',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
