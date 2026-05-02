import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/dashboard_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../models/shipment.dart';
import '../../widgets/metric_chip.dart';
import '../../widgets/add_shipment_dialog.dart';
import '../optimization/optimization_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supply Chain Overview'),
        actions: [
          Consumer<DashboardController>(
            builder: (context, controller, _) => IconButton(
              icon: Icon(
                controller.isGlobalStopped ? Icons.play_circle_outline : Icons.power_settings_new,
                color: controller.isGlobalStopped ? AppTheme.success : AppTheme.danger,
              ),
              tooltip: controller.isGlobalStopped ? 'Resume All Services' : 'Stop All Services',
              onPressed: () {
                if (controller.isGlobalStopped) {
                  controller.toggleGlobalStop(false);
                } else {
                  _showStopAllDialog(context);
                }
              },
            ),
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
                if (controller.isGlobalStopped) ...[
                    _NotificationBar(
                      message: 'SYSTEM HALTED: Global Stop Active',
                      color: AppTheme.danger,
                      actionLabel: 'RESUME',
                      onAction: () => controller.toggleGlobalStop(false),
                      onClose: () => controller.errorMessage = null,
                    ),
                  const SizedBox(height: 16),
                ],
                _SummaryStats(shipments: controller.recentShipments),

                if (controller.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _NotificationBar(
                    message: controller.errorMessage!,
                    color: AppTheme.danger,
                    onClose: () => controller.errorMessage = null,
                  ),
                ],
                if (controller.successMessage != null) ...[
                  const SizedBox(height: 16),
                  _NotificationBar(
                    message: controller.successMessage!,
                    color: AppTheme.success,
                    onClose: () => controller.successMessage = null,
                  ),
                ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const AddShipmentDialog(),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('New Shipment'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _showStopAllDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop All Services?'),
        content: const Text(
            'This will immediately terminate all active vehicle simulations across the entire system. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              context.read<DashboardController>().stopAllSimulations();
              Navigator.pop(dialogContext);
            },
            child: const Text('Stop Everything',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _NotificationBar extends StatelessWidget {
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClose;

  const _NotificationBar({
    required this.message,
    required this.color,
    required this.onClose,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: color),
                ),
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          IconButton(
            icon: Icon(Icons.close, size: 16, color: color),
            onPressed: onClose,
          ),
        ],
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
    final inTransit = shipments
        .where((s) => s.status == 'IN_TRANSIT' || s.status == 'ANALYZED')
        .length;

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
                children: [
                  MetricChip(
                    label: 'Delay',
                    value: shipment.ai.delayPrediction,
                    icon: Icons.timer,
                  ),
                  const SizedBox(width: 8),
                  MetricChip(
                    label: 'Speed',
                    value: '${shipment.speedKmH.toStringAsFixed(0)} km/h',
                    icon: Icons.speed,
                  ),
                  const Spacer(),
                  Consumer<DashboardController>(
                    builder: (context, controller, _) {
                      final isSimulatingThis = controller.isSimulating &&
                          controller.simulatingShipmentId ==
                              shipment.shipmentId;

                      return ElevatedButton.icon(
                        onPressed: () {
                          controller.toggleSimulation(shipment);
                          final isStarting = !isSimulatingThis;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isStarting
                                  ? '🚀 Simulation started for ${shipment.shipmentId}'
                                  : '🛑 Simulation stopped'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: isStarting
                                  ? AppTheme.primary
                                  : AppTheme.danger,
                            ),
                          );
                        },
                        icon: Icon(
                          isSimulatingThis
                              ? Icons.stop_circle
                              : Icons.play_arrow_rounded,
                          size: 18,
                        ),
                        label: Text(isSimulatingThis ? 'Stop' : 'Simulate'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSimulatingThis
                              ? AppTheme.danger.withValues(alpha: 0.1)
                              : AppTheme.primary.withValues(alpha: 0.1),
                          foregroundColor: isSimulatingThis
                              ? AppTheme.danger
                              : AppTheme.primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
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
