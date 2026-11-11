/// A Flutter 3D Rubik's cube widget with whole-cube rotation and per-layer
/// turns.
///
/// Stickers follow each cubie's local orientation, so updating position and
/// orientation matrices is enough to model a turn.
library;

export 'src/core/cubie.dart';
export 'src/core/cube_move.dart';
export 'src/core/cube_state.dart';
export 'src/core/matrix3.dart';
export 'src/core/vector3.dart';
export 'src/render/cube_painter.dart';
export 'src/render/cube_scene.dart';
export 'src/render/text_image.dart';
export 'src/theme/cube_theme.dart';
export 'src/widget/magic_cube.dart';
export 'src/widget/magic_cube_controller.dart';
