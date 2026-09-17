import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/equipment.dart';

void main() {
  group('Equipment and Nozzle Data Model Tests', () {
    test('Equipment supports rotationAngleDeg and default is 0.0', () {
      const eqDefault = Equipment(
        id: 'eq1',
        name: 'Емкость Е-1',
        x: 1000,
        y: 1000,
        z: 0,
        width: 1000,
        length: 1000,
        height: 2000,
      );

      expect(eqDefault.rotationAngleDeg, equals(0.0));

      final eqRotated = eqDefault.copyWith(rotationAngleDeg: 90.0);
      expect(eqRotated.rotationAngleDeg, equals(90.0));

      final json = eqRotated.toJson();
      expect(json['rotationAngleDeg'], equals(90.0));

      final fromJson = Equipment.fromJson(json);
      expect(fromJson.rotationAngleDeg, equals(90.0));
      expect(fromJson, equals(eqRotated));
    });

    test('Equipment fromJson without rotationAngleDeg defaults to 0.0 (backward compatibility)', () {
      final legacyJson = {
        'id': 'eq_legacy',
        'name': 'Насос Н-1',
        'type': 'box',
        'x': 500.0,
        'y': 500.0,
        'z': 0.0,
        'width': 800.0,
        'length': 1200.0,
        'height': 600.0,
        'nozzles': <dynamic>[],
      };

      final eq = Equipment.fromJson(legacyJson);
      expect(eq.rotationAngleDeg, equals(0.0));
    });

    test('Nozzle supports face and includeInMto fields', () {
      const nozzle = Nozzle(
        id: 'noz1',
        equipmentId: 'eq1',
        name: 'Ш-1',
        localX: 0,
        localY: 0,
        localZ: 2000,
        face: EquipmentFace.top,
        includeInMto: false,
      );

      expect(nozzle.face, equals(EquipmentFace.top));
      expect(nozzle.includeInMto, isFalse);

      final json = nozzle.toJson();
      expect(json['face'], equals('top'));
      expect(json['includeInMto'], isFalse);

      final fromJson = Nozzle.fromJson(json);
      expect(fromJson.face, equals(EquipmentFace.top));
      expect(fromJson.includeInMto, isFalse);
      expect(fromJson, equals(nozzle));

      final nozzleMto = nozzle.copyWith(includeInMto: true, face: EquipmentFace.left);
      expect(nozzleMto.includeInMto, isTrue);
      expect(nozzleMto.face, equals(EquipmentFace.left));
    });
  });
}
