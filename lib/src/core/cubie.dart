import 'matrix3.dart';
import 'vector3.dart';

const int kFaceCount = 6;

/// Order matches CubeTheme.faceColors: right, left, up, down, front, back.
const int kFaceRight = 0;
const int kFaceLeft = 1;
const int kFaceUp = 2;
const int kFaceDown = 3;
const int kFaceFront = 4;
const int kFaceBack = 5;

const List<Vec3> kFaceNormals = <Vec3>[
  Vec3(1, 0, 0),
  Vec3(-1, 0, 0),
  Vec3(0, 1, 0),
  Vec3(0, -1, 0),
  Vec3(0, 0, 1),
  Vec3(0, 0, -1),
];

const List<Vec3> kFaceTangentU = <Vec3>[
  Vec3(0, 1, 0),
  Vec3(0, 0, 1),
  Vec3(0, 0, 1),
  Vec3(1, 0, 0),
  Vec3(1, 0, 0),
  Vec3(0, 1, 0),
];

/// Second in-face tangent; satisfies u x v = normal.
const List<Vec3> kFaceTangentV = <Vec3>[
  Vec3(0, 0, 1),
  Vec3(0, 1, 0),
  Vec3(1, 0, 0),
  Vec3(0, 0, 1),
  Vec3(0, 1, 0),
  Vec3(1, 0, 0),
];

/// Stickers record the face each one originally belonged to; they follow
/// the cubie's local orientation, so rotating position and orientation is
/// enough to model a turn.
class Cubie {
  Cubie({required this.position, Mat3? orientation, List<int?>? stickers})
    : orientation = orientation ?? .identity,
      stickers = stickers ?? .filled(kFaceCount, null) {
    if (stickers != null && stickers.length != kFaceCount) {
      throw ArgumentError.value(
        stickers.length,
        'stickers',
        'Must have $kFaceCount faces',
      );
    }
  }

  Vec3 position;

  Mat3 orientation;

  final List<int?> stickers;

  bool get hasSticker => stickers.any((int? s) => s != null);

  Vec3 worldNormalOf(int faceIndex) {
    if (faceIndex < 0 || faceIndex >= kFaceCount) {
      throw RangeError.range(faceIndex, 0, kFaceCount - 1, 'faceIndex');
    }
    return orientation.transform(kFaceNormals[faceIndex]);
  }

  Cubie copy() => Cubie(
    position: position,
    orientation: orientation,
    stickers: .of(stickers),
  );

  void copyFrom(Cubie other) {
    if (other.stickers.length != kFaceCount) {
      throw ArgumentError.value(
        other.stickers.length,
        'other.stickers',
        'Must have $kFaceCount faces',
      );
    }
    position = other.position;
    orientation = other.orientation;
    for (int i = 0; i < kFaceCount; i++) {
      stickers[i] = other.stickers[i];
    }
  }
}
