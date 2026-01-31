import 'dart:math' as math;
import 'dart:ui';

enum ToolType { pressure, pen, eraser, lasso }

enum SelectionHandle {
  none,
  inside,
  mirror,
  cornerTL,
  cornerTR,
  cornerBR,
  cornerBL,
  edgeTop,
  edgeRight,
  edgeBottom,
  edgeLeft,
}

class DrawnLine {
  final List<Point> points;
  final Color color;
  final bool variableWidth;
  final bool isEraser;
  bool isFinished;

  DrawnLine(
    this.points, {
    required this.color,
    required this.variableWidth,
    this.isEraser = false,
    this.isFinished = false,
  });
}

class Point {
  final Offset offset;
  final double width;
  Point(this.offset, this.width);
}

class LassoSelection {
  final Image image;
  final Path maskPath;
  Rect baseRect;
  Offset translation;
  double scaleX;
  double scaleY;
  double rotation; // radians

  LassoSelection({
    required this.image,
    required this.maskPath,
    required this.baseRect,
    this.translation = Offset.zero,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.rotation = 0.0,
  });

  Offset get _center => baseRect.center;

  Offset transformPoint(Offset localPoint) {
    // localPoint is in canvas space but before selection transform.
    final Offset shifted = localPoint - _center;
    final double cosR = math.cos(rotation);
    final double sinR = math.sin(rotation);
    final Offset scaled = Offset(shifted.dx * scaleX, shifted.dy * scaleY);
    final Offset rotated = Offset(
      scaled.dx * cosR - scaled.dy * sinR,
      scaled.dx * sinR + scaled.dy * cosR,
    );
    return rotated + _center + translation;
  }

  Offset toLocal(Offset globalPoint) {
    // inverse transform: translate back, unrotate, unscale
    final Offset shifted = globalPoint - translation - _center;
    final double cosR = math.cos(-rotation);
    final double sinR = math.sin(-rotation);
    final Offset rotated = Offset(
      shifted.dx * cosR - shifted.dy * sinR,
      shifted.dx * sinR + shifted.dy * cosR,
    );
    return Offset(
      rotated.dx / scaleX + _center.dx,
      rotated.dy / scaleY + _center.dy,
    );
  }

  List<Offset> transformedCorners() {
    final rect = baseRect;
    return [
      transformPoint(rect.topLeft),
      transformPoint(rect.topRight),
      transformPoint(rect.bottomRight),
      transformPoint(rect.bottomLeft),
    ];
  }

  Path transformedPath() {
    final corners = transformedCorners();
    final path = Path()..moveTo(corners.first.dx, corners.first.dy);
    for (var i = 1; i < corners.length; i++) {
      path.lineTo(corners[i].dx, corners[i].dy);
    }
    path.close();
    return path;
  }

  Rect transformedBounds() {
    final corners = transformedCorners();
    double minX = corners.first.dx, maxX = corners.first.dx;
    double minY = corners.first.dy, maxY = corners.first.dy;
    for (final c in corners.skip(1)) {
      minX = math.min(minX, c.dx);
      maxX = math.max(maxX, c.dx);
      minY = math.min(minY, c.dy);
      maxY = math.max(maxY, c.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}
