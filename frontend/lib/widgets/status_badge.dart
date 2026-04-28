import 'package:flutter/material.dart';

import '../models/shipment.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.live,
    required this.usingFirestore,
    required this.lastUpdated,
    required this.selectedShipmentId,
    required this.shipments,
    required this.onShipmentSelected,
    super.key,
  });

  final bool live;
  final bool usingFirestore;
  final DateTime? lastUpdated;
  final String? selectedShipmentId;
  final List<Shipment> shipments;
  final ValueChanged<String> onShipmentSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Logistics Risk Monitor',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  color: live ? AppTheme.success : AppTheme.danger,
                  size: 12,
                ),
                const SizedBox(width: 8),
                Text(
                  live ? 'LIVE TRACKING ACTIVE' : 'LIVE TRACKING OFFLINE',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${usingFirestore ? 'Firestore stream' : 'Backend fallback'} - Last updated: ${relativeTime(lastUpdated)}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (shipments.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonHideUnderline(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: shipments.any((item) => item.shipmentId == selectedShipmentId)
                          ? selectedShipmentId
                          : shipments.first.shipmentId,
                      borderRadius: BorderRadius.circular(12),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      items: shipments
                          .map(
                            (shipment) => DropdownMenuItem<String>(
                              value: shipment.shipmentId,
                              child: Text(
                                '${shipment.title}  ${shipment.routeLabel}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          onShipmentSelected(value);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
