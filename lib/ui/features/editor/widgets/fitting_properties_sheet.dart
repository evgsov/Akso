import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../domain/enums/fitting_type.dart';
import '../../../../domain/enums/weld_type.dart';
import '../../../../domain/models/fitting.dart';
import '../../../../domain/models/fitting_definition.dart';
import '../../../../domain/models/piping_network.dart';
import 'fitting_catalog_dialog.dart';

const _uuid = Uuid();

/// Инспектор свойств выбранного фасонного элемента (отвода, тройника, фланца, перехода)
class FittingPropertiesSheet extends StatefulWidget {
  final PipingNetwork network;
  final String nodeId;
  final VoidCallback? onModified;

  const FittingPropertiesSheet({
    super.key,
    required this.network,
    required this.nodeId,
    this.onModified,
  });

  @override
  State<FittingPropertiesSheet> createState() => _FittingPropertiesSheetState();
}

class _FittingPropertiesSheetState extends State<FittingPropertiesSheet> {
  @override
  Widget build(BuildContext context) {
    final fit = widget.network.fittings[widget.nodeId];
    final connected = widget.network.getConnectedSegments(widget.nodeId);

    if (fit == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Свойства узла', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Подключено участков труб: ${connected.length}'),
            const SizedBox(height: 12),
            if (connected.length == 1 && widget.network.nodes[widget.nodeId]?.equipmentId == null) ...[
              FilledButton.icon(
                icon: const Icon(Icons.block),
                label: const Text('Установить заглушку (днище)'),
                onPressed: () {
                  widget.network.attachCapToNode(widget.nodeId);
                  setState(() {});
                  widget.onModified?.call();
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.radio_button_checked),
                label: const Text('Установить концевой фланец'),
                onPressed: () {
                  widget.network.attachEndFlangeToNode(widget.nodeId);
                  setState(() {});
                  widget.onModified?.call();
                  Navigator.pop(context);
                },
              ),
            ],
            if (connected.length == 3)
              FilledButton.icon(
                icon: const Icon(Icons.alt_route),
                label: const Text('Сформировать прямую врезку (У18)'),
                onPressed: () {
                  final s = connected[0];
                  final newFit = Fitting(
                    id: 'fit_${widget.nodeId}',
                    nodeId: widget.nodeId,
                    fittingType: FittingType.directBranch,
                    name: 'Прямая врезка У18',
                    standard: 'ГОСТ 16037-80 У18',
                    material: s.material,
                    weldType: WeldType.u18,
                    dn: s.dn,
                    radiusMm: 0.0,
                    cutsMainPipe: false,
                  );
                  widget.network.updateFitting(widget.nodeId, newFit);
                  widget.onModified?.call();
                  setState(() {});
                },
              ),
          ],
        ),
      );
    }

    final isElbow = fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45;
    final isBranch = fit.fittingType == FittingType.tee || fit.fittingType == FittingType.directBranch;
    final isFlange = fit.fittingType == FittingType.flange;
    final isReducer = fit.fittingType == FittingType.reducerConcentric || fit.fittingType == FittingType.reducerEccentric;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок с действиями
          Row(
            children: [
              Icon(_getFittingIcon(fit.fittingType), color: Colors.indigo),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fit.displayName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      fit.standard ?? 'ГОСТ',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Кнопки взаимодействия с коллекцией элементов
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.collections_bookmark_outlined, size: 16),
                  label: const Text('Выбрать из коллекции', style: TextStyle(fontSize: 12)),
                  onPressed: () => _openCollectionPicker(context),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                label: const Text('В коллекцию', style: TextStyle(fontSize: 12)),
                onPressed: () => _saveAsCustomTemplate(fit),
              ),
            ],
          ),
          const Divider(height: 20),
          // Бейджи основных характеристик
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildBadge('Ду: ${fit.dn}${fit.dnSecondary != null ? "×${fit.dnSecondary}" : ""}'),
              _buildBadge('Вычет/R: ${fit.effectiveRadiusMm.toStringAsFixed(1)} мм'),
              _buildBadge('Стыков: ${fit.effectiveWeldCount} (${fit.weldType.shortName})'),
              _buildBadge('Материал: ${fit.material}'),
            ],
          ),
          const SizedBox(height: 14),

          // 0. Наименование детали
          TextFormField(
            initialValue: fit.name ?? '',
            decoration: const InputDecoration(
              labelText: 'Наименование детали',
              hintText: 'напр. Отвод 90-159х4.5, Тройник Т-1',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onFieldSubmitted: (v) {
              _update(fit.copyWith(name: v.trim().isEmpty ? null : v.trim()));
            },
          ),
          const SizedBox(height: 12),

          // Заводской № / Номер партии
          TextFormField(
            initialValue: fit.serialNumber ?? '',
            decoration: const InputDecoration(
              labelText: 'Заводской № / Партия детали',
              hintText: 'напр. ПЛ-8492, № 12',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onFieldSubmitted: (v) {
              final text = v.trim();
              _update(fit.copyWith(
                serialNumber: text.isEmpty ? null : text,
                clearSerialNumber: text.isEmpty,
              ));
            },
          ),
          const SizedBox(height: 12),

          // 1. Выбор марки стали
          DropdownButtonFormField<String>(
            initialValue: fit.material,
            decoration: const InputDecoration(
              labelText: 'Марка стали детали',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: 'Сталь 20', child: Text('Сталь 20 (ГОСТ 1050-2013)')),
              DropdownMenuItem(value: '09Г2С', child: Text('09Г2С (ГОСТ 19281-2014)')),
              DropdownMenuItem(value: '12Х18Н10Т', child: Text('12Х18Н10Т (Нержавеющая)')),
              DropdownMenuItem(value: '10Г2', child: Text('10Г2')),
              DropdownMenuItem(value: 'Ст3сп', child: Text('Ст3сп')),
            ],
            onChanged: (newMat) {
              if (newMat == null) return;
              _update(fit.copyWith(material: newMat));
            },
          ),
          const SizedBox(height: 14),

          // 2. Специфические параметры по типам фитингов:

          // --- ФЛАНЕЦ ---
          if (isFlange) ...[
            const Text('Режим подключения фланца:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            SegmentedButton<FlangeConnectionType>(
              segments: const [
                ButtonSegment(
                  value: FlangeConnectionType.toEquipment,
                  label: Text('К оборудованию\n(1 стык)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.precision_manufacturing, size: 16),
                ),
                ButtonSegment(
                  value: FlangeConnectionType.pipeToPipe,
                  label: Text('Межтрубное\n(2 стыка)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.compare_arrows, size: 16),
                ),
                ButtonSegment(
                  value: FlangeConnectionType.blindFlange,
                  label: Text('Заглушка\n(1 стык)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.block, size: 16),
                ),
              ],
              selected: {fit.flangeConnectionType},
              onSelectionChanged: (set) {
                final newMode = set.first;
                final isPair = newMode == FlangeConnectionType.pipeToPipe;
                final rad = isPair ? (fit.dn <= 50 ? 35.0 : 45.0) : (fit.dn <= 50 ? 18.0 : 22.0);
                String newName;
                if (isPair) {
                  newName = 'Фланцевая пара Ду${fit.dn} Ру${fit.pressurePn}';
                } else if (newMode == FlangeConnectionType.blindFlange) {
                  newName = 'Заглушка фланцевая Ду${fit.dn} Ру${fit.pressurePn}';
                } else {
                  newName = 'Фланец Ду${fit.dn} Ру${fit.pressurePn} (${newMode.displayName})';
                }

                _update(fit.copyWith(
                  flangeConnectionType: newMode,
                  isFlangePair: isPair,
                  radiusMm: rad,
                  name: newName,
                ));
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: fit.pressurePn,
              decoration: const InputDecoration(
                labelText: 'Номинальное давление Ру (Pn)',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 10, child: Text('Ру10 (1.0 МПа)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 16, child: Text('Ру16 (1.6 МПа)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 25, child: Text('Ру25 (2.5 МПа)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 40, child: Text('Ру40 (4.0 МПа)', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (pn) {
                if (pn == null) return;
                _update(fit.copyWith(pressurePn: pn));
              },
            ),
          ],

          // --- ОТВОД ---
          if (isElbow) ...[
            const Text('Радиус гиба R отвода:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildRadiusChip('1.0 DN (ГОСТ 30753)', fit.dn * 1.0, fit),
                _buildRadiusChip('1.5 DN (ГОСТ 17375)', fit.dn * 1.5, fit),
                _buildRadiusChip('3.0 DN (ГОСТ 24950)', fit.dn * 3.0, fit),
                _buildRadiusChip('5.0 DN (ТУ гнутый)', fit.dn * 5.0, fit),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Точный радиус гиба R (мм)',
                border: OutlineInputBorder(),
                suffixText: 'мм',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              controller: TextEditingController(text: fit.effectiveRadiusMm.toStringAsFixed(0)),
              onSubmitted: (val) {
                final r = double.tryParse(val);
                if (r != null && r > 0) {
                  _update(fit.copyWith(customRadiusMm: r, radiusMm: r));
                }
              },
            ),
          ],

          // --- ТРОЙНИК ИЛИ ПРЯМАЯ ВРЕЗКА ---
          if (isBranch) ...[
            const Text('Тип узла ответвления:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            SegmentedButton<FittingType>(
              segments: const [
                ButtonSegment(
                  value: FittingType.tee,
                  label: Text('Тройник ГОСТ 17376 (3 стыка)'),
                  icon: Icon(Icons.call_split),
                ),
                ButtonSegment(
                  value: FittingType.directBranch,
                  label: Text('Прямая врезка У18 (1 шов)'),
                  icon: Icon(Icons.merge_type),
                ),
              ],
              selected: {fit.fittingType},
              onSelectionChanged: (set) {
                final newType = set.first;
                if (newType == FittingType.directBranch) {
                  _update(fit.copyWith(
                    fittingType: FittingType.directBranch,
                    name: 'Прямая врезка У18',
                    standard: 'ГОСТ 16037-80 У18',
                    weldType: WeldType.u18,
                    radiusMm: 0.0,
                    cutsMainPipe: false,
                  ));
                } else {
                  _update(fit.copyWith(
                    fittingType: FittingType.tee,
                    name: 'Тройник равнопроходный Ду${fit.dn}',
                    standard: 'ГОСТ 17376-2001',
                    weldType: WeldType.c17,
                    radiusMm: fit.dn * 1.0,
                    cutsMainPipe: true,
                  ));
                }
              },
            ),
            if (fit.fittingType == FittingType.tee) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Строительная длина L (мм)',
                        border: OutlineInputBorder(),
                        suffixText: 'мм',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      controller: TextEditingController(text: (fit.buildingLengthMm ?? fit.dn * 2.0).toStringAsFixed(0)),
                      onSubmitted: (v) {
                        final l = double.tryParse(v);
                        if (l != null) _update(fit.copyWith(buildingLengthMm: l, radiusMm: l / 2.0));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Вылет отвода H (мм)',
                        border: OutlineInputBorder(),
                        suffixText: 'мм',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      controller: TextEditingController(text: (fit.branchLengthMm ?? fit.dn * 1.0).toStringAsFixed(0)),
                      onSubmitted: (v) {
                        final h = double.tryParse(v);
                        if (h != null) _update(fit.copyWith(branchLengthMm: h));
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],

          // --- ПЕРЕХОД ---
          if (isReducer) ...[
            const Text('Тип перехода диаметров:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            SegmentedButton<FittingType>(
              segments: const [
                ButtonSegment(
                  value: FittingType.reducerConcentric,
                  label: Text('Концентрический'),
                  icon: Icon(Icons.filter_list),
                ),
                ButtonSegment(
                  value: FittingType.reducerEccentric,
                  label: Text('Эксцентрический'),
                  icon: Icon(Icons.tune),
                ),
              ],
              selected: {fit.fittingType},
              onSelectionChanged: (set) {
                final newType = set.first;
                _update(fit.copyWith(
                  fittingType: newType,
                  name: newType == FittingType.reducerEccentric
                      ? 'Переход эксц. ${fit.dn}х${fit.dnSecondary ?? fit.dn}'
                      : 'Переход конц. ${fit.dn}х${fit.dnSecondary ?? fit.dn}',
                ));
              },
            ),
            const SizedBox(height: 10),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Строительная длина L (мм)',
                border: OutlineInputBorder(),
                suffixText: 'мм',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              controller: TextEditingController(text: (fit.buildingLengthMm ?? fit.dn * 1.5).toStringAsFixed(0)),
              onSubmitted: (v) {
                final l = double.tryParse(v);
                if (l != null) _update(fit.copyWith(buildingLengthMm: l, radiusMm: l / 2.0));
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.rotate_right),
                label: Text('Поворот вокруг оси: ${fit.rotationAngleDeg.toStringAsFixed(0)}° (+90°)'),
                onPressed: () {
                  final newAngle = (fit.rotationAngleDeg + 90.0) % 360.0;
                  _update(fit.copyWith(rotationAngleDeg: newAngle));
                },
              ),
            ),
          ],

          const Divider(height: 24),
          // 3. Сварные стыки и ручное переопределение количества
          Row(
            children: [
              const Icon(Icons.hardware, size: 18, color: Colors.blueGrey),
              const SizedBox(width: 8),
              const Text('Сварные стыки узла:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Text(
                'Расчет: ${fit.effectiveWeldCount} ${fit.weldType.shortName}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<WeldType>(
                  isExpanded: true,
                  initialValue: fit.weldType,
                  decoration: const InputDecoration(
                    labelText: 'Тип шва ГОСТ 16037-80',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: WeldType.values.map((w) {
                    return DropdownMenuItem(value: w, child: Text('${w.shortName} (${w.gostCode})', overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (wt) {
                    if (wt == null) return;
                    _update(fit.copyWith(weldType: wt));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: fit.customWeldCount,
                  decoration: const InputDecoration(
                    labelText: 'Число швов',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('По ГОСТ', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 1, child: Text('1 стык', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 2, child: Text('2 стыка', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 3, child: Text('3 стыка', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 4, child: Text('4 стыка', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 0, child: Text('0 стыков', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (cnt) {
                    _update(fit.copyWith(customWeldCount: cnt));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: BorderSide(color: Colors.red.shade300),
              ),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Удалить деталь / фитинг'),
              onPressed: () {
                widget.network.removeFitting(widget.nodeId);
                widget.onModified?.call();
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _update(Fitting newFit) {
    widget.network.updateFitting(widget.nodeId, newFit);
    widget.onModified?.call();
    setState(() {});
  }

  void _openCollectionPicker(BuildContext context) {
    FittingCatalogDialog.show(
      context,
      network: widget.network,
      selectedNodeId: widget.nodeId,
      onCatalogChanged: () {
        widget.onModified?.call();
        setState(() {});
      },
    );
  }

  void _saveAsCustomTemplate(Fitting fit) {
    final customDef = FittingDefinition(
      id: 'custom_${fit.fittingType.name}_${_uuid.v4()}',
      name: '${fit.displayName} (Шаблон)',
      archetype: _resolveArchetype(fit.fittingType),
      fittingType: fit.fittingType,
      standard: fit.standard ?? 'ГОСТ',
      defaultMaterial: fit.material,
      fixedLengthMm: fit.buildingLengthMm ?? fit.effectiveRadiusMm,
      branchLengthMm: fit.branchLengthMm,
      weldType: fit.weldType,
      cutsMainPipe: fit.cutsMainPipe,
      isCustom: true,
      defaultWeldCount: fit.customWeldCount ?? fit.effectiveWeldCount,
      flangeConnectionType: fit.flangeConnectionType,
    );

    widget.network.catalog.addCustomDefinition(customDef);
    widget.onModified?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Элемент сохранен в коллекцию как «${customDef.name}»')),
    );
  }

  FittingArchetype _resolveArchetype(FittingType type) {
    switch (type) {
      case FittingType.elbow90:
      case FittingType.elbow45:
        return FittingArchetype.elbow;
      case FittingType.tee:
        return FittingArchetype.tee;
      case FittingType.directBranch:
        return FittingArchetype.directBranch;
      case FittingType.reducerConcentric:
      case FittingType.reducerEccentric:
        return FittingArchetype.reducer;
      case FittingType.flange:
        return FittingArchetype.flange;
      case FittingType.cap:
        return FittingArchetype.cap;
      case FittingType.cross:
        return FittingArchetype.cross;
    }
  }

  Widget _buildRadiusChip(String label, double radiusVal, Fitting fit) {
    final isSelected = (fit.effectiveRadiusMm - radiusVal).abs() < 1.0;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          _update(fit.copyWith(customRadiusMm: radiusVal, radiusMm: radiusVal));
        }
      },
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }

  IconData _getFittingIcon(FittingType type) {
    switch (type) {
      case FittingType.elbow90:
      case FittingType.elbow45:
        return Icons.turn_right;
      case FittingType.tee:
      case FittingType.directBranch:
        return Icons.alt_route;
      case FittingType.reducerConcentric:
      case FittingType.reducerEccentric:
        return Icons.filter_list;
      case FittingType.flange:
        return Icons.fiber_manual_record_outlined;
      case FittingType.cap:
        return Icons.block;
      case FittingType.cross:
        return Icons.add;
    }
  }
}
