import '../enums/fitting_type.dart';
import '../enums/weld_type.dart';
import 'fitting.dart';
import 'pipe_segment.dart';
import 'pipe_support.dart';
import 'valve.dart';
import 'weld_joint.dart';

/// Категория источника свойств в буфере обмена
enum PropertySourceKind {
  valve,
  fitting,
  segment,
  support,
  weld,
}

/// Настройки фильтрации переносимых свойств (чекбоксы / тумблеры в инспекторе)
class PropertyCopyOptions {
  /// Переносить марку стали, ГОСТ, давление Ру, тип сварного шва и фланцевое исполнение
  final bool copyMaterialAndStandard;

  /// Переносить тип элемента, наименование, строительные длины и параметры геометрии
  final bool copyDimensionsAndType;

  /// Переносить заводской номер / номер плавки (`serialNumber`) и позиционную марку (`mark`)
  final bool copySerialAndMark;

  const PropertyCopyOptions({
    this.copyMaterialAndStandard = true,
    this.copyDimensionsAndType = true,
    this.copySerialAndMark = false,
  });

  PropertyCopyOptions copyWith({
    bool? copyMaterialAndStandard,
    bool? copyDimensionsAndType,
    bool? copySerialAndMark,
  }) {
    return PropertyCopyOptions(
      copyMaterialAndStandard: copyMaterialAndStandard ?? this.copyMaterialAndStandard,
      copyDimensionsAndType: copyDimensionsAndType ?? this.copyDimensionsAndType,
      copySerialAndMark: copySerialAndMark ?? this.copySerialAndMark,
    );
  }
}

/// Универсальный снимок инженерных свойств элемента для копирования / «Кисти свойств» (Match Properties)
class ElementPropertySnapshot {
  final PropertySourceKind kind;
  final String sourceElementId;
  final Valve? valve;
  final Fitting? fitting;
  final PipeSegment? segment;
  final PipeSupport? support;
  final WeldJoint? weld;

  const ElementPropertySnapshot._({
    required this.kind,
    required this.sourceElementId,
    this.valve,
    this.fitting,
    this.segment,
    this.support,
    this.weld,
  });

  factory ElementPropertySnapshot.fromValve(Valve valve) {
    return ElementPropertySnapshot._(
      kind: PropertySourceKind.valve,
      sourceElementId: valve.id,
      valve: valve,
    );
  }

  factory ElementPropertySnapshot.fromFitting(Fitting fitting) {
    return ElementPropertySnapshot._(
      kind: PropertySourceKind.fitting,
      sourceElementId: fitting.id,
      fitting: fitting,
    );
  }

  factory ElementPropertySnapshot.fromSegment(PipeSegment segment) {
    return ElementPropertySnapshot._(
      kind: PropertySourceKind.segment,
      sourceElementId: segment.id,
      segment: segment,
    );
  }

  factory ElementPropertySnapshot.fromSupport(PipeSupport support) {
    return ElementPropertySnapshot._(
      kind: PropertySourceKind.support,
      sourceElementId: support.id,
      support: support,
    );
  }

  factory ElementPropertySnapshot.fromWeld(WeldJoint weld) {
    return ElementPropertySnapshot._(
      kind: PropertySourceKind.weld,
      sourceElementId: weld.id,
      weld: weld,
    );
  }

  /// Краткое описание образца для отображения в UI
  String get summaryLabel {
    switch (kind) {
      case PropertySourceKind.valve:
        final v = valve!;
        return '${v.name} Ду${v.dn}';
      case PropertySourceKind.fitting:
        final f = fitting!;
        return '${f.name ?? "Фитинг"} Ду${f.dn}';
      case PropertySourceKind.segment:
        final s = segment!;
        return 'Труба ${s.shortCallout} (${s.material})';
      case PropertySourceKind.support:
        final sup = support!;
        return 'Опора ${sup.type.displayName}';
      case PropertySourceKind.weld:
        final w = weld!;
        return 'Стык ${w.weldType.shortName} (${w.stamp})';
    }
  }

  /// Проверяет, совместим ли снимок с целевым типом элемента (включая кросс-совместимость по материалу/фланцам)
  bool canApplyTo(PropertySourceKind targetKind) {
    if (kind == targetKind) return true;
    // Кросс-копирование между арматурой, фитингами и трубами (общие свойства: сталь, Ру, ГОСТ фланцев, партия)
    const crossCompatible = {
      PropertySourceKind.valve,
      PropertySourceKind.fitting,
      PropertySourceKind.segment,
    };
    if (crossCompatible.contains(kind) && crossCompatible.contains(targetKind)) {
      return true;
    }
    return false;
  }

  /// Проверяет, принадлежат ли два типа фитингов к одному семейству (например, отводы, тройники, переходы)
  static bool isSameFittingFamily(FittingType a, FittingType b) {
    if (a == b) return true;
    if ((a == FittingType.elbow90 || a == FittingType.elbow45) &&
        (b == FittingType.elbow90 || b == FittingType.elbow45)) {
      return true;
    }
    if ((a == FittingType.tee || a == FittingType.directBranch) &&
        (b == FittingType.tee || b == FittingType.directBranch)) {
      return true;
    }
    if ((a == FittingType.reducerConcentric || a == FittingType.reducerEccentric) &&
        (b == FittingType.reducerConcentric || b == FittingType.reducerEccentric)) {
      return true;
    }
    return false;
  }

  /// Применение свойств к целевой арматуре (`Valve`)
  Valve applyToValve(
    Valve target, {
    PropertyCopyOptions options = const PropertyCopyOptions(),
  }) {
    var result = target;

    if (kind == PropertySourceKind.valve && valve != null) {
      final src = valve!;
      final sameDn = src.dn == target.dn;

      if (options.copyMaterialAndStandard) {
        result = result.copyWith(
          isFlanged: src.isFlanged,
          flangePressurePn: src.flangePressurePn,
          includeCounterFlanges: src.includeCounterFlanges,
          counterFlangeType: src.counterFlangeType,
          counterFlangeMaterial: src.counterFlangeMaterial,
        );
      }

      if (options.copyDimensionsAndType) {
        result = result.copyWith(
          valveType: src.valveType,
          name: src.name,
          customDefinitionId: src.customDefinitionId,
          clearCustomDefinition: src.customDefinitionId == null,
          handleAngleDeg: src.handleAngleDeg,
          lengthMm: sameDn ? src.lengthMm : result.lengthMm,
          counterFlangeLengthMm: sameDn ? src.counterFlangeLengthMm : result.counterFlangeLengthMm,
          clearCounterFlangeLength: sameDn && src.counterFlangeLengthMm == null,
        );
      }

      if (options.copySerialAndMark) {
        result = result.copyWith(
          serialNumber: src.serialNumber,
          clearSerialNumber: src.serialNumber == null,
          mark: src.mark,
          clearMark: src.mark == null,
        );
      }
      return result;
    }

    // Кросс-копирование: из Фитинга (особенно Фланца) в Арматуру
    if (kind == PropertySourceKind.fitting && fitting != null) {
      final srcFit = fitting!;
      if (options.copyMaterialAndStandard) {
        final isStandardFlangeType = srcFit.standard == 'ГОСТ 33259-2015 тип 11' ||
            srcFit.standard == 'ГОСТ 33259-2015 тип 01';
        result = result.copyWith(
          counterFlangeMaterial: srcFit.material,
          flangePressurePn: srcFit.fittingType == FittingType.flange
              ? srcFit.pressurePn
              : result.flangePressurePn,
          counterFlangeType: (srcFit.fittingType == FittingType.flange && isStandardFlangeType && srcFit.standard != null)
              ? srcFit.standard!
              : result.counterFlangeType,
        );
      }
      if (options.copyDimensionsAndType &&
          srcFit.fittingType == FittingType.flange &&
          srcFit.dn == target.dn &&
          srcFit.buildingLengthMm != null) {
        result = result.copyWith(
          counterFlangeLengthMm: srcFit.buildingLengthMm,
        );
      }
      if (options.copySerialAndMark) {
        result = result.copyWith(
          serialNumber: srcFit.serialNumber,
          clearSerialNumber: srcFit.serialNumber == null,
        );
      }
      return result;
    }

    // Кросс-копирование: из Трубы в Арматуру (материал фланцев / партия)
    if (kind == PropertySourceKind.segment && segment != null) {
      final srcSeg = segment!;
      if (options.copyMaterialAndStandard) {
        result = result.copyWith(counterFlangeMaterial: srcSeg.material);
      }
      if (options.copySerialAndMark) {
        result = result.copyWith(
          serialNumber: srcSeg.serialNumber,
          clearSerialNumber: srcSeg.serialNumber == null,
        );
      }
      return result;
    }

    return result;
  }

  /// Применение свойств к целевому фитингу (`Fitting`)
  Fitting applyToFitting(
    Fitting target, {
    PropertyCopyOptions options = const PropertyCopyOptions(),
  }) {
    var result = target;

    if (kind == PropertySourceKind.fitting && fitting != null) {
      final src = fitting!;
      final sameFamily = isSameFittingFamily(src.fittingType, target.fittingType);
      final sameDn = src.dn == target.dn && src.dnSecondary == target.dnSecondary;

      if (options.copyMaterialAndStandard) {
        result = result.copyWith(
          material: src.material,
          weldType: src.weldType,
          pressurePn: src.pressurePn,
          standard: sameFamily ? src.standard : result.standard,
        );
      }

      if (options.copyDimensionsAndType && sameFamily) {
        result = result.copyWith(
          name: src.name,
          definitionId: src.definitionId,
          customWeldCount: src.customWeldCount,
          clearCustomWeldCount: src.customWeldCount == null,
        );

        // 1. Отводы (90° и 45°): перенос коэффициента радиуса (1.0 DN / 1.5 DN) или точного радиуса при том же Ду
        if (target.fittingType == FittingType.elbow90 ||
            target.fittingType == FittingType.elbow45) {
          if (sameDn) {
            result = result.copyWith(
              radiusMm: src.radiusMm,
              customRadiusMm: src.customRadiusMm,
            );
          } else if (src.dn > 0) {
            final factor = src.effectiveRadiusMm / src.dn;
            final scaledRadius = (target.dn * factor).roundToDouble();
            result = result.copyWith(
              radiusMm: scaledRadius,
              customRadiusMm: scaledRadius,
            );
          }
        }

        // 2. Тройники и прямые врезки
        if (target.fittingType == FittingType.tee ||
            target.fittingType == FittingType.directBranch) {
          result = result.copyWith(
            fittingType: src.fittingType,
            cutsMainPipe: src.cutsMainPipe,
            buildingLengthMm: sameDn ? src.buildingLengthMm : result.buildingLengthMm,
            clearBuildingLengthMm: sameDn && src.buildingLengthMm == null,
            branchLengthMm: sameDn ? src.branchLengthMm : result.branchLengthMm,
            clearBranchLengthMm: sameDn && src.branchLengthMm == null,
          );
        }

        // 3. Переходы (концентрические / эксцентрические)
        if (target.fittingType == FittingType.reducerConcentric ||
            target.fittingType == FittingType.reducerEccentric) {
          result = result.copyWith(
            fittingType: src.fittingType,
            rotationAngleDeg: src.rotationAngleDeg,
            buildingLengthMm: sameDn ? src.buildingLengthMm : result.buildingLengthMm,
            clearBuildingLengthMm: sameDn && src.buildingLengthMm == null,
          );
        }

        // 4. Фланцы
        if (target.fittingType == FittingType.flange) {
          result = result.copyWith(
            flangeConnectionType: src.flangeConnectionType,
            isFlangePair: src.isFlangePair,
            isFlipped: src.isFlipped,
            pressurePn: src.pressurePn,
            buildingLengthMm: sameDn ? src.buildingLengthMm : result.buildingLengthMm,
            clearBuildingLengthMm: sameDn && src.buildingLengthMm == null,
          );
        }

        // 5. Заглушки / днища
        if (target.fittingType == FittingType.cap && sameDn) {
          result = result.copyWith(
            buildingLengthMm: src.buildingLengthMm,
            clearBuildingLengthMm: src.buildingLengthMm == null,
          );
        }
      }

      if (options.copySerialAndMark) {
        result = result.copyWith(
          serialNumber: src.serialNumber,
          clearSerialNumber: src.serialNumber == null,
          mark: src.mark,
          clearMark: src.mark == null,
        );
      }

      return result;
    }

    // Кросс-копирование: из Арматуры в Фитинг (особенно Фланец)
    if (kind == PropertySourceKind.valve && valve != null) {
      final srcValve = valve!;
      if (options.copyMaterialAndStandard) {
        result = result.copyWith(
          material: srcValve.effectiveCounterFlangeMaterial,
          pressurePn: target.fittingType == FittingType.flange
              ? srcValve.flangePressurePn
              : result.pressurePn,
          standard: target.fittingType == FittingType.flange
              ? srcValve.counterFlangeType
              : result.standard,
        );
      }
      if (options.copyDimensionsAndType &&
          target.fittingType == FittingType.flange &&
          target.dn == srcValve.dn &&
          srcValve.counterFlangeLengthMm != null) {
        result = result.copyWith(
          buildingLengthMm: srcValve.counterFlangeLengthMm,
        );
      }
      if (options.copySerialAndMark) {
        result = result.copyWith(
          serialNumber: srcValve.serialNumber,
          clearSerialNumber: srcValve.serialNumber == null,
        );
      }
      return result;
    }

    // Кросс-копирование: из Трубы в Фитинг
    if (kind == PropertySourceKind.segment && segment != null) {
      final srcSeg = segment!;
      if (options.copyMaterialAndStandard) {
        result = result.copyWith(material: srcSeg.material);
      }
      if (options.copySerialAndMark) {
        result = result.copyWith(
          serialNumber: srcSeg.serialNumber,
          clearSerialNumber: srcSeg.serialNumber == null,
        );
      }
      return result;
    }

    return result;
  }

  /// Применение свойств к целевому участку трубы (`PipeSegment`)
  PipeSegment applyToSegment(
    PipeSegment target, {
    PropertyCopyOptions options = const PropertyCopyOptions(),
  }) {
    var result = target;

    if (kind == PropertySourceKind.segment && segment != null) {
      final src = segment!;
      if (options.copyMaterialAndStandard) {
        result = result.copyWith(
          systemId: src.systemId,
          material: src.material,
        );
      }
      if (options.copyDimensionsAndType) {
        result = result.copyWith(
          dn: src.dn,
          outerDiameterMm: src.outerDiameterMm,
          wallThicknessMm: src.wallThicknessMm,
          name: src.name,
          clearName: src.name == null,
        );
      }
      if (options.copySerialAndMark) {
        result = result.copyWith(
          serialNumber: src.serialNumber,
          clearSerialNumber: src.serialNumber == null,
        );
      }
      return result;
    }

    // Кросс-копирование материала из Фитинга или Арматуры в Трубу
    if (kind == PropertySourceKind.fitting && fitting != null) {
      if (options.copyMaterialAndStandard) {
        result = result.copyWith(material: fitting!.material);
      }
      if (options.copySerialAndMark) {
        result = result.copyWith(
          serialNumber: fitting!.serialNumber,
          clearSerialNumber: fitting!.serialNumber == null,
        );
      }
      return result;
    }

    if (kind == PropertySourceKind.valve && valve != null) {
      if (options.copyMaterialAndStandard) {
        result = result.copyWith(material: valve!.effectiveCounterFlangeMaterial);
      }
      if (options.copySerialAndMark) {
        result = result.copyWith(
          serialNumber: valve!.serialNumber,
          clearSerialNumber: valve!.serialNumber == null,
        );
      }
      return result;
    }

    return result;
  }

  /// Применение свойств к целевой опоре (`PipeSupport`)
  PipeSupport applyToSupport(
    PipeSupport target, {
    PropertyCopyOptions options = const PropertyCopyOptions(),
  }) {
    if (kind != PropertySourceKind.support || support == null) return target;
    final src = support!;
    var result = target;
    if (options.copyDimensionsAndType) {
      result = result.copyWith(
        type: src.type,
        name: src.name,
      );
    }
    if (options.copySerialAndMark) {
      result = result.copyWith(
        mark: src.mark,
        clearMark: src.mark == null,
      );
    }
    return result;
  }

  /// Применение свойств к целевому сварному стыку (`WeldJoint`)
  WeldJoint applyToWeld(
    WeldJoint target, {
    PropertyCopyOptions options = const PropertyCopyOptions(),
  }) {
    if (kind != PropertySourceKind.weld || weld == null) return target;
    final src = weld!;
    var result = target;
    if (options.copyMaterialAndStandard) {
      result = result.copyWith(
        weldType: src.weldType,
        steelGrade: src.steelGrade,
        electrodeGrade: src.electrodeGrade,
        inspectionMethods: List.of(src.inspectionMethods),
        notes: src.notes,
      );
    }
    if (options.copyDimensionsAndType) {
      result = result.copyWith(
        stamp: src.stamp,
        style: src.style,
        clearStyle: src.style == null,
        tickSizeMm: src.tickSizeMm,
        clearTickSize: src.tickSizeMm == null,
      );
    }
    if (options.copySerialAndMark) {
      result = result.copyWith(date: src.date);
    }
    return result;
  }
}
