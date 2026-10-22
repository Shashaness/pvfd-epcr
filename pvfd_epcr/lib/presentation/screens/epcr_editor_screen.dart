import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../application/controllers/epcr_controller.dart';
import '../../application/services/epcr_lifecycle_service.dart';
import '../../data/repositories/epcr_repository.dart';
import '../../data/storage/epcr_storage_service.dart';
import '../../services/document_export_service.dart';
import '../../services/maps_service.dart';
import '../../services/printing_service.dart';
import '../../services/sharing_service.dart';
import 'epcr_list_screen.dart';
import '../widgets/epcr_field.dart';
import '../widgets/pmh_section.dart';
import '../widgets/responders_section.dart';
import '../widgets/add_vitals_dialog.dart';

/// Owns one EpcrController for its lifetime. All field widgets borrow its fields.
class PCRFormPage extends StatefulWidget {
  const PCRFormPage({
    super.key,
    this.documentsDirectory,
    this.storage,
    this.repository,
    this.controllerFactory,
  });
  final Future<Directory> Function()? documentsDirectory;
  final EpcrStorageService? storage;
  final EpcrRepository? repository;
  final EpcrController Function()? controllerFactory;
  @override
  State<PCRFormPage> createState() => _PCRFormPageState();
}

class _PCRFormPageState extends State<PCRFormPage> {
  late final EpcrController c;
  late final EpcrLifecycleService _lifecycle;
  late final DocumentExportService _exports;
  final _sharing = SharingService();
  final _printing = PrintingService();
  final _maps = MapsService();

  @override
  void initState() {
    super.initState();
    c =
        widget.controllerFactory?.call() ??
        EpcrController(
          repository:
              widget.repository ??
              LocalEpcrRepository(
                documentsDirectory: widget.documentsDirectory,
                storage: widget.storage,
              ),
          onMessage: _reportError,
        );
    c.onMessage = _reportError;
    c.addListener(_refresh);
    _lifecycle = EpcrLifecycleService(c)..attach();
    _exports = DocumentExportService(
      documentsDirectory: widget.documentsDirectory,
    );
    unawaited(c.checkRecovery());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _reportError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      _reportError(
        'Operation failed. Original reports were retained. Retry Save if edits are pending.',
      );
    }
  }

  @override
  void dispose() {
    _lifecycle.detach();
    c.removeListener(_refresh);
    c.dispose();
    super.dispose();
  }

  Future<void> showAddVitalsDialog() => showDialog<void>(
    context: context,
    builder: (_) => AddVitalsDialog(
      formatDateTime: c.formatDateTimeForDisplay,
      onSave: (vital) {
        c.vitals.add(vital);
        c.scheduleAutoSave();
      },
    ),
  );

  Future<void> exportNemsisXml() async {
    if (!c.validateForestGpsRequirement()) return;
    final snapshot = await c.autoSavePCR();
    if (!mounted) return;
    final file = await _exports.writeXml(snapshot);
    if (mounted) _reportError('NEMSIS XML exported to\n${file.path}');
  }

  Future<void> exportPdfAndNemsis() async {
    if (!c.validateForestGpsRequirement()) return;
    final snapshot = await c.autoSavePCR();
    if (!mounted) return;
    final file = await _exports.writePdf(snapshot);
    await _exports.writeXml(snapshot);
    if (mounted) {
      _reportError('PDF and NEMSIS XML exported to\n${file.parent.path}');
    }
  }

  Future<void> emailPdf() async {
    if (!c.validateForestGpsRequirement()) return;
    final snapshot = await c.autoSavePCR();
    if (!mounted) return;
    final file = await _exports.writePdf(snapshot, temporary: true);
    await _sharing.sharePdf(file, snapshot.id);
  }

  Future<void> emailNemsis() async {
    if (!c.validateForestGpsRequirement()) return;
    final snapshot = await c.autoSavePCR();
    if (!mounted) return;
    final file = await _exports.writeXml(snapshot, temporary: true);
    await _sharing.shareXml(file, snapshot.id);
  }

  Future<void> printCurrentPCR() async {
    if (!c.validateForestGpsRequirement()) return;
    final snapshot = await c.autoSavePCR();
    if (!mounted) return;
    await _printing.printPdf(
      await _exports.pdf.generate(snapshot.record.toJson()),
      snapshot.id,
    );
  }

  Future<void> openIncidentAddressInGoogleMaps() async {
    final address = c.incidentAddress.text.trim();
    if (address.isEmpty) {
      _reportError('Enter an incident address first.');
      return;
    }
    await _perform(() async {
      if (!await _maps.openAddress(address) && mounted) {
        _reportError('Could not open Google Maps.');
      }
    });
  }

  String vitalValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  String bloodPressureValue(Map<String, dynamic> vital) {
    final systolic = vital["systolic"]?.toString().trim() ?? "";
    final diastolic = vital["diastolic"]?.toString().trim() ?? "";

    if (systolic.isEmpty && diastolic.isEmpty) return '-';
    if (systolic.isEmpty) return '/$diastolic';
    if (diastolic.isEmpty) return '$systolic/';
    return '$systolic/$diastolic';
  }

  Widget buildGcsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Glasgow Coma Scale',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<int>(
              initialValue: c.gcsEye,
              decoration: const InputDecoration(
                labelText: 'Eye Opening',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 4, child: Text('4 - Spontaneous')),
                DropdownMenuItem(value: 3, child: Text('3 - To voice')),
                DropdownMenuItem(value: 2, child: Text('2 - To pain')),
                DropdownMenuItem(value: 1, child: Text('1 - None')),
              ],
              onChanged: (v) {
                setState(() => c.gcsEye = v ?? 4);
                c.scheduleAutoSave();
              },
            ),

            const SizedBox(height: 12),

            DropdownButtonFormField<int>(
              initialValue: c.gcsVerbal,
              decoration: const InputDecoration(
                labelText: 'Verbal Response',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 5, child: Text('5 - Oriented')),
                DropdownMenuItem(value: 4, child: Text('4 - Confused')),
                DropdownMenuItem(
                  value: 3,
                  child: Text('3 - Inappropriate words'),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text('2 - Incomprehensible sounds'),
                ),
                DropdownMenuItem(value: 1, child: Text('1 - None')),
              ],
              onChanged: (v) {
                setState(() => c.gcsVerbal = v ?? 5);
                c.scheduleAutoSave();
              },
            ),

            const SizedBox(height: 12),

            DropdownButtonFormField<int>(
              initialValue: c.gcsMotor,
              decoration: const InputDecoration(
                labelText: 'Motor Response',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 6, child: Text('6 - Obeys commands')),
                DropdownMenuItem(value: 5, child: Text('5 - Localizes pain')),
                DropdownMenuItem(
                  value: 4,
                  child: Text('4 - Withdraws from pain'),
                ),
                DropdownMenuItem(value: 3, child: Text('3 - Flexion')),
                DropdownMenuItem(value: 2, child: Text('2 - Extension')),
                DropdownMenuItem(value: 1, child: Text('1 - None')),
              ],
              onChanged: (v) {
                setState(() => c.gcsMotor = v ?? 6);
                c.scheduleAutoSave();
              },
            ),

            const SizedBox(height: 12),

            Text(
              'GCS Total: ${c.gcsTotal}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildVitalsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Vitals',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            FilledButton.icon(
              onPressed: showAddVitalsDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Vitals'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (c.vitals.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('No vitals entered yet.'),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Time')),
                DataColumn(label: Text('Pulse')),
                DataColumn(label: Text('O2 Sat')),
                DataColumn(label: Text('BP')),
                DataColumn(label: Text('Temp')),
                DataColumn(label: Text('BGL')),
              ],
              rows: c.vitals.map((vital) {
                return DataRow(
                  cells: [
                    DataCell(Text(vitalValue(vital["timeDisplay"]))),
                    DataCell(Text(vitalValue(vital["pulse"]))),
                    DataCell(Text(vitalValue(vital["o2Sat"]))),
                    DataCell(Text(bloodPressureValue(vital))),
                    DataCell(Text(vitalValue(vital["temp"]))),
                    DataCell(Text(vitalValue(vital["bloodGlucose"]))),
                  ],
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget buildForestLandSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Forest Land'),
              subtitle: const Text(
                'GPS Coordinates are required when checked.',
              ),
              value: c.forestLand,
              onChanged: (value) {
                setState(() => c.forestLand = value ?? false);
                c.scheduleAutoSave();
              },
            ),
            epcrField(
              c.forestLand ? 'GPS Coordinates *' : 'GPS Coordinates',
              c.gpsCoordinates,
              keyboard: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              prefixIcon: const Icon(Icons.gps_fixed),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildAdditionalContactsSection() {
    return Card(
      child: ExpansionTile(
        title: const Text('Additional Contacts'),
        subtitle: const Text('Emergency contact and reporting party'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          epcrField('Emergency Contact', c.emergencyContactName),
          epcrField(
            'EC Number',
            c.emergencyContactNumber,
            keyboard: TextInputType.phone,
          ),
          epcrField('Reporting Party', c.reportingParty),
          epcrField(
            'RP Number',
            c.reportingPartyNumber,
            keyboard: TextInputType.phone,
          ),
        ],
      ),
    );
  }

  Widget buildSignatureSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Form Completion',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            epcrField('Completed By', c.formCompletedBy),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PVFD ePCR', style: TextStyle(fontSize: 16)),
        /*actions: [
          IconButton(
            icon: const Icon(Icons.monitor_heart),
            tooltip: 'Add Vitals',
            onPressed: showAddVitalsDialog,
          ),
        ], */
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            /* const DrawerHeader(
              child: Text(
                'PVFD ePCR',
                style: TextStyle(fontSize: 14),
              ),
            ), */
            Padding(
              padding: EdgeInsets.only(left: 20.0, top: 30.0),
              child: Text('PVFD ePCR v0.1', style: TextStyle(fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New'),
              onTap: () {
                Navigator.pop(context);
                c.resetForm();
              },
            ),
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('List'),
              onTap: () async {
                Navigator.pop(context);

                final selectedPCR = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PCRListPage(loadPCRs: c.loadPCRs),
                  ),
                );

                if (selectedPCR != null) {
                  await c.loadPCR(selectedPCR);
                }
              },
            ),
            /* ListTile(
              leading: const Icon(Icons.monitor_heart),
              title: const Text('Add Vitals'),
              onTap: () {
                Navigator.pop(context);
                showAddVitalsDialog();
              },
            ), */
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('Print'),
              onTap: () async {
                Navigator.pop(context);
                await _perform(printCurrentPCR);
              },
            ),
            ExpansionTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              childrenPadding: const EdgeInsets.only(left: 16),
              children: [
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: const Text('PDF'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _perform(emailPdf);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('NEMSIS XML'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _perform(emailNemsis);
                  },
                ),
              ],
            ),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('Export PDF + NEMSIS'),
              onTap: () async {
                Navigator.pop(context);
                await _perform(exportPdfAndNemsis);
              },
            ),
            ListTile(
              leading: const Icon(Icons.send),
              title: const Text('Export NEMSIS Only'),
              onTap: () async {
                Navigator.pop(context);
                await _perform(exportNemsisXml);
              },
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          epcrField('ePCR Number', c.incidentNumber, readOnly: true),
          epcrField(
            'Incident Address',
            c.incidentAddress,
            prefixIcon: const Icon(Icons.location_on),
            suffixIcon: IconButton(
              icon: const Icon(Icons.map),
              tooltip: 'Open in Google Maps',
              onPressed: openIncidentAddressInGoogleMaps,
            ),
          ),
          RespondersSection(controller: c),
          PmhSection(controller: c),
          const SizedBox(height: 12),
          epcrField('Patient First Name', c.firstName),
          epcrField('Patient Last Name', c.lastName),
          epcrField('Age', c.age, keyboard: TextInputType.number),
          DropdownButtonFormField<String>(
            initialValue:
                ['Male', 'Female', 'Unknown'].contains(c.patientGender)
                ? c.patientGender
                : 'Unknown',
            decoration: const InputDecoration(
              labelText: 'Gender',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Unknown', child: Text('Unknown')),
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
            ],
            onChanged: (v) {
              setState(() => c.patientGender = v ?? 'Unknown');
              c.scheduleAutoSave();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue:
                ['EMR', 'EMT', 'AEMT', 'Paramedic'].contains(c.levelOfCare)
                ? c.levelOfCare
                : 'EMR',
            decoration: const InputDecoration(
              labelText: 'Provider Level',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'EMR', child: Text('EMR')),
              DropdownMenuItem(value: 'EMT', child: Text('EMT')),
              DropdownMenuItem(value: 'AEMT', child: Text('AEMT')),
              DropdownMenuItem(value: 'Paramedic', child: Text('Paramedic')),
            ],
            onChanged: (v) {
              setState(() => c.levelOfCare = v ?? 'EMR');
              c.scheduleAutoSave();
            },
          ),
          const SizedBox(height: 12),
          epcrField('Chief Complaint', c.chiefComplaint, lines: 2),
          epcrField('Allergies', c.allergies, lines: 2),
          epcrField('Medications', c.medications, lines: 2),
          buildVitalsSection(),
          buildGcsSection(),
          const SizedBox(height: 12),
          epcrField('Assessment / Narrative', c.assessment, lines: 5),
          epcrField('Treatment Provided', c.treatment, lines: 4),
          epcrField('Disposition / Transport', c.disposition, lines: 3),
          buildAdditionalContactsSection(),
          buildForestLandSection(),
          buildSignatureSection(),
          const SizedBox(height: 20),
          /* FilledButton.icon(
            onPressed: savePCR,
            icon: const Icon(Icons.save),
            label: const Text('Save Offline PCR'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: printCurrentPCR,
            icon: const Icon(Icons.print),
            label: const Text('Print PCR'),
          ), */
        ],
      ),
    );
  }
}
