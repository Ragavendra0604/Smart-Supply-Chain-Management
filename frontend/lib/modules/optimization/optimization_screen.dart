import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/shipment.dart';
import '../../widgets/info_card.dart';

class OptimizationScreen extends StatelessWidget {
  const OptimizationScreen({required this.shipment, super.key});

  final Shipment shipment;

  @override
  Widget build(BuildContext context) {
    final opt = shipment.ai.optimization;
    final allRoutes = shipment.ai.allRoutes;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Route Optimization'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(shipment: shipment),
            const SizedBox(height: 24),
            _RiskBanner(shipment: shipment),
            const SizedBox(height: 24),
            if (opt != null) ...[
              _ComparisonSection(opt: opt),
              const SizedBox(height: 24),
            ],
            if (allRoutes.isNotEmpty) ...[
              _AllRoutesSection(routes: allRoutes),
              const SizedBox(height: 24),
            ],
            _AiReasoning(
              explanation: shipment.ai.explanation,
              suggestion: shipment.ai.suggestion,
            ),
            const SizedBox(height: 24),
            if (shipment.news.isNotEmpty) _NewsSection(news: shipment.news),
            const SizedBox(height: 24),
            _ActionButtons(),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Shipment shipment;
  const _Header({required this.shipment});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Optimization Summary',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              '${shipment.origin} → ${shipment.destination}',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RiskBanner extends StatelessWidget {
  final Shipment shipment;
  const _RiskBanner({required this.shipment});

  @override
  Widget build(BuildContext context) {
    final level = shipment.ai.riskLevel.toUpperCase();
    final score = shipment.ai.riskScore;
    final delay = shipment.ai.delayPrediction;

    Color color;
    IconData icon;
    String message;

    if (level == 'HIGH') {
      color = AppTheme.danger;
      icon = Icons.warning_amber_rounded;
      message = 'High risk detected — optimized route applied automatically';
    } else if (level == 'MEDIUM') {
      color = AppTheme.warning;
      icon = Icons.info_outline;
      message = 'Moderate risk — monitor conditions en route';
    } else {
      color = AppTheme.success;
      icon = Icons.check_circle_outline;
      message = 'Low risk — optimal conditions for delivery';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$level RISK  •  Score: ${(score * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '+$delay',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonSection extends StatelessWidget {
  final ShipmentOptimizationData opt;
  const _ComparisonSection({required this.opt});

  @override
  Widget build(BuildContext context) {
    final timeSaved = _extractTimeDiff(opt.before.time, opt.after.time);
    final costSaved = opt.before.cost - opt.after.cost;
    final fuelSaved = opt.before.fuel - opt.after.fuel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Route Comparison',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        _MetricRow(
          label: 'Travel Time',
          before: opt.before.time,
          after: opt.after.time,
          icon: Icons.timer_outlined,
          savingLabel: timeSaved,
        ),
        const SizedBox(height: 12),
        _MetricRow(
          label: 'Estimated Cost',
          before: '\$${opt.before.cost.toStringAsFixed(2)}',
          after: '\$${opt.after.cost.toStringAsFixed(2)}',
          icon: Icons.payments_outlined,
          savingLabel: costSaved > 0 ? '-\$${costSaved.toStringAsFixed(2)}' : null,
          isSaving: costSaved > 0,
        ),
        const SizedBox(height: 12),
        _MetricRow(
          label: 'Fuel Consumption',
          before: '${opt.before.fuel.toStringAsFixed(1)} L',
          after: '${opt.after.fuel.toStringAsFixed(1)} L',
          icon: Icons.local_gas_station_outlined,
          savingLabel: fuelSaved > 0 ? '-${fuelSaved.toStringAsFixed(1)} L' : null,
          isSaving: fuelSaved > 0,
        ),
      ],
    );
  }

  String? _extractTimeDiff(String before, String after) {
    // Simple display — just show both
    if (before == '--' || after == '--') return null;
    return null; // Show actual times, no diff calculation needed
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String before;
  final String after;
  final IconData icon;
  final String? savingLabel;
  final bool isSaving;

  const _MetricRow({
    required this.label,
    required this.before,
    required this.after,
    required this.icon,
    this.savingLabel,
    this.isSaving = true,
  });

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (savingLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    savingLabel!,
                    style: const TextStyle(
                      color: AppTheme.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ValueColumn(
                  label: 'CURRENT',
                  value: before,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Icon(Icons.arrow_forward, color: AppTheme.textMuted, size: 20),
              Expanded(
                child: _ValueColumn(
                  label: 'OPTIMIZED',
                  value: after,
                  color: AppTheme.success,
                  isHighlight: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValueColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isHighlight;

  const _ValueColumn({
    required this.label,
    required this.value,
    required this.color,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _AllRoutesSection extends StatelessWidget {
  final List<Map<String, dynamic>> routes;
  const _AllRoutesSection({required this.routes});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'All Available Routes',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        ...routes.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;
          final isRecommended = r['is_recommended'] == true;
          final riskLevel = (r['risk_level'] ?? 'UNKNOWN').toString().toUpperCase();

          Color riskColor;
          if (riskLevel == 'HIGH') {
            riskColor = AppTheme.danger;
          } else if (riskLevel == 'MEDIUM') {
            riskColor = AppTheme.warning;
          } else {
            riskColor = AppTheme.success;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isRecommended
                  ? AppTheme.primary.withValues(alpha: 0.05)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isRecommended
                    ? AppTheme.primary.withValues(alpha: 0.3)
                    : Colors.grey.shade200,
                width: isRecommended ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isRecommended
                        ? AppTheme.primary
                        : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: isRecommended ? Colors.white : AppTheme.textMuted,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              r['summary'] ?? 'Route ${i + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: isRecommended
                                    ? AppTheme.primary
                                    : AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isRecommended) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '✓ BEST',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${r['distance_km'] ?? 0} km  •  ${r['travel_time_min'] ?? 0} min  •  \$${r['total_cost'] ?? 0}',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    riskLevel,
                    style: TextStyle(
                      color: riskColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _AiReasoning extends StatelessWidget {
  final String explanation;
  final String suggestion;
  const _AiReasoning({required this.explanation, required this.suggestion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'AI Reasoning & Recommendation',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (suggestion.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline,
                      color: AppTheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      suggestion,
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              explanation,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                height: 1.6,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (explanation.isEmpty && suggestion.isEmpty)
            const Text(
              'Run AI analysis to get route optimization recommendations.',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

class _NewsSection extends StatelessWidget {
  final List<ShipmentNewsItem> news;
  const _NewsSection({required this.news});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Live News Signals',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        InfoCard(
          child: Column(
            children: news.take(3).toList().asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.article_outlined,
                          size: 16, color: AppTheme.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.source,
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (i < news.length - 1 && i < 2)
                    const Divider(height: 20),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Optimized route dispatched to vehicle'),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        icon: const Icon(Icons.send_rounded),
        label: const Text(
          'APPLY OPTIMIZED ROUTE',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
