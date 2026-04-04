import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);
    final navTheme = theme.bottomNavigationBarTheme;

    return BottomNavigationBar(
      currentIndex: selectedIndex,
      onTap: onItemTapped,
      items: const <BottomNavigationBarItem>[
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.feed),
          label: 'Feed',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
      type: navTheme.type ?? BottomNavigationBarType.fixed,
      backgroundColor: navTheme.backgroundColor,
      selectedItemColor: navTheme.selectedItemColor ?? theme.colorScheme.primary,
      unselectedItemColor: navTheme.unselectedItemColor,
      selectedLabelStyle: navTheme.selectedLabelStyle,
      unselectedLabelStyle: navTheme.unselectedLabelStyle,
      showUnselectedLabels: navTheme.showUnselectedLabels ?? true,
    );
  }
}
