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
  late TextEditingController _widthCtrl;
  late TextEditingController _lengthCtrl;
  late TextEditingController _heightCtrl;
  EquipmentType _type = EquipmentType.box;

  @override
  void initState() {
    super.initState();
    final eq = widget.network.equipments[widget.equipmentId];
    _nameCtrl = TextEditingController(text: eq?.name ?? '');
    _serialCtrl = TextEditingController(text: eq?.serialNumber ?? '');
    _widthCtrl = TextEditingController(text: eq?.width.toString() ?? '1000.0');
    _lengthCtrl = TextEditingController(text: eq?.length.toString() ?? '1000.0');
    _heightCtrl = TextEditingController(text: eq?.height.toString() ?? '1000.0');
    _type = eq?.type ?? EquipmentType.box;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _serialCtrl.dispose();
    _widthCtrl.dispose();
    _lengthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  void _applyChanges() {
    final eq = widget.network.equipments[widget.equipmentId];
    if (eq == null) return;
    
    final w = double.tryParse(_widthCtrl.text) ?? eq.width;
    final l = double.tryParse(_lengthCtrl.text) ?? eq.length;
    final h = double.tryParse(_heightCtrl.text) ?? eq.height;

    final updated = eq.copyWith(
      name: _nameCtrl.text,
      serialNumber: _serialCtrl.text.trim().isEmpty ? null : _serialCtrl.text.trim(),
      clearSerialNumber: _serialCtrl.text.trim().isEmpty,
      type: _type,
      width: w,
      length: l,
      height: h,
    );

    widget.network.updateEquipment(updated);
    widget.onModified();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
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
    );
  }
}
