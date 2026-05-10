import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/drawing.dart';
import 'pixel_geometry.dart';

/// Upper bound for "paint everything" when merging layer timelines.
const int kLayerCompositeMaxSequence = 2000000000;

class _LayerCompositeFrameCache {
  const _LayerCompositeFrameCache({
    required this.allLines,
    required this.allPlacements,
    required this.revision,
    required this.linesByLayer,
    required this.placementsByLayer,
    required this.requiresIsolationByLayer,
  });

  final List<DrawnLine> allLines;
  final List<LayerPlacement> allPlacements;
  final int revision;
  final Map<DrawingLayer, List<DrawnLine>> linesByLayer;
  final Map<DrawingLayer, List<LayerPlacement>> placementsByLayer;
  final Map<DrawingLayer, bool> requiresIsolationByLayer;
}

/// Shared layer compositing for on-screen paint, export, and vector lasso replay.
class LayerCompositePainter {
  LayerCompositePainter._();

  static _LayerCompositeFrameCache? _frameCache;

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

  static void _paintRasterImage(
    Canvas canvas,
    ui.Image image,
    Rect dstRect, {
    required RasterSamplingMode sampling,
  }) {
    final Rect snappedDstRect = pixelRect(dstRect);
    final Paint paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
    final bool keepsNativePixels =
        snappedDstRect.width.round() == image.width &&
            snappedDstRect.height.round() == image.height;
    if (keepsNativePixels) {
      canvas.drawImage(image, pixelOffset(snappedDstRect.topLeft), paint);
      return;
    }

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      ),
      snappedDstRect,
      paint,
    );
  }

  static _LayerCompositeFrameCache _resolveFrameCache({
    required List<DrawnLine> allLines,
    required List<LayerPlacement> allPlacements,
    required int revision,
  }) {
    final _LayerCompositeFrameCache? cached = _frameCache;
    if (cached != null &&
        identical(cached.allLines, allLines) &&
        identical(cached.allPlacements, allPlacements) &&
        cached.revision == revision) {
      return cached;
    }

    final Map<DrawingLayer, List<DrawnLine>> linesByLayer =
        <DrawingLayer, List<DrawnLine>>{
      for (final DrawingLayer layer in DrawingLayer.values)
        layer: <DrawnLine>[],
    };
    for (final DrawnLine line in allLines) {
      linesByLayer[line.layer]!.add(line);
    }

    final Map<DrawingLayer, List<LayerPlacement>> placementsByLayer =
        <DrawingLayer, List<LayerPlacement>>{
      for (final DrawingLayer layer in DrawingLayer.values)
        layer: <LayerPlacement>[],
    };
    final Map<DrawingLayer, bool> requiresIsolationByLayer =
        <DrawingLayer, bool>{
      for (final DrawingLayer layer in DrawingLayer.values) layer: false,
    };
    for (final LayerPlacement placement in allPlacements) {
      final DrawingLayer? sourceLayer = placement.sourceLayer;
      if (sourceLayer != null) {
        placementsByLayer[sourceLayer]!.add(placement);
        if (placement.sourceMaskPath != null) {
          requiresIsolationByLayer[sourceLayer] = true;
        }
      }
      if (placement.targetLayer != sourceLayer) {
        placementsByLayer[placement.targetLayer]!.add(placement);
      }
      if (placement.isVectorPlacement) {
        requiresIsolationByLayer[placement.targetLayer] = true;
      }
    }
    for (final DrawnLine line in allLines) {
      if (line.isEraser) {
        requiresIsolationByLayer[line.layer] = true;
      }
    }

    final _LayerCompositeFrameCache nextCache = _LayerCompositeFrameCache(
      allLines: allLines,
      allPlacements: allPlacements,
      revision: revision,
      linesByLayer: linesByLayer,
      placementsByLayer: placementsByLayer,
      requiresIsolationByLayer: requiresIsolationByLayer,
    );
    _frameCache = nextCache;
    return nextCache;
  }

  static bool layerRequiresIsolation(
    DrawingLayer layer, {
    required List<DrawnLine> allLines,
    required List<LayerPlacement> allPlacements,
    int? cacheRevision,
  }) {
    if (cacheRevision != null) {
      final _LayerCompositeFrameCache cache = _resolveFrameCache(
        allLines: allLines,
        allPlacements: allPlacements,
        revision: cacheRevision,
      );
      return cache.requiresIsolationByLayer[layer] ?? false;
    }

    for (final DrawnLine line in allLines) {
      if (line.layer == layer && line.isEraser) {
        return true;
      }
    }
    for (final LayerPlacement placement in allPlacements) {
      if (placement.sourceLayer == layer && placement.sourceMaskPath != null) {
        return true;
      }
      if (placement.targetLayer == layer && placement.isVectorPlacement) {
        return true;
      }
    }
    return false;
  }

  /// Paints one layer's base bitmap + interleaved lines/placements up to [maxSequence].
  static void paintSourceContentsUpTo(
    Canvas canvas,
    DrawingLayer layer,
    int maxSequence, {
    required Size canvasSize,
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
    int? cacheRevision,
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
      _paintRasterImage(
        canvas,
        layerBaseImage,
        Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
        sampling: baseSampling,
      );
    }

    final List<DrawnLine> layerLines;
    final List<LayerPlacement> layerPlacements;
    if (cacheRevision != null) {
      final _LayerCompositeFrameCache cache = _resolveFrameCache(
        allLines: allLines,
        allPlacements: allPlacements,
        revision: cacheRevision,
      );
      layerLines = cache.linesByLayer[layer]!;
      layerPlacements = cache.placementsByLayer[layer]!;
    } else {
      layerLines = allLines
          .where((DrawnLine line) => line.layer == layer)
          .toList(growable: false);
      layerPlacements = allPlacements
          .where((LayerPlacement placement) =>
              placement.sourceLayer == layer || placement.targetLayer == layer)
          .toList(growable: false);
    }

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
          canvasSize: canvasSize,
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
          cacheRevision: cacheRevision,
          recursionDepth: recursionDepth,
        );
      }
      placementIndex++;
    }
  }

  static void paintPlacement(
    Canvas canvas,
    LayerPlacement placement, {
    required Size canvasSize,
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
    int? cacheRevision,
    int recursionDepth = 0,
  }) {
    if (placement.isVectorPlacement) {
      final Rect rect = pixelRect(placement.baseRect);
      final Offset translation = pixelOffset(placement.translation);
      final Offset center = pixelOffset(rect.center + translation);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(placement.rotation);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      canvas.clipPath(placement.vectorMaskPath!, doAntiAlias: false);
      paintSourceContentsUpTo(
        canvas,
        placement.vectorSourceLayer!,
        placement.vectorMaxSequence!,
        canvasSize: canvasSize,
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
        cacheRevision: cacheRevision,
        recursionDepth: recursionDepth + 1,
      );
      canvas.restore();
      return;
    }

    final ui.Image? img = placement.rasterImage;
    if (img == null) return;

    final Rect rect = pixelRect(placement.baseRect);
    final Offset translation = pixelOffset(placement.translation);
    final Offset center = pixelOffset(rect.center + translation);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(placement.rotation);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    _paintRasterImage(
      canvas,
      img,
      rect,
      sampling: RasterSamplingMode.pixelated,
    );
    canvas.restore();
  }

  static void paintLassoSelection(
    Canvas canvas,
    LassoSelection selection, {
    required Size canvasSize,
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
    int? cacheRevision,
  }) {
    final ui.Image? raster = selection.rasterImage;
    if (raster != null) {
      final Rect rect = pixelRect(selection.baseRect);
      final Offset translation = pixelOffset(selection.translation);
      final Offset center = pixelOffset(rect.center + translation);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(selection.rotation);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      _paintRasterImage(
        canvas,
        raster,
        rect,
        sampling: RasterSamplingMode.pixelated,
      );
      canvas.restore();
      return;
    }

    final Rect rect = pixelRect(selection.baseRect);
    final Offset translation = pixelOffset(selection.translation);
    final Offset center = pixelOffset(rect.center + translation);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(selection.rotation);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    canvas.clipPath(selection.maskPath, doAntiAlias: false);
    paintSourceContentsUpTo(
      canvas,
      selection.layer,
      selection.maxContentSequence,
      canvasSize: canvasSize,
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
      cacheRevision: cacheRevision,
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
    final List<Point> points = line.variableWidth
        ? _preserveVariableWidthPoints(line.points)
        : pixelPointList(line.points);
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
    paint
      ..isAntiAlias = true
      ..shader = toneShader
      ..color = toneShader == null
          ? line.color.withValues(alpha: line.eraserAlpha)
          : Colors.white
      ..colorFilter = toneShader == null
          ? null
          : ColorFilter.mode(
              line.color.withValues(alpha: line.eraserAlpha),
              BlendMode.srcIn,
            )
      ..blendMode = line.isEraser ? BlendMode.dstOut : BlendMode.srcOver
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (line.tool) {
      case ToolType.rect:
      case ToolType.fillRect:
        if (line.shapeRect == null) return;
        final Rect rect = pixelRect(line.shapeRect!);
        paint
          ..style = line.tool == ToolType.fillRect
              ? PaintingStyle.fill
              : PaintingStyle.stroke
          ..strokeCap = StrokeCap.butt
          ..strokeJoin = StrokeJoin.miter
          ..strokeWidth = pixelDouble(line.width);
        canvas.drawRect(rect, paint);
        return;
      case ToolType.circle:
      case ToolType.fillCircle:
        if (line.shapeRect == null) return;
        final Rect rect = pixelRect(line.shapeRect!);
        paint
          ..style = line.tool == ToolType.fillCircle
              ? PaintingStyle.fill
              : PaintingStyle.stroke
          ..strokeWidth = pixelDouble(line.width);
        canvas.drawOval(rect, paint);
        return;
      case ToolType.line:
      case ToolType.radial:
        if (points.length < 2) return;
        paint
          ..strokeWidth = points.first.width
          ..strokeCap = StrokeCap.butt
          ..strokeJoin = StrokeJoin.miter;
        final path = Path()
          ..moveTo(points.first.offset.dx, points.first.offset.dy)
          ..lineTo(points.last.offset.dx, points.last.offset.dy);
        canvas.drawPath(path, paint);
        return;
      case ToolType.dot30:
      case ToolType.dot60:
      case ToolType.dot80:
        if (points.isEmpty) return;
        paint
          ..isAntiAlias = false
          ..style = PaintingStyle.fill
          ..strokeWidth = 1;
        for (final p in points) {
          canvas.drawCircle(
            pixelOffset(p.offset),
            math.max(1, line.width.roundToDouble()) / 2,
            paint,
          );
        }
        return;
      default:
        if (points.length < 2) return;
        if (!line.variableWidth) {
          final path = _buildSmoothPath(points);
          paint
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = pixelDouble(line.width);
          canvas.drawPath(path, paint);
          return;
        }
        final path = _buildVariableWidthRibbon(points);
        paint
          ..isAntiAlias = true
          ..style = PaintingStyle.fill
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, paint);
        if (points.length >= 2) {
          final dense = _catmullRomDensePoints(
            _lowPassFilter(points, factor: 0.15),
            samples: 10,
          );
          if (dense.isNotEmpty) {
            canvas.drawCircle(dense.first.offset, dense.first.width / 2, paint);
            canvas.drawCircle(dense.last.offset, dense.last.width / 2, paint);
          }
        }
    }
  }

  static List<Point> _preserveVariableWidthPoints(List<Point> points) {
    return points
        .map(
          (point) => Point(
            pixelOffset(point.offset),
            math.max(1.0, point.width),
          ),
        )
        .toList(growable: false);
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
    _appendSmoothOffsets(path, left);
    for (int i = right.length - 1; i >= 0; i--) {
      if (i == right.length - 1) {
        path.lineTo(right[i].dx, right[i].dy);
      } else {
        final Offset current = right[i + 1];
        final Offset next = right[i];
        final Offset mid = Offset(
          (current.dx + next.dx) / 2,
          (current.dy + next.dy) / 2,
        );
        path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
      }
    }
    path.close();
    return path;
  }

  static void _appendSmoothOffsets(Path path, List<Offset> points) {
    if (points.length < 2) return;
    for (int i = 1; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    final last = points.last;
    path.lineTo(last.dx, last.dy);
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
        dense.add(Point(
          Offset(dx, dy),
          math.max(1, width),
        ));
      }
    }
    dense.add(Point(pts.last.offset, math.max(1.0, pts.last.width)));
    return dense;
  }

  static List<Point> _lowPassFilter(List<Point> points,
      {double factor = 0.55}) {
    if (points.length < 2) return points;
    final result = <Point>[
      Point(points.first.offset, math.max(1.0, points.first.width)),
    ];
    for (int i = 1; i < points.length; i++) {
      final previous = result.last;
      final current = points[i];
      final filteredOffset =
          Offset.lerp(previous.offset, current.offset, factor)!;
      result.add(Point(
        filteredOffset,
        math.max(1, current.width),
      ));
    }
    return result;
  }
}
