import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/dashboard_controller.dart';
import '../core/theme/app_theme.dart';

class AddShipmentDialog extends StatefulWidget {
  const AddShipmentDialog({super.key});

  @override
  State<AddShipmentDialog> createState() => _AddShipmentDialogState();
}

class _AddShipmentDialogState extends State<AddShipmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _originController = TextEditingController();
  final _destController = TextEditingController();
  bool _isSubmitting = false;

  String _selectedMode = 'ROAD';
  String _selectedPriority = 'NORMAL';

  @override
  void dispose() {
    _idController.dispose();
    _originController.dispose();
    _destController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await context.read<DashboardController>().createShipment(
            shipmentId: _idController.text.trim(),
            origin: _originController.text.trim(),
            destination: _destController.text.trim(),
            mode: _selectedMode,
            priority: _selectedPriority,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child:
                          const Icon(Icons.add_road, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Add New Shipment',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _idController,
                  decoration: _inputDecoration('Shipment ID', 'e.g. SH-102'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _originController,
                  decoration:
                      _inputDecoration('Origin Address', 'e.g. Mumbai, India'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _destController,
                  decoration: _inputDecoration(
                      'Destination Address', 'e.g. Delhi, India'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedMode,
                        decoration: _inputDecoration('Transport Mode', ''),
                        items: const [
                          DropdownMenuItem(value: 'ROAD', child: Text('Road')),
                          DropdownMenuItem(value: 'AIR', child: Text('Air')),
                          DropdownMenuItem(value: 'SEA', child: Text('Sea')),
                        ],
                        onChanged: (v) => setState(() => _selectedMode = v!),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedPriority,
                        decoration: _inputDecoration('Priority', ''),
                        items: const [
                          DropdownMenuItem(
                              value: 'NORMAL', child: Text('Normal')),
                          DropdownMenuItem(value: 'HIGH', child: Text('High')),
                          DropdownMenuItem(
                              value: 'URGENT', child: Text('Urgent')),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedPriority = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed:
                            _isSubmitting ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Create'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.grey.withValues(alpha: 0.05),
    );
  }
}
