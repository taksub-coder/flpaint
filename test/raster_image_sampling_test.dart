import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/models/drawing.dart';
import 'package:myapp/providers/drawing_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ensureToneShadersReady initializes tone shaders before use', () async {
    final DrawingProvider provider = DrawingProvider();

    await provider.ensureToneShadersReady();

    expect(provider.tone30Shader, isNotNull);
    expect(provider.tone60Shader, isNotNull);
    expect(provider.tone80Shader, isNotNull);
  });

  test('restore backup keeps restored layers in smooth sampling mode',
      () async {
    final Directory tempDir =
        await Directory.systemTemp.createTemp('flpaint_restore_sampling_');
    try {
      final ui.Image layerA = await _solidImage(const Color(0xFFFF0000));
      final ui.Image layerB = await _solidImage(const Color(0xFF00FF00));
      final ui.Image layerC = await _solidImage(const Color(0xFF0000FF));

      final String layerAPath =
          '${tempDir.path}${Platform.pathSeparator}layerA.png';
      final String layerBPath =
          '${tempDir.path}${Platform.pathSeparator}layerB.png';
      final String layerCPath =
          '${tempDir.path}${Platform.pathSeparator}layerC.png';
      await _writePng(layerA, layerAPath);
      await _writePng(layerB, layerBPath);
      await _writePng(layerC, layerCPath);

      final DrawingProvider provider = DrawingProvider();
      await provider.restoreBackup(
        LayerBackupSet(
          id: 'restore-test',
          isAutosave: false,
          savedAt: DateTime(2026, 4, 5),
          displayLabel: 'restore-test',
          layerAPath: layerAPath,
          layerBPath: layerBPath,
          layerCPath: layerCPath,
        ),
      );

      expect(provider.layerABaseImage, isNotNull);
      expect(provider.layerBBaseImage, isNotNull);
      expect(provider.layerCBaseImage, isNotNull);
      expect(provider.layerABaseSampling, RasterSamplingMode.smooth);
      expect(provider.layerBBaseSampling, RasterSamplingMode.smooth);
      expect(provider.layerCBaseSampling, RasterSamplingMode.smooth);
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('committed raster selections keep smooth sampling', () async {
    final DrawingProvider provider = DrawingProvider();
    provider.setCanvasSize(const Size(768, 1024));

    await provider.addTextToActiveLayer(
      text: 'Smooth',
      context: null,
      vertical: false,
    );

    final LassoSelection? selection = provider.selection;
    expect(selection, isNotNull);
    expect(selection!.rasterImage, isNotNull);
    expect(selection.rasterSampling, RasterSamplingMode.smooth);

    await provider.commitSelection();

    expect(provider.placements, hasLength(1));
    expect(provider.placements.single.rasterImage, isNotNull);
    expect(
        provider.placements.single.rasterSampling, RasterSamplingMode.smooth);
  });

  test('auto cleanup bakes vector layers with pixelated sampling', () async {
    final DrawingProvider provider = DrawingProvider();
    provider.setCanvasSize(const Size(768, 1024));

    for (int index = 0; index < 20; index++) {
      final double y = 20.0 + (index * 8.0);
      provider.startNewLine(Offset(20, y));
      provider.addPoint(Offset(120, y), Offset(20, y),
          preserveExactPoint: true);
      provider.endLine();
    }

    provider.optimizeMemoryForEmergency();
    await _waitForCondition(() => provider.layerABaseImage != null);

    expect(provider.layerABaseImage, isNotNull);
    expect(provider.layerABaseSampling, RasterSamplingMode.pixelated);
    expect(provider.lines, isEmpty);
  });

  test('auto cleanup bakes vector layers at physical pixel ratio', () async {
    final DrawingProvider provider = DrawingProvider();
    provider.setCanvasSize(const Size(100, 50), pixelRatio: 3.0);

    for (int index = 0; index < 20; index++) {
      final double y = 2.0 + (index * 2.0);
      provider.startNewLine(Offset(4, y));
      provider.addPoint(Offset(80, y), Offset(4, y), preserveExactPoint: true);
      provider.endLine();
    }

    provider.optimizeMemoryForEmergency();
    await _waitForCondition(() => provider.layerABaseImage != null);

    expect(provider.layerABaseImage!.width, 300);
    expect(provider.layerABaseImage!.height, 150);
    expect(provider.layerABaseSampling, RasterSamplingMode.pixelated);
    expect(provider.lines, isEmpty);
  });
}

Future<ui.Image> _solidImage(Color color) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = color,
  );
  return recorder.endRecording().toImage(4, 4);
}

Future<void> _writePng(ui.Image image, String path) async {
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('Failed to encode test image as PNG.');
  }
  await File(path).writeAsBytes(
    Uint8List.sublistView(data.buffer.asUint8List()),
    flush: true,
  );
}

Future<void> _waitForCondition(bool Function() condition) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
