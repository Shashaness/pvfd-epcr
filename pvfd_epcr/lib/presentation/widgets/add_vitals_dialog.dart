import 'package:flutter/material.dart';
import 'epcr_field.dart';

class AddVitalsDialog extends StatefulWidget {
  const AddVitalsDialog({
    super.key,
    required this.onSave,
    required this.formatDateTime,
  });
  final void Function(Map<String, dynamic>) onSave;
  final String Function(DateTime) formatDateTime;
  @override
  State<AddVitalsDialog> createState() => _AddVitalsDialogState();
}

class _AddVitalsDialogState extends State<AddVitalsDialog> {
  final pulseController = TextEditingController();
  final o2SatController = TextEditingController();
  final systolicController = TextEditingController();
  final diastolicController = TextEditingController();
  final tempController = TextEditingController();
  final bloodGlucoseController = TextEditingController();
  @override
  void dispose() {
    pulseController.dispose();
    o2SatController.dispose();
    systolicController.dispose();
    diastolicController.dispose();
    tempController.dispose();
    bloodGlucoseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Vitals'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            epcrField('Pulse', pulseController, keyboard: TextInputType.number),
            epcrField(
              'O2 Sat',
              o2SatController,
              keyboard: TextInputType.number,
            ),
            Row(
              children: [
                Expanded(
                  child: epcrField(
                    'Systolic',
                    systolicController,
                    keyboard: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: epcrField(
                    'Diastolic',
                    diastolicController,
                    keyboard: TextInputType.number,
                  ),
                ),
              ],
            ),
            epcrField(
              'Temp',
              tempController,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            epcrField(
              'Blood Glucose',
              bloodGlucoseController,
              keyboard: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final now = DateTime.now();

            widget.onSave({
              "time": now.toIso8601String(),
              "timeDisplay": widget.formatDateTime(now),
              "pulse": pulseController.text.trim(),
              "o2Sat": o2SatController.text.trim(),
              "systolic": systolicController.text.trim(),
              "diastolic": diastolicController.text.trim(),
              "temp": tempController.text.trim(),
              "bloodGlucose": bloodGlucoseController.text.trim(),
            });

            Navigator.pop(context);
          },
          child: const Text('Save Vitals'),
        ),
      ],
    );
  }
}
