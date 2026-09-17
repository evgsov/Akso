import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../domain/models/equipment.dart';
import '../../../../../domain/models/piping_network.dart';

class EquipmentPropertiesSheet extends StatefulWidget {
  final PipingNetwork network;
  final String equipmentId;
  final VoidCallback onModified;

  const EquipmentPropertiesSheet({
    super.key,
    required this.network,
    required this.equipmentId,
    required this.onModified,
  });

  @override
  State<EquipmentPropertiesSheet> createState() => _EquipmentPropertiesSheetState();
}

class _EquipmentPropertiesSheetState extends State<EquipmentPropertiesSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _serialCtrl;
  late TextEditingController _elevationCtrl;
  late TextEditingController _widthCtrl;
  late TextEditingController _lengthCtrl;
  late TextEditingController _heightCtrl;
  EquipmentType _type = EquipmentType.box;
  double _rotationAngleDeg = 0.0;

  @override
  void initState() {
    super.initState();
    final eq = widget.network.equipments[widget.equipmentId];
    _nameCtrl = TextEditingController(text: eq?.name ?? '');
    _serialCtrl = TextEditingController(text: eq?.serialNumber ?? '');
    final elevM = ((eq?.z ?? 0.0) / 1000.0);
    _elevationCtrl = TextEditingController(text: elevM.toStringAsFixed(3));
    _widthCtrl = TextEditingController(text: eq?.width.toString() ?? '1000.0');
    _lengthCtrl = TextEditingController(text: eq?.length.toString() ?? '1000.0');
    _heightCtrl = TextEditingController(text: eq?.height.toString() ?? '1000.0');
    _type = eq?.type ?? EquipmentType.box;
    _rotationAngleDeg = eq?.rotationAngleDeg ?? 0.0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _serialCtrl.dispose();
    _elevationCtrl.dispose();
    _widthCtrl.dispose();
    _lengthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  void _applyChanges() {
    final eq = widget.network.equipments[widget.equipmentId];
    if (eq == null) return;

    final elevM = double.tryParse(_elevationCtrl.text.replaceAll('+', '').replaceAll(',', '.'));
    if (elevM != null) {
      widget.network.changeEquipmentElevation(widget.equipmentId, elevM);
    }
    
    final updatedEq = widget.network.equipments[widget.equipmentId] ?? eq;
    final w = double.tryParse(_widthCtrl.text) ?? updatedEq.width;
    final l = double.tryParse(_lengthCtrl.text) ?? updatedEq.length;
    final h = double.tryParse(_heightCtrl.text) ?? updatedEq.height;

    final updated = updatedEq.copyWith(
      name: _nameCtrl.text,
      serialNumber: _serialCtrl.text.trim().isEmpty ? null : _serialCtrl.text.trim(),
      clearSerialNumber: _serialCtrl.text.trim().isEmpty,
      type: _type,
      width: w,
      length: l,
      height: h,
      rotationAngleDeg: _rotationAngleDeg,
    );

    widget.network.updateEquipment(updated);
    widget.onModified();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final eq = widget.network.equipments[widget.equipmentId];

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Свойства оборудования', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Название аппарата',
                hintText: 'напр. Насос Н-1, Емкость Е-1',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serialCtrl,
              decoration: const InputDecoration(
                labelText: 'Заводской номер',
                hintText: 'напр. № 10492, ЗАВ-02',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _elevationCtrl,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+-]'))],
              decoration: const InputDecoration(
                labelText: 'Высотная отметка основания (Z), м',
                hintText: '+0.000',
                suffixText: 'м',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            // Угол поворота и кнопка разворота
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Угол поворота вокруг Z:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('${_rotationAngleDeg.round()}°', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.rotate_right, size: 16),
                    label: const Text('Повернуть на 90°', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      widget.network.rotateEquipment(widget.equipmentId, 90.0);
                      final cur = widget.network.equipments[widget.equipmentId];
                      if (cur != null) {
                        setState(() => _rotationAngleDeg = cur.rotationAngleDeg);
                      }
                      widget.onModified();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            DropdownButtonFormField<EquipmentType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Форма корпуса', border: OutlineInputBorder(), isDense: true),
              items: EquipmentType.values.map((t) => DropdownMenuItem(
                value: t,
                child: Text(t.displayName),
              )).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _type = val);
                }
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _widthCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: InputDecoration(
                      labelText: _type == EquipmentType.box ? 'Ширина (X), мм' : 'Диаметр (X), мм',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lengthCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: InputDecoration(
                      labelText: _type == EquipmentType.box ? 'Глубина (Y), мм' : (_type == EquipmentType.cylinderVertical ? 'Диаметр (Y), мм' : 'Длина (Y), мм'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _heightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: InputDecoration(
                      labelText: _type == EquipmentType.box ? 'Высота (Z), мм' : (_type == EquipmentType.cylinderVertical ? 'Высота (Z), мм' : 'Диаметр (Z), мм'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),

            if (eq != null && eq.nozzles.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Штуцеры оборудования (${eq.nozzles.length}):', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...eq.nozzles.map((noz) {
                final faceStr = noz.face != null ? ' (${noz.face!.name})' : '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${noz.name}$faceStr Ду${noz.dn}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Row(
                              children: [
                                SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: Checkbox(
                                    value: noz.includeInMto,
                                    onChanged: (val) {
                                      if (val != null) {
                                        widget.network.setNozzleIncludeInMto(widget.equipmentId, noz.id, val);
                                        setState(() {});
                                        widget.onModified();
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text('Ответный фланец в МТО', style: TextStyle(fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        tooltip: 'Удалить штуцер',
                        onPressed: () {
                          widget.network.removeEquipmentNozzle(widget.equipmentId, noz.id);
                          setState(() {});
                          widget.onModified();
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _applyChanges,
                  child: const Text('Применить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
