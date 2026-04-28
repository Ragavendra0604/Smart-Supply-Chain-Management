import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/risk_utils.dart';
import '../../models/shipment.dart';
import '../../widgets/info_card.dart';
import '../../controllers/dashboard_controller.dart';
import 'package:provider/provider.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DashboardController>();
    final stats = controller.systemStats;

    return Scaffold(
      appBar: AppBar(title: const Text('Supply Chain Insights')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Network Efficiency',
              style: AppTheme.light.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            InfoCard(
              child: Column(
                children: [
                  _TrendItem(
                    label: 'Fleet Efficiency',
                    value: '${stats?['efficiencyRate'] ?? 100}%',
                    icon: Icons.trending_up,
                    color: AppTheme.success,
                  ),
                  const Divider(height: 24),
                  _TrendItem(
                    label: 'Avg. Predicted Delay',
                    value: '${stats?['avgDelay'] ?? 0} mins',
                    icon: Icons.timer_outlined,
                    color: AppTheme.warning,
                  ),
                  const Divider(height: 24),
                  _TrendItem(
                    label: 'Active Shipments',
                    value: '${stats?['totalShipments'] ?? 0}',
                    icon: Icons.local_shipping_outlined,
                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Active Region Risks',
              style: AppTheme.light.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _RegionRiskList(),
          ],
        ),
      ),
    );
  }
}

class _TrendItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _TrendItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(label, style: AppTheme.light.textTheme.bodyLarge)),
        Text(
          value,
          style: AppTheme.light.textTheme.titleLarge?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _RegionRiskList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final shipments = context.select<DashboardController, List<Shipment>>(
      (c) => c.recentShipments,
    );

    if (shipments.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Text('No active regions monitored'),
      ));
    }

    return Column(
      children: shipments.take(5).map((s) => _RegionItem(
        region: '${s.origin} Sector',
        risk: s.ai.riskLevel,
        color: riskColor(s.riskLevel),
      )).toList(),
    );
  }
}

class _RegionItem extends StatelessWidget {
  final String region;
  final String risk;
  final Color color;

  const _RegionItem({
    required this.region,
    required this.risk,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(region, style: const TextStyle(fontWeight: FontWeight.bold)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              risk,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
