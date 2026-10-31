
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

// ============================================================
// FAMILYCARE+ - CHILD DOCTOR CONSULTATION
// ============================================================
//
// Current Flask backend:
//
// GET    /api/v1/patients/profiles/{profileId}
// POST   /api/v1/patients/profiles/{profileId}/connect-doctor
//
// GET    /api/v1/children/{childId}/consultations
// POST   /api/v1/children/{childId}/consultations
// PATCH  /api/v1/children/{childId}/consultations/{recordId}
// DELETE /api/v1/children/{childId}/consultations/{recordId}
//
// GET    /api/v1/children/{childId}/consultation-requests
// POST   /api/v1/children/{childId}/consultation-requests
// PATCH  /api/v1/children/{childId}/consultation-requests/{recordId}
// DELETE /api/v1/children/{childId}/consultation-requests/{recordId}
//
// IMPORTANT:
// Consultation journal != doctor consultation request.
// A request is not a confirmed appointment.
// No live call, video call, chat or appointment booking.
// ============================================================

class DoctorConsultationColors {
  static const navy = Color(0xFF143C60);
  static const text = Color(0xFF263F45);
  static const muted = Color(0xFF81918C);
  static const background = Color(0xFFF2F7FD);
  static const border = Color(0xFFE4E9E6);
  static const cream = Color(0xFFFFFDF8);

  static const green = Color(0xFF347D61);
  static const blue = Color(0xFF2381F4);
  static const purple = Color(0xFF8963C4);
  static const orange = Color(0xFFCB955C);
  static const red = Color(0xFFB7434E);

  static const lightGreen = Color(0xFFEAF5ED);
  static const lightBlue = Color(0xFFEAF5FF);
  static const lightOrange = Color(0xFFFFF4E7);
}

// ============================================================
// ENUMS
// ============================================================

enum ConsultationStatus {
  planned,
  completed,
  cancelled,
}

extension ConsultationStatusDetails on ConsultationStatus {
  String get label {
    switch (this) {
      case ConsultationStatus.planned:
        return 'Planned';
      case ConsultationStatus.completed:
        return 'Completed';
      case ConsultationStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case ConsultationStatus.planned:
        return DoctorConsultationColors.blue;
      case ConsultationStatus.completed:
        return DoctorConsultationColors.green;
      case ConsultationStatus.cancelled:
        return DoctorConsultationColors.muted;
    }
  }
}

enum ConsultationMode {
  clinic,
  phone,
  video,
  homeVisit,
  other,
}

extension ConsultationModeDetails on ConsultationMode {
  String get label {
    switch (this) {
      case ConsultationMode.clinic:
        return 'Clinic / Hospital';
      case ConsultationMode.phone:
        return 'Phone';
      case ConsultationMode.video:
        return 'Video';
      case ConsultationMode.homeVisit:
        return 'Home Visit';
      case ConsultationMode.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case ConsultationMode.clinic:
        return Icons.local_hospital_outlined;
      case ConsultationMode.phone:
        return Icons.phone_outlined;
      case ConsultationMode.video:
        return Icons.videocam_outlined;
      case ConsultationMode.homeVisit:
        return Icons.home_outlined;
      case ConsultationMode.other:
        return Icons.medical_services_outlined;
    }
  }
}

enum ConsultationFilter {
  all,
  planned,
  completed,
  cancelled,
}

// ============================================================
// DATE UTILITIES
// ============================================================

class ConsultationDateFormatter {
  static const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String format(DateTime date) {
    return '${date.day} '
        '${months[date.month - 1]} '
        '${date.year}';
  }

  static String api(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime parse(dynamic raw) {
    final parsed = DateTime.tryParse(
      (raw ?? '').toString(),
    );

    if (parsed == null) {
      throw const FormatException('Invalid consultation date');
    }

    return parsed;
  }

  static DateTime? optional(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw.toString());
  }

  static String time(TimeOfDay? value) {
    if (value == null) return '';

    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  static TimeOfDay? parseTime(dynamic raw) {
    final value = (raw ?? '').toString();
    final parts = value.split(':');

    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return TimeOfDay(
      hour: hour,
      minute: minute,
    );
  }
}

// ============================================================
// PUBLIC CONSULTATION MODEL
// Compatible with child_dashboard_screen.dart
// ============================================================

class DoctorConsultationRecord {
  final String id;
  final String profileId;
  final ConsultationStatus status;
  final ConsultationMode mode;

  final DateTime consultationDate;
  final TimeOfDay? consultationTime;
  final DateTime? followUpDate;

  final String doctorName;
  final String clinicName;
  final String reason;
  final String symptoms;
  final String clinicalAdvice;
  final String notes;

  const DoctorConsultationRecord({
    required this.id,
    required this.profileId,
    required this.status,
    required this.mode,
    required this.consultationDate,
    this.consultationTime,
    this.followUpDate,
    this.doctorName = '',
    this.clinicName = '',
    required this.reason,
    this.symptoms = '',
    this.clinicalAdvice = '',
    this.notes = '',
  });

  DoctorConsultationRecord copyWith({
    ConsultationStatus? status,
  }) {
    return DoctorConsultationRecord(
      id: id,
      profileId: profileId,
      status: status ?? this.status,
      mode: mode,
      consultationDate: consultationDate,
      consultationTime: consultationTime,
      followUpDate: followUpDate,
      doctorName: doctorName,
      clinicName: clinicName,
      reason: reason,
      symptoms: symptoms,
      clinicalAdvice: clinicalAdvice,
      notes: notes,
    );
  }
}

// ============================================================
// CONSULTATION API MAPPER
//
// Current backend does not have separate fields for:
// visit time, doctor name, clinic, symptoms and advice.
//
// Store these as versioned JSON inside `notes`.
// This is a temporary compatibility format.
//
// Server `notes` limit: 2000 characters.
// ============================================================

class ConsultationApiMapper {
  static const String _prefix = 'FC_VISIT_V1:';

  static String _text(dynamic value) {
    return (value ?? '').toString();
  }

  static ConsultationStatus parseStatus(dynamic value) {
    switch (_text(value).toLowerCase()) {
      case 'completed':
        return ConsultationStatus.completed;
      case 'cancelled':
        return ConsultationStatus.cancelled;
      default:
        return ConsultationStatus.planned;
    }
  }

  static ConsultationMode parseMode(dynamic value) {
    final valueText = _text(value).toLowerCase();

    for (final mode in ConsultationMode.values) {
      if (mode.label.toLowerCase() == valueText) {
        return mode;
      }
    }

    if (valueText.contains('video')) {
      return ConsultationMode.video;
    }

    if (valueText.contains('phone')) {
      return ConsultationMode.phone;
    }

    if (valueText.contains('home')) {
      return ConsultationMode.homeVisit;
    }

    if (valueText.contains('clinic') ||
        valueText.contains('hospital')) {
      return ConsultationMode.clinic;
    }

    return ConsultationMode.other;
  }

  static DoctorConsultationRecord fromApi(
      Map<String, dynamic> json,
      String profileId,
      ) {
    final storedNotes = _text(json['notes']);

    Map<String, dynamic> extra = {};

    if (storedNotes.startsWith(_prefix)) {
      try {
        final decoded = jsonDecode(
          storedNotes.substring(_prefix.length),
        );

        if (decoded is Map) {
          extra = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Keep legacy text readable rather than losing it.
      }
    }

    final structured = extra.isNotEmpty;

    final doctorName = _text(extra['doctor_name']);

    return DoctorConsultationRecord(
      id: _text(json['id']),
      profileId: profileId,
      status: parseStatus(json['status']),
      mode: parseMode(json['category']),
      consultationDate:
      ConsultationDateFormatter.parse(json['date']),
      consultationTime: ConsultationDateFormatter.parseTime(
        extra['visit_time'],
      ),
      followUpDate: ConsultationDateFormatter.optional(
        json['nextDate'],
      ),
      doctorName: doctorName.isEmpty
          ? _text(json['provider'])
          : doctorName,
      clinicName: _text(extra['clinic_name']),
      reason: _text(json['title']),
      symptoms: _text(extra['symptoms']),
      clinicalAdvice: _text(extra['clinical_advice']),
      notes: structured
          ? _text(extra['notes'])
          : storedNotes,
    );
  }

  static Map<String, dynamic> toApi(
      DoctorConsultationRecord record,
      ) {
    final reason = record.reason.trim();

    if (reason.isEmpty || reason.runes.length > 160) {
      throw const ConsultationApiException(
        'Reason must be between 1 and 160 characters.',
      );
    }

    final metadata = <String, dynamic>{
      'visit_time': ConsultationDateFormatter.time(
        record.consultationTime,
      ),
      'doctor_name': record.doctorName.trim(),
      'clinic_name': record.clinicName.trim(),
      'symptoms': record.symptoms.trim(),
      'clinical_advice': record.clinicalAdvice.trim(),
      'notes': record.notes.trim(),
    };

    final encodedNotes = _prefix + jsonEncode(metadata);

    if (encodedNotes.runes.length > 2000) {
      throw const ConsultationApiException(
        'Combined visit notes exceed the backend '
            'limit of 2000 characters. '
            'Please shorten the symptoms, advice or notes.',
      );
    }

    return {
      'title': reason,
      'date': ConsultationDateFormatter.api(
        record.consultationDate,
      ),
      'status': record.status.label,
      'category': record.mode.label,
      'provider': record.doctorName.trim(),
      'nextDate': record.followUpDate == null
          ? ''
          : ConsultationDateFormatter.api(
        record.followUpDate!,
      ),
      'notes': encodedNotes,
    };
  }
}

// ============================================================
// DOCTOR REQUEST MODEL
// ============================================================

class DoctorConsultationRequest {
  final String id;
  final String title;
  final DateTime preferredDate;
  final String message;
  final String status;

  const DoctorConsultationRequest({
    required this.id,
    required this.title,
    required this.preferredDate,
    required this.message,
    this.status = 'REQUESTED',
  });

  factory DoctorConsultationRequest.fromApi(
      Map<String, dynamic> json,
      ) {
    return DoctorConsultationRequest(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      preferredDate:
      ConsultationDateFormatter.parse(json['date']),
      message: (json['notes'] ?? '').toString(),
      status: (json['status'] ?? 'REQUESTED').toString(),
    );
  }

  Map<String, dynamic> toApi() {
    return {
      'title': title.trim(),
      'date': ConsultationDateFormatter.api(preferredDate),
      'notes': message.trim(),
    };
  }
}

// ============================================================
// API EXCEPTION
// ============================================================

class ConsultationApiException implements Exception {
  final String message;
  final int statusCode;

  const ConsultationApiException(
      this.message, {
        this.statusCode = 0,
      });

  @override
  String toString() => message;
}

// ============================================================
// FLASK API CLIENT
// ============================================================

class _ConsultationApi {
  final String baseUrl;
  final String profileId;

  final http.Client _client = http.Client();

  _ConsultationApi({
    required this.baseUrl,
    required this.profileId,
  });

  String get childPath {
    return '/api/v1/children/'
        '${Uri.encodeComponent(profileId)}';
  }

  String get profilePath {
    return '/api/v1/patients/profiles/'
        '${Uri.encodeComponent(profileId)}';
  }

  String journalPath([String? recordId]) {
    const path = 'consultations';

    if (recordId == null) {
      return '$childPath/$path';
    }

    return '$childPath/$path/'
        '${Uri.encodeComponent(recordId)}';
  }

  String requestPath([String? recordId]) {
    const path = 'consultation-requests';

    if (recordId == null) {
      return '$childPath/$path';
    }

    return '$childPath/$path/'
        '${Uri.encodeComponent(recordId)}';
  }

  void dispose() {
    _client.close();
  }

  Future<Map<String, String>> _headers() async {
    final token = await FamilyCareSession.accessToken();

    if (token == null || token.trim().isEmpty) {
      throw const ConsultationApiException(
        'Please sign in again.',
        statusCode: 401,
      );
    }

    return {
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> call(
      String method,
      String path, {
        Map<String, dynamic>? body,
      }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers();

    late http.Response response;

    switch (method) {
      case 'GET':
        response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 35));
        break;

      case 'POST':
        response = await _client
            .post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        )
            .timeout(const Duration(seconds: 35));
        break;

      case 'PATCH':
        response = await _client
            .patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        )
            .timeout(const Duration(seconds: 35));
        break;

      case 'DELETE':
        response = await _client
            .delete(uri, headers: headers)
            .timeout(const Duration(seconds: 35));
        break;

      default:
        throw const ConsultationApiException(
          'Unsupported API method.',
        );
    }

    Map<String, dynamic> data = {};

    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(
          utf8.decode(response.bodyBytes),
        );

        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        } else {
          throw const FormatException();
        }
      } catch (_) {
        throw ConsultationApiException(
          'Server returned an invalid response.',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      String message =
          'Request failed (${response.statusCode}).';

      final error = data['error'];

      if (error is Map && error['message'] is String) {
        message = error['message'] as String;
      } else if (error is String && error.isNotEmpty) {
        message = error;
      }

      if (response.statusCode == 401) {
        message = 'Session expired. Please log in again.';
      }

      if (response.statusCode == 403) {
        message = 'You cannot access this child profile.';
      }

      throw ConsultationApiException(
        message,
        statusCode: response.statusCode,
      );
    }

    return data;
  }

  Future<List<Map<String, dynamic>>> getAll(
      String basePath,
      ) async {
    final items = <Map<String, dynamic>>[];

    for (int page = 1; page <= 100; page++) {
      final data = await call(
        'GET',
        '$basePath?page=$page&per_page=100',
      );

      final rawItems = data['items'];

      if (rawItems is! List) {
        throw const ConsultationApiException(
          'Invalid list response received from server.',
        );
      }

      for (final item in rawItems) {
        if (item is Map) {
          items.add(Map<String, dynamic>.from(item));
        }
      }

      final total = data['total'];

      if (rawItems.length < 100 ||
          (total is num &&
              items.length >= total.toInt())) {
        break;
      }
    }

    return items;
  }
}

// ============================================================
// MAIN DOCTOR CONSULTATION SCREEN
// ============================================================

class DoctorConsultationScreen extends StatefulWidget {
  final String profileId;
  final String childName;
  final DateTime? childDateOfBirth;
  final String apiBaseUrl;

  // Constructor compatibility with child dashboard.
  final List<DoctorConsultationRecord> initialRecords;

  final ValueChanged<List<DoctorConsultationRecord>>?
  onRecordsChanged;

  const DoctorConsultationScreen({
    super.key,
    required this.profileId,
    this.childName = 'Child',
    this.childDateOfBirth,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.initialRecords = const [],
    this.onRecordsChanged,
  });

  @override
  State<DoctorConsultationScreen> createState() =>
      _DoctorConsultationScreenState();
}

class _DoctorConsultationScreenState
    extends State<DoctorConsultationScreen> {
  late _ConsultationApi _api;

  final TextEditingController _searchController =
  TextEditingController();

  List<DoctorConsultationRecord> _records = [];
  List<DoctorConsultationRequest> _requests = [];

  Map<String, dynamic>? _childProfile;

  ConsultationFilter _filter = ConsultationFilter.all;

  bool _loadingDoctor = true;
  bool _loadingJournal = true;
  bool _loadingRequests = true;

  bool _connectingDoctor = false;
  bool _savingJournal = false;
  bool _savingRequest = false;

  String? _doctorError;
  String? _journalError;
  String? _requestsError;

  int _generation = 0;

  String get _baseUrl {
    final configured = widget.apiBaseUrl.trim();

    if (configured.isNotEmpty) {
      return configured.replaceAll(RegExp(r'/+$'), '');
    }

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5001';
    }

    return 'http://127.0.0.1:5001';
  }

  @override
  void initState() {
    super.initState();

    _api = _ConsultationApi(
      baseUrl: _baseUrl,
      profileId: widget.profileId,
    );

    _searchController.addListener(_searchChanged);

    _refreshAll();
  }

  @override
  void didUpdateWidget(
      covariant DoctorConsultationScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.profileId != widget.profileId ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _generation++;

      _api.dispose();

      _api = _ConsultationApi(
        baseUrl: _baseUrl,
        profileId: widget.profileId,
      );

      _records = [];
      _requests = [];
      _childProfile = null;

      _doctorError = null;
      _journalError = null;
      _requestsError = null;

      _filter = ConsultationFilter.all;

      _searchController.clear();

      _refreshAll();
    }
  }

  @override
  void dispose() {
    _generation++;

    _searchController.removeListener(_searchChanged);
    _searchController.dispose();

    _api.dispose();

    super.dispose();
  }

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  bool _validRequest(
      int generation,
      String profileId,
      ) {
    return mounted &&
        generation == _generation &&
        profileId == widget.profileId;
  }

  String _text(
      dynamic value, {
        String fallback = '',
      }) {
    final result = (value ?? '').toString().trim();
    return result.isEmpty ? fallback : result;
  }

  Map<String, dynamic>? get _connectedDoctor {
    final doctor = _childProfile?['doctor'];

    if (doctor is Map) {
      return Map<String, dynamic>.from(doctor);
    }

    return null;
  }

  String _friendlyError(Object error) {
    if (error is ConsultationApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'Server response timed out. Please retry.';
    }

    if (error is http.ClientException) {
      return 'Unable to connect to the server.';
    }

    if (error is PlatformException) {
      return 'Could not access your login session.';
    }

    if (error is FormatException) {
      return 'Invalid consultation data received.';
    }

    return 'Something went wrong. Please try again.';
  }

  void _showMessage(
      String message, {
        bool error = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error
              ? DoctorConsultationColors.red
              : DoctorConsultationColors.navy,
          content: Text(message),
        ),
      );
  }

  // ==========================================================
  // LOAD ALL DATA
  // ==========================================================

  Future<void> _refreshAll() async {
    if (!mounted) return;

    final generation = ++_generation;
    final profileId = widget.profileId;
    final api = _api;

    setState(() {
      _loadingDoctor = true;
      _loadingJournal = true;
      _loadingRequests = true;

      _doctorError = null;
      _journalError = null;
      _requestsError = null;
    });

    await Future.wait([
      _loadDoctor(api, generation, profileId),
      _loadJournal(api, generation, profileId),
      _loadRequests(api, generation, profileId),
    ]);
  }

  Future<void> _loadDoctor(
      _ConsultationApi api,
      int generation,
      String profileId,
      ) async {
    try {
      final response = await api.call(
        'GET',
        api.profilePath,
      );

      final rawProfile = response['profile'];

      if (rawProfile is! Map) {
        throw const ConsultationApiException(
          'Child profile data was not returned.',
        );
      }

      final profile =
      Map<String, dynamic>.from(rawProfile);

      if (profile['module'] != 'child') {
        throw const ConsultationApiException(
          'Selected profile is not a child profile.',
        );
      }

      if (!_validRequest(generation, profileId)) {
        return;
      }

      setState(() {
        _childProfile = profile;
        _doctorError = null;
        _loadingDoctor = false;
      });
    } catch (error) {
      if (!_validRequest(generation, profileId)) {
        return;
      }

      setState(() {
        _childProfile = null;
        _doctorError = _friendlyError(error);
        _loadingDoctor = false;
      });
    }
  }

  Future<void> _loadJournal(
      _ConsultationApi api,
      int generation,
      String profileId,
      ) async {
    try {
      final raw = await api.getAll(api.journalPath());

      final records = raw
          .map(
            (item) => ConsultationApiMapper.fromApi(
          item,
          profileId,
        ),
      )
          .toList();

      if (!_validRequest(generation, profileId)) {
        return;
      }

      setState(() {
        _records = records;
        _journalError = null;
        _loadingJournal = false;
      });

      widget.onRecordsChanged?.call(
        List<DoctorConsultationRecord>.unmodifiable(
          records,
        ),
      );
    } catch (error) {
      if (!_validRequest(generation, profileId)) {
        return;
      }

      setState(() {
        _journalError = _friendlyError(error);
        _loadingJournal = false;
      });
    }
  }

  Future<void> _loadRequests(
      _ConsultationApi api,
      int generation,
      String profileId,
      ) async {
    try {
      final raw = await api.getAll(api.requestPath());

      final requests = raw
          .map(DoctorConsultationRequest.fromApi)
          .toList();

      if (!_validRequest(generation, profileId)) {
        return;
      }

      setState(() {
        _requests = requests;
        _requestsError = null;
        _loadingRequests = false;
      });
    } catch (error) {
      if (!_validRequest(generation, profileId)) {
        return;
      }

      setState(() {
        _requestsError = _friendlyError(error);
        _loadingRequests = false;
      });
    }
  }

  // ==========================================================
  // CONNECT DOCTOR
  // ==========================================================

  Future<void> _connectDoctor() async {
    if (_connectingDoctor ||
        _loadingDoctor ||
        _connectedDoctor != null ||
        _childProfile == null) {
      return;
    }

    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final referralId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Connect Doctor'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the referral ID provided '
                        'by an approved FamilyCare+ doctor.',
                    style: TextStyle(
                      fontSize: 12,
                      color: DoctorConsultationColors.muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: controller,
                    textCapitalization:
                    TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9]'),
                      ),
                      LengthLimitingTextInputFormatter(160),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Doctor Referral ID',
                      prefixIcon: Icon(
                        Icons.verified_user_outlined,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final id = (value ?? '').trim();

                      if (!RegExp(r'^[A-Za-z0-9]{1,160}$')
                          .hasMatch(id)) {
                        return 'Enter a valid referral ID';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Connecting a doctor grants access '
                        'to the linked child profile and '
                        'medical reports.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: DoctorConsultationColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ??
                    false) {
                  Navigator.pop(
                    dialogContext,
                    controller.text.trim(),
                  );
                }
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );

    // Dispose after dialog is dismissed.
    // The value is already captured above.
    controller.dispose();

    if (!mounted ||
        referralId == null ||
        referralId.isEmpty) {
      return;
    }

    final profileId = widget.profileId;
    final api = _api;

    setState(() => _connectingDoctor = true);

    try {
      await api.call(
        'POST',
        '${api.profilePath}/connect-doctor',
        body: {'referral_id': referralId},
      );

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      await _refreshAll();

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      _showMessage(
        _doctorError == null
            ? 'Doctor connected successfully.'
            : 'Connection submitted. Refresh to verify.',
      );
    } catch (error) {
      if (mounted && widget.profileId == profileId) {
        _showMessage(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted && widget.profileId == profileId) {
        setState(() => _connectingDoctor = false);
      }
    }
  }

  // ==========================================================
  // SAVE CONSULTATION JOURNAL
  // ==========================================================

  Future<void> _openJournalEditor({
    DoctorConsultationRecord? existing,
    bool markCompleted = false,
  }) async {
    if (_loadingJournal ||
        _savingJournal ||
        _journalError != null) {
      return;
    }

    final profileId = widget.profileId;
    final api = _api;

    final record =
    await showModalBottomSheet<DoctorConsultationRecord>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ConsultationEditorSheet(
        profileId: profileId,
        childName: widget.childName,
        childDateOfBirth: widget.childDateOfBirth,
        initialDoctorName: _text(
          _connectedDoctor?['full_name'],
        ),
        existing: existing,
        markCompleted: markCompleted,
      ),
    );

    if (!mounted ||
        record == null ||
        widget.profileId != profileId) {
      return;
    }

    setState(() => _savingJournal = true);

    try {
      final payload = ConsultationApiMapper.toApi(
        record,
      );

      await api.call(
        existing == null ? 'POST' : 'PATCH',
        api.journalPath(existing?.id),
        body: payload,
      );

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      await _refreshAll();

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      _showMessage(
        _journalError != null
            ? 'Visit submitted. Refresh to verify.'
            : existing == null
            ? 'Consultation saved to FamilyCare+.'
            : 'Consultation updated successfully.',
      );
    } catch (error) {
      if (mounted && widget.profileId == profileId) {
        _showMessage(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted && widget.profileId == profileId) {
        setState(() => _savingJournal = false);
      }
    }
  }

  // ==========================================================
  // DELETE CONSULTATION JOURNAL
  // ==========================================================

  Future<void> _deleteJournal(
      DoctorConsultationRecord record,
      ) async {
    if (_savingJournal || _loadingJournal) return;

    final confirmed = await _confirmDelete(
      'Delete consultation?',
      'Remove "${record.reason}" from '
          'the saved consultation history?',
    );

    if (!mounted || !confirmed) return;

    final profileId = widget.profileId;
    final api = _api;

    setState(() => _savingJournal = true);

    try {
      await api.call(
        'DELETE',
        api.journalPath(record.id),
      );

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      await _refreshAll();

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      _showMessage(
        _journalError == null
            ? 'Consultation deleted successfully.'
            : 'Deletion submitted. Refresh to verify.',
      );
    } catch (error) {
      if (mounted && widget.profileId == profileId) {
        _showMessage(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted && widget.profileId == profileId) {
        setState(() => _savingJournal = false);
      }
    }
  }

  // ==========================================================
  // SEND / EDIT DOCTOR REQUEST
  // ==========================================================

  Future<void> _openRequestEditor({
    DoctorConsultationRequest? existing,
  }) async {
    if (_savingRequest ||
        _loadingRequests ||
        _connectedDoctor == null ||
        _requestsError != null) {
      return;
    }

    final profileId = widget.profileId;
    final api = _api;

    final draft =
    await showModalBottomSheet<DoctorConsultationRequest>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ConsultationRequestEditor(
        childName: widget.childName,
        childDateOfBirth: widget.childDateOfBirth,
        existing: existing,
      ),
    );

    if (!mounted ||
        draft == null ||
        widget.profileId != profileId) {
      return;
    }

    setState(() => _savingRequest = true);

    try {
      await api.call(
        existing == null ? 'POST' : 'PATCH',
        api.requestPath(existing?.id),
        body: draft.toApi(),
      );

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      await _refreshAll();

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      _showMessage(
        _requestsError != null
            ? 'Request submitted. Refresh to verify.'
            : existing == null
            ? 'Request sent to doctor queue. '
            'Appointment is not confirmed.'
            : 'Consultation request updated.',
      );
    } catch (error) {
      if (mounted && widget.profileId == profileId) {
        _showMessage(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted && widget.profileId == profileId) {
        setState(() => _savingRequest = false);
      }
    }
  }

  // ==========================================================
  // WITHDRAW DOCTOR REQUEST
  // ==========================================================

  Future<void> _withdrawRequest(
      DoctorConsultationRequest request,
      ) async {
    if (_savingRequest || _loadingRequests) return;

    final confirmed = await _confirmDelete(
      'Withdraw consultation request?',
      'This removes the request from the doctor queue. '
          'It does not cancel any appointment arranged '
          'separately.',
    );

    if (!mounted || !confirmed) return;

    final profileId = widget.profileId;
    final api = _api;

    setState(() => _savingRequest = true);

    try {
      await api.call(
        'DELETE',
        api.requestPath(request.id),
      );

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      await _refreshAll();

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      _showMessage(
        _requestsError == null
            ? 'Consultation request withdrawn.'
            : 'Withdrawal submitted. Refresh to verify.',
      );
    } catch (error) {
      if (mounted && widget.profileId == profileId) {
        _showMessage(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted && widget.profileId == profileId) {
        setState(() => _savingRequest = false);
      }
    }
  }

  // ==========================================================
  // DELETE CONFIRMATION
  // ==========================================================

  Future<bool> _confirmDelete(
      String title,
      String description,
      ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor:
              DoctorConsultationColors.red,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _copyText(
      String value,
      String label,
      ) async {
    if (value.trim().isEmpty) return;

    await Clipboard.setData(
      ClipboardData(text: value),
    );

    if (mounted) {
      _showMessage('$label copied.');
    }
  }

  // ==========================================================
  // RECORD COUNTS
  // ==========================================================

  int get _plannedCount => _records
      .where(
        (record) =>
    record.status == ConsultationStatus.planned,
  )
      .length;

  int get _completedCount => _records
      .where(
        (record) =>
    record.status == ConsultationStatus.completed,
  )
      .length;

  int get _followUpCount {
    final today = DateUtils.dateOnly(DateTime.now());

    return _records.where((record) {
      final date = record.followUpDate;

      return date != null &&
          record.status != ConsultationStatus.cancelled &&
          !DateUtils.dateOnly(date).isBefore(today);
    }).length;
  }

  DoctorConsultationRecord? get _nextFollowUp {
    final today = DateUtils.dateOnly(DateTime.now());

    final candidates = _records.where((record) {
      final date = record.followUpDate;

      return date != null &&
          record.status != ConsultationStatus.cancelled &&
          !DateUtils.dateOnly(date).isBefore(today);
    }).toList();

    candidates.sort(
          (a, b) =>
          a.followUpDate!.compareTo(b.followUpDate!),
    );

    return candidates.isEmpty ? null : candidates.first;
  }

  List<DoctorConsultationRecord> get _filteredRecords {
    final query =
    _searchController.text.trim().toLowerCase();

    final records = _records.where((record) {
      if (_filter != ConsultationFilter.all) {
        if (_filter == ConsultationFilter.planned &&
            record.status != ConsultationStatus.planned) {
          return false;
        }

        if (_filter == ConsultationFilter.completed &&
            record.status != ConsultationStatus.completed) {
          return false;
        }

        if (_filter == ConsultationFilter.cancelled &&
            record.status != ConsultationStatus.cancelled) {
          return false;
        }
      }

      if (query.isEmpty) return true;

      return [
        record.reason,
        record.doctorName,
        record.clinicName,
        record.symptoms,
        record.clinicalAdvice,
        record.notes,
      ].any(
            (value) => value.toLowerCase().contains(query),
      );
    }).toList();

    records.sort((a, b) {
      if (a.status == ConsultationStatus.planned &&
          b.status != ConsultationStatus.planned) {
        return -1;
      }

      if (b.status == ConsultationStatus.planned &&
          a.status != ConsultationStatus.planned) {
        return 1;
      }

      if (a.status == ConsultationStatus.planned &&
          b.status == ConsultationStatus.planned) {
        return a.consultationDate.compareTo(
          b.consultationDate,
        );
      }

      return b.consultationDate.compareTo(
        a.consultationDate,
      );
    });

    return records;
  }

  // ==========================================================
  // MAIN BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
      DoctorConsultationColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: DoctorConsultationColors.navy,
        elevation: 0,
        title: const Text(
          'Doctor Consultation',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _connectingDoctor ||
                _savingJournal ||
                _savingRequest
                ? null
                : _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton:
      _loadingJournal || _savingJournal || _journalError != null
          ? null
          : FloatingActionButton.extended(
        onPressed: () => _openJournalEditor(),
        backgroundColor:
        DoctorConsultationColors.blue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Visit'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              16,
              20,
              16,
              105,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints:
                  const BoxConstraints(maxWidth: 1150),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      _breadcrumb(),
                      const SizedBox(height: 18),
                      _hero(),
                      const SizedBox(height: 16),
                      _notice(
                        'Visit records are personal health '
                            'notes saved on FamilyCare+. '
                            'A consultation request is separate '
                            'from appointment booking.',
                        DoctorConsultationColors.lightBlue,
                        DoctorConsultationColors.blue,
                      ),
                      const SizedBox(height: 20),
                      _connectedDoctorCard(),
                      const SizedBox(height: 20),
                      _doctorRequestsCard(),
                      const SizedBox(height: 20),
                      _summaryCards(),
                      const SizedBox(height: 20),
                      _nextFollowUpCard(),
                      const SizedBox(height: 20),
                      _consultationHistory(),
                      const SizedBox(height: 20),
                      _notice(
                        'Parent-entered consultation notes '
                            'are not verified prescriptions '
                            'or medical advice. For urgent '
                            'concerns, contact an appropriate '
                            'healthcare professional or '
                            'emergency service.',
                        DoctorConsultationColors.lightGreen,
                        DoctorConsultationColors.green,
                      ),
                      const SizedBox(height: 24),
                      const Center(
                        child: Text(
                          'FamilyCare+ • Your family. Your care.',
                          style: TextStyle(
                            color:
                            DoctorConsultationColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _breadcrumb() {
    return const Row(
      children: [
        Text(
          'Child Care',
          style: TextStyle(
            color: DoctorConsultationColors.muted,
            fontSize: 12,
          ),
        ),
        SizedBox(width: 7),
        Icon(
          Icons.chevron_right_rounded,
          color: DoctorConsultationColors.muted,
          size: 17,
        ),
        SizedBox(width: 7),
        Text(
          'Doctor Consultation',
          style: TextStyle(
            color: DoctorConsultationColors.green,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _hero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF4FF),
            Color(0xFFF0F7F1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const Text(
                  'COMPASSIONATE CARE. EVERY STEP.',
                  style: TextStyle(
                    color: DoctorConsultationColors.green,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Doctor Consultation',
                  style: TextStyle(
                    fontSize: 26,
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w800,
                    color: DoctorConsultationColors.navy,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Keep ${widget.childName}\'s '
                      'doctor visits and care notes organized.',
                  style: const TextStyle(
                    color: DoctorConsultationColors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const CircleAvatar(
            radius: 32,
            backgroundColor: Color(0xFFDFEEE5),
            child: Icon(
              Icons.medical_services_rounded,
              color: DoctorConsultationColors.green,
              size: 34,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONNECTED DOCTOR UI
  // ==========================================================

  Widget _connectedDoctorCard() {
    Widget child;

    if (_loadingDoctor) {
      child = const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (_doctorError != null) {
      child = _errorView(
        _doctorError!,
        _refreshAll,
      );
    } else if (_connectedDoctor == null) {
      child = Column(
        children: [
          const Icon(
            Icons.person_add_alt_1_outlined,
            size: 45,
            color: DoctorConsultationColors.green,
          ),
          const SizedBox(height: 12),
          const Text(
            'No doctor connected',
            style: TextStyle(
              color: DoctorConsultationColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect using a referral ID provided '
                'by an approved FamilyCare+ doctor.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DoctorConsultationColors.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 17),
          FilledButton.icon(
            onPressed: _connectingDoctor
                ? null
                : _connectDoctor,
            icon: const Icon(
              Icons.person_add_alt_1_rounded,
            ),
            label: Text(
              _connectingDoctor
                  ? 'Connecting...'
                  : 'Connect Doctor',
            ),
            style: FilledButton.styleFrom(
              backgroundColor:
              DoctorConsultationColors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      );
    } else {
      final doctor = _connectedDoctor!;

      final name = _text(
        doctor['full_name'],
        fallback: 'Connected Doctor',
      );

      final email = _text(doctor['email']);
      final mobile = _text(doctor['mobile_number']);
      final referral = _text(doctor['referral_id']);

      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DoctorConsultationColors.lightGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 27,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.medical_services_rounded,
                    color: DoctorConsultationColors.green,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: DoctorConsultationColors.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Connected to this child',
                        style: TextStyle(
                          color: DoctorConsultationColors.green,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.verified_rounded,
                  color: DoctorConsultationColors.green,
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          if (email.isNotEmpty)
            _contactRow(
              Icons.email_outlined,
              'Email',
              email,
            ),
          if (mobile.isNotEmpty)
            _contactRow(
              Icons.phone_outlined,
              'Phone',
              mobile,
            ),
          if (referral.isNotEmpty)
            _contactRow(
              Icons.badge_outlined,
              'Referral ID',
              referral,
            ),
          const SizedBox(height: 10),
          _notice(
            'Connection is saved on the backend. '
                'This screen does not currently provide '
                'live chat, calling, or booking.',
            DoctorConsultationColors.lightBlue,
            DoctorConsultationColors.blue,
          ),
        ],
      );
    }

    return _sectionCard(
      title: 'Connected Doctor',
      subtitle: 'Doctor linked to this child profile',
      icon: Icons.medical_services_outlined,
      child: child,
    );
  }

  Widget _contactRow(
      IconData icon,
      String label,
      String value,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            icon,
            color: DoctorConsultationColors.green,
            size: 19,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                color: DoctorConsultationColors.muted,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: DoctorConsultationColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy $label',
            onPressed: () => _copyText(value, label),
            icon: const Icon(
              Icons.copy_rounded,
              color: DoctorConsultationColors.blue,
              size: 17,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // DOCTOR REQUESTS UI
  // ==========================================================

  Widget _doctorRequestsCard() {
    return _sectionCard(
      title: 'Consultation Requests',
      subtitle: 'Requests sent to the connected doctor',
      icon: Icons.send_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_connectedDoctor == null)
            _notice(
              'Connect a doctor before sending '
                  'a consultation request.',
              DoctorConsultationColors.lightOrange,
              DoctorConsultationColors.orange,
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _savingRequest ||
                    _loadingRequests ||
                    _requestsError != null
                    ? null
                    : () => _openRequestEditor(),
                icon: const Icon(Icons.send_outlined),
                label: const Text('Request Consultation'),
                style: FilledButton.styleFrom(
                  backgroundColor:
                  DoctorConsultationColors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          const SizedBox(height: 15),
          if (_loadingRequests)
            const Center(
              child: CircularProgressIndicator(),
            )
          else if (_requestsError != null)
            _errorView(
              _requestsError!,
              _refreshAll,
            )
          else if (_requests.isEmpty)
              const Text(
                'No consultation requests sent yet.',
                style: TextStyle(
                  fontSize: 12,
                  color: DoctorConsultationColors.muted,
                ),
              )
            else
              for (final request in _requests) ...[
                _requestCard(request),
                const SizedBox(height: 10),
              ],
          const SizedBox(height: 12),
          const Text(
            'A request is not a confirmed appointment. '
                'Doctor availability and appointment '
                'acceptance are not yet integrated.',
            style: TextStyle(
              color: DoctorConsultationColors.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestCard(
      DoctorConsultationRequest request,
      ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DoctorConsultationColors.cream,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: DoctorConsultationColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.title,
                  style: const TextStyle(
                    color: DoctorConsultationColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _tag(
                request.status,
                DoctorConsultationColors.orange,
              ),
            ],
          ),
          const SizedBox(height: 11),
          _detailRow(
            'Preferred Date',
            ConsultationDateFormatter.format(
              request.preferredDate,
            ),
          ),
          if (request.message.isNotEmpty) ...[
            const SizedBox(height: 10),
            _detailBlock(
              'Parent Message / Concerns',
              request.message,
            ),
          ],
          const Divider(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _savingRequest ||
                    _connectedDoctor == null
                    ? null
                    : () => _openRequestEditor(
                  existing: request,
                ),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 17,
                ),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: _savingRequest
                    ? null
                    : () => _withdrawRequest(request),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                ),
                label: const Text('Withdraw'),
                style: TextButton.styleFrom(
                  foregroundColor:
                  DoctorConsultationColors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SUMMARY CARDS
  // ==========================================================

  Widget _summaryCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
        constraints.maxWidth >= 760 ? 4 : 2;

        const gap = 11.0;

        final width =
            (constraints.maxWidth -
                gap * (columns - 1)) /
                columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _summaryCard(
              width,
              'Total Visits',
              _records.length,
              Icons.folder_copy_outlined,
              DoctorConsultationColors.blue,
            ),
            _summaryCard(
              width,
              'Planned',
              _plannedCount,
              Icons.event_outlined,
              DoctorConsultationColors.orange,
            ),
            _summaryCard(
              width,
              'Completed',
              _completedCount,
              Icons.verified_outlined,
              DoctorConsultationColors.green,
            ),
            _summaryCard(
              width,
              'Follow-ups',
              _followUpCount,
              Icons.event_repeat_outlined,
              DoctorConsultationColors.purple,
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCard(
      double width,
      String title,
      int count,
      IconData icon,
      Color color,
      ) {
    return Container(
      width: width,
      constraints:
      const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: DoctorConsultationColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(height: 11),
          Text(
            '$count',
            style: const TextStyle(
              color: DoctorConsultationColors.navy,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              color: DoctorConsultationColors.muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // NEXT FOLLOW-UP
  // ==========================================================

  Widget _nextFollowUpCard() {
    final next = _nextFollowUp;

    return _sectionCard(
      title: 'Next Follow-up',
      subtitle: 'Based on parent-entered visit dates',
      icon: Icons.event_repeat_outlined,
      child: next == null
          ? const Text(
        'No future follow-up date recorded.',
        style: TextStyle(
          color: DoctorConsultationColors.muted,
          fontSize: 12,
        ),
      )
          : Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            next.reason,
            style: const TextStyle(
              color: DoctorConsultationColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            ConsultationDateFormatter.format(
              next.followUpDate!,
            ),
            style: const TextStyle(
              color: DoctorConsultationColors.green,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'This is a recorded follow-up date, '
                'not an appointment confirmation.',
            style: TextStyle(
              color: DoctorConsultationColors.muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONSULTATION HISTORY
  // ==========================================================

  Widget _consultationHistory() {
    return _sectionCard(
      title: 'Consultation History',
      subtitle: 'Saved personal visit records',
      icon: Icons.history_edu_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search doctor, clinic, reason...',
              prefixIcon: const Icon(
                Icons.search_rounded,
              ),
              suffixIcon:
              _searchController.text.isNotEmpty
                  ? IconButton(
                tooltip: 'Clear search',
                onPressed:
                _searchController.clear,
                icon: const Icon(
                  Icons.close_rounded,
                ),
              )
                  : null,
              filled: true,
              fillColor: DoctorConsultationColors.cream,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 15),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', ConsultationFilter.all),
                _filterChip(
                  'Planned',
                  ConsultationFilter.planned,
                ),
                _filterChip(
                  'Completed',
                  ConsultationFilter.completed,
                ),
                _filterChip(
                  'Cancelled',
                  ConsultationFilter.cancelled,
                ),
              ],
            ),
          ),
          const SizedBox(height: 17),
          if (_loadingJournal)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_journalError != null)
            _errorView(
              _journalError!,
              _refreshAll,
            )
          else if (_filteredRecords.isEmpty)
              _emptyJournal()
            else
              for (final record in _filteredRecords) ...[
                _journalCard(record),
                const SizedBox(height: 11),
              ],
        ],
      ),
    );
  }

  Widget _filterChip(
      String label,
      ConsultationFilter filter,
      ) {
    final selected = _filter == filter;

    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: DoctorConsultationColors.blue,
        labelStyle: TextStyle(
          color: selected
              ? Colors.white
              : DoctorConsultationColors.text,
          fontSize: 11,
        ),
        onSelected: (_) {
          setState(() => _filter = filter);
        },
      ),
    );
  }

  Widget _journalCard(
      DoctorConsultationRecord record,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DoctorConsultationColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: DoctorConsultationColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: record.status.color
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  record.mode.icon,
                  color: record.status.color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.reason,
                      style: const TextStyle(
                        color: DoctorConsultationColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      record.mode.label,
                      style: const TextStyle(
                        color: DoctorConsultationColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Visit options',
                onSelected: (value) {
                  if (value == 'edit') {
                    _openJournalEditor(existing: record);
                  } else if (value == 'completed') {
                    _openJournalEditor(
                      existing: record,
                      markCompleted: true,
                    );
                  } else if (value == 'delete') {
                    _deleteJournal(record);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit'),
                  ),
                  if (record.status ==
                      ConsultationStatus.planned)
                    const PopupMenuItem(
                      value: 'completed',
                      child: Text('Mark Completed'),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: [
              _tag(
                record.status.label,
                record.status.color,
              ),
              _tag(
                ConsultationDateFormatter.format(
                  record.consultationDate,
                ),
                DoctorConsultationColors.blue,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (record.consultationTime != null)
            _detailRow(
              'Time',
              record.consultationTime!.format(context),
            ),
          if (record.doctorName.isNotEmpty)
            _detailRow('Doctor', record.doctorName),
          if (record.clinicName.isNotEmpty)
            _detailRow('Clinic', record.clinicName),
          if (record.followUpDate != null)
            _detailRow(
              'Follow-up',
              ConsultationDateFormatter.format(
                record.followUpDate!,
              ),
            ),
          if (record.symptoms.isNotEmpty) ...[
            const SizedBox(height: 10),
            _detailBlock(
              'Symptoms / Concerns',
              record.symptoms,
            ),
          ],
          if (record.clinicalAdvice.isNotEmpty) ...[
            const SizedBox(height: 10),
            _detailBlock(
              'Doctor Advice / Visit Summary',
              record.clinicalAdvice,
            ),
          ],
          if (record.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _detailBlock(
              'Additional Notes',
              record.notes,
            ),
          ],
          if (record.status ==
              ConsultationStatus.planned) ...[
            const SizedBox(height: 10),
            const Text(
              'Personal visit plan — not booked.',
              style: TextStyle(
                color: DoctorConsultationColors.orange,
                fontSize: 10,
              ),
            ),
          ],
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _savingJournal
                    ? null
                    : () => _openJournalEditor(
                  existing: record,
                ),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 17,
                ),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: _savingJournal
                    ? null
                    : () => _deleteJournal(record),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                ),
                label: const Text('Delete'),
                style: TextButton.styleFrom(
                  foregroundColor:
                  DoctorConsultationColors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyJournal() {
    final filtered =
        _filter != ConsultationFilter.all ||
            _searchController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: DoctorConsultationColors.cream,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.medical_information_outlined,
            color: DoctorConsultationColors.green,
            size: 43,
          ),
          const SizedBox(height: 12),
          Text(
            filtered
                ? 'No matching entries'
                : 'No consultation records yet',
            style: const TextStyle(
              color: DoctorConsultationColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filtered
                ? 'Try another filter or search term.'
                : 'Keep a record of your child\'s '
                'planned and completed visits.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: DoctorConsultationColors.muted,
              fontSize: 12,
            ),
          ),
          if (!filtered) ...[
            const SizedBox(height: 17),
            FilledButton.icon(
              onPressed: () => _openJournalEditor(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Visit Record'),
              style: FilledButton.styleFrom(
                backgroundColor:
                DoctorConsultationColors.blue,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // REUSABLE UI
  // ==========================================================

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: DoctorConsultationColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color:
                  DoctorConsultationColors.lightGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: DoctorConsultationColors.green,
                  size: 23,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color:
                        DoctorConsultationColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color:
                        DoctorConsultationColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 19),
          child,
        ],
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: DoctorConsultationColors.muted,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: DoctorConsultationColors.text,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailBlock(String title, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: DoctorConsultationColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          text,
          style: const TextStyle(
            color: DoctorConsultationColors.muted,
            fontSize: 11,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _notice(
      String message,
      Color background,
      Color iconColor,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: iconColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: DoctorConsultationColors.text,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(
      String message,
      VoidCallback retry,
      ) {
    return Column(
      children: [
        const Icon(
          Icons.cloud_off_outlined,
          size: 37,
          color: DoctorConsultationColors.orange,
        ),
        const SizedBox(height: 11),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: DoctorConsultationColors.red,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

// ============================================================
// ADD / EDIT PERSONAL VISIT RECORD
// ============================================================

class _ConsultationEditorSheet extends StatefulWidget {
  final String profileId;
  final String childName;
  final DateTime? childDateOfBirth;
  final String initialDoctorName;
  final DoctorConsultationRecord? existing;
  final bool markCompleted;

  const _ConsultationEditorSheet({
    required this.profileId,
    required this.childName,
    required this.initialDoctorName,
    this.childDateOfBirth,
    this.existing,
    this.markCompleted = false,
  });

  @override
  State<_ConsultationEditorSheet> createState() =>
      _ConsultationEditorSheetState();
}

class _ConsultationEditorSheetState
    extends State<_ConsultationEditorSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _doctor;
  late final TextEditingController _clinic;
  late final TextEditingController _reason;
  late final TextEditingController _symptoms;
  late final TextEditingController _advice;
  late final TextEditingController _notes;

  late ConsultationStatus _status;
  late ConsultationMode _mode;
  late DateTime _date;

  TimeOfDay? _time;
  DateTime? _followUp;

  bool _submitted = false;

  @override
  void initState() {
    super.initState();

    final old = widget.existing;

    _doctor = TextEditingController(
      text: old?.doctorName ??
          widget.initialDoctorName,
    );
    _clinic = TextEditingController(
      text: old?.clinicName ?? '',
    );
    _reason = TextEditingController(
      text: old?.reason ?? '',
    );
    _symptoms = TextEditingController(
      text: old?.symptoms ?? '',
    );
    _advice = TextEditingController(
      text: old?.clinicalAdvice ?? '',
    );
    _notes = TextEditingController(
      text: old?.notes ?? '',
    );

    _status = widget.markCompleted
        ? ConsultationStatus.completed
        : old?.status ?? ConsultationStatus.planned;

    _mode = old?.mode ?? ConsultationMode.clinic;

    _date = widget.markCompleted &&
        old != null &&
        old.consultationDate.isAfter(
          DateTime.now(),
        )
        ? DateUtils.dateOnly(DateTime.now())
        : old?.consultationDate ??
        DateUtils.dateOnly(DateTime.now());

    _time = old?.consultationTime;
    _followUp = old?.followUpDate;
  }

  @override
  void dispose() {
    _doctor.dispose();
    _clinic.dispose();
    _reason.dispose();
    _symptoms.dispose();
    _advice.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final dob = widget.childDateOfBirth;

    final first = dob != null && !dob.isAfter(today)
        ? DateUtils.dateOnly(dob)
        : DateTime(1900);

    final last = _status == ConsultationStatus.planned
        ? DateTime(today.year + 5, 12, 31)
        : today;

    if (first.isAfter(last)) return;

    DateTime initial = _date;

    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'SELECT VISIT DATE',
    );

    if (!mounted || selected == null) return;

    setState(() {
      _date = selected;

      if (_followUp != null &&
          _followUp!.isBefore(selected)) {
        _followUp = null;
      }
    });
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );

    if (!mounted || selected == null) return;

    setState(() => _time = selected);
  }

  Future<void> _pickFollowUp() async {
    final first = _date;
    final last = DateTime(
      DateTime.now().year + 10,
      12,
      31,
    );

    if (first.isAfter(last)) return;

    DateTime initial = _followUp ?? first;

    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'SELECT FOLLOW-UP DATE',
    );

    if (!mounted || selected == null) return;

    setState(() => _followUp = selected);
  }

  void _save() {
    setState(() => _submitted = true);

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final today = DateUtils.dateOnly(DateTime.now());

    if (_status != ConsultationStatus.planned &&
        _date.isAfter(today)) {
      _error(
        'Completed or cancelled visits '
            'cannot have future dates.',
      );
      return;
    }

    if (widget.childDateOfBirth != null &&
        _date.isBefore(
          DateUtils.dateOnly(widget.childDateOfBirth!),
        )) {
      _error(
        'Visit date cannot be before the child\'s birth.',
      );
      return;
    }

    if (_followUp != null &&
        _followUp!.isBefore(_date)) {
      _error(
        'Follow-up date cannot be before visit date.',
      );
      return;
    }

    final record = DoctorConsultationRecord(
      id: widget.existing?.id ?? '',
      profileId: widget.profileId,
      status: _status,
      mode: _mode,
      consultationDate: _date,
      consultationTime: _time,
      followUpDate: _followUp,
      doctorName: _doctor.text.trim(),
      clinicName: _clinic.text.trim(),
      reason: _reason.text.trim(),
      symptoms: _symptoms.text.trim(),
      clinicalAdvice: _advice.text.trim(),
      notes: _notes.text.trim(),
    );

    try {
      ConsultationApiMapper.toApi(record);
    } catch (error) {
      _error(error.toString());
      return;
    }

    Navigator.of(context).pop(record);
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: DoctorConsultationColors.red,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _consultationSheet(
      context,
      Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _editorTitle(
              widget.existing == null
                  ? 'Add Consultation Entry'
                  : 'Edit Consultation Entry',
              'For ${widget.childName}',
            ),
            const SizedBox(height: 22),
            _formLabel('Visit Status'),
            const SizedBox(height: 8),
            DropdownButtonFormField<ConsultationStatus>(
              initialValue: _status,
              isExpanded: true,
              decoration: _consultationDecoration(
                'Select status',
                Icons.event_available_outlined,
              ),
              items: ConsultationStatus.values.map((s) {
                return DropdownMenuItem(
                  value: s,
                  child: Text(s.label),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  _status = value;

                  if (value != ConsultationStatus.planned &&
                      _date.isAfter(DateTime.now())) {
                    _date = DateUtils.dateOnly(
                      DateTime.now(),
                    );

                    if (_followUp != null &&
                        _followUp!.isBefore(_date)) {
                      _followUp = null;
                    }
                  }
                });
              },
            ),
            const SizedBox(height: 17),
            _formLabel('Consultation Type'),
            const SizedBox(height: 8),
            DropdownButtonFormField<ConsultationMode>(
              initialValue: _mode,
              isExpanded: true,
              decoration: _consultationDecoration(
                'Select consultation mode',
                Icons.medical_services_outlined,
              ),
              items: ConsultationMode.values.map((m) {
                return DropdownMenuItem(
                  value: m,
                  child: Row(
                    children: [
                      Icon(m.icon, size: 17),
                      const SizedBox(width: 9),
                      Text(m.label),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _mode = value);
                }
              },
            ),
            const SizedBox(height: 17),
            _formDate(
              'Visit Date',
              ConsultationDateFormatter.format(_date),
              _pickDate,
              Icons.calendar_month_outlined,
            ),
            const SizedBox(height: 17),
            _formDate(
              'Visit Time (Optional)',
              _time == null
                  ? 'Select time'
                  : _time!.format(context),
              _pickTime,
              Icons.access_time_outlined,
              onClear: _time == null
                  ? null
                  : () {
                setState(() => _time = null);
              },
            ),
            const SizedBox(height: 17),
            _formTextField(
              controller: _doctor,
              label: 'Doctor Name (Optional)',
              hint: 'Enter doctor name',
              icon: Icons.person_outline_rounded,
              maxLength: 120,
            ),
            const SizedBox(height: 17),
            _formTextField(
              controller: _clinic,
              label: 'Clinic / Hospital (Optional)',
              hint: 'Enter clinic name',
              icon: Icons.local_hospital_outlined,
              maxLength: 150,
            ),
            const SizedBox(height: 17),
            _formTextField(
              controller: _reason,
              label: 'Reason for Visit *',
              hint: 'Why was or will the doctor be consulted?',
              icon: Icons.assignment_outlined,
              maxLength: 160,
              maxLines: 2,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Reason for visit is required.';
                }
                return null;
              },
            ),
            const SizedBox(height: 17),
            _formTextField(
              controller: _symptoms,
              label: 'Symptoms / Concerns (Optional)',
              hint: 'Record symptoms or concerns',
              icon: Icons.monitor_heart_outlined,
              maxLength: 1000,
              maxLines: 3,
            ),
            const SizedBox(height: 17),
            _formTextField(
              controller: _advice,
              label: 'Doctor Advice / Visit Summary',
              hint: 'Enter advice given during the visit',
              icon: Icons.medical_information_outlined,
              maxLength: 1200,
              maxLines: 3,
            ),
            const SizedBox(height: 17),
            _formDate(
              'Follow-up Date (Optional)',
              _followUp == null
                  ? 'Select follow-up date'
                  : ConsultationDateFormatter.format(
                _followUp!,
              ),
              _pickFollowUp,
              Icons.event_repeat_outlined,
              onClear: _followUp == null
                  ? null
                  : () {
                setState(() => _followUp = null);
              },
            ),
            const SizedBox(height: 17),
            _formTextField(
              controller: _notes,
              label: 'Additional Notes (Optional)',
              hint: 'Any other relevant information',
              icon: Icons.notes_rounded,
              maxLength: 800,
              maxLines: 3,
            ),
            const SizedBox(height: 18),
            _consultationNotice(
              'This is a parent-entered personal visit '
                  'record. Saving a planned visit does not '
                  'book an appointment. Doctor advice entered '
                  'here is not independently verified.',
              DoctorConsultationColors.lightOrange,
              DoctorConsultationColors.orange,
            ),
            const SizedBox(height: 23),
            _editorSaveButton(
              widget.existing == null
                  ? 'Save Visit Record'
                  : 'Save Changes',
              _save,
            ),
            _editorCancel(context),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DOCTOR CONSULTATION REQUEST EDITOR
// ============================================================

class _ConsultationRequestEditor extends StatefulWidget {
  final String childName;
  final DateTime? childDateOfBirth;
  final DoctorConsultationRequest? existing;

  const _ConsultationRequestEditor({
    required this.childName,
    this.childDateOfBirth,
    this.existing,
  });

  @override
  State<_ConsultationRequestEditor> createState() =>
      _ConsultationRequestEditorState();
}

class _ConsultationRequestEditorState
    extends State<_ConsultationRequestEditor> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _reason;
  late final TextEditingController _message;
  late DateTime _preferredDate;

  @override
  void initState() {
    super.initState();

    _reason = TextEditingController(
      text: widget.existing?.title ?? '',
    );

    _message = TextEditingController(
      text: widget.existing?.message ?? '',
    );

    _preferredDate = widget.existing?.preferredDate ??
        DateUtils.dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _reason.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());

    final first = today;
    final last = DateTime(today.year + 5, 12, 31);

    DateTime initial = _preferredDate;

    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'PREFERRED CONSULTATION DATE',
    );

    if (!mounted || picked == null) return;

    setState(() => _preferredDate = picked);
  }

  void _send() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final today = DateUtils.dateOnly(DateTime.now());

    if (_preferredDate.isBefore(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose today or a future preferred date.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      DoctorConsultationRequest(
        id: widget.existing?.id ?? '',
        title: _reason.text.trim(),
        preferredDate: _preferredDate,
        message: _message.text.trim(),
        status: widget.existing?.status ?? 'REQUESTED',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _consultationSheet(
      context,
      Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _editorTitle(
              widget.existing == null
                  ? 'Request Doctor Consultation'
                  : 'Edit Consultation Request',
              'For ${widget.childName}',
            ),
            const SizedBox(height: 22),
            _formTextField(
              controller: _reason,
              label: 'Reason / Subject *',
              hint: 'Reason for requesting consultation',
              icon: Icons.assignment_outlined,
              maxLength: 160,
              maxLines: 2,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Reason is required.';
                }
                return null;
              },
            ),
            const SizedBox(height: 17),
            _formDate(
              'Preferred Date',
              ConsultationDateFormatter.format(
                _preferredDate,
              ),
              _pickDate,
              Icons.event_outlined,
            ),
            const SizedBox(height: 17),
            _formTextField(
              controller: _message,
              label: 'Symptoms / Message (Optional)',
              hint: 'Describe your child\'s concern',
              icon: Icons.notes_outlined,
              maxLength: 2000,
              maxLines: 4,
            ),
            const SizedBox(height: 18),
            _consultationNotice(
              'Your request will be available to the '
                  'connected doctor through FamilyCare+. '
                  'Submitting does not confirm availability '
                  'or book an appointment.',
              DoctorConsultationColors.lightOrange,
              DoctorConsultationColors.orange,
            ),
            const SizedBox(height: 23),
            _editorSaveButton(
              widget.existing == null
                  ? 'Send Consultation Request'
                  : 'Update Request',
              _send,
            ),
            _editorCancel(context),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// REUSABLE EDITOR UI
// ============================================================

Widget _consultationSheet(
    BuildContext context,
    Widget content,
    ) {
  return Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Container(
      constraints: BoxConstraints(
        maxHeight:
        MediaQuery.sizeOf(context).height * 0.91,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            23,
            20,
            28,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints:
              const BoxConstraints(maxWidth: 650),
              child: content,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _editorTitle(
    String title,
    String subtitle,
    ) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: DoctorConsultationColors.navy,
          fontSize: 23,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        subtitle,
        style: const TextStyle(
          color: DoctorConsultationColors.muted,
          fontSize: 12,
        ),
      ),
    ],
  );
}

Widget _formLabel(String title) {
  return Text(
    title,
    style: const TextStyle(
      color: DoctorConsultationColors.text,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
  );
}

InputDecoration _consultationDecoration(
    String hint,
    IconData icon,
    ) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(
      icon,
      color: DoctorConsultationColors.green,
      size: 21,
    ),
    filled: true,
    fillColor: DoctorConsultationColors.cream,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 16,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(
        color: DoctorConsultationColors.border,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(
        color: DoctorConsultationColors.green,
        width: 1.7,
      ),
    ),
  );
}

Widget _formTextField({
  required TextEditingController controller,
  required String label,
  required String hint,
  required IconData icon,
  int maxLength = 120,
  int maxLines = 1,
  String? Function(String?)? validator,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _formLabel(label),
      const SizedBox(height: 9),
      TextFormField(
        controller: controller,
        validator: validator,
        maxLines: maxLines,
        textCapitalization:
        TextCapitalization.sentences,
        inputFormatters: [
          LengthLimitingTextInputFormatter(maxLength),
        ],
        decoration: _consultationDecoration(
          hint,
          icon,
        ),
      ),
    ],
  );
}

Widget _formDate(
    String label,
    String value,
    VoidCallback onTap,
    IconData icon, {
      VoidCallback? onClear,
    }) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _formLabel(label),
      const SizedBox(height: 9),
      Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(13),
              child: InputDecorator(
                decoration: _consultationDecoration(
                  'Select date or time',
                  icon,
                ),
                child: Text(
                  value,
                  style: const TextStyle(
                    color: DoctorConsultationColors.text,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          if (onClear != null)
            IconButton(
              tooltip: 'Clear',
              onPressed: onClear,
              icon: const Icon(
                Icons.close_rounded,
              ),
            ),
        ],
      ),
    ],
  );
}

Widget _editorSaveButton(
    String title,
    VoidCallback onPressed,
    ) {
  return SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.save_outlined),
      label: Text(title),
      style: FilledButton.styleFrom(
        backgroundColor: DoctorConsultationColors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
      ),
    ),
  );
}

Widget _editorCancel(BuildContext context) {
  return SizedBox(
    width: double.infinity,
    child: TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    ),
  );
}

Widget _consultationNotice(
    String message,
    Color background,
    Color iconColor,
    ) {
  return Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          color: iconColor,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: DoctorConsultationColors.text,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}
