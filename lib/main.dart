import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/drawing_provider.dart';
import 'widgets/drawing_canvas.dart';
import 'widgets/drawing_controls.dart';
import 'widgets/radial_tool_popup.dart';
import 'widgets/tool_sidebar.dart';

bool get _isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final DrawingProvider drawingProvider = DrawingProvider();
  await drawingProvider.ensureToneShadersReady();
  if (_isDesktopPlatform) {
    await windowManager.ensureInitialized();
    const WindowOptions windowOptions = WindowOptions(
      minimumSize: Size(480, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'Flaint_プロトタイプ2.1d',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      try {
        await windowManager.setMinimumSize(const Size(480, 800));
        await windowManager.show();
        await windowManager.focus();
        await windowManager.maximize();
      } catch (_) {
        await windowManager.show();
      }
    });
  }

  runApp(
    ChangeNotifierProvider<DrawingProvider>.value(
      value: drawingProvider,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flaint_プロトタイプ2.1d',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with WidgetsBindingObserver {
  static const double _canvasViewportPadding = 500.0;

  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey _interactiveViewerKey = GlobalKey();

  bool _panelSecondaryPointerDown = false;
  bool _panelPanZoomTracking = false;
  bool _suspendInteractiveViewerGestures = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _alignToTopLeft();
      context.read<DrawingProvider>().warmUp();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    if (!mounted) return;
    context.read<DrawingProvider>().optimizeMemoryForEmergency();
  }

  void _alignToTopLeft() {
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(
        -_canvasViewportPadding,
        -_canvasViewportPadding,
        0.0,
        1.0,
      )
      ..scaleByDouble(1.0, 1.0, 1.0, 1.0);
  }

  void _onCanvasTwoFingerPan(Offset delta) {
    if (delta == Offset.zero) return;
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final sceneDx = delta.dx / currentScale;
    final sceneDy = delta.dy / currentScale;
    _transformationController.value = _transformationController.value.clone()
      ..translateByDouble(sceneDx, sceneDy, 0.0, 1.0);
  }

  void _onCanvasTwoFingerScale(Offset focalPointGlobal, double scaleDelta) {
    if (!scaleDelta.isFinite || scaleDelta <= 0) return;
    final context = _interactiveViewerKey.currentContext;
    if (context == null) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final localFocal = renderObject.globalToLocal(focalPointGlobal);
    final sceneFocal = _transformationController.toScene(localFocal);

    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final targetScale = (currentScale * scaleDelta).clamp(0.1, 5.0).toDouble();
    final effectiveScale = targetScale / currentScale;
    if ((effectiveScale - 1.0).abs() < 0.0001) return;

    _transformationController.value = _transformationController.value.clone()
      ..translateByDouble(sceneFocal.dx, sceneFocal.dy, 0.0, 1.0)
      ..scaleByDouble(effectiveScale, effectiveScale, 1.0, 1.0)
      ..translateByDouble(-sceneFocal.dx, -sceneFocal.dy, 0.0, 1.0);
  }

  void _onSelectionHandleInteractionChanged(bool active) {
    if (_suspendInteractiveViewerGestures == active) return;
    setState(() {
      _suspendInteractiveViewerGestures = active;
    });
  }

  Offset _toCanvasPosition(Offset globalPoint) {
    final context = _interactiveViewerKey.currentContext;
    if (context == null) return globalPoint;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return globalPoint;
    final localPoint = renderObject.globalToLocal(globalPoint);
    final scenePoint = _transformationController.toScene(localPoint);
    return scenePoint -
        const Offset(_canvasViewportPadding, _canvasViewportPadding);
  }

  void _onPanelPointerDown(PointerDownEvent event) {
    if (!_isDesktopPlatform) return;
    _panelSecondaryPointerDown = (event.buttons & kSecondaryMouseButton) != 0;
    if (_panelSecondaryPointerDown) {
      windowManager.startDragging();
    }
  }

  void _onPanelPointerMove(PointerMoveEvent event) {
    if (!_isDesktopPlatform || !_panelSecondaryPointerDown) return;
    if ((event.buttons & kSecondaryMouseButton) == 0) {
      _panelSecondaryPointerDown = false;
      return;
    }
    _panelSecondaryPointerDown = false;
    windowManager.startDragging();
  }

  void _onPanelPointerUp(PointerEvent event) {
    _panelSecondaryPointerDown = false;
  }

  void _onPanelPanZoomStart(PointerPanZoomStartEvent event) {
    if (!_isDesktopPlatform) return;
    _panelPanZoomTracking = true;
  }

  void _onPanelPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!_isDesktopPlatform || !_panelPanZoomTracking) return;
    final delta = event.panDelta;
    if (delta == Offset.zero) return;
    windowManager.getPosition().then((position) {
      if (!_panelPanZoomTracking) return;
      windowManager.setPosition(position + delta);
    });
  }

  void _onPanelPanZoomEnd(PointerPanZoomEndEvent event) {
    if (!_isDesktopPlatform) return;
    _panelPanZoomTracking = false;
  }

  Widget _buildWindowMovablePanel({required Widget child}) {
    if (!_isDesktopPlatform) {
      return child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPanelPointerDown,
      onPointerMove: _onPanelPointerMove,
      onPointerUp: _onPanelPointerUp,
      onPointerCancel: _onPanelPointerUp,
      onPointerPanZoomStart: _onPanelPanZoomStart,
      onPointerPanZoomUpdate: _onPanelPanZoomUpdate,
      onPointerPanZoomEnd: _onPanelPanZoomEnd,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final drawingProvider = context.read<DrawingProvider>();

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: _buildWindowMovablePanel(
          child: AppBar(
            title: const Text('Flaint_プロトタイプ2.1d'),
            actions: [
              IconButton(
                icon: const Icon(Icons.undo),
                onPressed: drawingProvider.undo,
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                onPressed: drawingProvider.redo,
              ),
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  drawingProvider.clear();
                  _alignToTopLeft();
                },
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      color: const Color(0xFF404040),
                      child: Stack(
                        children: [
                          InteractiveViewer(
                            key: _interactiveViewerKey,
                            constrained: false,
                            boundaryMargin: const EdgeInsets.all(2000),
                            minScale: 0.1,
                            maxScale: 5.0,
                            panEnabled: !_suspendInteractiveViewerGestures,
                            scaleEnabled: !_suspendInteractiveViewerGestures,
                            trackpadScrollCausesScale: true,
                            transformationController: _transformationController,
                            child: SizedBox(
                              width: 768 + (_canvasViewportPadding * 2),
                              height: 1024 + (_canvasViewportPadding * 2),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.all(
                                      _canvasViewportPadding,
                                    ),
                                    child: _CanvasSheet(),
                                  ),
                                  Positioned.fill(
                                    child: RepaintBoundary(
                                      child: DrawingCanvas(
                                        onTwoFingerPan: _onCanvasTwoFingerPan,
                                        onTwoFingerScale:
                                            _onCanvasTwoFingerScale,
                                        toCanvas: _toCanvasPosition,
                                        onSelectionHandleInteractionChanged:
                                            _onSelectionHandleInteractionChanged,
                                        logicalCanvasSize:
                                            const Size(768, 1024),
                                        canvasVisualOffset: const Offset(
                                          _canvasViewportPadding,
                                          _canvasViewportPadding,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Positioned(
                            top: 12,
                            right: 12,
                            child: RepaintBoundary(
                              child: RadialToolPopup(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildWindowMovablePanel(
                    child: Container(
                      width: 70,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        border:
                            Border(left: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: const RepaintBoundary(
                        child: ToolSidebar(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildWindowMovablePanel(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(20),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: const RepaintBoundary(
                  child: DrawingControls(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CanvasSheet extends StatelessWidget {
  const _CanvasSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 768,
      height: 1024,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
          ),
        ],
      ),
    );
  }
}
