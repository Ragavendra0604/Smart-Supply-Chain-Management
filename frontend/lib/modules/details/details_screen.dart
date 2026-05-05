import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/dashboard_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/ai_insight_card.dart';
import '../../widgets/risk_card.dart';
import '../../widgets/info_card.dart';

class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardController>(
      builder: (context, controller, _) {
        final shipment = controller.latestShipment;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Shipment Details'),
          ),
          body: shipment == null
              ? const Center(child: Text('Select a shipment from the dashboard'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailHeader(shipment: shipment),
                      const SizedBox(height: 20),
                      Text('Risk Analysis', style: AppTheme.light.textTheme.titleLarge),
                      const SizedBox(height: 12),
                      RiskCard(risk: shipment.riskLevel, label: shipment.ai.riskLevel),
                      const SizedBox(height: 20),
                      Text('AI Insights', style: AppTheme.light.textTheme.titleLarge),
                      const SizedBox(height: 12),
                      AiInsightCard(shipment: shipment),
                      const SizedBox(height: 20),
                      Text('Logistics Metrics', style: AppTheme.light.textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InfoCard(
                              child: Column(
                                children: [
                                  const Icon(Icons.timer_outlined, color: AppTheme.accent),
                                  const SizedBox(height: 8),
                                  Text('Base ETA', style: AppTheme.light.textTheme.bodyMedium),
                                  Text(shipment.route.duration, style: AppTheme.light.textTheme.titleLarge),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InfoCard(
                              child: Column(
                                children: [
                                  const Icon(Icons.traffic_outlined, color: AppTheme.warning),
                                  const SizedBox(height: 8),
                                  Text('Traffic ETA', style: AppTheme.light.textTheme.bodyMedium),
                                  Text(shipment.route.trafficDuration, style: AppTheme.light.textTheme.titleLarge),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _DetailHeader extends StatelessWidget {
  final dynamic shipment;
  const _DetailHeader({required this.shipment});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.inventory_2, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shipment.shipmentId, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text('Last updated: ${shipment.updatedAt != null ? "${shipment.updatedAt!.hour.toString().padLeft(2, '0')}:${shipment.updatedAt!.minute.toString().padLeft(2, '0')}" : "Just now"}', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _HeaderStat(label: 'Origin', value: shipment.origin),
                const Icon(Icons.arrow_forward, color: Colors.white54, size: 16),
                _HeaderStat(label: 'Destination', value: shipment.destination),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  const _HeaderStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
