enum EquipmentType {
  box,
  cylinderVertical,
  cylinderHorizontal,
}

extension EquipmentTypeExt on EquipmentType {
  String get displayName {
    switch (this) {
      case EquipmentType.box:
        return 'Параллелепипед';
      case EquipmentType.cylinderVertical:
        return 'Цилиндр верт.';
      case EquipmentType.cylinderHorizontal:
        return 'Цилиндр гор.';
    }
  }
}

/// Штуцер технологического оборудования (точка подключения трубопровода)
class Nozzle {
  final String id;
  final String equipmentId;
  final String name;
  final double localX;
  final double localY;
  final double localZ;
  final double dirX;
  final double dirY;
  final double dirZ;
  final int dn;

  const Nozzle({
    required this.id,
    required this.equipmentId,
    required this.name,
    required this.localX,
    required this.localY,
    required this.localZ,
    this.dirX = 0.0,
    this.dirY = 0.0,
    this.dirZ = 1.0,
    this.dn = 50,
  });

  Nozzle copyWith({
    String? id,
    String? equipmentId,
    String? name,
    double? localX,
    double? localY,
    double? localZ,
    double? dirX,
    double? dirY,
    double? dirZ,
    int? dn,
  }) {
    return Nozzle(
      id: id ?? this.id,
      equipmentId: equipmentId ?? this.equipmentId,
      name: name ?? this.name,
      localX: localX ?? this.localX,
      localY: localY ?? this.localY,
      localZ: localZ ?? this.localZ,
      dirX: dirX ?? this.dirX,
      dirY: dirY ?? this.dirY,
      dirZ: dirZ ?? this.dirZ,
      dn: dn ?? this.dn,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'equipmentId': equipmentId,
        'name': name,
        'localX': localX,
        'localY': localY,
        'localZ': localZ,
        'dirX': dirX,
        'dirY': dirY,
        'dirZ': dirZ,
        'dn': dn,
      };

  factory Nozzle.fromJson(Map<String, dynamic> json) => Nozzle(
        id: json['id'] as String,
        equipmentId: json['equipmentId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        localX: (json['localX'] as num).toDouble(),
        localY: (json['localY'] as num).toDouble(),
        localZ: (json['localZ'] as num).toDouble(),
        dirX: (json['dirX'] as num?)?.toDouble() ?? 0.0,
        dirY: (json['dirY'] as num?)?.toDouble() ?? 0.0,
        dirZ: (json['dirZ'] as num?)?.toDouble() ?? 1.0,
        dn: (json['dn'] as num?)?.toInt() ?? 50,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Nozzle &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          equipmentId == other.equipmentId &&
          name == other.name &&
          localX == other.localX &&
          localY == other.localY &&
          localZ == other.localZ &&
          dirX == other.dirX &&
          dirY == other.dirY &&
          dirZ == other.dirZ &&
          dn == other.dn;

  @override
  int get hashCode => Object.hash(
        id,
        equipmentId,
        name,
        localX,
        localY,
        localZ,
        dirX,
        dirY,
        dirZ,
        dn,
      );
}

/// Технологическое оборудование (емкость, насос, теплообменник и др.)
class Equipment {
  final String id;
  final String name;
  final EquipmentType type;
  final double x;
  final double y;
  final double z;
  final double width;
  final double length;
  final double height;
  final List<Nozzle> nozzles;

  const Equipment({
    required this.id,
    required this.name,
    this.type = EquipmentType.box,
    required this.x,
    required this.y,
    required this.z,
    required this.width,
    required this.length,
    required this.height,
    this.nozzles = const [],
  });

  Equipment copyWith({
    String? id,
    String? name,
    EquipmentType? type,
    double? x,
    double? y,
    double? z,
    double? width,
    double? length,
    double? height,
    List<Nozzle>? nozzles,
  }) {
    return Equipment(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      width: width ?? this.width,
      length: length ?? this.length,
      height: height ?? this.height,
      nozzles: nozzles ?? this.nozzles,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'x': x,
        'y': y,
        'z': z,
        'width': width,
        'length': length,
        'height': height,
        'nozzles': nozzles.map((n) => n.toJson()).toList(),
      };

  factory Equipment.fromJson(Map<String, dynamic> json) => Equipment(
        id: json['id'] as String,
        name: json['name'] as String,
        type: EquipmentType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => EquipmentType.box,
        ),
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        z: (json['z'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        length: (json['length'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        nozzles: (json['nozzles'] as List<dynamic>?)
                ?.map((n) => Nozzle.fromJson(n as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Equipment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          x == other.x &&
          y == other.y &&
          z == other.z &&
          width == other.width &&
          length == other.length &&
          height == other.height;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        type,
        x,
        y,
        z,
        width,
        length,
        height,
      );
}
