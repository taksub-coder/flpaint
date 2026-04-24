import 'dart:math' as math;
import 'dart:ui';

import '../models/drawing.dart';

double pixelDouble(num value) => value.roundToDouble();

int pixelInt(num value) => math.max(1, value.round());

Offset pixelOffset(Offset offset) {
  return Offset(offset.dx.roundToDouble(), offset.dy.roundToDouble());
}

Size pixelSize(Size size) {
  return Size(size.width.roundToDouble(), size.height.roundToDouble());
}

Rect pixelRect(Rect rect) {
  final double left = rect.left.roundToDouble();
  final double top = rect.top.roundToDouble();
  final double right = rect.right.roundToDouble();
  final double bottom = rect.bottom.roundToDouble();
  return Rect.fromLTRB(
    math.min(left, right),
    math.min(top, bottom),
    math.max(left, right),
    math.max(top, bottom),
  );
}

Rect pixelOuterRect(Rect rect) {
  final double left = rect.left.floorToDouble();
  final double top = rect.top.floorToDouble();
  final double right = rect.right.ceilToDouble();
  final double bottom = rect.bottom.ceilToDouble();
  return Rect.fromLTRB(
    math.min(left, right),
    math.min(top, bottom),
    math.max(left, right),
    math.max(top, bottom),
  );
}

Rect pixelRectFromLTWH(double left, double top, double width, double height) {
  return Rect.fromLTWH(
    left.roundToDouble(),
    top.roundToDouble(),
    math.max(1, width.round()).toDouble(),
    math.max(1, height.round()).toDouble(),
  );
}

Point pixelPoint(Point point) {
  return Point(
    pixelOffset(point.offset),
    math.max(1, point.width.roundToDouble()),
  );
}

List<Point> pixelPointList(Iterable<Point> points) {
  return points.map(pixelPoint).toList(growable: false);
}

Path pixelPolylinePath(List<Point> points) {
  final Path path = Path();
  if (points.isEmpty) {
    return path;
  }
  final Offset first = pixelOffset(points.first.offset);
  path.moveTo(first.dx, first.dy);
  for (int i = 1; i < points.length; i++) {
    final Offset point = pixelOffset(points[i].offset);
    path.lineTo(point.dx, point.dy);
  }
  return path;
}
