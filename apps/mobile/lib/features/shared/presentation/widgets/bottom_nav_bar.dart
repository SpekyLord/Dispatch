import 'dart:ui';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:flutter/material.dart';

/// Glassmorphic bottom navigation bar — frosted glass with rounded top.
/// 4 tabs: Mesh, Map, Reports, Settings (matches design system).
class AppBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  const AppBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? dc.darkSurface.withValues(alpha: 0.8)
        : dc.surface.withValues(alpha: 0.8);
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.hub_outlined,
                    activeIcon: Icons.hub,
                    label: 'MESH',
                    isSelected: selectedIndex == 0,
                    selectedColor: selectedColor,
                    unselectedColor: unselectedColor,
                    onTap: () => onItemTapped(0),
                  ),
                  _NavItem(
                    icon: Icons.map_outlined,
                    activeIcon: Icons.map,
                    label: 'MAP',
                    isSelected: selectedIndex == 1,
                    selectedColor: selectedColor,
                    unselectedColor: unselectedColor,
                    onTap: () => onItemTapped(1),
                  ),
                  _NavItem(
                    icon: Icons.edit_note_outlined,
                    activeIcon: Icons.edit_note,
                    label: 'REPORTS',
                    isSelected: selectedIndex == 2,
                    selectedColor: selectedColor,
                    unselectedColor: unselectedColor,
                    onTap: () => onItemTapped(2),
                  ),
                  _NavItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    label: 'SETTINGS',
                    isSelected: selectedIndex == 3,
                    selectedColor: selectedColor,
                    unselectedColor: unselectedColor,
                    onTap: () => onItemTapped(3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
              style: TextStyle(
                fontFamily: 'Inter',
                color: color,
                fontSize: 11,
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
