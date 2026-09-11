import 'package:flutter/material.dart';
import '../../../../domain/models/pipe_dimension.dart';

/// Диалог добавления пользовательского типоразмера трубы (DN, Dн, стенки S, стандарт)
class CustomPipeDimensionDialog extends StatefulWidget {
  final int? initialDn;
  final double? initialOuterD;
  final double? initialWallS;

  const CustomPipeDimensionDialog({
    super.key,
    this.initialDn,
    this.initialOuterD,
    this.initialWallS,
  });

  static Future<PipeDimension?> show(
    BuildContext context, {
    int? initialDn,
    double? initialOuterD,
    double? initialWallS,
  }) {
    return showDialog<PipeDimension>(
      context: context,
      builder: (ctx) => CustomPipeDimensionDialog(
        initialDn: initialDn,
        initialOuterD: initialOuterD,
        initialWallS: initialWallS,
      ),
    );
  }

  @override
  State<CustomPipeDimensionDialog> createState() => _CustomPipeDimensionDialogState();
}

class _CustomPipeDimensionDialogState extends State<CustomPipeDimensionDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _dnController;
  late TextEditingController _outerDController;
  late TextEditingController _wallsController;
  late TextEditingController _standardController;

  @override
  void initState() {
    super.initState();
    final dn = widget.initialDn ?? 150;
    final outerD = widget.initialOuterD ?? (dn <= 50 ? (dn * 1.25 + 5.0) : (dn * 1.08));
    final wallS = widget.initialWallS ?? 4.5;

    _dnController = TextEditingController(text: '$dn');
    _outerDController = TextEditingController(
      text: outerD.truncateToDouble() == outerD
          ? outerD.toStringAsFixed(0)
          : outerD.toStringAsFixed(1),
    );
    _wallsController = TextEditingController(
      text: wallS.truncateToDouble() == wallS
          ? wallS.toStringAsFixed(0)
          : wallS.toStringAsFixed(1),
    );
    _standardController = TextEditingController(text: 'ГОСТ 8732-78');

    _dnController.addListener(() => setState(() {}));
    _outerDController.addListener(() => setState(() {}));
    _wallsController.addListener(() => setState(() {}));
    _standardController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _dnController.dispose();
    _outerDController.dispose();
    _wallsController.dispose();
    _standardController.dispose();
    super.dispose();
  }

  List<double> _parseWallThicknesses() {
    final raw = _wallsController.text;
    final parts = raw.split(RegExp(r'[,; ]+'));
    final list = <double>[];
    for (final p in parts) {
      final v = double.tryParse(p.trim().replaceAll(',', '.'));
      if (v != null && v > 0.0 && !list.contains(v)) {
        list.add(v);
      }
    }
    if (list.isEmpty) list.add(4.5);
    list.sort();
    return list;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final dn = int.parse(_dnController.text.trim());
    final outerD = double.parse(_outerDController.text.trim().replaceAll(',', '.'));
    final walls = _parseWallThicknesses();
    final std = _standardController.text.trim().isEmpty ? 'ГОСТ 8732-78' : _standardController.text.trim();

    final dim = PipeDimension(
      dn: dn,
      outerDiameterMm: outerD,
      wallThicknesses: walls,
      defaultWallThicknessMm: walls.first,
      standard: std,
      isCustom: true,
    );

    Navigator.of(context).pop(dim);
  }

  @override
  Widget build(BuildContext context) {
    final dnVal = int.tryParse(_dnController.text) ?? 0;
    final outerDVal = double.tryParse(_outerDController.text.replaceAll(',', '.')) ?? 0.0;
    final walls = _parseWallThicknesses();
    final std = _standardController.text.trim();

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.tune, color: Colors.indigo),
          SizedBox(width: 8),
          Text('Новый типоразмер трубы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Добавьте собственный диаметр и ряд толщин стенок для промышленного или нестандартного сортамента.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 16),

                // Предпросмотр
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.remove_red_eye_outlined, size: 20, color: Colors.indigo),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⌀${outerDVal.toStringAsFixed(outerDVal.truncateToDouble() == outerDVal ? 0 : 1)}×${walls.first.toStringAsFixed(walls.first.truncateToDouble() == walls.first ? 0 : 1)} (Ду$dnVal)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo),
                            ),
                            Text(
                              'Стенки: ${walls.map((w) => '${w.toStringAsFixed(w.truncateToDouble() == w ? 0 : 1)} мм').join(', ')} • $std',
                              style: const TextStyle(fontSize: 11, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Ду (DN)
                TextFormField(
                  controller: _dnController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Номинальный диаметр (Ду / DN), мм',
                    hintText: 'например, 150, 175, 225, 450...',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.straighten, size: 18),
                  ),
                  validator: (val) {
                    final v = int.tryParse(val ?? '');
                    if (v == null || v <= 0) return 'Укажите положительное целое число';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Dн
                TextFormField(
                  controller: _outerDController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Наружный диаметр (Dн), мм',
                    hintText: 'например, 159, 168.3, 219, 530...',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.circle_outlined, size: 18),
                  ),
                  validator: (val) {
                    final v = double.tryParse((val ?? '').replaceAll(',', '.'));
                    if (v == null || v <= 0) return 'Укажите положительное число';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Толщины стенок S
                TextFormField(
                  controller: _wallsController,
                  decoration: const InputDecoration(
                    labelText: 'Толщины стенок (S), мм (через запятую)',
                    hintText: 'например: 4.5, 6.0, 8.0, 10.0',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.line_weight, size: 18),
                  ),
                  validator: (val) {
                    final list = _parseWallThicknesses();
                    if (list.isEmpty) return 'Укажите хотя бы одну толщину стенки';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Стандарт
                TextFormField(
                  controller: _standardController,
                  decoration: const InputDecoration(
                    labelText: 'Стандарт (ГОСТ / ТУ / ASME)',
                    hintText: 'ГОСТ 8732-78, ТУ 14-3Р-55-2001, ASME B36.10...',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.menu_book, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Добавить в сортамент'),
        ),
      ],
    );
  }
}
