import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/dashboard_controller.dart';
import '../../models/shipment.dart';
import '../dashboard/dashboard_map.dart';
import '../../core/theme/app_theme.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardController>(
      builder: (context, controller, _) {
        final shipment = controller.latestShipment;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Live Tracking'),
            actions: [
              if (shipment != null)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, color: AppTheme.success, size: 8),
                      SizedBox(width: 4),
                      Text('LIVE', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
          body: shipment == null
              ? const Center(child: Text('No active shipment to track'))
              : Stack(
                  children: [
                    DashboardMap(shipment: shipment),
                    Positioned(
                      bottom: 20,
                      left: 16,
                      right: 16,
                      child: _TrackingInfoPanel(shipment: shipment),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _TrackingInfoPanel extends StatelessWidget {
  final Shipment shipment;
  const _TrackingInfoPanel({required this.shipment});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, color: AppTheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shipment.shipmentId, style: AppTheme.light.textTheme.titleLarge),
                      Text(shipment.currentPlace, style: AppTheme.light.textTheme.bodyMedium),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    shipment.status,
                    style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
