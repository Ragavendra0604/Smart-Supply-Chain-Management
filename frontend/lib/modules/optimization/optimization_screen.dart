import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/dashboard_controller.dart';
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
            _WhatIfSimulator(shipment: shipment),
            const SizedBox(height: 24),
            _ActionButtons(shipment: shipment),
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
            const Icon(Icons.location_on_outlined,
                size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              '${shipment.origin} → ${shipment.destination}',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (shipment.speedKmH > 0) ...[
              const Spacer(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('LIVE SPEED',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textMuted,
                                letterSpacing: 0.5)),
                        const SizedBox(width: 8),
                        Text('${shipment.speedKmH.toStringAsFixed(0)} km/h',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 120,
                      child: ClipRRect(
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
                    ),
                  ],
                ),
              ),
            ],
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
                  style: TextStyle(
                      color: color.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
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
              level == 'LOW' ? '+0 mins' : '+$delay',
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
          savingLabel:
              costSaved > 0 ? '-\$${costSaved.toStringAsFixed(2)}' : null,
          isSaving: costSaved > 0,
        ),
        const SizedBox(height: 12),
        _MetricRow(
          label: 'Fuel Consumption',
          before: '${opt.before.fuel.toStringAsFixed(1)} L',
          after: '${opt.after.fuel.toStringAsFixed(1)} L',
          icon: Icons.local_gas_station_outlined,
          savingLabel:
              fuelSaved > 0 ? '-${fuelSaved.toStringAsFixed(1)} L' : null,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              const Icon(Icons.arrow_forward,
                  color: AppTheme.textMuted, size: 20),
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
          final riskLevel =
              (r['risk_level'] ?? 'UNKNOWN').toString().toUpperCase();

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
                    color:
                        isRecommended ? AppTheme.primary : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color:
                            isRecommended ? Colors.white : AppTheme.textMuted,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFDDE7F5), // Light blue from image
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_box_outlined,
                      color: AppTheme.success, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      suggestion,
                      style: const TextStyle(
                        color: Color(0xFF1A3B70), // Darker blue for contrast
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
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
                  if (i < news.length - 1 && i < 2) const Divider(height: 20),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatefulWidget {
  final Shipment shipment;
  const _ActionButtons({required this.shipment});

  @override
  State<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<_ActionButtons> {
  bool _isApplying = false;

  Future<void> _handleApply(DashboardController controller) async {
    if (_isApplying) return;
    setState(() => _isApplying = true);

    try {
      await controller.applyOptimizedRoute(widget.shipment.shipmentId);

      if (!mounted) return;
      final success = controller.successMessage != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '✅ ${controller.successMessage}'
                : '❌ ${controller.errorMessage ?? 'Unknown error'}',
          ),
          backgroundColor: success ? AppTheme.success : AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DashboardController>();
    final hasAnalysis = widget.shipment.hasAnalysis;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 58,
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: (hasAnalysis && !_isApplying)
                      ? () => _handleApply(controller)
                      : null,
                  icon: _isApplying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    _isApplying ? 'APPLYING...' : 'APPLY ROUTE',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppTheme.primary.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: Consumer<DashboardController>(
                  builder: (context, controller, _) {
                    final isSimulatingThis = controller.isSimulating &&
                        controller.simulatingShipmentId ==
                            widget.shipment.shipmentId;
                    final bool isStopped = widget.shipment.status == 'STOPPED';

                    final String label = isSimulatingThis
                        ? 'STOP'
                        : (isStopped ? 'RESUME' : 'TEST');
                    final IconData icon = isSimulatingThis
                        ? Icons.stop
                        : (isStopped
                            ? Icons.play_arrow
                            : Icons.play_circle_outline);
                    final Color btnColor =
                        isSimulatingThis ? AppTheme.danger : AppTheme.success;

                    return ElevatedButton.icon(
                      onPressed: () =>
                          controller.toggleSimulation(widget.shipment),
                      icon: Icon(icon, size: 18),
                      label: Text(label,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w900)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: btnColor.withValues(alpha: 0.1),
                        foregroundColor: btnColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                              color: btnColor.withValues(alpha: 0.3)),
                        ),
                        elevation: 0,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (!hasAnalysis) ...[
          const SizedBox(height: 8),
          const Text(
            'Run AI Analysis first to enable route application.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

class _WhatIfSimulator extends StatefulWidget {
  final Shipment shipment;
  const _WhatIfSimulator({required this.shipment});

  @override
  State<_WhatIfSimulator> createState() => _WhatIfSimulatorState();
}

class _WhatIfSimulatorState extends State<_WhatIfSimulator> {
  double _trafficLevel = 0.4;
  String _weather = 'Clear';
  double _speedModifier = 1.0;
  bool _isHighPriority = false;
  String _selectedModel = 'gemini-2.5-flash';

  double _simulatedRisk = 0.0;
  String _simulatedDelay = "0 mins";
  bool _isAiLoading = false;
  bool _useHeuristics = true;

  @override
  void initState() {
    super.initState();
    _weather = widget.shipment.weather.condition.isEmpty
        ? 'Clear'
        : widget.shipment.weather.condition;
    _recalculate();
  }

  void _recalculate() {
    double risk = 0.1;
    if (_trafficLevel > 0.6) risk += 0.35;
    if (_weather.toLowerCase().contains('rain')) risk += 0.2;
    if (_weather.toLowerCase().contains('storm')) risk += 0.55;
    if (_speedModifier > 1.2) risk += 0.3;
    if (_isHighPriority) risk += 0.1;

    int delayMins = (40 * _trafficLevel).toInt();
    if (_weather.toLowerCase().contains('storm')) delayMins += 60;
    if (_weather.toLowerCase().contains('rain')) delayMins += 25;
    if (_speedModifier > 1.0) delayMins = (delayMins / _speedModifier).toInt();

    setState(() {
      _simulatedRisk = risk.clamp(0.05, 0.98);
      _simulatedDelay = "$delayMins mins";
      _useHeuristics = true;
    });
  }

  Future<void> _runAiSimulation() async {
    setState(() => _isAiLoading = true);
    try {
      final controller = context.read<DashboardController>();
      final result = await controller.simulateTacticalScenario(
        shipmentId: widget.shipment.shipmentId,
        weatherCondition: _weather,
        trafficLevel: _trafficLevel,
        speedModifier: _speedModifier,
        modelName: _selectedModel,
      );

      setState(() {
        _simulatedRisk = (result['risk_score'] as num).toDouble();
        _simulatedDelay = result['delay_prediction']?.toString() ?? '0 mins';
        _isAiLoading = false;
        _useHeuristics = false;
      });
    } catch (e) {
      setState(() => _isAiLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('AI Simulation failed. Falling back to heuristics.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.psychology_outlined,
                color: AppTheme.primary, size: 22),
            const SizedBox(width: 10),
            Text(
              'Tactical "What-if" Simulator',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InfoCard(
          child: Column(
            children: [
              _buildSimulatorControl(
                label: 'Traffic Density',
                value: '${(_trafficLevel * 100).toInt()}%',
                child: Slider(
                  value: _trafficLevel,
                  onChanged: (v) {
                    setState(() => _trafficLevel = v);
                    _recalculate();
                  },
                  activeColor: AppTheme.primary,
                ),
              ),
              const Divider(height: 24),
              _buildSimulatorControl(
                label: 'Weather Scenario',
                value: _weather,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['Clear', 'Rain', 'Storm', 'Fog'].map((w) {
                      final selected = _weather == w;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(w),
                          selected: selected,
                          onSelected: (s) {
                            if (s) {
                              setState(() => _weather = w);
                              _recalculate();
                            }
                          },
                          selectedColor:
                              AppTheme.primary.withValues(alpha: 0.1),
                          labelStyle: TextStyle(
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const Divider(height: 24),
              _buildSimulatorControl(
                label: 'Target Speed Factor',
                value: 'x${_speedModifier.toStringAsFixed(1)}',
                child: Slider(
                  value: _speedModifier,
                  min: 0.5,
                  max: 1.5,
                  onChanged: (v) {
                    setState(() => _speedModifier = v);
                    _recalculate();
                  },
                  activeColor: AppTheme.primary,
                ),
              ),
              const Divider(height: 24),
              _buildSimulatorControl(
                label: 'Inference Model',
                value:
                    _selectedModel.split('-').skip(1).join('-').toUpperCase(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['gemini-2.5-flash'].map((m) {
                      final selected = _selectedModel == m;
                      final label = m.contains('2.5')
                          ? '2.5 Flash'
                          : (m.contains('pro') ? '1.5 Pro' : '1.5 Flash');
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: selected,
                          onSelected: (s) {
                            if (s) {
                              setState(() => _selectedModel = m);
                              _recalculate();
                            }
                          },
                          selectedColor:
                              AppTheme.primary.withValues(alpha: 0.1),
                          labelStyle: TextStyle(
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 10,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Priority Cargo',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                subtitle: const Text(
                  'Simulate impact of time-critical delivery constraints',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                value: _isHighPriority,
                onChanged: (v) {
                  setState(() => _isHighPriority = v);
                  _recalculate();
                },
                activeColor: AppTheme.primary,
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI High Fidelity',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppTheme.textSecondary),
                      ),
                      Text(
                        'Powered by v3 XGBoost Engine',
                        style:
                            TextStyle(fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: _isAiLoading ? null : _runAiSimulation,
                      icon: _isAiLoading
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppTheme.primary))
                          : const Icon(Icons.bolt, size: 16),
                      label: const Text('RUN AI SIM',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w900)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppTheme.primary.withValues(alpha: 0.1),
                        foregroundColor: AppTheme.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _useHeuristics
                      ? AppTheme.primary.withValues(alpha: 0.05)
                      : AppTheme.success.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _useHeuristics
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : AppTheme.success.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _useHeuristics
                              ? 'HEURISTIC ESTIMATE'
                              : 'AI PREDICTION (${_selectedModel.toUpperCase()})',
                          style: TextStyle(
                            color: _useHeuristics
                                ? AppTheme.textMuted
                                : AppTheme.success,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                        if (!_useHeuristics)
                          const Icon(Icons.verified,
                              color: AppTheme.success, size: 14),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _SimResult(
                          label: 'SIMULATED RISK',
                          value: '${(_simulatedRisk * 100).toInt()}%',
                          color: _simulatedRisk > 0.7
                              ? AppTheme.danger
                              : (_simulatedRisk > 0.4
                                  ? AppTheme.warning
                                  : AppTheme.success),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        _SimResult(
                          label: 'EST. DELAY',
                          value: _simulatedDelay,
                          color: AppTheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSimulatorControl({
    required String label,
    required String value,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _SimResult extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SimResult({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
