import 'dart:math' as math;
import '../models/piping_network.dart';
import '../models/fitting.dart';
import '../enums/fitting_type.dart';
import '../enums/weld_type.dart';

class FittingDetector {
  static void autoDetectAllFittings(PipingNetwork network) {
    for (final nodeId in network.nodes.keys.toList()) {
      autoDetectFittingsForNode(network, nodeId);
    }
  }

  static void autoDetectFittingsForNode(PipingNetwork network, String nodeId) {
    // Если фитинг уже вручную настроен (прямая врезка, фланец), сохраняем его
    final existingFit = network.fittings[nodeId];
    if (existingFit != null &&
        (existingFit.fittingType == FittingType.directBranch ||
            existingFit.fittingType == FittingType.flange)) {
      return;
    }

    final connected = network.getConnectedSegments(nodeId);
    if (connected.length < 2) {
      if (existingFit != null && existingFit.fittingType != FittingType.flange) {
        network.fittings.remove(nodeId);
      }
      return;
    }

    if (connected.length == 2) {
      final s1 = connected[0];
      final s2 = connected[1];
      final nCenter = network.nodes[nodeId]!;
      final n1 = network.nodes[s1.startNodeId == nodeId ? s1.endNodeId : s1.startNodeId]!;
      final n2 = network.nodes[s2.startNodeId == nodeId ? s2.endNodeId : s2.startNodeId]!;

      // Векторы направлений от узла
      final v1x = n1.x - nCenter.x;
      final v1y = n1.y - nCenter.y;
      final v1z = n1.z - nCenter.z;
      final len1 = math.sqrt(v1x * v1x + v1y * v1y + v1z * v1z);

      final v2x = n2.x - nCenter.x;
      final v2y = n2.y - nCenter.y;
      final v2z = n2.z - nCenter.z;
      final len2 = math.sqrt(v2x * v2x + v2y * v2y + v2z * v2z);

      if (len1 > 0 && len2 > 0) {
        final cosAngle = ((v1x * v2x + v1y * v2y + v1z * v2z) / (len1 * len2)).clamp(-1.0, 1.0);
        final angleDeg = math.acos(cosAngle) * 180.0 / math.pi;
        final bendAngleDeg = 180.0 - angleDeg;

        if (bendAngleDeg >= 12.0 && bendAngleDeg <= 168.0) {
          // Это поворот трассы — создаем отвод или сохраняем пользовательский
          final targetType = (bendAngleDeg >= 25.0 && bendAngleDeg < 65.0)
              ? FittingType.elbow45
              : FittingType.elbow90;

          if (existingFit != null &&
              (existingFit.fittingType == targetType || existingFit.customRadiusMm != null)) {
            // Отвод уже существует и настроен — сохраняем его
            if (existingFit.dn != s1.dn) {
              network.fittings[nodeId] = existingFit.copyWith(dn: s1.dn);
            }
            return;
          }

          if (bendAngleDeg >= 65.0 && bendAngleDeg <= 115.0) {
            final def = network.catalog.getDefinition(network.catalog.defaultElbowId);
            final rad = def != null ? def.calculateDeduction(s1.dn) : (s1.dn * 1.5);
            network.fittings[nodeId] = Fitting(
              id: 'fit_$nodeId',
              nodeId: nodeId,
              fittingType: FittingType.elbow90,
              definitionId: def?.id,
              name: def?.name ?? 'Отвод 90° Ду${s1.dn}',
              standard: def?.standard ?? 'ГОСТ 17375-2001',
              material: s1.material,
              weldType: def?.weldType ?? WeldType.c17,
              dn: s1.dn,
              radiusMm: rad,
              customRadiusMm: def?.fixedLengthMm ?? (def?.radiusFactor != null ? def!.radiusFactor! * s1.dn : null),
            );
          } else if (bendAngleDeg >= 25.0 && bendAngleDeg < 65.0) {
            final def = network.catalog.getDefinition('elbow45_gost_17375');
            final rad = def != null ? def.calculateDeduction(s1.dn) : (s1.dn * 0.625);
            network.fittings[nodeId] = Fitting(
              id: 'fit_$nodeId',
              nodeId: nodeId,
              fittingType: FittingType.elbow45,
              definitionId: def?.id,
              name: def?.name ?? 'Отвод 45° Ду${s1.dn}',
              standard: def?.standard ?? 'ГОСТ 17375-2001',
              material: s1.material,
              weldType: def?.weldType ?? WeldType.c17,
              dn: s1.dn,
              radiusMm: rad,
              customRadiusMm: def?.fixedLengthMm ?? (def?.radiusFactor != null ? def!.radiusFactor! * s1.dn : null),
            );
          } else {
            // Другой угол поворота (косой/секторный)
            final def = network.catalog.getDefinition(network.catalog.defaultElbowId);
            final rad = def != null ? def.calculateDeduction(s1.dn) : (s1.dn * 1.5);
            network.fittings[nodeId] = Fitting(
              id: 'fit_$nodeId',
              nodeId: nodeId,
              fittingType: FittingType.elbow90,
              definitionId: def?.id,
              name: 'Отвод ${bendAngleDeg.round()}° Ду${s1.dn}',
              standard: def?.standard ?? 'ГОСТ 17375-2001',
              material: s1.material,
              weldType: def?.weldType ?? WeldType.c17,
              dn: s1.dn,
              radiusMm: rad,
              customRadiusMm: def?.fixedLengthMm ?? (def?.radiusFactor != null ? def!.radiusFactor! * s1.dn : null),
            );
          }
        } else if (s1.dn != s2.dn) {
          // Прямой переход диаметров
          network.fittings[nodeId] = Fitting(
            id: 'fit_$nodeId',
            nodeId: nodeId,
            fittingType: FittingType.reducerConcentric,
            name: 'Переход ${s1.dn}х${s2.dn}',
            standard: 'ГОСТ 17378-2001',
            material: s1.material,
            weldType: WeldType.c17,
            dn: s1.dn,
            dnSecondary: s2.dn,
            radiusMm: s1.dn * 1.5,
          );
        } else {
          // Прямая неразрывная труба без изменения диаметра
          if (existingFit != null && existingFit.fittingType != FittingType.flange) {
            network.fittings.remove(nodeId);
          }
        }
      }
    } else if (connected.length == 3) {
      if (existingFit != null &&
          (existingFit.fittingType == FittingType.tee ||
              existingFit.fittingType == FittingType.directBranch)) {
        return;
      }

      final def = network.catalog.getDefinition(network.catalog.defaultBranchId);
      final isDirect = def?.fittingType == FittingType.directBranch ||
          network.catalog.defaultBranchId == 'direct_branch_u18';

      // Определение проходного и ответвленного диаметров тройника
      final dns = connected.map((s) => s.dn).toList()..sort();
      final mainDn = dns[1];
      final branchDn = dns.first != dns.last ? (dns[0] == dns[1] ? dns[2] : dns[0]) : mainDn;
      final isReducing = branchDn != mainDn;

      if (isDirect) {
        network.fittings[nodeId] = Fitting(
          id: 'fit_$nodeId',
          nodeId: nodeId,
          fittingType: FittingType.directBranch,
          definitionId: def?.id,
          name: def?.name ?? 'Прямая врезка Ду$branchDn в Ду$mainDn',
          standard: def?.standard ?? 'ГОСТ 16037-80 У18',
          material: connected[0].material,
          weldType: WeldType.u18,
          dn: mainDn,
          dnSecondary: branchDn,
          radiusMm: 0.0,
          cutsMainPipe: false,
        );

        final branchSeg = network.identifyBranchSegment(nodeId, connected);
        if (branchSeg != null) {
          final r = branchSeg.startNodeId == nodeId ? 0.0 : 1.0;
          network.ensureWeldExists(branchSeg.id, r, WeldType.u18);
        }
      } else {
        network.fittings[nodeId] = Fitting(
          id: 'fit_$nodeId',
          nodeId: nodeId,
          fittingType: FittingType.tee,
          definitionId: def?.id,
          name: isReducing ? 'Тройник переходной $mainDnх$branchDn' : 'Тройник равнопроходный Ду$mainDn',
          standard: def?.standard ?? 'ГОСТ 17376-2001',
          material: connected[0].material,
          weldType: WeldType.c17,
          dn: mainDn,
          dnSecondary: branchDn,
          radiusMm: mainDn * 1.0,
          cutsMainPipe: true,
        );

        for (final seg in connected) {
          final r = seg.startNodeId == nodeId ? 0.0 : 1.0;
          network.ensureWeldExists(seg.id, r, def?.weldType ?? WeldType.c17);
        }
      }
    } else if (connected.length >= 4) {
      final s = connected[0];
      network.fittings[nodeId] = Fitting(
        id: 'fit_$nodeId',
        nodeId: nodeId,
        fittingType: FittingType.cross,
        name: 'Крестовина Ду${s.dn}',
        standard: 'ГОСТ',
        material: s.material,
        dn: s.dn,
        radiusMm: s.dn * 1.0,
      );
    }
  }
}
