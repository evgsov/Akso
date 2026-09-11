/// Описание инженерной системы (ХВС, ГВС, канализация, отопление, пар, мазут и т.д.)
class PipingSystem {
  final String id;
  final String code;
  final String name;
  final int colorValue;
  final int dxfAciColor;
  final int defaultDn;
  final String defaultMaterial;
  final List<int> availableDns;
  final String? defaultElbowId;
  final String? defaultBranchId;
  final String? defaultFlangeId;
  final bool isCustom;

  const PipingSystem({
    required this.id,
    required this.code,
    required this.name,
    required this.colorValue,
    required this.dxfAciColor,
    this.defaultDn = 25,
    this.defaultMaterial = 'Сталь 20',
    this.availableDns = const [15, 20, 25, 32, 40, 50, 65, 80, 100, 150],
    this.defaultElbowId,
    this.defaultBranchId,
    this.defaultFlangeId,
    this.isCustom = false,
  });

  /// Стандартные предустановленные системы по ГОСТ 21.205
  static const List<PipingSystem> defaults = [
    PipingSystem(
      id: 'sys_b1',
      code: 'В1',
      name: 'Холодное водоснабжение',
      colorValue: 0xFF1E88E5, // Синий
      dxfAciColor: 5, // Blue ACI
      defaultDn: 25,
      defaultMaterial: 'Сталь 20',
      availableDns: [15, 20, 25, 32, 40, 50, 65, 80, 100],
    ),
    PipingSystem(
      id: 'sys_t3',
      code: 'Т3',
      name: 'Горячее водоснабжение (подача)',
      colorValue: 0xFFE53935, // Красный
      dxfAciColor: 1, // Red ACI
      defaultDn: 25,
      defaultMaterial: 'Сталь 20',
      availableDns: [15, 20, 25, 32, 40, 50, 65, 80],
    ),
    PipingSystem(
      id: 'sys_t4',
      code: 'Т4',
      name: 'Горячее водоснабжение (циркуляция)',
      colorValue: 0xFFFB8C00, // Оранжевый
      dxfAciColor: 30, // Orange ACI
      defaultDn: 20,
      defaultMaterial: 'Сталь 20',
      availableDns: [15, 20, 25, 32, 40, 50],
    ),
    PipingSystem(
      id: 'sys_k1',
      code: 'К1',
      name: 'Канализация бытовая',
      colorValue: 0xFF6D4C41, // Коричневый
      dxfAciColor: 130, // Brown ACI
      defaultDn: 110,
      defaultMaterial: 'Чугун / ПНД',
      availableDns: [50, 110, 160, 200],
    ),
    PipingSystem(
      id: 'sys_o1',
      code: 'О1',
      name: 'Отопление (подающий трубопровод)',
      colorValue: 0xFFD81B60, // Маджента / Бордовый
      dxfAciColor: 6, // Magenta ACI
      defaultDn: 32,
      defaultMaterial: '09Г2С',
      availableDns: [15, 20, 25, 32, 40, 50, 65, 80, 100, 150],
    ),
    PipingSystem(
      id: 'sys_o2',
      code: 'О2',
      name: 'Отопление (обратный трубопровод)',
      colorValue: 0xFF00ACC1, // Циан
      dxfAciColor: 4, // Cyan ACI
      defaultDn: 32,
      defaultMaterial: '09Г2С',
      availableDns: [15, 20, 25, 32, 40, 50, 65, 80, 100, 150],
    ),
    PipingSystem(
      id: 'sys_tx',
      code: 'ТХ',
      name: 'Технологический трубопровод (промышленный)',
      colorValue: 0xFF00897B, // Teal
      dxfAciColor: 3, // Green/Teal ACI
      defaultDn: 250,
      defaultMaterial: '09Г2С',
      availableDns: [
        50, 65, 80, 100, 125, 150, 200, 250, 300, 350, 400, 500, 600, 700, 800, 1000, 1200, 1400,
      ],
    ),
    PipingSystem(
      id: 'sys_ts',
      code: 'ТС',
      name: 'Тепловая сеть (магистральная)',
      colorValue: 0xFFE65100, // Deep Orange
      dxfAciColor: 1, // Red ACI
      defaultDn: 300,
      defaultMaterial: 'Сталь 20',
      availableDns: [
        100, 125, 150, 200, 250, 300, 350, 400, 500, 600, 700, 800, 1000, 1200, 1400,
      ],
    ),
  ];

  PipingSystem copyWith({
    String? id,
    String? code,
    String? name,
    int? colorValue,
    int? dxfAciColor,
    int? defaultDn,
    String? defaultMaterial,
    List<int>? availableDns,
    String? defaultElbowId,
    String? defaultBranchId,
    String? defaultFlangeId,
    bool? isCustom,
  }) {
    return PipingSystem(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      dxfAciColor: dxfAciColor ?? this.dxfAciColor,
      defaultDn: defaultDn ?? this.defaultDn,
      defaultMaterial: defaultMaterial ?? this.defaultMaterial,
      availableDns: availableDns ?? this.availableDns,
      defaultElbowId: defaultElbowId ?? this.defaultElbowId,
      defaultBranchId: defaultBranchId ?? this.defaultBranchId,
      defaultFlangeId: defaultFlangeId ?? this.defaultFlangeId,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'colorValue': colorValue,
        'dxfAciColor': dxfAciColor,
        'defaultDn': defaultDn,
        'defaultMaterial': defaultMaterial,
        'availableDns': availableDns,
        'defaultElbowId': defaultElbowId,
        'defaultBranchId': defaultBranchId,
        'defaultFlangeId': defaultFlangeId,
        'isCustom': isCustom,
      };

  factory PipingSystem.fromJson(Map<String, dynamic> json) => PipingSystem(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        colorValue: json['colorValue'] as int,
        dxfAciColor: json['dxfAciColor'] as int,
        defaultDn: json['defaultDn'] as int? ?? 25,
        defaultMaterial: json['defaultMaterial'] as String? ?? 'Сталь 20',
        availableDns: (json['availableDns'] as List<dynamic>?)?.map((e) => e as int).toList() ??
            const [15, 20, 25, 32, 40, 50, 65, 80, 100, 150],
        defaultElbowId: json['defaultElbowId'] as String?,
        defaultBranchId: json['defaultBranchId'] as String?,
        defaultFlangeId: json['defaultFlangeId'] as String?,
        isCustom: json['isCustom'] as bool? ?? false,
      );
}
