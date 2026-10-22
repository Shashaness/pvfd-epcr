import 'package:flutter/material.dart';
import '../../application/controllers/epcr_controller.dart';

/// Owns only display filtering; editable selections belong to the controller.
class PmhSection extends StatefulWidget {
  const PmhSection({super.key, required this.controller});
  final EpcrController controller;
  @override
  State<PmhSection> createState() => _PmhSectionState();
}

class _PmhSectionState extends State<PmhSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  EpcrController get c => widget.controller;
  bool showAllPMH = true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final visiblePMH = showAllPMH
        ? EpcrController.pmhOptions
        : EpcrController.pmhOptions.where(c.selectedPMH.contains).toList();

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
                    'PMH',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  icon: Icon(
                    showAllPMH ? Icons.visibility_off : Icons.visibility,
                  ),
                  label: Text(showAllPMH ? 'Show Selected' : 'Show All'),
                  onPressed: () {
                    setState(() {
                      showAllPMH = !showAllPMH;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (visiblePMH.isEmpty)
              const Text(
                'No PMH selected.',
                style: TextStyle(color: Colors.grey),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: visiblePMH.map((item) {
                  return FilterChip(
                    label: Text(item),
                    selected: c.selectedPMH.contains(item),
                    onSelected: (selected) {
                      setState(() {
                        if (item == 'None' && selected) {
                          c.selectedPMH
                            ..clear()
                            ..add('None');
                        } else {
                          c.selectedPMH.remove('None');

                          if (selected) {
                            c.selectedPMH.add(item);
                          } else {
                            c.selectedPMH.remove(item);
                          }
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
