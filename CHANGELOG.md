## 1.0.0

- 👆 **Gestures** — drag a sticker to turn its layer (axis auto-detected, snaps to the nearest 90°); drag outside the cube to orbit with inertia, or use two fingers to orbit while the in-progress turn smoothly rolls back.
- 🌍 **Free viewpoint** — full 360° flips with no gimbal lock; view animations always take the shortest path.
- 🔤 **Notation & NxN** — standard `U D L R F B M E S x y z` with `'` / `2`, numeric layer prefixes (e.g. `3X'`) for odd cubes up to 11×11; `parse` / `notation` round-trip and throw `FormatException` on malformed tokens.
- 🧠 **State & controller** — scramble, undo, step-by-step restore, solved detection, solved-face count, bounded history and queued animations; `taskEpoch` marks the state generation, and one controller is safe to share across widgets.
- 🎨 **Appearance** — four hot-swappable themes, two-level corner rounding with patches, raised stickers with side walls and shadows, view-space lighting, and a fully validated `CubeTheme`.
- 🖼️ **Centre-piece logo** — an `ui.Image` on one centre sticker that follows the cubie's perspective and lighting; helpers rasterise text, icons or the Flutter logo into square transparent images.
- 📐 **Pixel-quality rendering** — adaptive arc tessellation (≤0.12 px), hairline anti-aliasing on side walls, stencil-free on Web, plus near-plane / degenerate-homography guards.
- ⚡ **Performance** — static layers cached as `Picture`s, theme/signature-keyed caches for geometry, shading and outlines, pooled temporaries, and unified cache disposal on last unmount (~69% less per-frame work at 400×400 on a 3×3).
- 🧪 **Quality** — regression tests for notation, state math, controller lifecycle, layer sorting, corner patches, logo perspective and anti-aliasing; CI runs format / analyze / tests for the package and example.
