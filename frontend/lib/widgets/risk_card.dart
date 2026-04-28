import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/risk_utils.dart';

class RiskCard extends StatelessWidget {
  const RiskCard({
    required this.risk,
    required this.label,
    super.key,
  });

  final RiskLevel risk;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        children: [
          Icon(
            _getIcon(),
            color: color,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _getDescription(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor() {
    switch (risk) {
      case RiskLevel.high: return AppTheme.danger;
      case RiskLevel.medium: return AppTheme.warning;
      case RiskLevel.low: return AppTheme.success;
      case RiskLevel.unknown: return AppTheme.textMuted;
    }
  }

  IconData _getIcon() {
    switch (risk) {
      case RiskLevel.high: return Icons.gpp_bad_rounded;
      case RiskLevel.medium: return Icons.gpp_maybe_rounded;
      case RiskLevel.low: return Icons.gpp_good_rounded;
      case RiskLevel.unknown: return Icons.help_outline_rounded;
    }
  }

  String _getDescription() {
    switch (risk) {
      case RiskLevel.high: return 'Immediate action required';
      case RiskLevel.medium: return 'Active monitoring needed';
      case RiskLevel.low: return 'Optimal conditions';
      case RiskLevel.unknown: return 'Status pending';
    }
  }
}
