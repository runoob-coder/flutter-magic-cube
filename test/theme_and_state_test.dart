import 'dart:ui' show Color;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('主题相等性', () {
    const CubeTheme base = CubeTheme();

    // One field per variant: painter caches key on the theme object, so
    // any field missing from == reuses another theme's cached picture.
    final Map<String, CubeTheme> variants = <String, CubeTheme>{
      'up': const CubeTheme(up: Color(0xFF010203)),
      'down': const CubeTheme(down: Color(0xFF010203)),
      'left': const CubeTheme(left: Color(0xFF010203)),
      'right': const CubeTheme(right: Color(0xFF010203)),
      'front': const CubeTheme(front: Color(0xFF010203)),
      'back': const CubeTheme(back: Color(0xFF010203)),
      'body': const CubeTheme(body: Color(0xFF010203)),
      'gap': const CubeTheme(gap: 0.5),
      'stickerScale': const CubeTheme(stickerScale: 0.5),
      'stickerRadius': const CubeTheme(stickerRadius: 0.9),
      'stickerThickness': const CubeTheme(stickerThickness: 0.1),
      'stickerSideShade': const CubeTheme(stickerSideShade: 0.1),
      'stickerShadowOpacity': const CubeTheme(stickerShadowOpacity: 0.9),
      'stickerShadowOffset': const CubeTheme(stickerShadowOffset: 0.3),
      'stickerShadowBlur': const CubeTheme(stickerShadowBlur: 4),
      'outerCornerRadius': const CubeTheme(outerCornerRadius: 0.2),
      'bodyCornerRadius': const CubeTheme(bodyCornerRadius: 0.9),
      'ambient': const CubeTheme(ambient: 0.2),
      'diffuse': const CubeTheme(diffuse: 0.9),
      'stickerAmbient': const CubeTheme(stickerAmbient: 0.2),
      'stickerDiffuse': const CubeTheme(stickerDiffuse: 0.9),
    };

    test('改动任意一个字段都不会被判为相等的默认主题', () {
      variants.forEach((String name, CubeTheme variant) {
        expect(variant == base, isFalse, reason: '$name 未被纳入相等性判断');
      });
    });

    test('改动任意一个字段都不会被当成同一个缓存键', () {
      final Map<CubeTheme, int> cache = <CubeTheme, int>{base: 0};
      variants.forEach((String name, CubeTheme variant) {
        expect(cache[variant], isNull, reason: '$name 命中了其它主题的缓存条目');
      });
      expect(cache[const CubeTheme()], 0);
    });

    test('相等性覆盖 logo 与 lighting 四个字段（共 25 个字段）', () async {
      final ui.Image logo = await renderFlutterLogoToImage(size: 4);
      addTearDown(logo.dispose);
      const CubeTheme base = CubeTheme();
      final Map<String, CubeTheme> rest = <String, CubeTheme>{
        'logoFace': const CubeTheme(logoFace: 3),
        'logoScale': const CubeTheme(logoScale: 0.5),
        'lighting': const CubeTheme(lighting: false),
        'centerLogo': CubeTheme(centerLogo: logo),
      };
      rest.forEach((String name, CubeTheme variant) {
        expect(variant == base, isFalse, reason: '$name 未被纳入相等性判断');
        expect(
          <CubeTheme, int>{base: 0}[variant],
          isNull,
          reason: '$name 命中了默认主题的缓存条目',
        );
      });
      expect(variants.length + rest.length, 25);
    });

    test('只有光照参数不同时不再串色', () {
      const CubeTheme dim = CubeTheme(ambient: 0.2, diffuse: 0.1);
      const CubeTheme bright = CubeTheme(ambient: 0.9, diffuse: 0.8);
      expect(dim == bright, isFalse);
      expect(
        const CubeTheme(stickerSideShade: 0.2) ==
            const CubeTheme(stickerSideShade: 0.9),
        isFalse,
      );
    });
  });

  group('魔方状态构造校验', () {
    test('二阶及以上、奇数阶才允许', () {
      expect(() => CubeState(size: 3), returnsNormally);
      expect(() => CubeState(size: 5), returnsNormally);
      expect(() => CubeState(size: 7), returnsNormally);
      expect(CubeState(size: 5).cubies.length, 5 * 5 * 5);
    });

    test('偶数阶与非法的阶数会抛出而不是静默构造', () {
      // asserts vanish in release; an even-sized cube would put its
      // center layer on a half coordinate and break layer conversions.
      expect(() => CubeState(size: 4), throwsArgumentError);
      expect(() => CubeState(size: 6), throwsArgumentError);
      expect(() => CubeState(size: 1), throwsArgumentError);
      expect(() => CubeState(size: 0), throwsArgumentError);
    });

    test('每个状态实例有全局唯一的 id', () {
      // Cache is keyed by state id; identityHashCode can be reused after
      // GC.
      final CubeState a = CubeState();
      final CubeState b = CubeState();
      final CubeState c = CubeState()..applyMove(CubeMove.parse('R'));
      expect(a.id, isNot(b.id));
      expect(b.id, isNot(c.id));
      expect(<int>{a.id, b.id, c.id}.length, 3);
    });
  });
}
