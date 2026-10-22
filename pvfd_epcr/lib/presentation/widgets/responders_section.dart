import 'package:flutter/material.dart';
import '../../application/controllers/epcr_controller.dart';

/// Owns only display filtering; editable selections belong to the controller.
class RespondersSection extends StatefulWidget {
  const RespondersSection({super.key, required this.controller});
  final EpcrController controller;
  @override
  State<RespondersSection> createState() => _RespondersSectionState();
}

class _RespondersSectionState extends State<RespondersSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  EpcrController get c => widget.controller;
  bool showAllResponders = true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final visibleResponders = showAllResponders
        ? EpcrController.responderOptions
        : EpcrController.responderOptions
              .where(c.selectedResponders.contains)
              .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Responders',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  icon: Icon(
                    showAllResponders ? Icons.visibility_off : Icons.visibility,
                  ),
                  label: Text(showAllResponders ? 'Show Selected' : 'Show All'),
                  onPressed: () {
                    setState(() {
                      showAllResponders = !showAllResponders;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (visibleResponders.isEmpty)
              const Text(
                'No responders selected.',
                style: TextStyle(color: Colors.grey),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: visibleResponders.map((responder) {
                  return FilterChip(
                    label: Text(responder),
                    selected: c.selectedResponders.contains(responder),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          c.selectedResponders.add(responder);
                        } else {
                          c.selectedResponders.remove(responder);
                        }
                      });
                      c.scheduleAutoSave();
                    },
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
