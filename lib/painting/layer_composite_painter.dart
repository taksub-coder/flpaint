import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/drawing.dart';

/// Upper bound for "paint everything" when merging layer timelines.
const int kLayerCompositeMaxSequence = 2000000000;

/// Shared layer compositing for on-screen paint, export, and vector lasso replay.
class LayerCompositePainter {
  LayerCompositePainter._();

  static ui.Image? _baseForLayer(
    DrawingLayer layer, {
    required ui.Image? layerABaseImage,
    required ui.Image? layerBBaseImage,
    required ui.Image? layerCBaseImage,
  }) {
    switch (layer) {
      case DrawingLayer.layerA:
        return layerABaseImage;
      case DrawingLayer.layerB:
        return layerBBaseImage;
      case DrawingLayer.layerC:
        return layerCBaseImage;
    }
  }

  static RasterSamplingMode _baseSamplingForLayer(
    DrawingLayer layer, {
    required RasterSamplingMode layerABaseSampling,
    required RasterSamplingMode layerBBaseSampling,
    required RasterSamplingMode layerCBaseSampling,
  }) {
    switch (layer) {
      case DrawingLayer.layerA:
        return layerABaseSampling;
      case DrawingLayer.layerB:
        return layerBBaseSampling;
      case DrawingLayer.layerC:
        return layerCBaseSampling;
    }
  }

  static ui.ImageShader? _toneShaderForTool(
    ToolType tool, {
    required ui.ImageShader? tone30Shader,
    required ui.ImageShader? tone60Shader,
    required ui.ImageShader? tone80Shader,
  }) {
    switch (tool) {
      case ToolType.tone30:
        return tone30Shader;
      case ToolType.tone60:
        return tone60Shader;
      case ToolType.tone80:
        return tone80Shader;
      default:
        return null;
    }
  }

  /// Paints one layer's base bitmap + interleaved lines/placements up to [maxSequence].
  static void paintSourceContentsUpTo(
    Canvas canvas,
    DrawingLayer layer,
    int maxSequence, {
    required List<DrawnLine> allLines,
    required List<LayerPlacement> allPlacements,
    required ui.Image? layerABaseImage,
    required ui.Image? layerBBaseImage,
    required ui.Image? layerCBaseImage,
    required RasterSamplingMode layerABaseSampling,
    required RasterSamplingMode layerBBaseSampling,
    required RasterSamplingMode layerCBaseSampling,
    required ui.ImageShader? tone30Shader,
    required ui.ImageShader? tone60Shader,
    required ui.ImageShader? tone80Shader,
    int recursionDepth = 0,
  }) {
    if (recursionDepth > 48) {
      return;
    }

    final ui.Image? layerBaseImage = _baseForLayer(
      layer,
      layerABaseImage: layerABaseImage,
      layerBBaseImage: layerBBaseImage,
      layerCBaseImage: layerCBaseImage,
    );
    if (layerBaseImage != null) {
      final RasterSamplingMode baseSampling = _baseSamplingForLayer(
        layer,
        layerABaseSampling: layerABaseSampling,
        layerBBaseSampling: layerBBaseSampling,
        layerCBaseSampling: layerCBaseSampling,
      );
      canvas.drawImage(
        layerBaseImage,
        Offset.zero,
        Paint()
          ..isAntiAlias = false
          ..filterQuality = baseSampling == RasterSamplingMode.smooth
              ? FilterQuality.medium
              : FilterQuality.none,
      );
    }

    final List<DrawnLine> layerLines = allLines
        .where((DrawnLine line) => line.layer == layer)
        .toList(growable: false);
    final List<LayerPlacement> layerPlacements = allPlacements
        .where((LayerPlacement placement) =>
            placement.sourceLayer == layer || placement.targetLayer == layer)
        .toList(growable: false);

    int lineIndex = 0;
    int placementIndex = 0;

    while (lineIndex < layerLines.length ||
        placementIndex < layerPlacements.length) {
      while (lineIndex < layerLines.length &&
          layerLines[lineIndex].sequence > maxSequence) {
        lineIndex++;
      }
      while (placementIndex < layerPlacements.length &&
          layerPlacements[placementIndex].sequence > maxSequence) {
        placementIndex++;
      }

      final DrawnLine? nextLine =
          lineIndex < layerLines.length ? layerLines[lineIndex] : null;
      final LayerPlacement? nextPlacement =
          placementIndex < layerPlacements.length
              ? layerPlacements[placementIndex]
              : null;

      if (nextLine == null && nextPlacement == null) {
        break;
      }

      if (nextPlacement == null ||
          (nextLine != null && nextLine.sequence < nextPlacement.sequence)) {
        _paintLine(
          canvas,
          nextLine!,
          tone30Shader: tone30Shader,
          tone60Shader: tone60Shader,
          tone80Shader: tone80Shader,
        );
        lineIndex++;
        continue;
      }

      if (nextPlacement.sourceLayer == layer &&
          nextPlacement.sourceMaskPath != null) {
        canvas.drawPath(
          nextPlacement.sourceMaskPath!,
          Paint()
            ..blendMode = BlendMode.clear
            ..isAntiAlias = false,
        );
      }
      if (nextPlacement.targetLayer == layer) {
        paintPlacement(
          canvas,
          nextPlacement,
          allLines: allLines,
          allPlacements: allPlacements,
          layerABaseImage: layerABaseImage,
          layerBBaseImage: layerBBaseImage,
          layerCBaseImage: layerCBaseImage,
          layerABaseSampling: layerABaseSampling,
          layerBBaseSampling: layerBBaseSampling,
          layerCBaseSampling: layerCBaseSampling,
          tone30Shader: tone30Shader,
          tone60Shader: tone60Shader,
          tone80Shader: tone80Shader,
          recursionDepth: recursionDepth,
        );
      }
      placementIndex++;
    }
  }

  static void paintPlacement(
    Canvas canvas,
    LayerPlacement placement, {
    required List<DrawnLine> allLines,
    required List<LayerPlacement> allPlacements,
    required ui.Image? layerABaseImage,
    required ui.Image? layerBBaseImage,
    required ui.Image? layerCBaseImage,
    required RasterSamplingMode layerABaseSampling,
    required RasterSamplingMode layerBBaseSampling,
    required RasterSamplingMode layerCBaseSampling,
    required ui.ImageShader? tone30Shader,
    required ui.ImageShader? tone60Shader,
    required ui.ImageShader? tone80Shader,
    int recursionDepth = 0,
  }) {
    if (placement.isVectorPlacement) {
      final Rect rect = placement.baseRect;
      final Offset center = rect.center + placement.translation;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(placement.rotation);
      canvas.scale(placement.scaleX, placement.scaleY);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      canvas.clipPath(placement.vectorMaskPath!, doAntiAlias: false);
      paintSourceContentsUpTo(
        canvas,
        placement.vectorSourceLayer!,
        placement.vectorMaxSequence!,
        allLines: allLines,
        allPlacements: allPlacements,
        layerABaseImage: layerABaseImage,
        layerBBaseImage: layerBBaseImage,
        layerCBaseImage: layerCBaseImage,
        layerABaseSampling: layerABaseSampling,
        layerBBaseSampling: layerBBaseSampling,
        layerCBaseSampling: layerCBaseSampling,
        tone30Shader: tone30Shader,
        tone60Shader: tone60Shader,
        tone80Shader: tone80Shader,
        recursionDepth: recursionDepth + 1,
      );
      canvas.restore();
      return;
    }

    final ui.Image? img = placement.rasterImage;
    if (img == null) return;

    final Rect rect = placement.baseRect;
    final Offset center = rect.center + placement.translation;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(placement.rotation);
    canvas.scale(placement.scaleX, placement.scaleY);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    paintImage(
      canvas: canvas,
      rect: rect,
      image: img,
      fit: BoxFit.fill,
      filterQuality: placement.rasterSampling == RasterSamplingMode.smooth
          ? FilterQuality.medium
          : FilterQuality.none,
    );
    canvas.restore();
  }

  static void paintLassoSelection(
    Canvas canvas,
    LassoSelection selection, {
    required List<DrawnLine> allLines,
    required List<LayerPlacement> allPlacements,
    required ui.Image? layerABaseImage,
    required ui.Image? layerBBaseImage,
    required ui.Image? layerCBaseImage,
    required RasterSamplingMode layerABaseSampling,
    required RasterSamplingMode layerBBaseSampling,
    required RasterSamplingMode layerCBaseSampling,
    required ui.ImageShader? tone30Shader,
    required ui.ImageShader? tone60Shader,
    required ui.ImageShader? tone80Shader,
  }) {
    final ui.Image? raster = selection.rasterImage;
    if (raster != null) {
      final Rect rect = selection.baseRect;
      final Offset center = rect.center + selection.translation;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(selection.rotation);
      canvas.scale(selection.scaleX, selection.scaleY);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      paintImage(
        canvas: canvas,
        rect: rect,
        image: raster,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.none,
      );
      canvas.restore();
      return;
    }

    final Rect rect = selection.baseRect;
    final Offset center = rect.center + selection.translation;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(selection.rotation);
    canvas.scale(selection.scaleX, selection.scaleY);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    canvas.clipPath(selection.maskPath, doAntiAlias: false);
    paintSourceContentsUpTo(
      canvas,
      selection.layer,
      selection.maxContentSequence,
      allLines: allLines,
      allPlacements: allPlacements,
      layerABaseImage: layerABaseImage,
      layerBBaseImage: layerBBaseImage,
      layerCBaseImage: layerCBaseImage,
      layerABaseSampling: layerABaseSampling,
      layerBBaseSampling: layerBBaseSampling,
      layerCBaseSampling: layerCBaseSampling,
      tone30Shader: tone30Shader,
      tone60Shader: tone60Shader,
      tone80Shader: tone80Shader,
      recursionDepth: 0,
    );
    canvas.restore();
  }

  static void _paintLine(
    Canvas canvas,
    DrawnLine line, {
    required ui.ImageShader? tone30Shader,
    required ui.ImageShader? tone60Shader,
    required ui.ImageShader? tone80Shader,
  }) {
    final paint = Paint()
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final toneShader = line.isEraser
        ? null
        : _toneShaderForTool(
            line.tool,
            tone30Shader: tone30Shader,
            tone60Shader: tone60Shader,
            tone80Shader: tone80Shader,
          );
    final bool isToneStroke = toneShader != null;
    paint
      ..isAntiAlias = !isToneStroke
      ..shader = toneShader
      ..color = (toneShader == null ? line.color : Colors.white)
          .withValues(alpha: line.eraserAlpha)
      ..blendMode = line.isEraser ? BlendMode.dstOut : BlendMode.srcOver
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..filterQuality =
          toneShader == null ? FilterQuality.low : FilterQuality.none;

    switch (line.tool) {
      case ToolType.rect:
      case ToolType.fillRect:
        if (line.shapeRect == null) return;
        paint
          ..style = line.tool == ToolType.fillRect
              ? PaintingStyle.fill
              : PaintingStyle.stroke
          ..strokeCap = StrokeCap.butt
          ..strokeJoin = StrokeJoin.miter
          ..strokeWidth = line.width;
        canvas.drawRect(line.shapeRect!, paint);
        return;
      case ToolType.circle:
      case ToolType.fillCircle:
        if (line.shapeRect == null) return;
        paint
          ..style = line.tool == ToolType.fillCircle
              ? PaintingStyle.fill
              : PaintingStyle.stroke
          ..strokeWidth = line.width;
        canvas.drawOval(line.shapeRect!, paint);
        return;
      case ToolType.line:
        if (line.points.length < 2) return;
        paint
          ..strokeWidth = line.points.first.width
          ..strokeCap = StrokeCap.butt
          ..strokeJoin = StrokeJoin.miter;
        final path = Path()
          ..moveTo(line.points.first.offset.dx, line.points.first.offset.dy)
          ..lineTo(line.points.last.offset.dx, line.points.last.offset.dy);
        canvas.drawPath(path, paint);
        return;
      case ToolType.dot30:
      case ToolType.dot60:
      case ToolType.dot80:
        if (line.points.isEmpty) return;
        paint
          ..style = PaintingStyle.fill
          ..strokeWidth = 1;
        for (final p in line.points) {
          canvas.drawCircle(p.offset, line.width / 2, paint);
        }
        return;
      default:
        if (line.points.length < 2) return;
        if (!line.variableWidth) {
          final path = _buildSmoothPath(line.points);
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = line.width;
          canvas.drawPath(path, paint);
          return;
        }
        final path = _buildVariableWidthRibbon(line.points);
        paint
          ..style = PaintingStyle.fill
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, paint);
    }
  }

  static Path _buildSmoothPath(List<Point> points) {
    final path = Path();
    if (points.isEmpty) return path;
    if (points.length == 1) {
      path.addOval(Rect.fromCircle(
          center: points.first.offset, radius: points.first.width / 2));
      return path;
    }
    final filtered = _lowPassFilter(points, factor: 0.6);
    path.moveTo(filtered.first.offset.dx, filtered.first.offset.dy);
    for (int i = 1; i < filtered.length - 1; i++) {
      final current = filtered[i].offset;
      final next = filtered[i + 1].offset;
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    path.lineTo(filtered.last.offset.dx, filtered.last.offset.dy);
    return path;
  }

  static Path _buildVariableWidthRibbon(List<Point> points) {
    if (points.length < 2) return Path();
    final filtered = _lowPassFilter(points, factor: 0.15);
    final dense = _catmullRomDensePoints(filtered, samples: 10);

    final left = <Offset>[];
    final right = <Offset>[];
    for (int i = 0; i < dense.length; i++) {
      final p = dense[i].offset;
      final w = dense[i].width;
      Offset dir;
      if (i == 0) {
        dir = dense[i + 1].offset - p;
      } else if (i == dense.length - 1) {
        dir = p - dense[i - 1].offset;
      } else {
        dir = dense[i + 1].offset - dense[i - 1].offset;
      }
      final len = dir.distance;
      if (len < 0.001) continue;
      final n = Offset(-dir.dy / len, dir.dx / len);
      final halfW = w / 2;
      left.add(p + n * halfW);
      right.add(p - n * halfW);
    }

    final path = Path();
    if (left.isEmpty || right.isEmpty) return path;
    path.moveTo(left.first.dx, left.first.dy);
    for (int i = 1; i < left.length; i++) {
      path.lineTo(left[i].dx, left[i].dy);
    }
    for (int i = right.length - 1; i >= 0; i--) {
      path.lineTo(right[i].dx, right[i].dy);
    }
    path.close();
    return path;
  }

  static List<Point> _catmullRomDensePoints(List<Point> pts,
      {int samples = 8}) {
    if (pts.length < 2) return pts;
    final List<Point> dense = [];
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
      for (int s = 0; s < samples; s++) {
        final t = s / samples;
        final t2 = t * t;
        final t3 = t2 * t;
        final dx = 0.5 *
            ((2 * p1.offset.dx) +
                (-p0.offset.dx + p2.offset.dx) * t +
                (2 * p0.offset.dx -
                        5 * p1.offset.dx +
                        4 * p2.offset.dx -
                        p3.offset.dx) *
                    t2 +
                (-p0.offset.dx +
                        3 * p1.offset.dx -
                        3 * p2.offset.dx +
                        p3.offset.dx) *
                    t3);
        final dy = 0.5 *
            ((2 * p1.offset.dy) +
                (-p0.offset.dy + p2.offset.dy) * t +
                (2 * p0.offset.dy -
                        5 * p1.offset.dy +
                        4 * p2.offset.dy -
                        p3.offset.dy) *
                    t2 +
                (-p0.offset.dy +
                        3 * p1.offset.dy -
                        3 * p2.offset.dy +
                        p3.offset.dy) *
                    t3);
        final width = ui.lerpDouble(p1.width, p2.width, t)!;
        dense.add(Point(Offset(dx, dy), width));
      }
    }
    dense.add(pts.last);
    return dense;
  }

  static List<Point> _lowPassFilter(List<Point> points,
      {double factor = 0.55}) {
    if (points.length < 2) return points;
    final result = <Point>[points.first];
    for (int i = 1; i < points.length; i++) {
      final previous = result.last;
      final current = points[i];
      final filteredOffset =
          Offset.lerp(previous.offset, current.offset, factor)!;
      result.add(Point(filteredOffset, current.width));
    }
    return result;
  }
}
