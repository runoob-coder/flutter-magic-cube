import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 三档屏幕尺寸：手机 / 平板 / 大屏桌面。
enum DemoScreenClass { compact, medium, expanded }

extension DemoScreenClassFlags on DemoScreenClass {
  bool get isCompact => this == DemoScreenClass.compact;
  bool get isMedium => this == DemoScreenClass.medium;
  bool get isExpanded => this == DemoScreenClass.expanded;
}

/// 断点、间距、尺寸的唯一真值源。
///
/// 组件不再各自写死 20 / 14 / 220 / 54 这类数值，统一从 [DemoLayout] 取值，
/// 保证同一档位下各端的字体、留白与点击区一致。
abstract final class AppMetrics {
  static const double compactBreakpoint = 600;
  static const double expandedBreakpoint = 1024;

  /// 超宽屏上内容区的最大宽度，避免桌面端元素被拉得过长。
  static const double contentMaxWidth = 1200;

  /// 触屏控件的最小点击区（Material 建议值）。
  static const double minTouchTarget = 48;

  static const double compactGutter = 12;
  static const double mediumGutter = 20;
  static const double expandedGutter = 28;

  static const double compactSectionGap = 12;
  static const double mediumSectionGap = 16;
  static const double expandedSectionGap = 20;

  static const double compactTimerFontSize = 40;
  static const double mediumTimerFontSize = 48;
  static const double expandedTimerFontSize = 54;

  static const double panelSpacing = 14;
  static const double maxPanelWidth = 320;
  static const double maxCompactPanelWidth = 420;
  static const double maxCubeSize = 520;
  static const double minCubeSize = 120;

  /// 桌面双栏里左栏（魔方）占内容宽度的比例。
  static const double expandedLeftColumnRatio = 0.52;

  /// 顶部栏高度，参与魔方的可用高度计算。
  static const double headerHeight = 56;

  /// 魔方之外固定占用的垂直空间（顶部栏、计时器、说明、滑块、内边距）。
  static const double compactChromeHeight = 200;
  static const double mediumChromeHeight = 250;
  static const double expandedChromeHeight = 280;
}

/// 一次布局计算的结果，由页面层向下显式传递。
class DemoLayout {
  const DemoLayout({
    required this.screenClass,
    required this.contentWidth,
    required this.leftColumnWidth,
    required this.gutter,
    required this.sectionGap,
    required this.panelWidth,
    required this.cubeSize,
    required this.timerFontSize,
    required this.inlineHeaderActions,
    required this.collapseSecondary,
  });

  final DemoScreenClass screenClass;
  final double contentWidth;
  final double leftColumnWidth;
  final double gutter;
  final double sectionGap;
  final double panelWidth;
  final double cubeSize;
  final double timerFontSize;

  /// 桌面顶部栏直接显示快捷操作；窄屏收成菜单按钮。
  final bool inlineHeaderActions;

  /// 手机端把次要内容默认折叠。
  final bool collapseSecondary;

  bool get isCompact => screenClass == DemoScreenClass.compact;
  bool get isMedium => screenClass == DemoScreenClass.medium;
  bool get isExpanded => screenClass == DemoScreenClass.expanded;

  factory DemoLayout.from(BoxConstraints constraints, Size screen) {
    final double width = constraints.maxWidth;
    final double height = constraints.maxHeight;
    final DemoScreenClass screenClass = width >= AppMetrics.expandedBreakpoint
        ? DemoScreenClass.expanded
        : width >= AppMetrics.compactBreakpoint
        ? DemoScreenClass.medium
        : DemoScreenClass.compact;

    final double gutter = switch (screenClass) {
      DemoScreenClass.compact => AppMetrics.compactGutter,
      DemoScreenClass.medium => AppMetrics.mediumGutter,
      DemoScreenClass.expanded => AppMetrics.expandedGutter,
    };
    final double sectionGap = switch (screenClass) {
      DemoScreenClass.compact => AppMetrics.compactSectionGap,
      DemoScreenClass.medium => AppMetrics.mediumSectionGap,
      DemoScreenClass.expanded => AppMetrics.expandedSectionGap,
    };
    final double timerFontSize = switch (screenClass) {
      DemoScreenClass.compact => AppMetrics.compactTimerFontSize,
      DemoScreenClass.medium => AppMetrics.mediumTimerFontSize,
      DemoScreenClass.expanded => AppMetrics.expandedTimerFontSize,
    };

    final double contentWidth = math.min(width, AppMetrics.contentMaxWidth);
    final double leftColumnWidth = screenClass.isExpanded
        ? contentWidth * AppMetrics.expandedLeftColumnRatio
        : 0;
    // 右栏（桌面）或整行（平板/手机）能分给数据面板的宽度。
    final double availableWidth = contentWidth - gutter * 2 - leftColumnWidth;
    final double panelWidth = screenClass.isCompact
        ? math.min(availableWidth, AppMetrics.maxCompactPanelWidth)
        : math.min(
            (availableWidth - AppMetrics.panelSpacing) / 2,
            AppMetrics.maxPanelWidth,
          );

    // 魔方尺寸同时受可用宽与可用高约束：只按屏幕总高算会在矮屏 / 横屏
    // 把顶部固定区撑出 Column 之外。
    final double widthLimit = switch (screenClass) {
      DemoScreenClass.compact => math.min(screen.width * 0.82, 420),
      DemoScreenClass.medium => math.min(contentWidth * 0.7, 460),
      DemoScreenClass.expanded => math.min(
        leftColumnWidth - gutter * 2,
        AppMetrics.maxCubeSize,
      ),
    };
    final double heightFactor = switch (screenClass) {
      DemoScreenClass.compact => 0.42,
      DemoScreenClass.medium => 0.48,
      DemoScreenClass.expanded => 0.62,
    };
    final double chromeHeight = switch (screenClass) {
      DemoScreenClass.compact => AppMetrics.compactChromeHeight,
      DemoScreenClass.medium => AppMetrics.mediumChromeHeight,
      DemoScreenClass.expanded => AppMetrics.expandedChromeHeight,
    };
    final double heightLimit = math.min(
      height * heightFactor,
      height - chromeHeight,
    );
    final double cubeSize = math
        .min(widthLimit, heightLimit)
        .clamp(AppMetrics.minCubeSize, AppMetrics.maxCubeSize);

    return DemoLayout(
      screenClass: screenClass,
      contentWidth: contentWidth,
      leftColumnWidth: leftColumnWidth,
      gutter: gutter,
      sectionGap: sectionGap,
      panelWidth: panelWidth,
      cubeSize: cubeSize,
      timerFontSize: timerFontSize,
      inlineHeaderActions: screenClass.isExpanded,
      collapseSecondary: screenClass.isCompact,
    );
  }
}
