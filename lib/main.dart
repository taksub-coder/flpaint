// flpaint_プロトタイプF1.0_トーンモアレ修正＿描始め座標修正完成版
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter/gestures.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/drawing_provider.dart';
import 'widgets/drawing_canvas.dart';
import 'widgets/drawing_controls.dart';
import 'widgets/tool_sidebar.dart';

bool get _isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_isDesktopPlatform) {
    // window_manager の初期化
    await windowManager.ensureInitialized();

    // ウィンドウオプションを設定
    WindowOptions windowOptions = const WindowOptions(
      size: Size(838, 980),           // キャンバス768 + サイドバー70 + 余裕
      minimumSize: Size(480, 800),
      maximumSize: Size(3000, 3000),   // 必要に応じて大きく
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'FLPaint - プロトタイプE.2g',
      // 必要に応じて windowButtonVisibility: false, などを追加可能
    );

    // ウィンドウを表示・フォーカスするまで待機
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 追加でサイズを確実に適用（最新版で安定する書き方）
      await windowManager.setSize(const Size(838, 980));
      await windowManager.setMinimumSize(const Size(480, 800));
      await windowManager.center();
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => DrawingProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FLPaint',
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

class _MyHomePageState extends State<MyHomePage> {
  static const double _canvasViewportPadding = 500.0;
  final TransformationController _transformationController = TransformationController();
  final GlobalKey _interactiveViewerKey = GlobalKey();
  bool _panelSecondaryPointerDown = false;
  bool _panelPanZoomTracking = false;
  bool _suspendInteractiveViewerGestures = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _alignToTopLeft();
    });
  }

  void _alignToTopLeft() {
    // スケール1.0で左上に寄せる（翻訳を0にセット）
    _transformationController.value = Matrix4.identity()
      ..translate(-_canvasViewportPadding, -_canvasViewportPadding)  // 左上座標を(0,0)に固定
      ..scale(1.0);          // スケールは1.0（キャンバス原寸）
  }

  void _onCanvasTwoFingerPan(Offset delta) {
    if (delta == Offset.zero) return;
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final sceneDx = delta.dx / currentScale;
    final sceneDy = delta.dy / currentScale;
    _transformationController.value = _transformationController.value.clone()
      ..translate(sceneDx, sceneDy);
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
      ..translate(sceneFocal.dx, sceneFocal.dy)
      ..scale(effectiveScale)
      ..translate(-sceneFocal.dx, -sceneFocal.dy);
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
    return scenePoint - const Offset(_canvasViewportPadding, _canvasViewportPadding);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _onPanelPointerDown(PointerDownEvent event) {
    if (!_isDesktopPlatform) return;
    _panelSecondaryPointerDown =
        (event.buttons & kSecondaryMouseButton) != 0;
    if (_panelSecondaryPointerDown) {
      windowManager.startDragging();
    }
  }

  void _onPanelPointerMove(PointerMoveEvent event) {
    if (!_isDesktopPlatform) return;
    if (!_panelSecondaryPointerDown) return;
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
    if (!_isDesktopPlatform) return;
    if (!_panelPanZoomTracking) return;
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
        title: const Text('FLPaint'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: drawingProvider.undo),
          IconButton(icon: const Icon(Icons.redo), onPressed: drawingProvider.redo),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              drawingProvider.clear();
              _alignToTopLeft(); // クリア時も左上にリセット
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
                  // キャンバスエリア
                  Expanded(
                    child: Container(
                      color: const Color(0xFF404040), // キャンバス外：ダークグレー
                      child: InteractiveViewer(
                        key: _interactiveViewerKey,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(2000),
                        minScale: 0.1,
                        maxScale: 5.0,
                        panEnabled: !_suspendInteractiveViewerGestures,
                        scaleEnabled: !_suspendInteractiveViewerGestures,
                        trackpadScrollCausesScale: true,
                        transformationController: _transformationController,
                        child: Padding(
                          padding: const EdgeInsets.all(_canvasViewportPadding), // 広大な余白でズームアウト対応
                          child: Container(
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
                            // DrawingCanvas を確実に最前面にする
                            child: DrawingCanvas(
                              onTwoFingerPan: _onCanvasTwoFingerPan,
                              onTwoFingerScale: _onCanvasTwoFingerScale,
                              toCanvas: _toCanvasPosition,
                              onSelectionHandleInteractionChanged:
                                  _onSelectionHandleInteractionChanged,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 固定サイドバー
                  _buildWindowMovablePanel(
                    child: Container(
                      width: 70,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        border: Border(left: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: const ToolSidebar(),
                    ),
                  ),
                ],
              ),
            ),
            // 固定スライダーパネル
            _buildWindowMovablePanel(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 4, offset: const Offset(0, -2))
                  ],
                ),
                child: const DrawingControls(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
