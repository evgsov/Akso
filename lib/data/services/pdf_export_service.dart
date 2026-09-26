import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/math/axonometry_projector.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/models/callout.dart';
import '../../domain/models/drawing_sheet.dart';
import '../../domain/models/drawing_style_config.dart';
import '../../domain/models/node_3d.dart';
import '../../domain/models/piping_network.dart';
import '../../domain/models/title_block_data.dart';
import '../../domain/models/custom_valve_definition.dart';
import '../../domain/services/viewport_transform_service.dart';
import '../../domain/models/vector_scene.dart';
import '../../domain/services/sheet_geometry_builder.dart';
import '../../ui/canvas/painters/callout_painter.dart';

/// Сервис векторной генерации, сохранения и печати чертежей в формате PDF (1:1)
/// по стандартам ГОСТ 21.101-2020 / СПДС.
class PdfExportService {
  /// Генерирует векторный PDF-документ чертежного листа 1:1 со всеми графами штампа,
  /// рамкой 20-5-5-5 мм, техническими требованиями и геометрией трубопроводов.
  static Future<Uint8List> generateSheetPdf({
    required DrawingSheet sheet,
    required PipingNetwork network,
    DrawingStyleConfig styleConfig = const DrawingStyleConfig(),
    ProjectionType projectionType = ProjectionType.gostFrontal45,
    double orbitAzimuth = -math.pi / 4,
    double orbitElevation = math.pi / 6,
    Node3D targetCenter = const Node3D(id: 'center', x: 0, y: 0, z: 0),
    Map<String, CustomValveDefinition>? customValves,
    Map<String, String>? calloutTemplates,
  }) async {
    final pdf = pw.Document(
      title: sheet.name,
      author: sheet.titleBlockData.organization,
    );

    final fontRegular = await _loadFont(isBold: false);
    final fontBold = await _loadFont(isBold: true);

    final widthMm = sheet.format.widthMm;
    final heightMm = sheet.format.heightMm;
    const mm = PdfPageFormat.mm;

    final pageFormat = PdfPageFormat(widthMm * mm, heightMm * mm, marginAll: 0);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          final pdfFontRegular = fontRegular.getFont(context);
          final pdfFontBold = fontBold.getFont(context);

          return pw.Stack(
            children: [
              // 1. Векторные линии видового экрана, выносок, размеров, рамки листа и штампа
              pw.CustomPaint(
                size: PdfPoint(pageFormat.width, pageFormat.height),
                painter: (canvas, size) {
                  final scene = SheetGeometryBuilder.buildScene(
                    sheet: sheet,
                    network: network,
                    projectionType: projectionType,
                    styleConfig: styleConfig,
                    orbitAzimuth: orbitAzimuth,
                    orbitElevation: orbitElevation,
                    targetCenter: targetCenter,
                    customValves: customValves,
                    calloutTemplates: calloutTemplates,
                  );

                  _renderVectorSceneToPdf(
                    canvas: canvas,
                    scene: scene,
                    sheet: sheet,
                    fontRegular: pdfFontRegular,
                    fontBold: pdfFontBold,
                    heightMm: heightMm,
                    mm: mm,
                  );
                },
              ),

              // 2. Текстовые аннотации видового экрана (размерные числа, полки выносок)
              ..._buildViewportAnnotationTexts(
                sheet: sheet,
                network: network,
                projectionType: projectionType,
                orbitAzimuth: orbitAzimuth,
                orbitElevation: orbitElevation,
                targetCenter: targetCenter,
                fontRegular: fontRegular,
                fontBold: fontBold,
                pdfFontRegular: pdfFontRegular,
                pdfFontBold: pdfFontBold,
                calloutTemplates: calloutTemplates,
                heightMm: heightMm,
                mm: mm,
              ),

              // 3. Заголовок схемы в левом верхнем углу (как в исполнительных схемах)
              if (sheet.titleBlockData.drawingTitle.isNotEmpty)
                pw.Positioned(
                  left: (sheet.format.frameLeftMm + 5.0) * mm,
                  top: (sheet.format.frameTopMm + 2.5) * mm,
                  child: pw.Text(
                    sheet.titleBlockData.drawingTitle,
                    style: pw.TextStyle(font: fontBold, fontSize: 9.5),
                  ),
                ),

              // 4. Надпись формата листа под штампом за рамкой
              pw.Positioned(
                right: sheet.format.frameRightMm * mm,
                bottom: (sheet.format.frameBottomMm - 4.0) * mm,
                child: pw.Text(
                  'Формат ${sheet.format.type.name.toUpperCase()}',
                  style: pw.TextStyle(font: fontRegular, fontSize: 7),
                ),
              ),

              // 5. Текстовые поля штампа (Форма 3 по ГОСТ 21.101-2020 / СПДС)
              ..._buildTitleBlockTexts(
                sheet: sheet,
                fontRegular: fontRegular,
                fontBold: fontBold,
                mm: mm,
              ),

              // 6. Блок приложения к акту (настраиваемое положение и границы)
              ..._buildTopRightCornerBlock(
                sheet: sheet,
                fontRegular: fontRegular,
                mm: mm,
              ),

              // 7. Технические требования (ТТ) (настраиваемое положение и границы)
              if (sheet.technicalRequirements != null &&
                  sheet.technicalRequirements!.text.isNotEmpty)
                _buildTechnicalRequirements(
                  sheet: sheet,
                  fontRegular: fontRegular,
                  fontBold: fontBold,
                  mm: mm,
                ),

              // 8. Блок «Условные обозначения»
              if (sheet.legend != null && sheet.legend!.isVisible)
                _buildDrawingLegend(
                  sheet: sheet,
                  fontRegular: fontRegular,
                  fontBold: fontBold,
                  mm: mm,
                ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Отрисовка унифицированной векторной сцены (VectorScene) в PDF canvas
  static void _renderVectorSceneToPdf({
    required PdfGraphics canvas,
    required VectorScene scene,
    required DrawingSheet sheet,
    required PdfFont fontRegular,
    required PdfFont fontBold,
    required double heightMm,
    required double mm,
  }) {
    final vp = sheet.viewport;
    final vpXPt = vp.xMm * mm;
    final vpYPt = (heightMm - vp.yMm - vp.heightMm) * mm;
    final vpWPt = vp.widthMm * mm;
    final vpHPt = vp.heightMm * mm;

    // Рамка видового экрана (тонкая)
    canvas.setStrokeColor(PdfColors.blueGrey300);
    canvas.setLineWidth(0.25 * mm);
    canvas.drawRect(vpXPt, vpYPt, vpWPt, vpHPt);
    canvas.strokePath();

    // Клиппирование области видового экрана для 3D геометрии
    canvas.saveContext();
    canvas.drawRect(vpXPt, vpYPt, vpWPt, vpHPt);
    canvas.clipPath();

    bool isClipped = true;

    for (final item in scene.getOrderedItems()) {
      if (item.layer == VectorSceneLayer.frameAndStamp && isClipped) {
        canvas.restoreContext();
        isClipped = false;
      }

      final prim = item.primitive;
      if (prim is VectorPolyline) {
        _renderPolyline(canvas, prim, heightMm, mm);
      } else if (prim is VectorPath) {
        _renderPath(canvas, prim, heightMm, mm);
      } else if (prim is VectorCircle) {
        _renderCircle(canvas, prim, heightMm, mm);
      } else if (prim is VectorEllipse) {
        _renderEllipse(canvas, prim, heightMm, mm);
      } else if (prim is VectorRect) {
        _renderRect(canvas, prim, heightMm, mm);
      } else if (prim is VectorText) {
        // Тексты размеров и выносок рендерятся как высокоточные виджеты pw.Positioned с автоповоротом
        if (item.layer == VectorSceneLayer.axes || item.layer == VectorSceneLayer.frameAndStamp) {
          _renderText(canvas, prim, fontRegular, fontBold, heightMm, mm);
        }
      }
    }

    if (isClipped) {
      canvas.restoreContext();
    }
  }

  static void _renderPolyline(
    PdfGraphics canvas,
    VectorPolyline polyline,
    double heightMm,
    double mm,
  ) {
    if (polyline.points.length < 2) return;
    canvas.setStrokeColor(PdfColor.fromInt(polyline.colorValue));
    canvas.setLineWidth(polyline.strokeWidthMm * mm);

    if (polyline.smoothJoin) {
      canvas.setLineCap(PdfLineCap.round);
      canvas.setLineJoin(PdfLineJoin.round);
    } else {
      canvas.setLineCap(PdfLineCap.butt);
      canvas.setLineJoin(PdfLineJoin.miter);
    }

    final hasDash = polyline.dashPattern != null && polyline.dashPattern!.isNotEmpty;
    if (hasDash) {
      canvas.setLineDashPattern(
        polyline.dashPattern!.map((d) => d * mm).toList(),
      );
    }

    final first = polyline.points.first;
    canvas.moveTo(first.dx * mm, (heightMm - first.dy) * mm);
    for (int i = 1; i < polyline.points.length; i++) {
      final pt = polyline.points[i];
      canvas.lineTo(pt.dx * mm, (heightMm - pt.dy) * mm);
    }

    canvas.strokePath(close: polyline.isClosed);

    if (hasDash) {
      canvas.setLineDashPattern(const []);
    }
  }

  static void _renderPath(
    PdfGraphics canvas,
    VectorPath path,
    double heightMm,
    double mm,
  ) {
    if (path.commands.isEmpty) return;

    if (path.smoothJoin) {
      canvas.setLineCap(PdfLineCap.round);
      canvas.setLineJoin(PdfLineJoin.round);
    } else {
      canvas.setLineCap(PdfLineCap.butt);
      canvas.setLineJoin(PdfLineJoin.miter);
    }

    for (final cmd in path.commands) {
      if (cmd is VectorPathMoveTo) {
        canvas.moveTo(cmd.point.dx * mm, (heightMm - cmd.point.dy) * mm);
      } else if (cmd is VectorPathLineTo) {
        canvas.lineTo(cmd.point.dx * mm, (heightMm - cmd.point.dy) * mm);
      } else if (cmd is VectorPathCubicTo) {
        canvas.curveTo(
          cmd.control1.dx * mm,
          (heightMm - cmd.control1.dy) * mm,
          cmd.control2.dx * mm,
          (heightMm - cmd.control2.dy) * mm,
          cmd.endPoint.dx * mm,
          (heightMm - cmd.endPoint.dy) * mm,
        );
      } else if (cmd is VectorPathClose) {
        canvas.closePath();
      }
    }

    final hasStroke = path.strokeWidthMm != null && path.strokeColorValue != null;
    final hasFill = path.fillColorValue != null;

    if (hasFill && hasStroke) {
      canvas.setFillColor(PdfColor.fromInt(path.fillColorValue!));
      canvas.setStrokeColor(PdfColor.fromInt(path.strokeColorValue!));
      canvas.setLineWidth(path.strokeWidthMm! * mm);
      canvas.fillAndStrokePath();
    } else if (hasFill) {
      canvas.setFillColor(PdfColor.fromInt(path.fillColorValue!));
      canvas.fillPath();
    } else if (hasStroke) {
      canvas.setStrokeColor(PdfColor.fromInt(path.strokeColorValue!));
      canvas.setLineWidth(path.strokeWidthMm! * mm);
      canvas.strokePath();
    }
  }

  static void _renderCircle(
    PdfGraphics canvas,
    VectorCircle circle,
    double heightMm,
    double mm,
  ) {
    final cxPt = circle.center.dx * mm;
    final cyPt = (heightMm - circle.center.dy) * mm;
    final rPt = circle.radiusMm * mm;

    canvas.drawEllipse(cxPt, cyPt, rPt, rPt);

    if (circle.isFilled && circle.fillColorValue != null) {
      canvas.setFillColor(PdfColor.fromInt(circle.fillColorValue!));
      if (circle.strokeWidthMm > 0 && circle.strokeColorValue != circle.fillColorValue) {
        canvas.setStrokeColor(PdfColor.fromInt(circle.strokeColorValue));
        canvas.setLineWidth(circle.strokeWidthMm * mm);
        canvas.fillAndStrokePath();
      } else {
        canvas.fillPath();
      }
    } else {
      canvas.setStrokeColor(PdfColor.fromInt(circle.strokeColorValue));
      canvas.setLineWidth(circle.strokeWidthMm * mm);
      canvas.strokePath();
    }
  }

  static void _renderEllipse(
    PdfGraphics canvas,
    VectorEllipse ellipse,
    double heightMm,
    double mm,
  ) {
    final cxPt = ellipse.center.dx * mm;
    final cyPt = (heightMm - ellipse.center.dy) * mm;
    final rxPt = ellipse.radiusXMm * mm;
    final ryPt = ellipse.radiusYMm * mm;

    canvas.drawEllipse(cxPt, cyPt, rxPt, ryPt);

    if (ellipse.isFilled && ellipse.fillColorValue != null) {
      canvas.setFillColor(PdfColor.fromInt(ellipse.fillColorValue!));
      if (ellipse.strokeWidthMm > 0 && ellipse.strokeColorValue != ellipse.fillColorValue) {
        canvas.setStrokeColor(PdfColor.fromInt(ellipse.strokeColorValue));
        canvas.setLineWidth(ellipse.strokeWidthMm * mm);
        canvas.fillAndStrokePath();
      } else {
        canvas.fillPath();
      }
    } else {
      canvas.setStrokeColor(PdfColor.fromInt(ellipse.strokeColorValue));
      canvas.setLineWidth(ellipse.strokeWidthMm * mm);
      canvas.strokePath();
    }
  }

  static void _renderRect(
    PdfGraphics canvas,
    VectorRect vRect,
    double heightMm,
    double mm,
  ) {
    final rect = vRect.rect;
    final xPt = rect.left * mm;
    final yPt = (heightMm - rect.bottom) * mm;
    final wPt = rect.width * mm;
    final hPt = rect.height * mm;

    canvas.drawRect(xPt, yPt, wPt, hPt);

    final hasStroke = vRect.strokeWidthMm != null && vRect.strokeColorValue != null;
    final hasFill = vRect.fillColorValue != null;

    if (hasFill && hasStroke) {
      canvas.setFillColor(PdfColor.fromInt(vRect.fillColorValue!));
      canvas.setStrokeColor(PdfColor.fromInt(vRect.strokeColorValue!));
      canvas.setLineWidth(vRect.strokeWidthMm! * mm);
      canvas.fillAndStrokePath();
    } else if (hasFill) {
      canvas.setFillColor(PdfColor.fromInt(vRect.fillColorValue!));
      canvas.fillPath();
    } else if (hasStroke) {
      canvas.setStrokeColor(PdfColor.fromInt(vRect.strokeColorValue!));
      canvas.setLineWidth(vRect.strokeWidthMm! * mm);
      canvas.strokePath();
    }
  }

  static void _renderText(
    PdfGraphics canvas,
    VectorText text,
    PdfFont fontRegular,
    PdfFont fontBold,
    double heightMm,
    double mm,
  ) {
    final font = text.isBold ? fontBold : fontRegular;
    final metrics = font.stringMetrics(text.text);
    final textW = metrics.width * text.fontSizePt;
    final textH = metrics.ascent * text.fontSizePt;

    final xPt = text.position.dx * mm - textW / 2.0;
    final yPt = (heightMm - text.position.dy) * mm - textH / 2.0;

    if (text.maskFillColorValue != null) {
      final pad = (text.maskPaddingMm ?? 0.5) * mm;
      canvas.setFillColor(PdfColor.fromInt(text.maskFillColorValue!));
      canvas.drawRect(xPt - pad, yPt - pad, textW + pad * 2, textH + pad * 2);
      canvas.fillPath();
    }

    canvas.setFillColor(PdfColor.fromInt(text.colorValue));
    canvas.drawString(font, text.fontSizePt, text.text, xPt, yPt);
  }

  /// Генерация текстовых аннотаций видового экрана (размерные числа, тексты выносок)
  static List<pw.Widget> _buildViewportAnnotationTexts({
    required DrawingSheet sheet,
    required PipingNetwork network,
    required ProjectionType projectionType,
    required double orbitAzimuth,
    required double orbitElevation,
    required Node3D targetCenter,
    required pw.Font fontRegular,
    required pw.Font fontBold,
    required PdfFont pdfFontRegular,
    required PdfFont pdfFontBold,
    Map<String, String>? calloutTemplates,
    required double heightMm,
    required double mm,
  }) {
    final vp = sheet.viewport;
    final templates = calloutTemplates ?? defaultCalloutTemplates;
    final projector = AxonometryProjector(
      projectionType: projectionType,
      orbitAzimuth: orbitAzimuth,
      orbitElevation: orbitElevation,
      targetCenter: targetCenter,
    );
    final widgets = <pw.Widget>[];

    // Размеры (размерные числа над размерной линией)
    for (final dim in network.dimensions.values) {
      final raw1 = projector.projectRaw(
        dim.startPoint.x,
        dim.startPoint.y,
        dim.startPoint.z,
      );
      final raw2 = projector.projectRaw(
        dim.endPoint.x,
        dim.endPoint.y,
        dim.endPoint.z,
      );
      final p1Mm = ViewportTransformService.model2dToSheetMm(raw1, vp);
      final p2Mm = ViewportTransformService.model2dToSheetMm(raw2, vp);

      final delta = p2Mm - p1Mm;
      final dist2d = delta.distance;
      if (dist2d < 1.0) continue;

      final u = delta / dist2d;
      final n = Offset(-u.dy, u.dx);
      final offsetDist = (dim.offsetDistance == 0.0
          ? 10.0
          : dim.offsetDistance * vp.viewScale);
      final offsetVec = n * offsetDist;

      final midMm = (p1Mm + p2Mm) / 2.0 + offsetVec;
      final textPosMm = midMm + n * (offsetDist >= 0 ? 2.5 : -2.5);

      // Проверяем попадание в рамку видового экрана
      if (textPosMm.dx < vp.xMm ||
          textPosMm.dx > vp.xMm + vp.widthMm ||
          textPosMm.dy < vp.yMm ||
          textPosMm.dy > vp.yMm + vp.heightMm) {
        continue;
      }

      // Угол направления размерной линии (ГОСТ 2.307 — текст параллелен линии)
      // Используем дельту в координатах листа (Y инвертирован для PDF)
      var angle = math.atan2(-(p2Mm.dy - p1Mm.dy), p2Mm.dx - p1Mm.dx);
      // Нормализация: текст не должен быть перевёрнут
      if (angle > math.pi / 2) angle -= math.pi;
      if (angle < -math.pi / 2) angle += math.pi;

      // Ширина текста для центрирования
      final dimTextMetrics = pdfFontRegular.stringMetrics(dim.displayText);
      final textWidthMm = dimTextMetrics.width * 6.5 / mm;

      widgets.add(
        pw.Positioned(
          left: (textPosMm.dx - textWidthMm / 2.0 - 1.5) * mm,
          top: (textPosMm.dy - 3.0) * mm,
          child: pw.Transform.rotate(
            angle: angle,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 1.5,
                vertical: 0.5,
              ),
              color: PdfColors.white,
              child: pw.Text(
                dim.displayText,
                style: pw.TextStyle(font: fontRegular, fontSize: 6.5),
              ),
            ),
          ),
        ),
      );
    }

    // Выноски (текст на полке)
    for (final callout in network.callouts.values) {
      if (!sheet.isCalloutVisible(callout)) continue;

      final anchor3D = CalloutPainter.getTarget3DPoint(network, callout);
      if (anchor3D == null) continue;

      final anchorRaw = projector.projectRaw(
        anchor3D.x,
        anchor3D.y,
        anchor3D.z,
      );
      final anchorMm = ViewportTransformService.model2dToSheetMm(anchorRaw, vp);

      final effOffsetX = callout.getEffectiveOffsetX(sheet.id);
      final effOffsetY = callout.getEffectiveOffsetY(sheet.id);

      final isRight = callout.shelfDirection == ShelfDirection.right
          ? true
          : (callout.shelfDirection == ShelfDirection.left
                ? false
                : effOffsetX >= 0);

      // Корректный пересчёт экранного смещения на миллиметры листа
      const offsetScale = 0.35;
      final leaderEndMm =
          anchorMm +
          Offset(
            effOffsetX * offsetScale,
            effOffsetY * offsetScale,
          );

      if (leaderEndMm.dx < vp.xMm - 20 ||
          leaderEndMm.dx > vp.xMm + vp.widthMm + 20 ||
          leaderEndMm.dy < vp.yMm - 20 ||
          leaderEndMm.dy > vp.yMm + vp.heightMm + 20) {
        continue;
      }

      final topText = network.generateCalloutText(callout, templates);
      final bottomText = network.generateCalloutBottomText(callout, templates);

      final fontSizePt = callout.textHeight * 2.83465;
      final bottomFontSizePt = callout.textHeight * 0.85 * 2.83465;

      final topMetrics = pdfFontRegular.stringMetrics(topText);
      final topTextWidthMm = topMetrics.width * fontSizePt / mm;

      final textX = isRight
          ? leaderEndMm.dx + 1.0
          : leaderEndMm.dx - topTextWidthMm - 2.0;

      double shelfDy = leaderEndMm.dy;
      if (callout.targetType == CalloutTargetType.node ||
          callout.elevationStyle != null) {
        if (!callout.arrowOnNode) {
          final styleName = templates['elevation_style'];
          final defaultStyle = ElevationMarkStyleExt.fromString(
            styleName,
            fallback: ElevationMarkStyle.gostOutline,
          );
          final effectiveStyle = callout.elevationStyle ?? defaultStyle;

          if (effectiveStyle == ElevationMarkStyle.compactFlag) {
            shelfDy -= (callout.textHeight * 1.1);
          } else {
            shelfDy -= (callout.textHeight * 1.3);
          }
        }
      }

      final textY = shelfDy - (callout.textHeight * 1.05);
      final bottomTextY = shelfDy + 0.5; // Верхняя строка (над полкой)
      widgets.add(
        pw.Positioned(
          left: textX * mm,
          top: textY * mm,
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 1.0),
            color: PdfColors.white,
            child: pw.Text(
              topText,
              style: pw.TextStyle(font: fontRegular, fontSize: fontSizePt),
            ),
          ),
        ),
      );

      // Нижняя строка (под полкой)
      if (bottomText != null && bottomText.trim().isNotEmpty) {
        widgets.add(
          pw.Positioned(
            left: textX * mm,
            top: bottomTextY * mm,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 1.0),
              color: PdfColors.white,
              child: pw.Text(
                bottomText,
                style: pw.TextStyle(font: fontRegular, fontSize: bottomFontSizePt),
              ),
            ),
          ),
        );
      }
    }

    // Подписи штуцеров оборудования
    for (final eq in network.equipments.values) {
      final rad = eq.rotationAngleDeg * math.pi / 180.0;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);

      for (final noz in eq.nozzles) {
        final node = network.nodes[noz.id];
        final double wx, wy, wz;
        if (node != null) {
          wx = node.x;
          wy = node.y;
          wz = node.z;
        } else {
          wx = eq.x + noz.localX * cosA - noz.localY * sinA;
          wy = eq.y + noz.localX * sinA + noz.localY * cosA;
          wz = eq.z + noz.localZ;
        }

        final effDir = network.getNozzleEffectiveDirection(noz);
        final spudLenMm = network.getNozzleEffectiveSpudLength(
          noz,
          defaultSpudMm: 120.0,
        );

        final fx = wx + effDir.x * spudLenMm;
        final fy = wy + effDir.y * spudLenMm;
        final fz = wz + effDir.z * spudLenMm;

        final rFlange = projector.projectRaw(fx, fy, fz);
        final pFlangeMm = ViewportTransformService.model2dToSheetMm(
          rFlange,
          vp,
        );

        // Экранное смещение (8, -12) переводим в миллиметры (примерно 2мм вправо, 3мм вверх)
        final textX = pFlangeMm.dx + 2.0;
        final textY = pFlangeMm.dy - 3.0;

        final labelText = noz.name.isNotEmpty
            ? '${noz.name} Ду${noz.dn}'
            : 'Ду${noz.dn}';

        widgets.add(
          pw.Positioned(
            left: textX * mm,
            top: textY * mm,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 1.0,
                vertical: 0.5,
              ),
              color: PdfColors.white,
              child: pw.Text(
                labelText,
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 6.5,
                  color: const PdfColor.fromInt(0xFF006064),
                ),
              ),
            ),
          ),
        );
      }

      if (eq.name.isNotEmpty) {
        final topCenterR = projector.projectRaw(eq.x, eq.y, eq.z + eq.height);
        final pTopMm = ViewportTransformService.model2dToSheetMm(
          topCenterR,
          vp,
        );

        // Смещение вверх (около 4 мм на листе)
        final textY = pTopMm.dy - 4.0;

        final eqMetrics = pdfFontBold.stringMetrics(eq.name);
        final eqWidthMm = eqMetrics.width * 8.0 / mm;

        widgets.add(
          pw.Positioned(
            left: (pTopMm.dx - eqWidthMm / 2.0 - 2.0) * mm,
            top: (textY - 1.0) * mm,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 2.0,
                vertical: 1.0,
              ),
              color: PdfColors.white,
              child: pw.Text(
                eq.name,
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 8.0,
                  color: const PdfColor.fromInt(0xFF0D47A1),
                ),
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  /// Генерация текстовых виджетов для граф штампа по ГОСТ 21.101-2020 / СПДС (Форма 3)
  static List<pw.Widget> _buildTitleBlockTexts({
    required DrawingSheet sheet,
    required pw.Font fontRegular,
    required pw.Font fontBold,
    required double mm,
  }) {
    final widthMm = sheet.format.widthMm;
    final heightMm = sheet.format.heightMm;
    final tb = sheet.titleBlockData;

    final stampLeft = (widthMm - sheet.format.frameRightMm - 185.0) * mm;
    final stampTop = (heightMm - sheet.format.frameBottomMm - 55.0) * mm;

    final widgets = <pw.Widget>[];

    // --- ЛЕВЫЙ БЛОК (0..65 мм) ---
    // Таблица изменений (Y = 0..25 мм):
    // Шапка таблицы изменений: строка 5 (Y = 20..25 мм)
    final revHeaderTop = stampTop + 20.0 * mm;

    widgets.add(
      pw.Positioned(
        left: stampLeft,
        top: revHeaderTop,
        child: pw.Container(
          width: 10.0 * mm,
          height: 5.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'Изм.',
            style: pw.TextStyle(font: fontRegular, fontSize: 5),
          ),
        ),
      ),
    );
    widgets.add(
      pw.Positioned(
        left: stampLeft + 10.0 * mm,
        top: revHeaderTop,
        child: pw.Container(
          width: 10.0 * mm,
          height: 5.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'Кол. уч.',
            style: pw.TextStyle(font: fontRegular, fontSize: 5),
          ),
        ),
      ),
    );
    widgets.add(
      pw.Positioned(
        left: stampLeft + 20.0 * mm,
        top: revHeaderTop,
        child: pw.Container(
          width: 10.0 * mm,
          height: 5.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'Лист',
            style: pw.TextStyle(font: fontRegular, fontSize: 5),
          ),
        ),
      ),
    );
    widgets.add(
      pw.Positioned(
        left: stampLeft + 30.0 * mm,
        top: revHeaderTop,
        child: pw.Container(
          width: 10.0 * mm,
          height: 5.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            '№ док.',
            style: pw.TextStyle(font: fontRegular, fontSize: 5),
          ),
        ),
      ),
    );
    widgets.add(
      pw.Positioned(
        left: stampLeft + 40.0 * mm,
        top: revHeaderTop,
        child: pw.Container(
          width: 15.0 * mm,
          height: 5.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'Подп.',
            style: pw.TextStyle(font: fontRegular, fontSize: 5),
          ),
        ),
      ),
    );
    widgets.add(
      pw.Positioned(
        left: stampLeft + 55.0 * mm,
        top: revHeaderTop,
        child: pw.Container(
          width: 10.0 * mm,
          height: 5.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'Дата',
            style: pw.TextStyle(font: fontRegular, fontSize: 5),
          ),
        ),
      ),
    );

    // Отрисовка записей изменений над шапкой (снизу вверх: строки 4, 3, 2, 1)
    for (int r = 0; r < tb.revisions.length && r < 4; r++) {
      final rev = tb.revisions[r];
      final revTop = stampTop + ((3 - r) * 5.0) * mm;
      widgets.add(
        pw.Positioned(
          left: stampLeft,
          top: revTop,
          child: pw.Container(
            width: 10.0 * mm,
            height: 5.0 * mm,
            alignment: pw.Alignment.center,
            child: pw.Text(
              rev.changeIndex,
              style: pw.TextStyle(font: fontRegular, fontSize: 5),
            ),
          ),
        ),
      );
      widgets.add(
        pw.Positioned(
          left: stampLeft + 10.0 * mm,
          top: revTop,
          child: pw.Container(
            width: 10.0 * mm,
            height: 5.0 * mm,
            alignment: pw.Alignment.center,
            child: pw.Text(
              rev.changeCount,
              style: pw.TextStyle(font: fontRegular, fontSize: 5),
            ),
          ),
        ),
      );
      widgets.add(
        pw.Positioned(
          left: stampLeft + 20.0 * mm,
          top: revTop,
          child: pw.Container(
            width: 10.0 * mm,
            height: 5.0 * mm,
            alignment: pw.Alignment.center,
            child: pw.Text(
              rev.sheetNum,
              style: pw.TextStyle(font: fontRegular, fontSize: 5),
            ),
          ),
        ),
      );
      widgets.add(
        pw.Positioned(
          left: stampLeft + 30.0 * mm,
          top: revTop,
          child: pw.Container(
            width: 10.0 * mm,
            height: 5.0 * mm,
            alignment: pw.Alignment.center,
            child: pw.Text(
              rev.docNum,
              style: pw.TextStyle(font: fontRegular, fontSize: 5),
            ),
          ),
        ),
      );
      widgets.add(
        pw.Positioned(
          left: stampLeft + 40.0 * mm,
          top: revTop,
          child: pw.Container(
            width: 15.0 * mm,
            height: 5.0 * mm,
            alignment: pw.Alignment.center,
            child: pw.Text(
              rev.signature,
              style: pw.TextStyle(font: fontRegular, fontSize: 5),
            ),
          ),
        ),
      );
      widgets.add(
        pw.Positioned(
          left: stampLeft + 55.0 * mm,
          top: revTop,
          child: pw.Container(
            width: 10.0 * mm,
            height: 5.0 * mm,
            alignment: pw.Alignment.center,
            child: pw.Text(
              rev.date,
              style: pw.TextStyle(font: fontRegular, fontSize: 5),
            ),
          ),
        ),
      );
    }

    // Строки согласований: Графы 10..13 (Y = 25..55 мм: 6 строк по 5 мм)
    final approvals = tb.approvals.isNotEmpty
        ? tb.approvals
        : const [
            TitleBlockApproval(role: 'Геодезист', name: ''),
            TitleBlockApproval(role: 'Исп. директор', name: ''),
            TitleBlockApproval(role: 'Разраб.', name: ''),
            TitleBlockApproval(role: 'Пров.', name: ''),
            TitleBlockApproval(role: 'ГИП', name: ''),
          ];

    for (int i = 0; i < approvals.length && i < 6; i++) {
      final app = approvals[i];
      final rowTop = stampTop + (25.0 + i * 5.0) * mm + (1.2 * mm);

      // Должность (20 мм)
      if (app.role.isNotEmpty) {
        widgets.add(
          pw.Positioned(
            left: stampLeft + 1.5 * mm,
            top: rowTop,
            child: pw.Text(
              app.role,
              style: pw.TextStyle(font: fontRegular, fontSize: 6),
            ),
          ),
        );
      }

      // Фамилия (20 мм)
      if (app.name.isNotEmpty) {
        widgets.add(
          pw.Positioned(
            left: stampLeft + 21.0 * mm,
            top: rowTop,
            child: pw.Text(
              app.name,
              style: pw.TextStyle(font: fontRegular, fontSize: 6.5),
            ),
          ),
        );
      }

      // Дата (10 мм)
      if (app.date.isNotEmpty) {
        widgets.add(
          pw.Positioned(
            left: stampLeft + 56.0 * mm,
            top: rowTop,
            child: pw.Text(
              app.date,
              style: pw.TextStyle(font: fontRegular, fontSize: 5.5),
            ),
          ),
        );
      }
    }

    // --- ПРАВЫЙ БЛОК (65..185 мм, ширина 120 мм) ---
    final xCenter = stampLeft + 65.0 * mm;
    final xRight = stampLeft + 135.0 * mm;

    // Строка 1 (0..10 мм, высота 10 мм): Графа 4: Обозначение документа / шифр проекта (120 мм ширина)
    if (tb.documentCode.isNotEmpty) {
      widgets.add(
        pw.Positioned(
          left: xCenter,
          top: stampTop,
          child: pw.Container(
            width: 120.0 * mm,
            height: 10.0 * mm,
            alignment: pw.Alignment.center,
            child: pw.Text(
              tb.documentCode,
              style: pw.TextStyle(font: fontBold, fontSize: 11),
            ),
          ),
        ),
      );
    }

    // Строка 2 (10..25 мм, высота 15 мм): Графа 1: Наименование объекта строительства (120 мм ширина)
    if (tb.projectName.isNotEmpty) {
      widgets.add(
        pw.Positioned(
          left: xCenter + 2.0 * mm,
          top: stampTop + 10.0 * mm,
          child: pw.Container(
            width: 116.0 * mm,
            height: 15.0 * mm,
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              tb.projectName,
              style: pw.TextStyle(font: fontRegular, fontSize: 7.5),
              maxLines: 2,
            ),
          ),
        ),
      );
    }

    // Строка 3 (25..40 мм, высота 15 мм):
    // Слева (65..135 мм, 70 мм): Графа 2: Наименование здания / сооружения
    if (tb.buildingName.isNotEmpty) {
      widgets.add(
        pw.Positioned(
          left: xCenter + 2.0 * mm,
          top: stampTop + 25.0 * mm,
          child: pw.Container(
            width: 66.0 * mm,
            height: 15.0 * mm,
            alignment: pw.Alignment.center,
            child: pw.Text(
              tb.buildingName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: fontRegular, fontSize: 7.5),
              maxLines: 2,
            ),
          ),
        ),
      );
    }

    // Справа (135..185 мм, 50 мм): Стадия | Лист | Листов (Y = 25..40 мм)
    // Шапка (25..30 мм: высота 5 мм)
    widgets.add(
      pw.Positioned(
        left: xRight,
        top: stampTop + 25.0 * mm,
        child: pw.Container(
          width: 15.0 * mm,
          height: 5.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'Стадия',
            style: pw.TextStyle(font: fontRegular, fontSize: 5),
          ),
        ),
      ),
    );
    widgets.add(
      pw.Positioned(
        left: xRight + 15.0 * mm,
        top: stampTop + 25.0 * mm,
        child: pw.Container(
          width: 15.0 * mm,
          height: 5.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'Лист',
            style: pw.TextStyle(font: fontRegular, fontSize: 5),
          ),
        ),
      ),
    );
    widgets.add(
      pw.Positioned(
        left: xRight + 30.0 * mm,
        top: stampTop + 25.0 * mm,
        child: pw.Container(
          width: 20.0 * mm,
          height: 5.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'Листов',
            style: pw.TextStyle(font: fontRegular, fontSize: 5),
          ),
        ),
      ),
    );

    // Значения (30..40 мм: высота 10 мм)
    widgets.add(
      pw.Positioned(
        left: xRight,
        top: stampTop + 30.0 * mm,
        child: pw.Container(
          width: 15.0 * mm,
          height: 10.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            tb.stage,
            style: pw.TextStyle(font: fontBold, fontSize: 8),
          ),
        ),
      ),
    );
    widgets.add(
      pw.Positioned(
        left: xRight + 15.0 * mm,
        top: stampTop + 30.0 * mm,
        child: pw.Container(
          width: 15.0 * mm,
          height: 10.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            tb.sheetNumber.toString(),
            style: pw.TextStyle(font: fontBold, fontSize: 8),
          ),
        ),
      ),
    );
    widgets.add(
      pw.Positioned(
        left: xRight + 30.0 * mm,
        top: stampTop + 30.0 * mm,
        child: pw.Container(
          width: 20.0 * mm,
          height: 10.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            tb.totalSheets.toString(),
            style: pw.TextStyle(font: fontBold, fontSize: 8),
          ),
        ),
      ),
    );

    // Строка 4 (40..55 мм, высота 15 мм):
    // Слева (65..135 мм, 70 мм): Графа 3: Наименование схемы / чертежа
    if (tb.drawingTitle.isNotEmpty) {
      widgets.add(
        pw.Positioned(
          left: xCenter + 2.0 * mm,
          top: stampTop + 40.0 * mm,
          child: pw.Container(
            width: 66.0 * mm,
            height: 15.0 * mm,
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              tb.drawingTitle,
              style: pw.TextStyle(font: fontBold, fontSize: 8.5),
              maxLines: 2,
            ),
          ),
        ),
      );
    }

    // Справа (135..185 мм, 50 мм): Графа 9: Организация
    if (tb.organization.isNotEmpty) {
      widgets.add(
        pw.Positioned(
          left: xRight + 1.0 * mm,
          top: stampTop + 40.0 * mm,
          child: pw.Container(
            width: 48.0 * mm,
            height: 15.0 * mm,
            alignment: pw.Alignment.center,
            child: pw.Text(
              tb.organization,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: fontBold, fontSize: 8),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  /// Виджет правого верхнего угла (Приложение к акту)
  static List<pw.Widget> _buildTopRightCornerBlock({
    required DrawingSheet sheet,
    required pw.Font fontRegular,
    required double mm,
  }) {
    final tr = sheet.titleBlockData.topRightCorner;
    final text = tr.formattedText;
    if (text.isEmpty || tr.mode == TopRightCornerMode.none) return const [];

    final widthMm = sheet.format.widthMm;
    final frameRightMm = widthMm - sheet.format.frameRightMm;

    final blockW = tr.widthMm;
    final blockH = tr.heightMm;
    final blockX = tr.xMm ?? (frameRightMm - blockW);
    final blockY = tr.yMm ?? sheet.format.frameTopMm;

    return [
      pw.Positioned(
        left: blockX * mm,
        top: blockY * mm,
        child: pw.Container(
          width: blockW * mm,
          height: blockH * mm,
          padding: const pw.EdgeInsets.all(2.0),
          decoration: tr.hasBorder
              ? pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 0.5),
                  color: PdfColors.white,
                )
              : null,
          alignment: pw.Alignment.topRight,
          child: pw.Text(
            text,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              font: fontRegular,
              fontSize: 7,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ),
      ),
    ];
  }

  /// Виджет технических требований (ТТ) / примечаний
  static pw.Widget _buildTechnicalRequirements({
    required DrawingSheet sheet,
    required pw.Font fontRegular,
    required pw.Font fontBold,
    required double mm,
  }) {
    final tt = sheet.technicalRequirements!;
    final blockW = tt.widthMm;
    final blockH = tt.heightMm;
    final blockX = tt.xMm;
    final blockY = tt.yMm;

    return pw.Positioned(
      left: blockX * mm,
      top: blockY * mm,
      child: pw.Container(
        width: blockW * mm,
        height: blockH * mm,
        padding: const pw.EdgeInsets.all(3.0),
        decoration: tt.hasBorder
            ? pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 0.5),
                color: PdfColors.white,
              )
            : const pw.BoxDecoration(color: PdfColors.white),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (tt.title.isNotEmpty) ...[
              pw.Text(
                tt.title,
                style: pw.TextStyle(font: fontBold, fontSize: 7.5),
              ),
              pw.SizedBox(height: 1.5 * mm),
            ],
            pw.Expanded(
              child: pw.Text(
                tt.text,
                style: pw.TextStyle(font: fontRegular, fontSize: 6.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Виджет блока «Условные обозначения» (Легенда)
  static pw.Widget _buildDrawingLegend({
    required DrawingSheet sheet,
    required pw.Font fontRegular,
    required pw.Font fontBold,
    required double mm,
  }) {
    final leg = sheet.legend!;

    return pw.Positioned(
      left: leg.xMm * mm,
      top: leg.yMm * mm,
      child: pw.Container(
        width: leg.widthMm * mm,
        height: leg.heightMm * mm,
        padding: const pw.EdgeInsets.all(3.0),
        decoration: leg.hasBorder
            ? pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 0.5),
                color: PdfColors.white,
              )
            : const pw.BoxDecoration(color: PdfColors.white),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              leg.title,
              style: pw.TextStyle(font: fontBold, fontSize: 7.5),
            ),
            pw.SizedBox(height: 1.5 * mm),
            pw.Expanded(
              child: pw.ListView.builder(
                itemCount: leg.items.length,
                itemBuilder: (ctx, i) {
                  final item = leg.items[i];
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.0),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(
                          width: 14.0 * mm,
                          height: 3.5 * mm,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(
                              color: PdfColors.grey500,
                              width: 0.5,
                            ),
                          ),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            item.subLabel ?? item.label,
                            style: pw.TextStyle(font: fontRegular, fontSize: 5),
                          ),
                        ),
                        pw.SizedBox(width: 2.0 * mm),
                        pw.Expanded(
                          child: pw.Text(
                            item.label,
                            style: pw.TextStyle(font: fontRegular, fontSize: 6),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Загрузка TTF шрифта с поддержкой кириллицы (Roboto)
  static Future<pw.Font> _loadFont({bool isBold = false}) async {
    final fileName = isBold ? 'Roboto-Bold.ttf' : 'Roboto-Regular.ttf';

    // 1. Попытка чтения локального файла в assets/fonts (для Desktop и Unit тестов)
    try {
      final file = File('assets/fonts/$fileName');
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}

    // 2. Попытка загрузки через rootBundle (для бандла приложения)
    try {
      final data = await rootBundle.load('assets/fonts/$fileName');
      return pw.Font.ttf(data);
    } catch (_) {}

    // 3. Fallback: Google Fonts онлайн или Helvetica
    try {
      return isBold
          ? await PdfGoogleFonts.robotoBold()
          : await PdfGoogleFonts.robotoRegular();
    } catch (_) {
      return isBold ? pw.Font.helveticaBold() : pw.Font.helvetica();
    }
  }

  /// Сохранение сгенерированного PDF файла через нативный диалог (FilePicker / Share)
  static Future<bool> savePdfFile({
    required Uint8List bytes,
    required String suggestedFileName,
  }) async {
    String name = suggestedFileName.trim();
    if (!name.toLowerCase().endsWith('.pdf')) {
      name = '$name.pdf';
    }

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Сохранить чертеж в формате PDF',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );

      if (uri == null) return false;

      String targetPath = uri.scheme == 'file'
          ? uri.toFilePath()
          : (uri.path.isNotEmpty ? uri.path : uri.toString());
      if (!targetPath.toLowerCase().endsWith('.pdf')) {
        targetPath = '$targetPath.pdf';
      }

      final file = File(targetPath);
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } else {
      // Mobile / Web шеринг
      return await Printing.sharePdf(bytes: bytes, filename: name);
    }
  }

  /// Отправка листа на печать в системный диалог принтера
  static Future<bool> printSheet({
    required Uint8List bytes,
    String jobName = 'Чертеж_АКСО',
  }) async {
    return await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: jobName,
    );
  }
}
