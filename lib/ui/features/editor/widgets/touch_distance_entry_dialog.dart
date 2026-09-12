import 'dart:math' as math;
import 'package:flutter/material.dart';

enum TouchDirectionPreset {
  plusX(
    key: 'dir_plus_x',
    label: 'Вперед (+X)',
    shortLabel: '+X',
    dirX: 1.0,
    dirY: 0.0,
    dirZ: 0.0,
    icon: Icons.arrow_forward,
  ),
  minusX(
    key: 'dir_minus_x',
    label: 'Назад (-X)',
    shortLabel: '-X',
    dirX: -1.0,
    dirY: 0.0,
    dirZ: 0.0,
    icon: Icons.arrow_back,
  ),
  plusY(
    key: 'dir_plus_y',
    label: 'Влево (+Y)',
    shortLabel: '+Y',
    dirX: 0.0,
    dirY: 1.0,
    dirZ: 0.0,
    icon: Icons.turn_left,
  ),
  minusY(
    key: 'dir_minus_y',
    label: 'Вправо (-Y)',
    shortLabel: '-Y',
    dirX: 0.0,
    dirY: -1.0,
    dirZ: 0.0,
    icon: Icons.turn_right,
  ),
  plusZ(
    key: 'dir_plus_z',
    label: 'Вверх (+Z)',
    shortLabel: '+Z',
    dirX: 0.0,
    dirY: 0.0,
    dirZ: 1.0,
    icon: Icons.arrow_upward,
  ),
  minusZ(
    key: 'dir_minus_z',
    label: 'Вниз (-Z)',
    shortLabel: '-Z',
    dirX: 0.0,
    dirY: 0.0,
    dirZ: -1.0,
    icon: Icons.arrow_downward,
  ),
  customAngle(
    key: 'dir_custom_angle',
    label: 'Свой угол (°)',
    shortLabel: 'Угол',
    dirX: null,
    dirY: null,
    dirZ: null,
    icon: Icons.rotate_right,
  );

  final String key;
  final String label;
  final String shortLabel;
  final double? dirX;
  final double? dirY;
  final double? dirZ;
  final IconData icon;

  const TouchDirectionPreset({
    required this.key,
    required this.label,
    required this.shortLabel,
    required this.dirX,
    required this.dirY,
    required this.dirZ,
    required this.icon,
  });
}

class TouchDistanceEntryDialog extends StatefulWidget {
  final void Function(double lengthMm, {double? dirX, double? dirY, double? dirZ}) onCommit;
  final double? initialLength;
  final TouchDirectionPreset initialDirection;

  const TouchDistanceEntryDialog({
    super.key,
    required this.onCommit,
    this.initialLength,
    this.initialDirection = TouchDirectionPreset.plusX,
  });

  static Future<void> show(
    BuildContext context, {
    required void Function(double lengthMm, {double? dirX, double? dirY, double? dirZ}) onCommit,
    double? initialLength,
    TouchDirectionPreset initialDirection = TouchDirectionPreset.plusX,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => TouchDistanceEntryDialog(
        onCommit: onCommit,
        initialLength: initialLength,
        initialDirection: initialDirection,
      ),
    );
  }

  @override
  State<TouchDistanceEntryDialog> createState() => _TouchDistanceEntryDialogState();
}

class _TouchDistanceEntryDialogState extends State<TouchDistanceEntryDialog> {
  late final TextEditingController _lengthController;
  late final TextEditingController _angleController;
  late TouchDirectionPreset _selectedPreset;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedPreset = widget.initialDirection;
    final initLen = widget.initialLength != null && widget.initialLength! > 0
        ? widget.initialLength!.round().toString()
        : '1000';
    _lengthController = TextEditingController(text: initLen);
    _angleController = TextEditingController(text: '45');
  }

  @override
  void dispose() {
    _lengthController.dispose();
    _angleController.dispose();
    super.dispose();
  }

  void _submit() {
    final rawLen = _lengthController.text.trim().replaceAll(' ', '');
    final length = double.tryParse(rawLen);
    if (length == null || length <= 0) {
      setState(() {
        _errorMessage = 'Введите корректную длину (> 0 мм)';
      });
      return;
    }

    double dx = 1.0;
    double dy = 0.0;
    double dz = 0.0;

    if (_selectedPreset == TouchDirectionPreset.customAngle) {
      final rawAngle = _angleController.text.trim().replaceAll(' ', '');
      final angle = double.tryParse(rawAngle) ?? 0.0;
      final rad = angle * math.pi / 180.0;
      dx = math.cos(rad);
      dy = math.sin(rad);
      dz = 0.0;
    } else {
      dx = _selectedPreset.dirX ?? 1.0;
      dy = _selectedPreset.dirY ?? 0.0;
      dz = _selectedPreset.dirZ ?? 0.0;
    }

    widget.onCommit(length, dirX: dx, dirY: dy, dirZ: dz);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.straighten, color: Colors.indigo),
          SizedBox(width: 8),
          Text(
            'Точная длина и направление',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Длина (мм):',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('touch_length_input'),
                controller: _lengthController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '1000',
                  suffixText: 'мм',
                  errorText: _errorMessage,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: const Icon(Icons.straighten, size: 20),
                ),
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [250, 500, 1000, 1500, 2000, 3000].map((len) {
                  return ActionChip(
                    label: Text('$len мм', style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _lengthController.text = '$len';
                        _errorMessage = null;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Направление построения:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TouchDirectionPreset.values.map((preset) {
                  final isSelected = _selectedPreset == preset;
                  return SizedBox(
                    height: 42,
                    child: isSelected
                        ? FilledButton.icon(
                            key: Key(preset.key),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: Icon(preset.icon, size: 18),
                            label: Text(preset.label, style: const TextStyle(fontSize: 13)),
                            onPressed: () {
                              setState(() => _selectedPreset = preset);
                            },
                          )
                        : OutlinedButton.icon(
                            key: Key(preset.key),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: Icon(preset.icon, size: 18),
                            label: Text(preset.label, style: const TextStyle(fontSize: 13)),
                            onPressed: () {
                              setState(() => _selectedPreset = preset);
                            },
                          ),
                  );
                }).toList(),
              ),
              if (_selectedPreset == TouchDirectionPreset.customAngle) ...[
                const SizedBox(height: 12),
                const Text(
                  'Угол в плоскости XY (°):',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('touch_angle_input'),
                  controller: _angleController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '45',
                    suffixText: '°',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.rotate_right, size: 20),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('touch_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          key: const Key('touch_build_button'),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Построить'),
          onPressed: _submit,
        ),
      ],
    );
  }
}
