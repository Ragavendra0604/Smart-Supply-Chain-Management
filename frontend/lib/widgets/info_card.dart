import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class InfoCard extends StatelessWidget {
  const InfoCard({
    required this.child,
    this.color = const Color(0xFFF8FAFC),
    this.borderColor = AppTheme.line,
    super.key,
  });

  final Widget child;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}
