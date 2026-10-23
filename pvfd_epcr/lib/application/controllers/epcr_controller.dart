import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../../core/epcr_id.dart';
import '../../domain/models/epcr_record.dart';
import '../../domain/models/record_json.dart';
import '../../domain/validation/epcr_validator.dart';
import '../../data/repositories/epcr_repository.dart';
import '../../data/storage/protected_storage_crypto.dart';

/// Sole owner of editable fields and save workflow. No widget/context dependency.
class EpcrController extends ChangeNotifier {
  EpcrController({required this.repository, this.onMessage}) {
    createNewPCR();
    for (final controller in [
      incidentNumber,
      incidentAddress,
      gpsCoordinates,
      emergencyContactName,
      emergencyContactNumber,
      reportingParty,
      reportingPartyNumber,
      formCompletedBy,
      firstName,
      lastName,
      age,
      chiefComplaint,
      assessment,
      treatment,
      disposition,
      allergies,
      medications,
    ]) {
      controller.addListener(scheduleAutoSave);
    }
  }
  final EpcrRepository repository;
  Future<EpcrRecord>? _recordFile;
  EpcrRecord _original = EpcrRecord.fromJson({});
  Map<String, dynamic> _baseline = {};
  bool _dirty = false;
  bool _isNewRecord = true;
  int _revision = 0;

  final incidentNumber = TextEditingController();
  final incidentAddress = TextEditingController();
  final gpsCoordinates = TextEditingController();
  final emergencyContactName = TextEditingController();
  final emergencyContactNumber = TextEditingController();
  final reportingParty = TextEditingController();
  final reportingPartyNumber = TextEditingController();
  final formCompletedBy = TextEditingController();
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final age = TextEditingController();
  final chiefComplaint = TextEditingController();
  final assessment = TextEditingController();
  final treatment = TextEditingController();
  final disposition = TextEditingController();

  final allergies = TextEditingController();
  final medications = TextEditingController();

  int gcsEye = 4;
  int gcsVerbal = 5;
  int gcsMotor = 6;

  int get gcsTotal => gcsEye + gcsVerbal + gcsMotor;

  String patientGender = 'Unknown';
  String levelOfCare = 'EMR';

  bool forestLand = false;

  final Set<String> selectedResponders = <String>{};

  final Set<String> selectedPMH = {};

  static const List<String> responderOptions = [
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
    'R2',
    'R3',
    'R4',
    'R5',
  ];

  static const List<String> pmhOptions = [
    'None',
    'Asthma',
    'Cardiac',
    'Cancer',
    'Stroke',
    'Seizure',
    'Diabetes',
    'HTN',
  ];

  late String epcrNumber;
  late DateTime dateTimeCreated;

  final List<Map<String, dynamic>> vitals = [];

  Timer? _autosaveTimer;
  bool _isLoading = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _change(VoidCallback action) {
    action();
    _notify();
  }

  void _reportError(String message) {
    lastError = message;
    if (!_disposed) onMessage?.call(message);
    _notify();
  }

  bool get isDirty => _dirty;
  int get revision => _revision;
  bool get isLoading => _isLoading;
  int _activeSaves = 0;
  bool get isSaving => _activeSaves > 0;
  String? lastError;
  void Function(String message)? onMessage;
  bool _disposed = false;

  String generateEpcrNumber(DateTime dt) => newEpcrId(dt);

  Future<void> checkRecovery() async {
    try {
      final count = await repository.orphanCount();
      if (count > 0) {
        _reportError('Interrupted save files retained for manual recovery.');
      }
    } on ProtectedStorageException catch (error) {
      _reportError(
        error.code == 'legacyPlaintextRejected'
            ? 'Legacy plaintext ePCR storage detected. Loading and saving are blocked; a confirmed development reset is required. No migration was performed.'
            : 'Protected storage unavailable. Original files have been retained.',
      );
    } catch (_) {
      _reportError('Unable to inspect interrupted saves.');
    }
  }

  Future<bool> flush() async {
    _autosaveTimer?.cancel();
    if (!_dirty) return true;
    try {
      do {
        await autoSavePCR();
      } while (_dirty && !_disposed);
      return true;
    } catch (_) {
      _reportError(
        'Unable to save PCR. Edits remain pending; retry Save before switching records.',
      );
      return false;
    }
  }

  String formatDateTimeForDisplay(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.month)}/${two(dt.day)}/${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  void createNewPCR() {
    if (_disposed) return;
    _original = EpcrRecord.fromJson({});
    _isNewRecord = true;
    _baseline = {};
    _recordFile = null;
    _dirty = false;
    dateTimeCreated = DateTime.now();
    epcrNumber = generateEpcrNumber(dateTimeCreated);
    incidentNumber.text = epcrNumber;
  }

  Future<void> resetForm() async {
    if (!await flush() || _disposed) return;
    _change(() {
      _isLoading = true;

      incidentAddress.clear();
      gpsCoordinates.clear();
      emergencyContactName.clear();
      emergencyContactNumber.clear();
      reportingParty.clear();
      reportingPartyNumber.clear();
      formCompletedBy.clear();
      selectedResponders.clear();
      selectedPMH.clear();
      // signaturePoints.clear();
      forestLand = false;
      firstName.clear();
      lastName.clear();
      age.clear();
      chiefComplaint.clear();
      assessment.clear();
      treatment.clear();
      disposition.clear();
      vitals.clear();

      allergies.clear();
      medications.clear();

      gcsEye = 4;
      gcsVerbal = 5;
      gcsMotor = 6;

      patientGender = 'Unknown';
      levelOfCare = 'EMR';

      createNewPCR();

      _isLoading = false;
    });

    scheduleAutoSave();
  }

  void scheduleAutoSave() {
    if (_isLoading || _disposed) return;

    _dirty = true;
    _revision++;
    _notify();
    _autosaveTimer?.cancel();

    _autosaveTimer = Timer(const Duration(milliseconds: 750), () {
      unawaited(flush());
    });
  }

  Future<EpcrDocumentSnapshot> autoSavePCR() async {
    if (_disposed) throw StateError('Editor is disposed');
    final pcr = EpcrRecord.fromJson(buildPCRJson());
    final revision = _revision;
    final id = epcrNumber;
    final created = dateTimeCreated;
    var documentId = id;
    var documentJson = pcr.toJson();
    final newRecord = _isNewRecord;
    final existing = _recordFile;
    _activeSaves++;
    _notify();
    try {
      if (existing == null) {
        var first = true;
        final operation = repository.create(
          pcr,
          idFactory: () {
            if (first) {
              first = false;
              return id;
            }
            return newEpcrId(DateTime.now());
          },
        );
        _recordFile = operation;
        try {
          final record = await operation;
          documentId = record.id;
          documentJson = record.toJson();
          if (epcrNumber == id) epcrNumber = record.id;
        } catch (_) {
          if (identical(_recordFile, operation)) _recordFile = null;
          rethrow;
        }
      } else {
        final location = await existing;
        final json = pcr.toJson();
        if (newRecord) {
          documentId = location.id;
          documentJson = {
            ...json,
            'epcrNumber': location.id,
            'appRecordId': location.id,
          };
        }
        await repository.save(
          EpcrRecord.fromJson(
            newRecord
                ? {
                    ...json,
                    'epcrNumber': location.id,
                    'appRecordId': location.id,
                  }
                : json,
            sourcePath: location.sourcePath,
          ),
        );
      }
      if (epcrNumber == id && revision == _revision) _dirty = false;
      lastError = null;
      return EpcrDocumentSnapshot(
        record: EpcrRecord.fromJson(documentJson),
        id: documentId,
        dateTimeCreated: created,
      );
    } catch (_) {
      _dirty = true;
      rethrow;
    } finally {
      _activeSaves--;
      _notify();
    }
  }

  Future<void> savePCR() async {
    if (!validateForestGpsRequirement()) return;
    _dirty = true;
    if (!await flush() || _disposed) return;
    onMessage?.call('PCR saved offline.');
  }

  EpcrDocumentSnapshot get documentSnapshot => EpcrDocumentSnapshot(
    record: EpcrRecord.fromJson(buildPCRJson()),
    id: epcrNumber,
    dateTimeCreated: dateTimeCreated,
  );

  Map<String, dynamic> buildPCRJson() => _original
      .applyEdits(_baseline, _formJson(), pmhOptions: pmhOptions)
      .toJson();

  Map<String, dynamic> _formJson() {
    return {
      "appRecordId": epcrNumber,
      "epcrNumber": epcrNumber,
      "nemsisVersionTarget": "3.5.1",
      "incident": {
        "incidentNumber": incidentNumber.text,
        "incidentAddress": incidentAddress.text.trim(),
        "responders": selectedResponders.toList()..sort(),
        "forestLand": forestLand,
        "gpsCoordinates": gpsCoordinates.text.trim(),
        "dateTimeCreated": dateTimeCreated.toIso8601String(),
      },
      "patient": {
        "firstName": firstName.text,
        "lastName": lastName.text,
        "age": age.text,
        "gender": patientGender,
      },
      "crew": {"levelOfCare": levelOfCare},
      "contacts": {
        "emergencyContactName": emergencyContactName.text.trim(),
        "emergencyContactNumber": emergencyContactNumber.text.trim(),
        "reportingParty": reportingParty.text.trim(),
        "reportingPartyNumber": reportingPartyNumber.text.trim(),
      },
      "formCompletion": {
        "completedBy": formCompletedBy.text.trim(),
        /* "signaturePointCount": signaturePoints.where((p) => p != null).length,
        "signaturePoints": signaturePoints.map((p) {
          if (p == null) return null;
          return {"x": p.dx, "y": p.dy};
        }).toList(), */
      },
      "clinical": {
        "chiefComplaint": chiefComplaint.text,
        "vitals": vitals,
        'pmh': selectedPMH.toList(),
        "assessment": assessment.text,
        "treatment": treatment.text,
        "disposition": disposition.text,
        "allergies": allergies.text,
        "medications": medications.text,
        "glasgowComaScale": {
          "eye": gcsEye,
          "verbal": gcsVerbal,
          "motor": gcsMotor,
          "total": gcsTotal,
        },
      },
    };
  }

  Future<List<Map<String, dynamic>>> loadPCRs() async {
    var damaged = false;
    final records = await repository.list(onUnreadable: () => damaged = true);
    if (damaged) {
      _reportError(
        'Some reports could not be read. Original files were retained for recovery.',
      );
    }
    return records
        .map((record) => {...record.toJson(), '_filePath': record.sourcePath})
        .toList();
  }

  Future<void> loadPCR(Map<String, dynamic> pcr) async {
    if (!await flush() || _disposed) return;
    final path = pcr['_filePath'];
    if (path is! String) {
      _reportError('Unable to locate original report.');
      return;
    }
    _autosaveTimer?.cancel();
    _recordFile = Future.value(EpcrRecord.fromJson(pcr, sourcePath: path));
    _original = EpcrRecord.fromJson(pcr, sourcePath: path);
    _isNewRecord = false;
    _change(() {
      _isLoading = true;

      epcrNumber = pcr["epcrNumber"]?.toString() ?? "";
      if (epcrNumber.isEmpty) {
        epcrNumber =
            pcr["appRecordId"]?.toString() ??
            generateEpcrNumber(DateTime.now());
      }

      final incident = recordMap(pcr["incident"]);
      final patient = recordMap(pcr["patient"]);
      final crew = recordMap(pcr["crew"]);
      final contacts = recordMap(pcr["contacts"]);
      final formCompletion = recordMap(pcr["formCompletion"]);
      final clinical = recordMap(pcr["clinical"]);
      final savedVitals = recordList(clinical["vitals"]);

      incidentNumber.text =
          incident["incidentNumber"]?.toString() ?? epcrNumber;
      incidentAddress.text = incident["incidentAddress"]?.toString() ?? "";
      gpsCoordinates.text = incident["gpsCoordinates"]?.toString() ?? "";
      forestLand = incident["forestLand"] == true;
      selectedResponders
        ..clear()
        ..addAll(recordList(incident["responders"]).map((r) => r.toString()));

      selectedPMH
        ..clear()
        ..addAll(readPmh(pcr));

      emergencyContactName.text =
          contacts["emergencyContactName"]?.toString() ?? "";
      emergencyContactNumber.text =
          contacts["emergencyContactNumber"]?.toString() ?? "";
      reportingParty.text = contacts["reportingParty"]?.toString() ?? "";
      reportingPartyNumber.text =
          contacts["reportingPartyNumber"]?.toString() ?? "";
      formCompletedBy.text = formCompletion["completedBy"]?.toString() ?? "";

      final createdText = incident["dateTimeCreated"]?.toString();
      dateTimeCreated = DateTime.tryParse(createdText ?? "") ?? DateTime.now();

      firstName.text = patient["firstName"]?.toString() ?? "";
      lastName.text = patient["lastName"]?.toString() ?? "";
      age.text = patient["age"]?.toString() ?? "";
      patientGender = patient["gender"]?.toString() ?? "Unknown";

      levelOfCare = crew["levelOfCare"]?.toString() ?? "EMR";

      chiefComplaint.text = clinical["chiefComplaint"]?.toString() ?? "";
      assessment.text = clinical["assessment"]?.toString() ?? "";
      treatment.text = clinical["treatment"]?.toString() ?? "";
      disposition.text = clinical["disposition"]?.toString() ?? "";

      allergies.text = clinical["allergies"]?.toString() ?? "";
      medications.text = clinical["medications"]?.toString() ?? "";

      final gcs = recordMap(clinical["glasgowComaScale"]);
      gcsEye = int.tryParse(gcs["eye"]?.toString() ?? "") ?? 4;
      gcsEye = gcsEye.clamp(1, 4);
      gcsVerbal = int.tryParse(gcs["verbal"]?.toString() ?? "") ?? 5;
      gcsVerbal = gcsVerbal.clamp(1, 5);
      gcsMotor = int.tryParse(gcs["motor"]?.toString() ?? "") ?? 6;
      gcsMotor = gcsMotor.clamp(1, 6);

      vitals
        ..clear()
        ..addAll(
          savedVitals.whereType<Map>().map((v) => Map<String, dynamic>.from(v)),
        );

      _isLoading = false;
    });

    _baseline = jsonDecode(jsonEncode(_formJson())) as Map<String, dynamic>;
    _dirty = false;
    _notify();
  }

  bool validateForestGpsRequirement() {
    final error = const EpcrValidator().forestGps(
      forestLand: forestLand,
      gpsCoordinates: gpsCoordinates.text,
    );
    if (error == null) return true;
    _reportError(error);
    return false;
  }

  @override
  void dispose() {
    if (_disposed) return;
    // flush captures the final snapshot synchronously, before controllers die.
    unawaited(flush());
    _disposed = true;
    onMessage = null;
    _autosaveTimer?.cancel();

    incidentNumber.dispose();
    incidentAddress.dispose();
    gpsCoordinates.dispose();
    emergencyContactName.dispose();
    emergencyContactNumber.dispose();
    reportingParty.dispose();
    reportingPartyNumber.dispose();
    formCompletedBy.dispose();
    firstName.dispose();
    lastName.dispose();
    age.dispose();
    chiefComplaint.dispose();
    assessment.dispose();
    treatment.dispose();
    disposition.dispose();

    allergies.dispose();
    medications.dispose();

    super.dispose();
  }
}
