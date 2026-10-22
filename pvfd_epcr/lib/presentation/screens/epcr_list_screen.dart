import 'package:flutter/material.dart';
import '../../domain/models/record_json.dart';

class PCRListPage extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> Function() loadPCRs;

  const PCRListPage({super.key, required this.loadPCRs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved ePCRs')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: loadPCRs(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load saved ePCRs. Original files have been retained.',
              ),
            );
          }

          final pcrs = snapshot.data ?? [];

          if (pcrs.isEmpty) {
            return const Center(child: Text('No saved ePCRs found.'));
          }

          return ListView.builder(
            itemCount: pcrs.length,
            itemBuilder: (context, index) {
              final pcr = pcrs[index];

              final epcrNumber = pcr["epcrNumber"]?.toString() ?? "Unknown";
              final patient = recordMap(pcr["patient"]);
              final incident = recordMap(pcr["incident"]);
              final incidentAddress =
                  incident["incidentAddress"]?.toString() ?? "";

              final firstName = patient["firstName"]?.toString() ?? "";
              final lastName = patient["lastName"]?.toString() ?? "";
              final age = patient["age"]?.toString() ?? "";

              final patientName = "$firstName $lastName".trim();

              return ListTile(
                leading: const Icon(Icons.description),
                title: Text('ePCR $epcrNumber'),
                subtitle: Text(
                  [
                    patientName.isEmpty
                        ? 'No patient name entered'
                        : '$patientName${age.isNotEmpty ? " — Age $age" : ""}',
                    if (incidentAddress.isNotEmpty) incidentAddress,
                  ].join('\n'),
                ),
                onTap: () {
                  Navigator.pop(context, pcr);
                },
              );
            },
          );
        },
      ),
    );
  }
}
