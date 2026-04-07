import 'dart:ui';

import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:flutter/material.dart';

class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
    this.onCenterActionTap,
    this.centerActionLabel = 'Submit\nReport',
    this.centerActionIcon = Icons.add_rounded,
    this.showCitizenReportsTab = false,
    this.showCitizenNotificationsTab = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final VoidCallback? onCenterActionTap;
  final String centerActionLabel;
  final IconData centerActionIcon;
  final bool showCitizenReportsTab;
  final bool showCitizenNotificationsTab;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? dc.darkSurface.withValues(alpha: 0.8)
        : dc.surface.withValues(alpha: 0.92);
    final selectedColor = isDark ? dc.darkPrimaryAccent : dc.primary;
    final unselectedColor = isDark
        ? dc.darkInk.withValues(alpha: 0.5)
        : dc.onSurface.withValues(alpha: 0.5);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            boxShadow: [
              BoxShadow(
                color: dc.onSurface.withValues(alpha: 0.06),
                blurRadius: 32,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      icon: Icons.hub_outlined,
                      activeIcon: Icons.hub,
                      label: 'MESH',
                      isSelected: selectedIndex == 0,
                      selectedColor: selectedColor,
                      unselectedColor: unselectedColor,
                      onTap: () => onItemTapped(0),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.map_outlined,
                      activeIcon: Icons.map,
                      label: 'MAP',
                      isSelected: selectedIndex == 1,
                      selectedColor: selectedColor,
                      unselectedColor: unselectedColor,
                      onTap: () => onItemTapped(1),
                    ),
                  ),
                  if (showCitizenReportsTab)
                    Expanded(
                      child: _NavItem(
                        icon: Icons.assignment_outlined,
                        activeIcon: Icons.assignment,
                        label: 'REPORTS',
                        isSelected: selectedIndex == 2,
                        selectedColor: selectedColor,
                        unselectedColor: unselectedColor,
                        onTap: () => onItemTapped(2),
                      ),
                    ),
                  if (onCenterActionTap != null)
                    Expanded(
                      child: _CenterActionItem(
                        icon: centerActionIcon,
                        label: centerActionLabel,
                        accentColor: selectedColor,
                        onTap: onCenterActionTap!,
                      ),
                    ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.dynamic_feed_outlined,
                      activeIcon: Icons.dynamic_feed,
                      label: 'FEED',
                      isSelected: selectedIndex == _feedIndex,
                      selectedColor: selectedColor,
                      unselectedColor: unselectedColor,
                      onTap: () => onItemTapped(_feedIndex),
                    ),
                  ),
                  if (showCitizenNotificationsTab)
                    Expanded(
                      child: _NavItem(
                        icon: Icons.notifications_none_rounded,
                        activeIcon: Icons.notifications_rounded,
                        label: 'NOTIFS',
                        isSelected: selectedIndex == _notificationsIndex,
                        selectedColor: selectedColor,
                        unselectedColor: unselectedColor,
                        onTap: () => onItemTapped(_notificationsIndex),
                      ),
                    )
                  else
                    Expanded(
                      child: _NavItem(
                        icon: Icons.settings_outlined,
                        activeIcon: Icons.settings,
                        label: 'SETTINGS',
                        isSelected: selectedIndex == _settingsIndex,
                        selectedColor: selectedColor,
                        unselectedColor: unselectedColor,
                        onTap: () => onItemTapped(_settingsIndex),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int get _feedIndex {
    if (showCitizenReportsTab && showCitizenNotificationsTab) {
      return 3;
    }
    return showCitizenReportsTab ? 3 : 2;
  }

  int get _notificationsIndex {
    if (showCitizenReportsTab && showCitizenNotificationsTab) {
      return 4;
    }
    return _settingsIndex;
  }

  int get _settingsIndex {
    return showCitizenReportsTab ? 4 : 3;
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? selectedColor : unselectedColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: isSelected
            ? BoxDecoration(
                color: isDark
                    ? dc.darkPrimaryAccent.withValues(alpha: 0.12)
                    : dc.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isSelected ? activeIcon : icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontFamily: 'Inter',
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterActionItem extends StatelessWidget {
  const _CenterActionItem({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark
                    ? dc.darkPrimaryAccent.withValues(alpha: 0.2)
                    : dc.primaryContainer,
                shape: BoxShape.circle,
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.28),
                ),
              ),
              child: Icon(icon, color: accentColor, size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontFamily: 'Inter',
                color: accentColor,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                height: 1.05,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
