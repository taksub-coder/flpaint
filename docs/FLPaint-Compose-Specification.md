# FLPaint Compose 完全詳細仕様書（正式版 v1.0）

**対象**：Jetpack Compose + Kotlin による Android お絵描きアプリ  
**目標**：Android 5.0 (API 21) 〜 最新まで対応し、旧型タブレット（RAM 1〜2GB）でも軽快に動作するプロトタイプを **1週間** で実装可能なレベルに仕様を固定する。

---

## 1. アプリケーション概要

| 項目 | 内容 |
|------|------|
| アプリ名 | FLPaint Compose（候補：FLPaint Lite / 古いタブレット向けFLPaint） |
| 最小SDK | **API 21** (Android 5.0 Lollipop) |
| ターゲットSDK | 最新（35 前後を想定） |
| キャンバス固定サイズ | **768 × 1024 px**（A4縦相当、白背景） |
| 設計思想 | Jetpack Compose + Canvas 直描画（Skia オーバーヘッド排除） |
| APKサイズ目標 | **5〜8MB 以内** |

### 1.1 主要コンセプト

- **3レイヤー**（A / B / C）＋ 表示/非表示・不透明度
- **本格 Lasso 選択変形**（移動・スケール・回転・左右反転）
- **縦書きテキスト**（小さい文字・句読点の位置・長音「ー」→「｜」）
- **トーン** 30% / 60% / 80%（BitmapShader + 45°回転）
- 旧型機でも **60fps 維持** を目指す軽量設計

---

## 2. データモデル（クラス定義）

### 2.1 クラス一覧（テキスト図）

```
┌─────────────────────────────────────────────────────────────────┐
│  enum ToolType                                                    │
│  Pen | Pressure | Eraser | Line | Rect | FillRect | Circle |     │
│  FillCircle | Lasso | Tone30 | Tone60 | Tone80                    │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  enum DrawingLayer   A | B | C                                   │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  enum SelectionHandle                                             │
│  None | Inside | Mirror | CornerTL | CornerTR | CornerBR |       │
│  CornerBL | EdgeTop | EdgeRight | EdgeBottom | EdgeLeft           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  data class Point(x: Float, y: Float, width: Float = 1f)         │
│  ※ pressure は API 26 未満では使わず、width で代用               │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  data class Stroke(                                               │
│    val tool: ToolType,                                            │
│    val color: Int = Color.Black.toArgb(),                        │
│    val width: Float,                                              │
│    val points: List<Point>,          // 空の場合は shape 用       │
│    val layer: DrawingLayer,                                       │
│    val isEraser: Boolean = false,                                 │
│    val eraserAlpha: Float = 1f,     // 0.5f = 半透明消し         │
│    val variableWidth: Boolean = false,                           │
│    val shapeRect: Rect? = null,      // 矩形・円・直線用          │
│    val shapeStart: Offset? = null,  // 直線の始点（end は最後のPoint）│
│    val isFinished: Boolean = true                                │
│  )                                                                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  data class LassoSelection(                                       │
│    val image: ImageBitmap?,                                       │
│    val maskPath: Path,                                            │
│    val bounds: Rect,                                              │
│    var offset: Offset = Offset.Zero,                              │
│    var scaleX: Float = 1f, var scaleY: Float = 1f,               │
│    var rotation: Float = 0f,  // radians                         │
│    val layer: DrawingLayer                                        │
│  )                                                                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  data class Snapshot(                                             │
│    val strokes: List<Stroke>,                                    │
│    val layerAImage: ImageBitmap?, val layerBImage: ImageBitmap?,  │
│    val layerCImage: ImageBitmap?,                                 │
│    val selection: LassoSelection?                                │
│  )                                                                │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 レイヤー状態（ViewModel 側）

| プロパティ | 型 | 説明 |
|------------|-----|------|
| activeLayer | DrawingLayer | 現在描画対象のレイヤー |
| layerVisible | Map<DrawingLayer, Boolean> | 各レイヤー表示 ON/OFF |
| layerOpacity | Map<DrawingLayer, Float> | 0f〜1f |

---

## 3. 機能要件と実装仕様

### 3.1 描画ツール

#### 3.1.1 ペン（通常）

| 項目 | 内容 |
|------|------|
| **仕様** | variableWidth = false のスムージングパス。固定幅で描画。 |
| **実装のポイント** | 入力点列に低域通過フィルタ（factor 0.5〜0.6）をかけ、`quadraticBezierTo` で滑らかにつなぐ。Path は **1本の Stroke ごとに 1 インスタンス** を再利用（`rewind()`）。 |
| **注意するエッジケース** | 1点だけのタップ→半径 width/2 の円を描く。2点のときは lineTo のみ。 |
| **最適化** | Path オブジェクトを ViewModel または Painter 内で保持し `path.rewind()` で再利用。toImageBitmap() は **ストローク描画時には使わない**。 |

#### 3.1.2 筆圧風ペン

| 項目 | 内容 |
|------|------|
| **仕様** | 速度ベースのテーパー＋幅変化（variableWidth = true）。先端・終端で細く、中間で太く。 |
| **実装のポイント** | 点間の時間差から速度を算出し、速度が大きいほど細くする。Catmull-Rom で補間した点列の法線方向に ±width/2 を並べてポリゴン（リボン）を生成し fill 描画。 |
| **注意するエッジケース** | 最初の数点は「入り」テーパー（7〜14px で 1px から太く）、最後は「抜き」テーパーで細くする。点が 2 個以下の場合は通常ペンと同様のフォールバック。 |
| **最適化** | 補間サンプル数は 8〜10 で十分。Path は 1 本用を再利用。 |

#### 3.1.3 消しゴム

| 項目 | 内容 |
|------|------|
| **仕様** | 半透明消し（dstOut, alpha=0.5）と完全消し（alpha=1.0）を **ドラッグごとに交互** にする。または長押しで完全消しに切り替え（オプション）。 |
| **実装のポイント** | Stroke に `isEraser=true`, `eraserAlpha=0.5f or 1f` を付与。描画時は `BlendMode.DST_OUT` と `paint.alpha = eraserAlpha`。次のストローク開始時に前回の eraserAlpha を反転。 |
| **注意するエッジケース** | レイヤー合成時、消しゴムは「そのレイヤー内」でしか効かない。他レイヤーは透過で見えるだけ。 |
| **最適化** | 消しゴムも 1 本の Path でスムージングしてから描画。ImageBitmap の再生成は Undo 時のみ。 |

#### 3.1.4 直線・矩形・円

| 項目 | 内容 |
|------|------|
| **仕様** | ドラッグ開始→終了で 1 本の Stroke。直線は points[0], points[1]、矩形・円は shapeRect に格納。 |
| **実装のポイント** | ツールが Line/Rect/FillRect/Circle/FillCircle のとき、pointerInput の down で shapeStart、move で shapeEnd を更新し、up で Stroke を確定。Rect は left=min(start.x,end.x) などで計算。 |
| **注意するエッジケース** | 幅 0 や高さ 0 の Rect（クリックのみ）は最小サイズ 1px にクランプするか、ストロークを追加しない。 |
| **最適化** | 図形は Path を毎回 new せず、確定時に 1 回だけ drawRect/drawOval/drawLine で描画し、Stroke として points または shapeRect のみ保持。 |

#### 3.1.5 トーン 30% / 60% / 80%

| 項目 | 内容 |
|------|------|
| **仕様** | 2×2 のチェック模様 Bitmap を 45° 回転した BitmapShader で塗りつぶし。ドラッグで指定矩形範囲に適用。 |
| **実装のポイント** | 起動時に 30%/60%/80% 用の Bitmap を **1 回だけ** 生成（2×2 または 4×4 で十分）。Matrix.preRotate(45f) で Shader に設定。Tone ツールのドラッグ終了で、shapeRect を Tone 用 Stroke として追加（描画時はその Rect に Shader を fill）。 |
| **注意するエッジケース** | トーンは「白地に黒ドット」なので、既存描画の上に乗せる場合は BlendMode を考慮（SRC_OVER で黒部分だけ描く）。 |
| **最適化** | **静的 Shader をアプリ起動時に 1 回だけ生成** し、Composable または ViewModel で保持。PictureRecorder/toImageBitmap はトーン描画では使わない。 |

#### 3.1.6 投げ縄（Lasso）選択

| 項目 | 内容 |
|------|------|
| **仕様** | 指で閉じたパスを描き、その内側を選択。選択後は画像として切り出し、変形可能に。 |
| **実装のポイント** | Lasso ツール時は pointerInput で点列を貯め、up 時に Path を閉じ、bounds を計算。bounds が 2px 未満の場合は無視。選択領域を **PictureRecorder + clipPath** で描画し toImageBitmap で切り出し。LassoSelection に image, maskPath, bounds を保存。 |
| **注意するエッジケース** | 自己交差パスは Android の Path.fillType で EVEN_ODD または WINDING を指定。点が 3 未満の場合は選択しない。 |
| **最適化** | 切り出し解像度は bounds そのまま（または 1x）。必要なら変形プレビュー時のみダウンサンプル。 |

---

### 3.2 レイヤー管理

| 項目 | 内容 |
|------|------|
| **仕様** | 3 レイヤー（A / B / C）。各レイヤー：表示/非表示、不透明度 0〜100%。アクティブレイヤーのみに新規描画が追加される。 |
| **実装のポイント** | ViewModel に `activeLayer`, `layerVisible[Layer]`, `layerOpacity[Layer]` を保持。描画時は下から A→B→C の順に、visible かつ opacity>0 のレイヤーだけ `saveLayer(alpha)` して合成。 |
| **注意するエッジケース** | レイヤー画像（baseImage）が null の場合は白背景として扱う。不透明度 0 のレイヤーは描画ループでスキップ。 |
| **最適化** | レイヤー画像は「インポート画像＋確定したストロークの合成」を保持。毎フレーム全ストロークを描かない（後述の「描画パイプライン」参照）。 |

---

### 3.3 選択・変形（Lasso）

| 項目 | 内容 |
|------|------|
| **仕様** | 閉じた投げ縄で領域選択→ハンドル表示（8 箇所＋中央移動＋左右反転）。移動・等倍/非等倍スケール・回転・左右反転。確定でアクティブレイヤーに合成。 |
| **実装のポイント** | ハンドルは LassoSelection の bounds を offset/scale/rotation で変換した四角の 4 頂点＋4 辺中点＋反転ボタン（左上付近）。hitTest でどのハンドルか判定。中央は「中身」ドラッグで移動（offset 更新）。コーナーは scaleX/scaleY、辺は一方だけスケール。回転は 2 本指または専用ハンドルで rotation 更新。反転は scaleX *= -1。確定時は選択画像をマスクしてレイヤー画像に合成し、選択を null に。 |
| **注意するエッジケース** | スケール 0 や極端に小さい値は 0.05 程度にクランプ。選択確定時、元レイヤーの選択領域は「マスクでクリア」してから合成（Porter-Duff clear）。 |
| **最適化** | 変形中は **低解像度プレビュー**（bounds を 1/2 や 1/4 にダウンサンプルした ImageBitmap で描画）を検討。確定時のみフル解像で合成。 |

---

### 3.4 テキスト入力

| 項目 | 内容 |
|------|------|
| **仕様** | ダイアログで多行テキスト入力。フォント：ゴシック/明朝、サイズ S:16 / M:32 / L:64、横/縦。縦書き時は拗音・句読点の位置調整、長音「ー」→「｜」オプション。テキストは Bitmap 化してアクティブレイヤーに貼り付け（Lasso 同様に選択状態で出してもよい）。 |
| **実装のポイント** | ダイアログで TextField + フォント/サイズ/縦横の選択。OK で TextMeasurer（Compose）または Canvas.drawText で Bitmap に描画。縦書きは 1 文字ずつ配置し、`ゃゅょ` 等はオフセットテーブルで右にずらす。句読点は 90° 回転＋オフセット。「ー」は置換で「｜」に。生成した ImageBitmap を LassoSelection として表示し、そのまま移動・確定でレイヤーに合成。 |
| **注意するエッジケース** | 空文字のときは何もしない。非常に長いテキストは maxLines や最大高さで打ち切り。 |
| **最適化** | テキスト Bitmap は必要なサイズだけ生成（レイアウト結果の width/height）。toImageBitmap は 1 回だけ。 |

---

### 3.5 ファイル入出力

| 項目 | 内容 |
|------|------|
| **仕様** | 画像インポート（PNG/JPG）→アクティブレイヤーの背景画像として合成。画像エクスポート（PNG/JPG）→ MediaStore または SAF。透過 PNG は背景白合成オプション。 |
| **実装のポイント** | インポート：SAF または MediaStore で Uri 取得→BitmapFactory.decodeStream。768×1024 に scale してからレイヤー baseImage と合成（既存 base の上に drawBitmap）。エクスポート：全レイヤーを合成した Bitmap を PNG/JPEG でエンコードし、MediaStore または SAF で保存。透過 PNG は白背景で composite してから JPEG 化。 |
| **注意するエッジケース** | 大サイズ画像のインポートは OOM を防ぐため inSampleSize や max width/height で縮小。エクスポート時は Context が null でないか確認。 |
| **最適化** | デコードは Options.inPreferredConfig = RGB_565 や inSampleSize でメモリ削減。エクスポート JPEG は quality 70〜85 で Undo 用スナップショットと兼用可能。 |

---

### 3.6 Undo / Redo

| 項目 | 内容 |
|------|------|
| **仕様** | スナップショット方式。全ストローク＋各レイヤー base 画像＋選択状態。スタック上限 20〜30。 |
| **実装のポイント** | アクション前に `Snapshot(strokes, layerAImage, layerBImage, layerCImage, selection)` を deep copy して undoStack に push。redo 時は現在状態を redoStack に push してから undoStack.pop を restore。undoStack.size > 30 なら removeAt(0)。 |
| **注意するエッジケース** | ImageBitmap のコピーは「同じピクセルで新規 ImageBitmap を生成」する必要がある。選択中に Undo すると選択が消える。 |
| **最適化** | スナップショットの画像は **WebP または quality 70% JPEG** で ByteArray にシリアライズして保持し、復元時だけ decode。メモリを 150MB 以下に抑える。 |

---

### 3.7 その他

| 機能 | 仕様・実装 |
|------|------------|
| **ズーム・パン** | `detectTransformGestures` で scale/pan を検出。offset と scale を state で保持し、Canvas に translate(offset) scale(scale) を適用。scale は 0.1〜5.0 にクランプ。 |
| **クリア** | 全ストローク削除、全レイヤー base 画像 null、選択 null、Undo/Redo スタッククリア。ズーム・パンは左上リセット（scale=1, offset=0）。 |
| **右クリック相当** | 長押しでコンテキストメニュー（選択の切り取り/コピー/削除、レイヤー操作など）。`pointerInput(onLongPress) { }` で表示。 |

---

## 4. UI/UX 構成（Compose）

### 4.1 画面構成（テキスト図）

```
┌──────────────────────────────────────────────────────────────────┐
│  TopAppBar  [ Undo ] [ Redo ] [ Clear ] [ Import ] [ Export ]     │
├─────────────────────────────────────────────────────────┬──────────┤
│                                                         │ ツール   │
│  キャンバス 768×1024                                    │ 縦並び   │
│  (Modifier.pointerInput + Canvas)                      │ 70〜80dp │
│  背景白、周囲はダークグレー                             │ Pen      │
│  InteractiveViewer 相当の offset/scale を state で管理  │ Pressure │
│                                                         │ Eraser   │
│                                                         │ Line     │
│                                                         │ Rect     │
│                                                         │ ...      │
│                                                         │ Lasso    │
│                                                         │ Tone30~80│
├─────────────────────────────────────────────────────────┴──────────┤
│  BottomBar 高さ約 120dp                                             │
│  [ ペン幅 Slider ] [ 消しゴム幅 Slider ] [ レイヤーA/B/C ボタン ]   │
│  各レイヤー：選択・表示ON/OFF・不透明度スライダー（省略可）          │
└──────────────────────────────────────────────────────────────────┘
```

### 4.2 コンポーザブル構成

| コンポーネント | 役割 |
|----------------|------|
| `Scaffold` | 全体土台。topBar, content, bottomBar。 |
| `TopAppBar` | Undo / Redo / Clear / Import / Export。 |
| `Row` (main + sidebar) | `Modifier.weight(1f)` のキャンバスエリアと、固定幅のツールバー。 |
| `Canvas` + `Modifier.pointerInput` | 描画とジェスチャーを同一領域で処理。座標は「キャンバス座標」に変換して ViewModel に渡す。 |
| `DrawingViewModel` | strokes, layers, selection, undo/redo, ツール状態。`mutableStateListOf` / `mutableStateOf` で保持。 |

### 4.3 ジェスチャーと座標変換

- キャンバスは `BoxWithConstraints` または固定 768×1024 の外側に `scale`/`translate` をかけた `Canvas` を配置。
- タッチ座標は **逆変換**（offset/scale の逆）で「キャンバス論理座標」に変換してから ViewModel に渡す。
- 2 本指：`detectTransformGestures` で `pan`, `zoom` を検出し、offset と scale を更新。1 本指のドラッグは描画または選択ハンドル操作に振り分ける（選択ありなら hitTest を先に実行）。

---

## 5. データフロー

### 5.1 描画パイプライン（テキスト図）

```
  [ ユーザー入力 ]
        │
        ▼
  pointerInput (down/move/up)
        │
        ├─ 2本指 → offset/scale 更新 (state)
        ├─ Lasso ツール → 点列追加 or 選択ハンドル操作
        └─ その他ツール → ViewModel.startStroke / addPoint / endStroke
                                │
                                ▼
  ViewModel (strokes, currentStroke, selection, layerImages)
        │
        ▼
  Canvas 描画 (onDraw)
        │
        ├─ 各レイヤー：baseImage を draw (opacity)
        ├─ 各レイヤー：そのレイヤーの strokes を draw (Pen/Shape/Tone/Eraser)
        ├─ 選択中：選択画像を transform して draw
        └─ Lasso 下書き：Path を stroke で draw
```

### 5.2 状態の流れ（表）

| イベント | ViewModel の変更 |
|----------|------------------|
| タッチダウン（描画） | startNewStroke(canvasPoint) → currentStroke 追加、undo 用 saveState() |
| タッチムーブ（描画） | addPoint(canvasPoint) → currentStroke.points に追加 |
| タッチアップ（描画） | endStroke() → currentStroke を確定、variableWidth ならテーパー適用 |
| タッチアップ（Lasso） | finishLasso() → 領域切り出し → selection に設定 |
| 選択ハンドルドラッグ | translateSelection(delta) / setSelectionScale(...) / setSelectionRotation(...) |
| 確定ボタン or ツール変更 | commitSelection() → レイヤー画像に合成、selection = null |
| Undo | restore(undoStack.pop()); redoStack.push(current) |
| Redo | restore(redoStack.pop()); undoStack.push(current) |

---

## 6. 主要アルゴリズム（簡易）

### 6.1 スムージングパス

- 入力: `List<Point>`
- 低域通過: `p_filtered[i] = lerp(p_filtered[i-1], p_raw[i], 0.5〜0.6)`
- 出力: `path.moveTo(p0); for (i in 1..n-2) quadraticBezierTo(p[i], mid(p[i], p[i+1])); lineTo(p[n-1])`

### 6.2 可変幅リボン（筆圧風）

- Catmull-Rom で補間点列を生成（サンプル数 8〜10）。
- 各点で進行方向の法線を求め、±width/2 の左右点をリストに追加。
- 左列＋右列を逆順でつなぎ、close() した Path を fill。

### 6.3 トーンシェーダー

- 2×2 Bitmap: 30%=1 ドット、60%=2 ドット（対角）、80%=3 ドット。
- BitmapShader(TileMode.REPEAT) + Matrix.setRotate(45f) で 45° 回転。
- 起動時に 3 種類を 1 回だけ生成して保持。

### 6.4 Lasso マスク

- Path を閉じ、getBounds() で矩形取得。
- PictureRecorder + Canvas.clipPath(path) でレイヤー内容を描画し、toImageBitmap で切り出し。
- 確定時: レイヤー Canvas で maskPath に BlendMode.CLEAR を描画してから、選択画像を offset/scale/rotation で描画。

### 6.5 縦書きテキスト

- 1 文字ずつ TextMeasurer で計測。拗音・句読点はオフセットテーブル（右・上にずらす）と回転（句読点 90°）を適用。
- 「ー」「ｰ」は「｜」に置換。レイアウト結果を 1 枚の ImageBitmap に描画。

---

## 7. 非機能要件と旧型機向け最適化

### 7.1 目標値

| 項目 | 目標 |
|------|------|
| 描画 | 60fps（最低 30fps） |
| メモリ | ピーク 150MB 以下 |
| APK | 8MB 以下 |
| 起動 | 2 秒以内 |

### 7.2 最適化チェックリスト

1. **ImageBitmap / toImageBitmap**  
   ストローク描画のたびに使わない。Lasso 切り出し・テキスト・インポート・Undo スナップショット・レイヤー合成時のみ。

2. **Path の再利用**  
   スムージングパス・リボン・図形用に 1 本ずつ `Path()` を保持し、`rewind()` でクリアしてから再利用。

3. **トーン**  
   静的 BitmapShader を起動時に 1 回だけ生成し、Composable または ViewModel で保持。

4. **選択変形プレビュー**  
   変形中は選択画像を 1/2 や 1/4 にダウンサンプルしたコピーで描画し、確定時のみフル解像で合成。

5. **Undo スタック**  
   スナップショットの画像は WebP または quality 70% JPEG の ByteArray で保持。復元時だけ decode。

6. **メインスレッド**  
   ジェスチャー処理と描画は Main で完結。画像デコード・エンコードのみ Background で実行し、結果を state に反映。

---

## 8. 技術スタック（推奨）

| 項目 | 推奨 |
|------|------|
| 言語 | Kotlin 2.x |
| UI | Jetpack Compose 1.6.x 〜 1.7.x（API 21 対応版） |
| 描画 | Compose Canvas + android.graphics.* (Path, Paint, Bitmap, BitmapShader) |
| 状態 | ViewModel + mutableStateOf / mutableStateListOf / SnapshotStateList |
| 権限 | Accompanist Permissions または ActivityResultContracts |
| 画像読み込み | BitmapFactory（軽量）。必要なら Coil を R8 で tree-shake。 |
| 保存 | MediaStore + SAF (API 21〜) |

---

## 9. エッジケース一覧（実装時の注意）

| 状況 | 対応 |
|------|------|
| キャンバス外タッチ | 論理座標に変換後、0〜768, 0〜1024 にクランプするか無視。 |
| 選択中にツール変更 | 選択を確定（commit）してからツール切り替え。 |
| Undo で選択が消える | スナップショットに selection を含め、restore で復元。 |
| レイヤー画像が null | 白で描画またはスキップ。 |
| Lasso 点が 3 未満 | 選択しない。Lasso 下書きのみクリア。 |
| 図形の幅 0・高さ 0 | 1px にクランプするか、Stroke を追加しない。 |
| 縦書きの空行 | 改行のみの行は高さを 1em 程度確保。 |
| 大サイズ画像インポート | inSampleSize や maxWidth/Height で縮小してから 768×1024 にフィット。 |

---

## 10. 今後拡張（Nice to have）

- ブラシプリセット
- レイヤー名変更
- プロジェクト保存（.flpaint 形式）
- API 26 以降でのスタイラス筆圧（MotionEvent.getPressure()）

---

## 11. 1 週間プロトタイプの実装順序

| 日 | 内容 |
|----|------|
| 1 | プロジェクト作成、キャンバス 768×1024 表示、ズーム・パン、ペン（通常）のストローク描画、ViewModel + strokes 管理。 |
| 2 | 直線・矩形・円、消しゴム、筆圧風ペン（可変幅リボン）、トーン 30/60/80（静的 Shader）。 |
| 3 | 3 レイヤー（表示/非表示・不透明度・アクティブ）、レイヤー画像の合成表示。 |
| 4 | Lasso：点列→Path→切り出し→LassoSelection、ハンドル表示、移動・スケール・回転・反転、確定でレイヤーに合成。 |
| 5 | Undo/Redo（スナップショット＋画像のシリアライズ）、クリア、インポート/エクスポート（SAF/MediaStore）。 |
| 6 | テキストダイアログ、横書き/縦書き、Bitmap 化して Lasso 同様に配置・確定。 |
| 7 | バグ修正、パフォーマンス確認（Path 再利用・Undo 圧縮）、右クリック相当の長押しメニュー。 |

---

---

## 12. 既存 FLPaint（Flutter）との対応（参照用）

本プロジェクトの Flutter 版（`lib/`）と Compose 版で概念が同じ部分の対応表。実装時の参照用。

| Flutter (Dart) | Compose (Kotlin) |
|----------------|------------------|
| `DrawnLine` | `Stroke` |
| `Point(offset, width)` | `Point(x, y, width)` |
| `DrawingLayer.layerA/B/C` | `DrawingLayer.A/B/C` |
| `LassoSelection` (image, maskPath, baseRect, translation, scaleX/Y, rotation) | `LassoSelection` 同様（bounds, offset, scaleX/Y, rotation） |
| `DrawingProvider` (ChangeNotifier) | `DrawingViewModel` (StateFlow / mutableStateOf) |
| `_DrawingSnapshot` | `Snapshot`（strokes + layer images + selection） |
| `_buildSmoothPath` + `_lowPassFilter` + `quadraticBezierTo` | 低域通過 + quadraticBezierTo（§6.1） |
| `_buildVariableWidthRibbon` + Catmull-Rom | 可変幅リボン（§6.2） |
| `_tone30Shader` 等（ImageShader + 45°） | BitmapShader + Matrix.setRotate(45f)（§6.3） |
| `DrawingCanvas` + `CustomPaint` + `Listener`/`GestureDetector` | `Canvas` + `Modifier.pointerInput` |
| `InteractiveViewer` + `TransformationController` | `detectTransformGestures` + offset/scale state |
| キャンバス 768×1024、padding で余白 | 同様 768×1024、scale/translate でズーム・パン |

---

**以上で「FLPaint Compose 完全詳細仕様書」とする。この仕様書に従えば、Jetpack Compose + Kotlin で 1 週間程度のプロトタイプ実装が可能である。**
