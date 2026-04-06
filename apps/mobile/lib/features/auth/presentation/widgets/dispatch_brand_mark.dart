import 'package:flutter/material.dart';

class DispatchBrandMark extends StatelessWidget {
  const DispatchBrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Dispatch logo',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: Image.asset(
            'assets/branding/dispatch_logo_transparent.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
