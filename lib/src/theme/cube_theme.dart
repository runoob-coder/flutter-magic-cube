import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/cubie.dart';

/// Distinguishes an omitted argument from an explicit null that clears the
/// logo, which ?? cannot do.
const Object _kUnsetLogo = Object();

class CubeTheme {
  const CubeTheme({
    this.up = const Color(0xFFF5F5F5),
    this.down = const Color(0xFFFFD500),
    this.left = const Color(0xFFFF6C00),
    this.right = const Color(0xFFC41E3A),
    this.front = const Color(0xFF009E60),
    this.back = const Color(0xFF0051BA),
    this.body = const Color(0xFF141414),
    this.gap = 0.055,
    this.stickerScale = 0.84,
    this.stickerRadius = 0.3,
    this.bodyCornerRadius = 0.15,
    this.stickerThickness = 0.04,
    this.stickerSideShade = 0.72,
    this.stickerShadowOpacity = 0.34,
    this.stickerShadowOffset = 0.1,
    this.stickerShadowBlur = 0,
    this.outerCornerRadius = 0.5,
    this.ambient = 0.62,
    this.diffuse = 0.42,
    this.stickerAmbient = 0.66,
    this.stickerDiffuse = 0.4,
    this.centerLogo,
    this.logoFace = kFaceUp,
    this.logoScale = 0.75,
    this.lighting = true,
  });

  const CubeTheme.flat()
    : this(stickerThickness: 0, stickerSideShade: 1, stickerShadowOpacity: 0);

  const CubeTheme.classic() : this();

  const CubeTheme.pastel()
    : this(
        up: const Color(0xFFF7F3E8),
        down: const Color(0xFFF6D36B),
        left: const Color(0xFFFFA987),
        right: const Color(0xFFE4737B),
        front: const Color(0xFF8FD1A8),
        back: const Color(0xFF7FA8DC),
        body: const Color(0xFF2B2B2B),
      );

  const CubeTheme.neon()
    : this(
        up: const Color(0xFFEDEDED),
        down: const Color(0xFFFFE94A),
        left: const Color(0xFFFF7A2F),
        right: const Color(0xFFFF2D55),
        front: const Color(0xFF17E06B),
        back: const Color(0xFF2E7BFF),
        body: const Color(0xFF0C0C0E),
        gap: 0.07,
        stickerScale: 0.8,
        stickerRadius: 0.34,
        stickerThickness: 0.055,
        stickerShadowOpacity: 0.4,
        outerCornerRadius: 0.45,
        ambient: 0.58,
        diffuse: 0.5,
        stickerAmbient: 0.6,
        stickerDiffuse: 0.48,
      );

  final Color up;

  final Color down;

  final Color left;

  final Color right;

  final Color front;

  final Color back;

  final Color body;

  /// Gap between cubies, in cubie-pitch units (1 = one cubie).
  final double gap;

  final double stickerScale;

  /// Corner radius as a fraction of the sticker half-width.
  final double stickerRadius;

  /// Sticker lift along the face normal, in cubie-pitch units. Clamped to
  /// maxStickerThickness so it cannot cover gaps or break the outline; 0
  /// returns to flat stickers.
  final double stickerThickness;

  static const double maxStickerThickness = 0.15;

  static const double maxStickerShadowOffset = 0.35;

  final double stickerSideShade;

  final double stickerShadowOpacity;

  final double stickerShadowOffset;

  /// Blur costs a Gaussian pass per sticker; keep 0 on low-end devices and
  /// Web.
  final double stickerShadowBlur;

  final double outerCornerRadius;

  /// Rounds all non-exterior cubie corners. The clipped quarter-discs are
  /// backed by a darker plastic fillet, so rounding never exposes the page
  /// background at the junctions between cubies. 0 disables rounding.
  final double bodyCornerRadius;

  final double ambient;

  final double diffuse;

  final double stickerAmbient;

  final double stickerDiffuse;

  /// Printed on a sticker, so it follows that cubie. The caller owns the
  /// image; CubeTheme does not dispose it.
  final ui.Image? centerLogo;

  final int logoFace;

  final double logoScale;

  /// Shading uses a view-space light direction; disable it to keep colors
  /// constant while the cube or a layer turns.
  final bool lighting;

  /// Ordered right, left, up, down, front, back (see kFaceRight...kFaceBack).
  List<Color> get faceColors => <Color>[right, left, up, down, front, back];

  /// null means keep the current value; use copyWith(centerLogo: null) to
  /// clear the logo.
  CubeTheme withLogo({ui.Image? centerLogo, int? logoFace, double? logoScale}) {
    if (centerLogo == null && logoFace == null && logoScale == null) {
      return this;
    }
    return copyWith(
      centerLogo: centerLogo ?? this.centerLogo,
      logoFace: logoFace ?? this.logoFace,
      logoScale: logoScale ?? this.logoScale,
    );
  }

  CubeTheme copyWith({
    Color? up,
    Color? down,
    Color? left,
    Color? right,
    Color? front,
    Color? back,
    Color? body,
    double? gap,
    double? stickerScale,
    double? stickerRadius,
    double? stickerThickness,
    double? stickerSideShade,
    double? stickerShadowOpacity,
    double? stickerShadowOffset,
    double? stickerShadowBlur,
    double? outerCornerRadius,
    double? bodyCornerRadius,
    double? ambient,
    double? diffuse,
    double? stickerAmbient,
    double? stickerDiffuse,
    bool? lighting,
    Object? centerLogo = _kUnsetLogo,
    int? logoFace,
    double? logoScale,
  }) {
    return CubeTheme(
      up: up ?? this.up,
      down: down ?? this.down,
      left: left ?? this.left,
      right: right ?? this.right,
      front: front ?? this.front,
      back: back ?? this.back,
      body: body ?? this.body,
      gap: gap ?? this.gap,
      stickerScale: stickerScale ?? this.stickerScale,
      stickerRadius: stickerRadius ?? this.stickerRadius,
      stickerThickness: stickerThickness ?? this.stickerThickness,
      stickerSideShade: stickerSideShade ?? this.stickerSideShade,
      stickerShadowOpacity: stickerShadowOpacity ?? this.stickerShadowOpacity,
      stickerShadowOffset: stickerShadowOffset ?? this.stickerShadowOffset,
      stickerShadowBlur: stickerShadowBlur ?? this.stickerShadowBlur,
      outerCornerRadius: outerCornerRadius ?? this.outerCornerRadius,
      bodyCornerRadius: bodyCornerRadius ?? this.bodyCornerRadius,
      ambient: ambient ?? this.ambient,
      diffuse: diffuse ?? this.diffuse,
      stickerAmbient: stickerAmbient ?? this.stickerAmbient,
      stickerDiffuse: stickerDiffuse ?? this.stickerDiffuse,
      centerLogo: identical(centerLogo, _kUnsetLogo)
          ? this.centerLogo
          : centerLogo as ui.Image?,
      logoFace: logoFace ?? this.logoFace,
      logoScale: logoScale ?? this.logoScale,
      lighting: lighting ?? this.lighting,
    );
  }

  /// Every rendering field must participate: painters key their caches on
  /// this object, so a false equality would reuse another theme's picture.
  @override
  bool operator ==(Object other) =>
      other is CubeTheme &&
      up == other.up &&
      down == other.down &&
      left == other.left &&
      right == other.right &&
      front == other.front &&
      back == other.back &&
      body == other.body &&
      gap == other.gap &&
      stickerScale == other.stickerScale &&
      stickerRadius == other.stickerRadius &&
      stickerThickness == other.stickerThickness &&
      stickerSideShade == other.stickerSideShade &&
      stickerShadowOpacity == other.stickerShadowOpacity &&
      stickerShadowOffset == other.stickerShadowOffset &&
      stickerShadowBlur == other.stickerShadowBlur &&
      outerCornerRadius == other.outerCornerRadius &&
      bodyCornerRadius == other.bodyCornerRadius &&
      ambient == other.ambient &&
      diffuse == other.diffuse &&
      stickerAmbient == other.stickerAmbient &&
      stickerDiffuse == other.stickerDiffuse &&
      lighting == other.lighting &&
      centerLogo == other.centerLogo &&
      logoFace == other.logoFace &&
      logoScale == other.logoScale;

  /// Object.hash accepts at most 20 arguments.
  @override
  int get hashCode => Object.hash(
    Object.hash(up, down, left, right, front, back, body),
    Object.hash(
      gap,
      stickerScale,
      stickerRadius,
      stickerThickness,
      stickerSideShade,
      stickerShadowOpacity,
      stickerShadowOffset,
      stickerShadowBlur,
      outerCornerRadius,
      bodyCornerRadius,
    ),
    Object.hash(
      ambient,
      diffuse,
      stickerAmbient,
      stickerDiffuse,
      lighting,
      centerLogo,
      logoFace,
      logoScale,
    ),
  );
}
