import 'package:material_ui/material_ui.dart';

import 'responsive.dart';

abstract final class AppPalette {
  static const Color backgroundTop = Color(0xFF121216);
  static const Color backgroundBottom = Color(0xFF1F1F28);
  static const Color accent = Color(0xFFFFD500);
  static const Color surface = Color(0x14FFFFFF);
  static const Color surfaceStrong = Color(0x24FFFFFF);
  // Solid buttons: translucent white over Material can flatten to white
  // on some Web render paths, making near-white labels unreadable.
  static const Color buttonSurface = Color(0xFF26262E);
  static const Color buttonSurfaceHighlighted = Color(0xFF2F2F3A);
  static const Color buttonBorder = Color(0x2EFFFFFF);
  static const Color buttonForegroundDisabled = Color(0x62FFFFFF);
  static const Color textPrimary = Color(0xFFF6F6F8);
  static const Color textSecondary = Color(0xFF9B9BA6);
  static const Color border = Color(0x1FFFFFFF);

  // 统一间距 / 圆角 / 点击区：页面与各面板只从这里取值。
  static const double spaceXs = 6;
  static const double spaceSm = 10;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double panelPadding = 14;
  static const double panelRadius = 18;
  static const double minTouchTarget = AppMetrics.minTouchTarget;

  static const LinearGradient background = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[backgroundTop, backgroundBottom],
  );

  static const TextStyle timerText = TextStyle(
    color: textPrimary,
    fontSize: 54,
    fontWeight: FontWeight.w700,
    height: 1,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle statusText = TextStyle(
    color: textSecondary,
    fontSize: 15,
    letterSpacing: 1.4,
  );

  static const TextStyle panelTitle = TextStyle(
    color: textSecondary,
    fontSize: 12,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle statValue = TextStyle(
    color: textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle statLabel = TextStyle(
    color: textSecondary,
    fontSize: 13,
  );

  /// 计时数字按屏幕档位缩放，其余样式保持统一。
  static TextStyle timerTextFor(double fontSize) =>
      timerText.copyWith(fontSize: fontSize);
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    required this.child,
    this.padding = AppPalette.panelPadding,
  });

  final String? title;
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(AppPalette.panelRadius),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Text(title!, style: AppPalette.panelTitle),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.highlighted = false,
    this.compact = false,
    this.expanded = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool compact;

  /// 单列菜单里铺满整行，其它场景保持内容宽度。
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onTap == null;
    // Darken disabled buttons instead of Opacity, which triggers
    // saveLayer and can hit Web stencil-buffer allocation failures.
    final Color background = !highlighted
        ? (disabled
              ? AppPalette.buttonSurface
              : AppPalette.buttonSurfaceHighlighted)
        : AppPalette.accent;
    final Color foreground = highlighted
        ? const Color(0xFF1B1B1B)
        : disabled
        ? AppPalette.buttonForegroundDisabled
        : AppPalette.textPrimary;
    final Widget button = ConstrainedBox(
      // 统一触屏点击区；compact 的 30 个记号按钮同样适用。
      constraints: const BoxConstraints(
        minWidth: AppPalette.minTouchTarget,
        minHeight: AppPalette.minTouchTarget,
      ),
      child: Material(
        color: background,
        shape: StadiumBorder(
          side: highlighted
              ? BorderSide.none
              : BorderSide(color: AppPalette.buttonBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          // widthFactor/heightFactor keep the pill at its content width while
          // still centring it inside the 48px minimum touch target. A plain
          // Center would stretch every button to the full available width.
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 18,
                vertical: compact ? 8 : 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 16, color: foreground),
                    const SizedBox(width: AppPalette.spaceXs),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: compact ? 13 : 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
