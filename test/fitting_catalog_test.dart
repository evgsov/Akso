import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/models/fitting_catalog.dart';

void main() {
  group('FittingCatalog & Custom Definitions Tests', () {
    late FittingCatalog catalog;

    setUp(() {
      catalog = FittingCatalog();
    });

    test('Каталог инициализирует библиотеку стандартных ГОСТ/ОСТ элементов', () {
      expect(catalog.definitions.isNotEmpty, isTrue);
      expect(catalog.definitions.containsKey('elbow_gost_17375'), isTrue);
      expect(catalog.definitions.containsKey('elbow_gost_30753'), isTrue);
      expect(catalog.definitions.containsKey('direct_branch_u18'), isTrue);
      expect(catalog.definitions.containsKey('flange_weld_neck_11'), isTrue);
    });

    test('Вычисление строительного вычета катушки по формуле R = k * DN', () {
      final elbow17375 = catalog.getDefinition('elbow_gost_17375')!;
      // R = 1.5 * DN
      expect(elbow17375.calculateDeduction(100), equals(150.0));
      expect(elbow17375.calculateDeduction(50), equals(75.0));

      final elbow30753 = catalog.getDefinition('elbow_gost_30753')!;
      // R = 1.0 * DN
      expect(elbow30753.calculateDeduction(100), equals(100.0));

      final bentElbow = catalog.getDefinition('elbow_bent_gost_24950')!;
      // R = 3.0 * DN
      expect(bentElbow.calculateDeduction(100), equals(300.0));
    });

    test('Прямая врезка У18 не укорачивает магистральную трубу (вычет = 0)', () {
      final branch = catalog.getDefinition('direct_branch_u18')!;
      expect(branch.cutsMainPipe, isFalse);
      expect(branch.calculateDeduction(100), equals(0.0));
      expect(branch.weldType, equals(WeldType.u18));
    });

    test('Создание пользовательского элемента через createFromBase', () {
      final custom = catalog.createFromBase(
        baseDefinitionId: 'elbow_gost_17375',
        newName: 'Отвод гнутый R=3DN ТУ 102-488',
        newStandard: 'ТУ 102-488-05',
        newMaterial: '09Г2С',
        newRadiusFactor: 3.0,
        newWeldType: WeldType.c17,
      );

      expect(custom.isCustom, isTrue);
      expect(custom.name, equals('Отвод гнутый R=3DN ТУ 102-488'));
      expect(custom.standard, equals('ТУ 102-488-05'));
      expect(custom.defaultMaterial, equals('09Г2С'));
      expect(custom.calculateDeduction(100), equals(300.0));

      // Проверяем наличие в каталоге
      expect(catalog.getDefinition(custom.id), isNotNull);
      expect(catalog.customDefinitions.contains(custom), isTrue);
    });

    test('Сериализация и десериализация каталога с пользовательскими элементами', () {
      final custom = catalog.createFromBase(
        baseDefinitionId: 'tee_gost_17376',
        newName: 'Тройник кованый Ру40 заказной',
        newStandard: 'СТ ЦКБА 025-2006',
        newMaterial: '12Х18Н10Т',
        newFixedLengthMm: 180.0,
      );

      catalog.defaultElbowId = 'elbow_gost_30753';
      catalog.defaultBranchId = custom.id;

      final json = catalog.toJson();
      expect(json['defaultElbowId'], equals('elbow_gost_30753'));
      expect(json['defaultBranchId'], equals(custom.id));

      final restoredCatalog = FittingCatalog();
      restoredCatalog.loadFromJson(json);

      expect(restoredCatalog.defaultElbowId, equals('elbow_gost_30753'));
      expect(restoredCatalog.defaultBranchId, equals(custom.id));
      final restoredCustom = restoredCatalog.getDefinition(custom.id);
      expect(restoredCustom, isNotNull);
      expect(restoredCustom!.name, equals('Тройник кованый Ру40 заказной'));
      expect(restoredCustom.calculateDeduction(100), equals(180.0));
      expect(restoredCustom.defaultMaterial, equals('12Х18Н10Т'));
    });
  });
}
