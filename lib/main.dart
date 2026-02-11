// flpaint_プロトタイプE.2g_描画優先ズーム対応版
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/gestures.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/drawing_provider.dart';
import 'widgets/drawing_canvas.dart';
import 'widgets/drawing_controls.dart';
import 'widgets/tool_sidebar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // window_manager の初期化
  await windowManager.ensureInitialized();

  // ウィンドウオプションを設定
  WindowOptions windowOptions = const WindowOptions(
    size: Size(838, 980),           // キャンバス768 + サイドバー70 + 余裕
    minimumSize: Size(600, 800),
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
    await windowManager.setMinimumSize(const Size(600, 800));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  });

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
      title: 'Drawing App',
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
  final TransformationController _transformationController = TransformationController();

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
      ..translate(0.0, 0.0)  // 左上座標を(0,0)に固定
      ..scale(1.0);          // スケールは1.0（キャンバス原寸）
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drawingProvider = context.read<DrawingProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drawing App'),
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
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(2000),
                        minScale: 0.1,
                        maxScale: 5.0,
                        panEnabled: true,
                        scaleEnabled: true,
                        trackpadScrollCausesScale: true,
                        transformationController: _transformationController,
                        child: Padding(
                          padding: const EdgeInsets.all(500.0), // 広大な余白でズームアウト対応
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
                            child: const DrawingCanvas(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 固定サイドバー
                  Container(
                    width: 70,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      border: Border(left: BorderSide(color: Colors.grey[300]!)),
                    ),
                    child: const ToolSidebar(),
                  ),
                ],
              ),
            ),
            // 固定スライダーパネル
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 4, offset: const Offset(0, -2))
                ],
              ),
              child: const DrawingControls(),
            ),
          ],
        ),
      ),
    );
  }
}