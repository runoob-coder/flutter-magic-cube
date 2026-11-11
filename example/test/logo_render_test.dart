import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';

/// The default logo is vector-drawn (no font dependency); require a
/// non-empty image with transparent corners.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renderFlutterLogoToImage 默认画出一个非空、背景透明的标志', () async {
    const int size = 128;
    final ui.Image image = await renderFlutterLogoToImage(
      size: size.toDouble(),
    );
    expect(image.width, size);
    expect(image.height, size);

    final ByteData bytes = (await image.toByteData())!;
    int opaque = 0;
    for (int i = 0; i < size * size; i++) {
      if (bytes.getUint8(i * 4 + 3) > 16) opaque++;
    }
    image.dispose();

    expect(opaque, greaterThan(200));
    expect(opaque, lessThan(size * size * 0.85));

    expect(bytes.getUint8(3), lessThanOrEqualTo(16));
    expect(bytes.getUint8((size - 1) * 4 + 3), lessThanOrEqualTo(16));
    expect(bytes.getUint8(((size - 1) * size) * 4 + 3), lessThanOrEqualTo(16));
    expect(bytes.getUint8(((size * size) - 1) * 4 + 3), lessThanOrEqualTo(16));
  });
}
