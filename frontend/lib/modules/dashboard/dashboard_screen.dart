import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/dashboard_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../models/shipment.dart';
import '../../widgets/metric_chip.dart';
import '../optimization/optimization_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supply Chain Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_fill, color: Colors.green),
            tooltip: 'Start Live Simulation',
            onPressed: () async {
              try {
                await context.read<DashboardController>().startLiveSimulation();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Simulation started!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to start: $e')),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle, color: Colors.red),
            tooltip: 'Stop Live Simulation',
            onPressed: () async {
              await context.read<DashboardController>().stopLiveSimulation();
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
        ],
      ),
      body: Consumer<DashboardController>(
        builder: (context, controller, _) {
          if (controller.isBootstrapping) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.recentShipments.isEmpty) {
            return _EmptyDashboard(onRefresh: controller.bootstrap);
          }

          return RefreshIndicator(
            onRefresh: controller.bootstrap,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryStats(shipments: controller.recentShipments),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Shipments',
                      style: AppTheme.light.textTheme.titleLarge,
                    ),
                    TextButton(onPressed: () {}, child: const Text('View All')),
                  ],
                ),
                const SizedBox(height: 12),
                ...controller.recentShipments.map(
                  (s) => _ShipmentCard(shipment: s),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryStats extends StatelessWidget {
  final List<Shipment> shipments;
  const _SummaryStats({required this.shipments});

  @override
  Widget build(BuildContext context) {
    final atRisk = shipments.where((s) => s.ai.riskLevel == 'HIGH').length;
    final inTransit = shipments.where((s) => s.status == 'IN_TRANSIT' || s.status == 'ANALYZED').length;

    return Row(
      children: [
        _StatCard(
          label: 'Active',
          value: inTransit.toString(),
          icon: Icons.local_shipping,
          color: AppTheme.primary,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'At Risk',
          value: atRisk.toString(),
          icon: Icons.warning_amber_rounded,
          color: atRisk > 0 ? AppTheme.danger : AppTheme.success,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShipmentCard extends StatelessWidget {
  final Shipment shipment;
  const _ShipmentCard({required this.shipment});

  @override
  Widget build(BuildContext context) {
    final riskColor = _getRiskColor(shipment.ai.riskLevel);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          context.read<DashboardController>().selectShipment(
            shipment.shipmentId,
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OptimizationScreen(shipment: shipment),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    shipment.shipmentId,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: riskColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      shipment.ai.riskLevel,
                      style: TextStyle(
                        color: riskColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${shipment.origin} → ${shipment.destination}',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  MetricChip(
                    label: 'Delay',
                    value: shipment.ai.delayPrediction,
                    icon: Icons.timer,
                  ),
                  Text(
                    shipment.status,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getRiskColor(String level) {
    switch (level.toUpperCase()) {
      case 'HIGH':
        return AppTheme.danger;
      case 'MEDIUM':
        return AppTheme.warning;
      case 'LOW':
        return AppTheme.success;
      default:
        return AppTheme.textMuted;
    }
  }
}

class _EmptyDashboard extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyDashboard({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          const Text(
            'No shipments found',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start the simulator to see live data',
            style: TextStyle(color: AppTheme.textMuted),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onRefresh,
            child: const Text('Refresh Dashboard'),
          ),
        ],
      ),
    );
  }
}
