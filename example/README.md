# magic_cube example

Source: <https://github.com/runoob-coder/flutter-magic-cube/tree/main/example>

Demonstrates the full usage of the [`magic_cube`](../) widget:

- **Double-tap the cube**: scrambles automatically and starts the timer; once solved it
  stops the clock and records the result;
- **Drag on a sticker**: turns the corresponding layer (any layer, including middle
  slices);
- **Drag outside the cube**: orbits the viewpoint, with inertia on release;
- **Scramble / Undo / Restore step by step / Reset**: demonstrates `scramble`, `undo`,
  `undoAll` and `reset`;
- **Algorithm input**: type standard notation such as `R U R' U'` and run it, or tap the
  notation buttons;
- **Stats panel**: total attempts, fastest, slowest, ao5, ao12, plus solved-face count
  and move count;
- **Appearance**: hot-switch between classic / pastel / neon themes, auto-rotation and
  viewpoint reset;
- **Localization**: every UI string follows the system language, with English and
  Simplified Chinese bundles.

## Run

The example is a standalone Flutter app (there is no pub workspace in this
repository), so it needs its own dependency resolution:

```bash
cd example
flutter pub get
flutter run                  # or -d chrome / -d macos
```

## Localization

The UI follows the device language by default (`MaterialApp.locale` is left unset). The
language switcher in the top-right corner can override it with **Follow system**,
**English** or **Simplified Chinese**; its label shows `AUTO`, `EN` or `中文` for the current
choice. The choice is kept in memory only, so restarting the demo follows the system again,
and switching refreshes every string including the document title. English
(`lib/l10n/app_en.arb`) is the template and the fallback for unsupported languages;
`lib/l10n/app_zh.arb` provides Simplified Chinese for `zh` and its script/regional variants.

Messages are generated with Flutter's
[`flutter gen-l10n`](https://docs.flutter.dev/ui/internationalization) workflow configured
in `l10n.yaml`. After editing an `.arb` file, run `flutter pub get` or `flutter gen-l10n`
in this directory to regenerate `lib/l10n/app_localizations*.dart`; those generated files
are build artifacts and are not checked in. The iOS and macOS bundles declare `en` and
`zh` in their `Info.plist` files.

## Responsive layout

Three breakpoints (compact < 600, medium < 1024, expanded ≥ 1024 logical pixels) are
computed once in `lib/responsive.dart` and passed down as a `DemoLayout`:

- **Desktop**: a fixed cube + timer column on the left and a scrolling information column
  on the right, centred inside a 1200px content area. Frequent actions sit in the top bar.
- **Tablet**: a single column with the two data panels side by side; the top bar shows the
  title and a menu button that opens the full action list.
- **Phone**: the first screen shows only the cube, timer and core actions. Stats, progress,
  notation buttons, the algorithm field and appearance controls live in collapsible
  sections that start closed, so nothing is removed, only de-emphasised.

All buttons (including the 30 notation buttons), menu entries and section headers have a
48px minimum touch target, and spacing / radii / type sizes come from the shared tokens in
`lib/app_theme.dart` and `lib/responsive.dart`. The cube region stays outside every scroll
view so layer-turn drags are never stolen by scrolling, and the cube size is bounded by
both available width and height for short or landscape windows. No extra assets, fonts or
per-frame work were added, so Web and mobile load and render the same content.

## Code structure

| File | Purpose |
| --- | --- |
| `lib/main.dart` | Responsive page layout, language selection state and interaction wiring |
| `lib/responsive.dart` | Breakpoints, spacing / size tokens and the `DemoLayout` value object |
| `lib/l10n/*.arb` | English and Chinese message catalogs (source of all UI text) |
| `lib/session.dart` | Timer and result model (phases, ao5/ao12, formatting) |
| `lib/app_theme.dart` | Shared colors, panels, pill buttons and spacing tokens |
| `lib/widgets/demo_app_bar.dart` | Responsive top bar, compact-screen action menu and language switcher |
| `lib/widgets/collapsible_section.dart` | Collapsible secondary sections used on phones |
| `lib/widgets/*.dart` | Timer header, stats board, progress board, action bar, notation panel |
| `test/responsive_layout_test.dart` | Phone / tablet / desktop / landscape layout regression |
| `test/localization_test.dart` | Localization, language switching and follow-system regression |
