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

/// Грань или поверхность оборудования, к которой привязан штуцер
enum EquipmentFace {
  top,
  bottom,
  left,
  right,
  front,
  back,
  cylindrical,
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

  /// Грань аппарата, на которой размещен штуцер (null, если произвольное положение)
  final EquipmentFace? face;

  /// Включать ли ответный фланец штуцера в заказную спецификацию MTO (по умолчанию false - комплектный)
  final bool includeInMto;

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
    this.face,
    this.includeInMto = false,
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
    EquipmentFace? face,
    bool? includeInMto,
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
      face: face ?? this.face,
      includeInMto: includeInMto ?? this.includeInMto,
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
        if (face != null) 'face': face!.name,
        'includeInMto': includeInMto,
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
        face: json['face'] != null
            ? EquipmentFace.values.firstWhere(
                (f) => f.name == json['face'],
                orElse: () => EquipmentFace.top,
              )
            : null,
        includeInMto: json['includeInMto'] as bool? ?? false,
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
          dn == other.dn &&
          face == other.face &&
          includeInMto == other.includeInMto;

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
        face,
        includeInMto,
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

  /// Угол поворота оборудования в плоскости XY (в градусах, по умолчанию 0.0)
  final double rotationAngleDeg;

  /// Заводской номер оборудования (аппарата, насоса, емкости)
  final String? serialNumber;

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
    this.rotationAngleDeg = 0.0,
    this.serialNumber,
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
    double? rotationAngleDeg,
    String? serialNumber,
    bool clearSerialNumber = false,
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
      rotationAngleDeg: rotationAngleDeg ?? this.rotationAngleDeg,
      serialNumber: clearSerialNumber ? null : (serialNumber ?? this.serialNumber),
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
        'rotationAngleDeg': rotationAngleDeg,
        if (serialNumber != null) 'serialNumber': serialNumber,
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
        rotationAngleDeg: (json['rotationAngleDeg'] as num?)?.toDouble() ?? 0.0,
        serialNumber: json['serialNumber'] as String?,
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
          height == other.height &&
          rotationAngleDeg == other.rotationAngleDeg;

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
        rotationAngleDeg,
      );
}
