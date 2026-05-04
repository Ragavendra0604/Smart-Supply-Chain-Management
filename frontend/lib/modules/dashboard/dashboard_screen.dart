import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/dashboard_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../models/shipment.dart';
import '../../widgets/metric_chip.dart';
import '../../widgets/add_shipment_dialog.dart';
import '../optimization/optimization_screen.dart';

import '../../services/walkthrough_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey _keyStopButton = GlobalKey();
  final GlobalKey _keySpeedSlider = GlobalKey();
  final GlobalKey _keyStats = GlobalKey();
  final GlobalKey _keyShipmentList = GlobalKey();
  final GlobalKey _keyAddButton = GlobalKey();

  final WalkthroughService _walkthroughService = WalkthroughService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowWalkthrough();
    });
  }

  Future<void> _checkAndShowWalkthrough() async {
    if (!mounted) return;

    final controller = context.read<DashboardController>();
    if (controller.recentShipments.isEmpty || controller.isBootstrapping) {
      // Wait for data to load if it's currently loading or empty
      Future.delayed(
          const Duration(milliseconds: 500), _checkAndShowWalkthrough);
      return;
    }

    final completed = await _walkthroughService.isWalkthroughCompleted();
    if (!completed) {
      _startWalkthrough();
    }
  }

  void _startWalkthrough() {
    final targets = _walkthroughService.createDashboardTargets(
      keyStopButton: _keyStopButton,
      keySpeedSlider: _keySpeedSlider,
      keyStats: _keyStats,
      keyShipmentList: _keyShipmentList,
      keyAddButton: _keyAddButton,
    );

    _walkthroughService.showWalkthrough(
      context: context,
      targets: targets,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supply Chain Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Show Walkthrough',
            onPressed: _startWalkthrough,
          ),
          Consumer<DashboardController>(
            builder: (context, controller, _) => IconButton(
              key: _keyStopButton,
              icon: Icon(
                controller.isGlobalStopped
                    ? Icons.play_circle_outline
                    : Icons.power_settings_new,
                color: controller.isGlobalStopped
                    ? AppTheme.success
                    : AppTheme.danger,
              ),
              tooltip: controller.isGlobalStopped
                  ? 'Resume All Services'
                  : 'Stop All Services',
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

          final isWide = MediaQuery.of(context).size.width > 900;
          final content = isWide 
            ? _buildWideLayout(context, controller) 
            : _buildMobileLayout(context, controller);

          return RefreshIndicator(
            onRefresh: controller.bootstrap,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: content,
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: _keyAddButton,
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

  Widget _buildMobileLayout(BuildContext context, DashboardController controller) {
    return ListView(
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
        const SizedBox(height: 16),
        _SimulationSpeedController(
          key: _keySpeedSlider,
          controller: controller,
        ),
        const SizedBox(height: 24),
        _SummaryStats(
          key: _keyStats,
          shipments: controller.recentShipments,
        ),
        _buildMessages(controller),
        const SizedBox(height: 24),
        _buildShipmentListHeader(),
        const SizedBox(height: 12),
        _buildShipmentList(controller),
      ],
    );
  }

  Widget _buildWideLayout(BuildContext context, DashboardController controller) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Column: Shipments
          Expanded(
            flex: 3,
            child: ListView(
              children: [
                _buildShipmentListHeader(),
                const SizedBox(height: 16),
                _buildShipmentList(controller),
              ],
            ),
          ),
          const SizedBox(width: 32),
          // Sidebar: Stats & Controls
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (controller.isGlobalStopped) ...[
                    _NotificationBar(
                      message: 'SYSTEM HALTED',
                      color: AppTheme.danger,
                      actionLabel: 'RESUME',
                      onAction: () => controller.toggleGlobalStop(false),
                      onClose: () => controller.errorMessage = null,
                    ),
                    const SizedBox(height: 20),
                  ],
                  _SummaryStats(
                    key: _keyStats,
                    shipments: controller.recentShipments,
                  ),
                  const SizedBox(height: 24),
                  _SimulationSpeedController(
                    key: _keySpeedSlider,
                    controller: controller,
                  ),
                  const SizedBox(height: 24),
                  _buildMessages(controller),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(DashboardController controller) {
    return Column(
      children: [
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
      ],
    );
  }

  Widget _buildShipmentListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Recent Shipments',
          style: AppTheme.light.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.filter_list, size: 18),
          label: const Text('View All'),
        ),
      ],
    );
  }

  Widget _buildShipmentList(DashboardController controller) {
    return Container(
      key: _keyShipmentList,
      child: Column(
        children: controller.recentShipments
            .map((s) => _ShipmentCard(shipment: s))
            .toList(),
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
  const _SummaryStats({super.key, required this.shipments});

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
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('SPEED',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textMuted,
                                    letterSpacing: 0.5)),
                            Text('${shipment.speedKmH.toStringAsFixed(0)} km/h',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primary)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (shipment.speedKmH / 120).clamp(0.0, 1.0),
                            backgroundColor:
                                AppTheme.primary.withValues(alpha: 0.1),
                            color: shipment.speedKmH > 90
                                ? AppTheme.danger
                                : (shipment.speedKmH > 70
                                    ? AppTheme.warning
                                    : AppTheme.primary),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Consumer<DashboardController>(
                    builder: (context, controller, _) {
                      final isSimulatingThis = controller.isSimulating &&
                          controller.simulatingShipmentId ==
                              shipment.shipmentId;
                      final bool isStopped = shipment.status == 'STOPPED';
                      final String buttonLabel = isSimulatingThis
                          ? 'Stop'
                          : (isStopped ? 'Resume' : 'Simulate');
                      final IconData buttonIcon = isSimulatingThis
                          ? Icons.stop_circle
                          : (isStopped
                              ? Icons.play_circle_filled_rounded
                              : Icons.play_arrow_rounded);

                      return ElevatedButton.icon(
                        onPressed: () {
                          controller.toggleSimulation(shipment);
                          final isStarting = !isSimulatingThis;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isStarting
                                  ? (isStopped
                                      ? '▶️ Simulation resumed'
                                      : '🚀 Simulation started for ${shipment.shipmentId}')
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
                          buttonIcon,
                          size: 18,
                        ),
                        label: Text(buttonLabel),
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

class _SimulationSpeedController extends StatelessWidget {
  final DashboardController controller;
  const _SimulationSpeedController({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.speed, color: AppTheme.primary, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Simulation Speed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${controller.simulationSpeedMultiplier.toStringAsFixed(1)}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.primary,
              inactiveTrackColor: AppTheme.primary.withValues(alpha: 0.1),
              thumbColor: AppTheme.primary,
              overlayColor: AppTheme.primary.withValues(alpha: 0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: controller.simulationSpeedMultiplier,
              min: 1.0,
              max: 10.0,
              divisions: 9,
              onChanged: (value) => controller.setSimulationSpeed(value),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Real-time (1x)',
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                Text('Accelerated (10x)',
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
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
