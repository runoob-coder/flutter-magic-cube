import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';

/// Dumps one transparent RGBA PNG per cube state into `screenshots/`.
///
/// The canvas is deliberately left clear: no background paint is applied, so
/// the PNGs can be dropped onto any page colour. One case per test on
/// purpose: a second `toImage()` inside the same test never returns on this
/// machine, so every test rasterizes exactly once.
/// Run `flutter test test/screenshot_dump_test.dart` to refresh the images.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Directory output = _screenshotDirectory();
  output.createSync(recursive: true);

  tearDown(() {
    CubePainter.disposeCaches();
    CubeScene.disposeSceneCache();
  });

  for (final _Shot shot in _shots) {
    test('导出 ${shot.label} -> ${shot.fileName}', () async {
      final _Frame frame = await shot.frame();
      final _Raster raster = await _rasterize(frame);
      final File file = File('${output.path}/${shot.fileName}');
      await file.writeAsBytes(raster.png, flush: true);

      expect(file.existsSync(), isTrue, reason: '截图没有写到磁盘');
      expect(file.lengthSync(), raster.png.length);
      expect(raster.png.length, greaterThan(1024));
      expect(raster.png.sublist(0, 8), const <int>[
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ], reason: '文件必须是 PNG');
      expect(
        raster.opaquePixels,
        greaterThan((_side * _side * 0.05).round()),
        reason: '画面几乎没有不透明像素，魔方没有被画出来',
      );
      // A close-up shot can legitimately fill the canvas; all other frames
      // must keep clear margins, which proves no background was painted.
      if (shot.expectTransparentMargins) {
        expect(
          raster.transparentPixels,
          greaterThan((_side * _side * 0.05).round()),
          reason: '画布被铺满了，说明又画上了背景',
        );
        expect(
          raster.transparentCorners,
          greaterThanOrEqualTo(2),
          reason: '画布四角应保持透明',
        );
      }
      expect(
        raster.distinctColors,
        greaterThan(8),
        reason: '画面缺少贴纸配色，可能只画出了背景',
      );
      stdout.writeln('[screenshot] ${file.path}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}

const int _side = 480;

class _Frame {
  const _Frame({
    this.state,
    this.theme = const CubeTheme(),
    this.yaw = MagicCubeController.defaultYaw,
    this.pitch = MagicCubeController.defaultPitch,
    this.view,
    this.turn,
    this.zoom = 1,
  });

  final CubeState? state;

  final CubeTheme theme;

  final double yaw;

  final double pitch;

  /// Non-null for free poses (flipped past a pole or rolled); `CubeScene`
  /// prefers it over yaw/pitch.
  final Mat3? view;

  final CubeTurn? turn;

  final double zoom;
}

class _Shot {
  const _Shot(
    this.fileName,
    this.label,
    this.frame, {
    this.expectTransparentMargins = true,
  });

  final String fileName;

  final String label;

  final FutureOr<_Frame> Function() frame;

  /// False only for the close-up: it leaves ~4.8% clear pixels, below the
  /// generic margin threshold.
  final bool expectTransparentMargins;
}

class _Raster {
  const _Raster({
    required this.png,
    required this.opaquePixels,
    required this.transparentPixels,
    required this.transparentCorners,
    required this.distinctColors,
  });

  final Uint8List png;

  final int opaquePixels;

  final int transparentPixels;

  final int transparentCorners;

  final int distinctColors;
}

final List<_Shot> _shots = <_Shot>[
  _Shot('01_solved_default.png', '复原态 · 默认视角', () => const _Frame()),
  _Shot(
    '02_solved_front.png',
    '复原态 · 正视',
    () => const _Frame(yaw: 0, pitch: 0),
  ),
  _Shot(
    '03_solved_top.png',
    '复原态 · 俯视',
    () => const _Frame(yaw: 0.2, pitch: 1.15),
  ),
  _Shot(
    '04_solved_flipped.png',
    '复原态 · 翻过极点',
    () => _Frame(
      yaw: 0.35,
      pitch: 2.1,
      view: Mat3.fromViewAngles(yaw: 0.35, pitch: 2.1),
    ),
  ),
  _Shot('05_after_r.png', '单步 R', () => _Frame(state: _after('R'))),
  _Shot(
    '06_after_sexy_move.png',
    "R U R' U' 序列",
    () => _Frame(state: _after("R U R' U'")),
  ),
  _Shot(
    '07_scrambled_20.png',
    '20 步打乱',
    () => _Frame(state: _scrambled(length: 20)),
  ),
  _Shot(
    '08_turning_u_45.png',
    '顶层 U 转动 45°',
    () => const _Frame(
      turn: CubeTurn(axis: CubeAxis.y, layer: 2, angle: math.pi / 4),
    ),
  ),
  _Shot(
    '09_turning_m_60.png',
    '中层转动 60°',
    () => const _Frame(
      turn: CubeTurn(axis: CubeAxis.y, layer: 1, angle: math.pi / 3),
    ),
  ),
  _Shot(
    '10_turning_r_120.png',
    '右层转动 120°',
    () => const _Frame(
      turn: CubeTurn(axis: CubeAxis.x, layer: 2, angle: 2 * math.pi / 3),
    ),
  ),
  _Shot(
    '11_whole_cube_x_35.png',
    '整体转动 35°',
    () => const _Frame(
      turn: CubeTurn(axis: CubeAxis.x, layer: 1, angle: 0.61, wholeCube: true),
    ),
  ),
  _Shot(
    '12_scrambled_turning.png',
    '打乱态 + 顶层转动中',
    () => _Frame(
      state: _scrambled(length: 12, seed: 41),
      turn: const CubeTurn(axis: CubeAxis.y, layer: 2, angle: -math.pi / 5),
    ),
  ),
  _Shot('13_size5_solved.png', '五阶复原', () => _Frame(state: CubeState(size: 5))),
  _Shot(
    '14_size5_scrambled.png',
    '五阶打乱',
    () => _Frame(state: _scrambled(size: 5, length: 12)),
  ),
  _Shot('15_size7_solved.png', '七阶复原', () => _Frame(state: CubeState(size: 7))),
  _Shot(
    '16_theme_flat.png',
    '平面贴纸主题',
    () => const _Frame(theme: CubeTheme.flat()),
  ),
  _Shot(
    '17_theme_pastel.png',
    '柔和配色主题',
    () => const _Frame(theme: CubeTheme.pastel()),
  ),
  _Shot(
    '18_theme_neon.png',
    '霓虹配色主题',
    () => const _Frame(theme: CubeTheme.neon()),
  ),
  _Shot(
    '19_no_lighting.png',
    '关闭光照',
    () => const _Frame(theme: CubeTheme(lighting: false)),
  ),
  _Shot(
    '20_square_corners.png',
    '全直角外框',
    () => const _Frame(
      theme: CubeTheme(outerCornerRadius: 0, bodyCornerRadius: 0),
    ),
  ),
  _Shot('21_center_logo.png', '中心块 logo', () async {
    final ui.Image logo = await _centerLogo();
    addTearDown(logo.dispose);
    return _Frame(
      theme: CubeTheme(centerLogo: logo, logoFace: kFaceUp, logoScale: 0.9),
    );
  }),
  _Shot(
    '22_zoom_in.png',
    '放大特写',
    () => const _Frame(zoom: 1.35),
    expectTransparentMargins: false,
  ),

  // Fixed notation patterns: repeatable states, unlike random scrambles.
  _Shot(
    '23_pattern_half_turns.png',
    '六面半转图案',
    () => _Frame(state: _after('R2 L2 U2 D2 F2 B2')),
  ),
  _Shot(
    '24_pattern_slice_half_turns.png',
    '中层半转图案',
    () => _Frame(state: _after('M2 E2 S2')),
  ),
  _Shot(
    '25_pattern_oll_cross.png',
    '顶面十字 OLL',
    () => _Frame(state: _after("F R U R' U' F'")),
  ),
  _Shot(
    '26_pattern_sune.png',
    'Sune OLL',
    () => _Frame(state: _after("R U R' U R U2 R'")),
  ),
  _Shot(
    '27_pattern_t_oll.png',
    'T 形 OLL',
    () => _Frame(state: _after("R U R' U' R' F R F'")),
  ),
  _Shot(
    '28_pattern_sexy_x3.png',
    'sexy move ×3',
    () => _Frame(state: _repeated("R U R' U'", 3)),
  ),
  _Shot(
    '29_scrambled_40.png',
    '40 步打乱',
    () => _Frame(state: _scrambled(length: 40, seed: 7)),
  ),
  _Shot(
    '30_partially_solved.png',
    '打乱后回退一半',
    () => _Frame(state: _partiallySolved()),
  ),

  // More camera poses, including a free rotation with roll.
  _Shot('31_view_back.png', '背面视角', () => const _Frame(yaw: 2.6, pitch: 0.35)),
  _Shot(
    '32_view_top_down.png',
    '接近正上方',
    () => const _Frame(yaw: 0.15, pitch: 1.5),
  ),
  _Shot(
    '33_view_rolled.png',
    '自由姿态 · 带滚转',
    () => _Frame(
      yaw: -0.5,
      pitch: 0.5,
      view: Mat3.rotationZ(0.4)
          .multiply(Mat3.fromViewAngles(yaw: -0.5, pitch: 0.5)),
    ),
  ),
  _Shot('34_view_zoom_out.png', '缩小取景', () => const _Frame(zoom: 0.72)),

  // More layers and angles caught mid-turn.
  _Shot(
    '35_turn_f_30.png',
    'F 层转动 30°',
    () => const _Frame(
      turn: CubeTurn(axis: CubeAxis.z, layer: 2, angle: math.pi / 6),
    ),
  ),
  _Shot(
    '36_turn_l_150.png',
    'L 层转动 150°',
    () => const _Frame(
      turn: CubeTurn(axis: CubeAxis.x, layer: 0, angle: 5 * math.pi / 6),
    ),
  ),
  _Shot(
    '37_turn_d_135.png',
    'D 层转动 135°',
    () => const _Frame(
      turn: CubeTurn(axis: CubeAxis.y, layer: 0, angle: 3 * math.pi / 4),
    ),
  ),
  _Shot(
    '38_turn_u_171.png',
    'U 层接近半转',
    () => const _Frame(
      turn: CubeTurn(axis: CubeAxis.y, layer: 2, angle: 0.95 * math.pi),
    ),
  ),
  _Shot(
    '39_turn_whole_y_45.png',
    '整体 y 转动 45°',
    () => const _Frame(
      turn: CubeTurn(
        axis: CubeAxis.y,
        layer: 1,
        angle: math.pi / 4,
        wholeCube: true,
      ),
    ),
  ),
  _Shot(
    '40_turn_5x5_inner.png',
    '五阶内层转动中',
    () => _Frame(
      state: CubeState(size: 5),
      turn: const CubeTurn(axis: CubeAxis.x, layer: 1, angle: math.pi / 3),
    ),
  ),

  // One-field-at-a-time theme variations.
  _Shot(
    '41_theme_dark.png',
    '深色贴纸主题',
    () => const _Frame(
      theme: CubeTheme(
        up: ui.Color(0xFF3B4252),
        down: ui.Color(0xFF4C566A),
        left: ui.Color(0xFF5E81AC),
        right: ui.Color(0xFFBF616A),
        front: ui.Color(0xFFA3BE8C),
        back: ui.Color(0xFFB48EAD),
        body: ui.Color(0xFFECEFF4),
      ),
    ),
  ),
  _Shot(
    '42_theme_wide_gap.png',
    '加宽缝隙',
    () => const _Frame(theme: CubeTheme(gap: 0.18)),
  ),
  _Shot(
    '43_theme_small_stickers.png',
    '小贴纸',
    () => const _Frame(theme: CubeTheme(stickerScale: 0.62)),
  ),
  _Shot(
    '44_theme_round_stickers.png',
    '大圆角贴纸',
    () => const _Frame(theme: CubeTheme(stickerRadius: 0.95)),
  ),
  _Shot(
    '45_theme_thick_stickers.png',
    '厚贴纸 + 阴影',
    () => const _Frame(
      theme: CubeTheme(
        stickerThickness: 0.12,
        stickerShadowOpacity: 0.6,
        stickerShadowOffset: 0.2,
      ),
    ),
  ),
  _Shot(
    '46_theme_dramatic_light.png',
    '强对比光照',
    () => const _Frame(
      theme: CubeTheme(
        ambient: 0.25,
        diffuse: 0.85,
        stickerAmbient: 0.3,
        stickerDiffuse: 0.85,
      ),
    ),
  ),
  _Shot(
    '47_theme_no_shadow.png',
    '无贴纸阴影',
    () => const _Frame(theme: CubeTheme(stickerShadowOpacity: 0)),
  ),
  _Shot('48_theme_logo_front.png', '正面中心 logo', () async {
    final ui.Image logo = await _centerLogo();
    addTearDown(logo.dispose);
    return _Frame(
      yaw: 0,
      pitch: 0,
      theme: CubeTheme(centerLogo: logo, logoFace: kFaceFront, logoScale: 1),
    );
  }),

  // Higher orders: 11 is the hard limit in validateCubeSize().
  _Shot('49_size9_solved.png', '九阶复原', () => _Frame(state: CubeState(size: 9))),
  _Shot(
    '50_size7_scrambled.png',
    '七阶打乱',
    () => _Frame(state: _scrambled(size: 7, length: 16)),
  ),
];

CubeState _after(String notation, {int size = 3}) =>
    CubeState(size: size)
      ..applyMoves(CubeMove.parseSequence(notation, size: size));

CubeState _repeated(String notation, int times) {
  final CubeState state = CubeState();
  final List<CubeMove> sequence = CubeMove.parseSequence(notation);
  for (int i = 0; i < times; i++) {
    state.applyMoves(sequence);
  }
  return state;
}

CubeState _scrambled({int size = 3, int length = 20, int seed = 2026}) =>
    CubeState(size: size)..applyMoves(
      CubeMove.randomScramble(
        length: length,
        size: size,
        random: math.Random(seed),
      ),
    );

/// A long scramble with its last half undone: a part-way-through solve.
CubeState _partiallySolved() {
  final List<CubeMove> scramble = CubeMove.randomScramble(
    length: 40,
    random: math.Random(77),
  );
  final CubeState state = CubeState()..applyMoves(scramble);
  for (final CubeMove move in scramble.reversed.take(20)) {
    state.applyMove(move.inverse);
  }
  return state;
}

Future<_Raster> _rasterize(_Frame frame) async {
  final ui.Size viewport = ui.Size(_side.toDouble(), _side.toDouble());
  final CubeTheme theme = frame.theme;
  final CubeState state = frame.state ?? CubeState();
  final CubeScene scene = CubeScene(
    state: state,
    turn: frame.turn,
    yaw: frame.yaw,
    pitch: frame.pitch,
    view: frame.view,
    viewport: viewport,
    gap: theme.gap,
    cornerRadius: theme.outerCornerRadius,
    zoom: frame.zoom,
    // An NxN cube grows linearly in world units. Scaling the camera
    // distance and the framing radius together keeps the perspective (and
    // therefore the composition) identical to the 3x3 shot; scaling only
    // fitRadius still crops larger cubes because near faces move closer to
    // the camera.
    cameraDistance: 9.5 * state.size / 3,
    fitRadius: 2.45 * state.size / 3,
    stickerScale: theme.stickerScale,
  );
  expect(scene.drawOrder, isNotEmpty, reason: '场景没有生成任何可绘制的面');

  // No drawPaint here: the recorder starts with a clear canvas, so the PNG
  // keeps a transparent background (including the sticker shadows, which
  // stay semi-transparent instead of blending into a solid colour).
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  CubePainter(scene: scene, theme: theme).paint(canvas, viewport);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(_side, _side);
  picture.dispose();

  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  final ByteData? raw = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  expect(png, isNotNull, reason: 'PNG 编码失败');
  expect(raw, isNotNull, reason: '像素读取失败');

  final Uint8List pixels = raw!.buffer.asUint8List(
    raw.offsetInBytes,
    raw.lengthInBytes,
  );
  int opaquePixels = 0;
  int transparentPixels = 0;
  final Set<int> colors = <int>{};
  for (int i = 0; i < pixels.lengthInBytes; i += 4) {
    final int alpha = pixels[i + 3];
    if (alpha <= 8) {
      transparentPixels++;
      continue;
    }
    if (alpha >= 200) opaquePixels++;
    colors.add(
      ((pixels[i] >> 4) << 8) |
          ((pixels[i + 1] >> 4) << 4) |
          (pixels[i + 2] >> 4),
    );
  }
  int transparentCorners = 0;
  for (final int index in <int>[
    0,
    _side - 1,
    (_side - 1) * _side,
    _side * _side - 1,
  ]) {
    if (pixels[index * 4 + 3] <= 8) transparentCorners++;
  }

  return _Raster(
    png: png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    opaquePixels: opaquePixels,
    transparentPixels: transparentPixels,
    transparentCorners: transparentCorners,
    distinctColors: colors.length,
  );
}

/// A geometric logo built from raw pixels: `flutter test` does not register
/// package fonts, so text would rasterize as a box.
Future<ui.Image> _centerLogo() async {
  const int side = 128;
  final Uint8List pixels = Uint8List(side * side * 4);
  const double center = (side - 1) / 2;
  for (int y = 0; y < side; y++) {
    for (int x = 0; x < side; x++) {
      final double dx = x - center;
      final double dy = y - center;
      final double distance = math.sqrt(dx * dx + dy * dy);
      if (distance > side * 0.44) continue;
      final bool cross =
          (dx.abs() < 10 || dy.abs() < 10) && distance < side * 0.38;
      final int offset = (y * side + x) * 4;
      pixels[offset] = cross ? 0xFF : 0x12;
      pixels[offset + 1] = cross ? 0xFF : 0x2A;
      pixels[offset + 2] = cross ? 0xFF : 0x50;
      pixels[offset + 3] = 0xFF;
    }
  }
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    side,
    side,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// `flutter test` usually starts in the package root; walk up as a fallback
/// when it is launched from a subdirectory. CI can redirect the output with
/// MAGIC_CUBE_SCREENSHOT_DIR.
Directory _screenshotDirectory() {
  final String? override = Platform.environment['MAGIC_CUBE_SCREENSHOT_DIR'];
  if (override != null && override.isNotEmpty) return Directory(override);

  Directory dir = Directory.current;
  for (int i = 0; i < 8; i++) {
    final File pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        Directory('${dir.path}/lib').existsSync() &&
        pubspec.readAsStringSync().contains('name: magic_cube')) {
      return Directory('${dir.path}/screenshots');
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return Directory('screenshots');
}
