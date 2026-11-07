
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

// ============================================================
// FAMILYCARE+ - VACCINATION SCREEN
// ============================================================
// Supported filters:
// 1. All
// 2. Completed
// 3. Upcoming
// 4. Overdue
//
// Backend:
// GET    /api/v1/children/{id}
// GET    /api/v1/children/{id}/vaccinations
// GET    /api/v1/children/{id}/vaccinations/history
// POST   /api/v1/children/{id}/vaccinations/history
// PATCH  /api/v1/children/{id}/vaccinations/history/{record_id}
// DELETE /api/v1/children/{id}/vaccinations/history/{record_id}
// GET    /api/v1/children/{id}/vaccination-context
// PUT    /api/v1/children/{id}/vaccination-context
// GET    /api/v1/children/{id}/reminders
// PUT    /api/v1/children/{id}/reminder-preferences
//
// Fallback schedules are informational references only.
// Recorded vaccination dates are parent-reported unless
// independently verified through an authorized clinical process.
// ============================================================

class VaccinationScreen extends StatefulWidget {
  final String? childId;
  final String? profileId;
  final String apiBaseUrl;

  const VaccinationScreen({
    super.key,
    this.childId,
    this.profileId,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
  });

  @override
  State<VaccinationScreen> createState() =>
      _VaccinationScreenState();
}

// ============================================================
// THEME
// ============================================================

class _VColor {
  static const navy = Color(0xFF173D60);
  static const text = Color(0xFF243E53);
  static const blue = Color(0xFF2378DB);
  static const green = Color(0xFF28795C);
  static const red = Color(0xFFB54450);
  static const orange = Color(0xFF9B661A);
  static const muted = Color(0xFF687D8D);
  static const bg = Color(0xFFF4F7FC);
  static const border = Color(0xFFE1E9F1);
  static const pale = Color(0xFFEAF4FF);
}

// ============================================================
// API ERROR
// ============================================================

class _ApiProblem implements Exception {
  final String message;

  const _ApiProblem(this.message);

  @override
  String toString() => message;
}

// ============================================================
// VACCINATION SCREEN STATE
// ============================================================

class _VaccinationScreenState
    extends State<VaccinationScreen> {
  final http.Client _client = http.Client();

  Map<String, dynamic>? _child;
  Map<String, dynamic> _contextData = {};

  List<Map<String, dynamic>> _doses = [];
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _reminders = [];

  String _programme = 'UIP';

  // Only four filters are supported.
  String _filter = 'all';

  String? _expandedDoseKey;

  String? _childError;
  String? _scheduleError;
  String? _historyError;
  String? _contextError;
  String? _reminderError;

  bool _loadingChild = true;
  bool _loadingSchedule = true;
  bool _loadingHistory = true;
  bool _loadingContext = true;
  bool _loadingReminders = true;

  bool _working = false;
  bool _inAppReminders = true;

  int _revision = 0;
  int _scheduleSequence = 0;

  // ==========================================================
  // CHILD ID
  // ==========================================================

  String get _id {
    final first = widget.childId?.trim() ?? '';

    return first.isNotEmpty
        ? first
        : (widget.profileId?.trim() ?? '');
  }

  // ==========================================================
  // BACKEND URL
  // ==========================================================

  String get _baseUrl {
    final configured = widget.apiBaseUrl.trim();

    if (configured.isNotEmpty) {
      return configured.replaceAll(
        RegExp(r'/+$'),
        '',
      );
    }

    if (!kIsWeb &&
        defaultTargetPlatform ==
            TargetPlatform.android) {
      return 'http://10.0.2.2:5001';
    }

    return 'http://127.0.0.1:5001';
  }

  String _path(String id) {
    return '/api/v1/children/${Uri.encodeComponent(id)}';
  }

  // ==========================================================
  // INITIALIZATION
  // ==========================================================

  @override
  void initState() {
    super.initState();
    _reloadAll();
  }

  @override
  void didUpdateWidget(
      covariant VaccinationScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.childId != widget.childId ||
        oldWidget.profileId != widget.profileId ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _expandedDoseKey = null;
      _child = null;
      _doses = [];
      _records = [];
      _reminders = [];
      _contextData = {};

      _reloadAll();
    }
  }

  @override
  void dispose() {
    _revision++;
    _scheduleSequence++;

    _client.close();

    super.dispose();
  }

  bool _valid(int revision, String id) {
    return mounted &&
        revision == _revision &&
        _id == id;
  }

  // ==========================================================
  // HTTP REQUEST
  // ==========================================================

  Future<Map<String, dynamic>> _request(
      String method,
      String path, {
        Map<String, dynamic>? body,
      }) async {
    String? token;

    try {
      token = await FamilyCareSession.accessToken();
    } on PlatformException {
      throw const _ApiProblem(
        'Unable to access your login session.',
      );
    }

    if (token == null || token.trim().isEmpty) {
      throw const _ApiProblem(
        'Login session missing. Please log in again.',
      );
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
    };

    final uri = Uri.parse('$_baseUrl$path');

    late http.Response response;

    try {
      switch (method) {
        case 'GET':
          response = await _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 30));
          break;

        case 'POST':
          response = await _client
              .post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          )
              .timeout(const Duration(seconds: 30));
          break;

        case 'PATCH':
          response = await _client
              .patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          )
              .timeout(const Duration(seconds: 30));
          break;

        case 'PUT':
          response = await _client
              .put(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          )
              .timeout(const Duration(seconds: 30));
          break;

        case 'DELETE':
          response = await _client
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 30));
          break;

        default:
          throw const _ApiProblem(
            'Unsupported API method.',
          );
      }
    } on TimeoutException {
      throw const _ApiProblem(
        'Request timed out. Refresh before retrying.',
      );
    } on http.ClientException {
      throw const _ApiProblem(
        'Unable to connect to the server.',
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
        } else if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          throw const _ApiProblem(
            'Server returned an invalid response.',
          );
        }
      } on FormatException {
        if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          throw const _ApiProblem(
            'Server returned invalid JSON.',
          );
        }
      }
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final error = data['error'];

      String message =
          'Request failed (${response.statusCode}).';

      if (error is Map &&
          error['message'] is String) {
        message = error['message'] as String;
      }

      if (response.statusCode == 401) {
        message =
        'Session expired. Please log in again.';
      }

      if (response.statusCode == 403) {
        message =
        'You do not have access to this child.';
      }

      if (response.statusCode == 404) {
        message =
        'The child or vaccination record was not found.';
      }

      throw _ApiProblem(message);
    }

    return data;
  }

  String _message(Object error) {
    return error is _ApiProblem
        ? error.message
        : 'Something went wrong. Refresh and try again.';
  }

  void _snack(
      String message, {
        bool error = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
          error ? _VColor.red : _VColor.navy,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ==========================================================
  // LOAD ALL
  // ==========================================================

  Future<void> _reloadAll() async {
    final revision = ++_revision;
    final id = _id;

    if (id.isEmpty) {
      setState(() {
        _loadingChild = false;
        _loadingSchedule = false;
        _loadingHistory = false;
        _loadingContext = false;
        _loadingReminders = false;

        _childError =
        'Child profile ID was not provided.';
      });

      return;
    }

    await Future.wait<void>([
      _loadChild(revision, id),
      _loadSchedule(revision, id, _programme),
      _loadHistory(revision, id),
      _loadContext(revision, id),
      _loadReminders(revision, id),
    ]);
  }

  // ==========================================================
  // CHILD PROFILE
  // ==========================================================

  Future<void> _loadChild(
      int revision,
      String id,
      ) async {
    setState(() {
      _loadingChild = true;
      _childError = null;
    });

    try {
      final result = await _request(
        'GET',
        _path(id),
      );

      if (result['child'] is! Map) {
        throw const _ApiProblem(
          'Invalid child details.',
        );
      }

      if (!_valid(revision, id)) return;

      setState(() {
        _child = Map<String, dynamic>.from(
          result['child'] as Map,
        );
      });
    } catch (error) {
      if (_valid(revision, id)) {
        setState(() {
          _childError = _message(error);
        });
      }
    } finally {
      if (_valid(revision, id)) {
        setState(() {
          _loadingChild = false;
        });
      }
    }
  }

  // ==========================================================
  // VACCINATION SCHEDULE
  // ==========================================================

  Future<void> _loadSchedule(
      int revision,
      String id,
      String programme,
      ) async {
    final sequence = ++_scheduleSequence;

    setState(() {
      _loadingSchedule = true;
      _scheduleError = null;
      _doses = [];
    });

    try {
      final response = await _request(
        'GET',
        '${_path(id)}/vaccinations'
            '?schedule_type=$programme&view=all',
      );

      if (response['items'] is! List) {
        throw const _ApiProblem(
          'Vaccination schedule response is invalid.',
        );
      }

      if (!_valid(revision, id) ||
          sequence != _scheduleSequence ||
          _programme != programme) {
        return;
      }

      setState(() {
        _doses = _maps(response['items']);
      });
    } catch (error) {
      if (_valid(revision, id) &&
          sequence == _scheduleSequence) {
        setState(() {
          _scheduleError = _message(error);
        });
      }
    } finally {
      if (_valid(revision, id) &&
          sequence == _scheduleSequence) {
        setState(() {
          _loadingSchedule = false;
        });
      }
    }
  }

  // ==========================================================
  // VACCINATION HISTORY
  // ==========================================================

  Future<void> _loadHistory(
      int revision,
      String id,
      ) async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });

    try {
      final items = <Map<String, dynamic>>[];
      int page = 1;

      while (page <= 100) {
        final response = await _request(
          'GET',
          '${_path(id)}/vaccinations/history'
              '?page=$page&per_page=100',
        );

        if (response['items'] is! List) {
          throw const _ApiProblem(
            'Invalid vaccination history.',
          );
        }

        final batch = _maps(response['items']);

        items.addAll(batch);

        final total = response['total'];

        if (batch.isEmpty ||
            batch.length < 100 ||
            (total is num && page * 100 >= total)) {
          break;
        }

        page++;
      }

      if (_valid(revision, id)) {
        setState(() {
          _records = items;
        });
      }
    } catch (error) {
      if (_valid(revision, id)) {
        setState(() {
          _historyError = _message(error);
        });
      }
    } finally {
      if (_valid(revision, id)) {
        setState(() {
          _loadingHistory = false;
        });
      }
    }
  }

  // ==========================================================
  // VACCINATION CONTEXT
  // ==========================================================

  Future<void> _loadContext(
      int revision,
      String id,
      ) async {
    setState(() {
      _loadingContext = true;
      _contextError = null;
    });

    try {
      final response = await _request(
        'GET',
        '${_path(id)}/vaccination-context',
      );

      if (response['context'] is! Map) {
        throw const _ApiProblem(
          'Invalid vaccination preferences.',
        );
      }

      if (_valid(revision, id)) {
        setState(() {
          _contextData = _map(
            response['context'],
          );
        });
      }
    } catch (error) {
      if (_valid(revision, id)) {
        setState(() {
          _contextError = _message(error);
        });
      }
    } finally {
      if (_valid(revision, id)) {
        setState(() {
          _loadingContext = false;
        });
      }
    }
  }

  // ==========================================================
  // REMINDERS
  // ==========================================================

  Future<void> _loadReminders(
      int revision,
      String id,
      ) async {
    setState(() {
      _loadingReminders = true;
      _reminderError = null;
    });

    try {
      final response = await _request(
        'GET',
        '${_path(id)}/reminders',
      );

      if (response['items'] is! List) {
        throw const _ApiProblem(
          'Invalid reminder data.',
        );
      }

      final prefs = _map(
        response['preferences'],
      );

      if (_valid(revision, id)) {
        setState(() {
          _reminders = _maps(
            response['items'],
          );

          _inAppReminders =
              prefs['in_app'] != false;
        });
      }
    } catch (error) {
      if (_valid(revision, id)) {
        setState(() {
          _reminderError = _message(error);
        });
      }
    } finally {
      if (_valid(revision, id)) {
        setState(() {
          _loadingReminders = false;
        });
      }
    }
  }

  // ==========================================================
  // JSON HELPERS
  // ==========================================================

  static Map<String, dynamic> _map(
      dynamic raw,
      ) {
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _maps(
      dynamic raw,
      ) {
    if (raw is! List) {
      return <Map<String, dynamic>>[];
    }

    return raw
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
    )
        .toList();
  }

  static String _str(
      dynamic value, [
        String fallback = '',
      ]) {
    final result = value?.toString().trim() ?? '';

    return result.isEmpty ? fallback : result;
  }

  static String _formatDate(dynamic value) {
    final date = value is String
        ? DateTime.tryParse(value)
        : null;

    if (date == null) {
      return 'Not available';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // ==========================================================
  // AGE / DATE OF BIRTH
  // ==========================================================

  DateTime? get _dob {
    final value = _child?['date_of_birth'];

    return value is String
        ? DateTime.tryParse(value)
        : null;
  }

  String get _ageText {
    final age = _map(_child?['age']);

    return _str(
      age['display'],
      'Age not available',
    );
  }

  static const List<String> _ageGroupLabels = [
    '0–1 year',
    '1–5 years',
    '5–10 years',
    '10–12 years',
  ];

  static int? _groupForCompletedYears(
      int years,
      ) {
    if (years < 0 || years >= 13) return null;
    if (years < 1) return 0;
    if (years < 5) return 1;
    if (years < 10) return 2;
    return 3;
  }

  static int? _groupForFractionalYears(
      double years,
      ) {
    if (!years.isFinite ||
        years < 0 ||
        years >= 13) {
      return null;
    }

    if (years < 1) return 0;
    if (years < 5) return 1;
    if (years < 10) return 2;
    return 3;
  }

  int? get _currentBand {
    final age = _map(_child?['age']);
    final years = age['completed_years'];

    if (years is num) {
      return _groupForCompletedYears(
        years.toInt(),
      );
    }

    final dob = _dob;
    if (dob == null) return null;

    final today = DateUtils.dateOnly(
      DateTime.now(),
    );

    final birth = DateUtils.dateOnly(dob);

    if (birth.isAfter(today)) return null;

    int completed = today.year - birth.year;

    if (today.month < birth.month ||
        (today.month == birth.month &&
            today.day < birth.day)) {
      completed--;
    }

    return _groupForCompletedYears(completed);
  }

  int? _bandFor(
      Map<String, dynamic> dose,
      ) {
    final dob = _dob;
    final raw = dose['recommended_date'];

    if (dob != null && raw is String) {
      final recommended = DateTime.tryParse(raw);

      if (recommended != null) {
        int completed =
            recommended.year - dob.year;

        if (recommended.month < dob.month ||
            (recommended.month == dob.month &&
                recommended.day < dob.day)) {
          completed--;
        }

        return _groupForCompletedYears(completed);
      }
    }

    final start = dose['age_start'];
    if (start is! num) return null;

    final years = switch (
    _str(dose['age_unit']).toLowerCase()
    ) {
      'years' => start.toDouble(),
      'months' => start.toDouble() / 12.0,
      'weeks' => start.toDouble() / 52.18,
      'days' => start.toDouble() / 365.25,
      _ => -1.0,
    };

    return _groupForFractionalYears(years);
  }

  // ==========================================================
  // FILTERING - ONLY FOUR OPTIONS
  // ==========================================================

  bool _matchesFilter(
      Map<String, dynamic> dose,
      ) {
    if (_filter == 'all') {
      return true;
    }

    final status = _str(
      dose['status'],
    ).toUpperCase();

    // Match both backend completion and recorded history.
    final isCompleted =
        status == 'COMPLETED' ||
            _historyForDose(dose) != null;

    if (_filter == 'completed') {
      return isCompleted;
    }

    // Recorded doses must not appear in pending filters.
    if (isCompleted) {
      return false;
    }

    if (_filter != 'upcoming' &&
        _filter != 'overdue') {
      return false;
    }

    // Backend-supplied classifications only.
    // No locally invented due dates.
    if (status == _filter.toUpperCase()) {
      return true;
    }

    final views = dose['views'];

    return views is List &&
        views.any(
              (view) =>
          _str(view).toLowerCase() == _filter,
        );
  }

  // ==========================================================
  // SWITCH UIP / IAP
  // ==========================================================

  Future<void> _switchProgramme(
      String next,
      ) async {
    if (_programme == next || _working) {
      return;
    }

    setState(() {
      _programme = next;
      _filter = 'all';
      _expandedDoseKey = null;
    });

    await _loadSchedule(
      _revision,
      _id,
      next,
    );
  }

  // ==========================================================
  // SAVE CONTEXT
  // ==========================================================

  Future<void> _saveContext() async {
    if (_working ||
        _loadingContext ||
        _id.isEmpty) {
      return;
    }

    final updated =
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ContextDialog(
        initial: _contextData,
      ),
    );

    if (updated == null || !mounted) return;

    final revision = _revision;
    final id = _id;

    setState(() {
      _working = true;
    });

    try {
      await _request(
        'PUT',
        '${_path(id)}/vaccination-context',
        body: updated,
      );

      if (!_valid(revision, id)) return;

      _snack(
        'Vaccination preferences saved.',
      );

      await Future.wait<void>([
        _loadContext(revision, id),
        _loadSchedule(revision, id, _programme),
        _loadReminders(revision, id),
      ]);
    } catch (error) {
      if (_valid(revision, id)) {
        _snack(
          _message(error),
          error: true,
        );
      }
    } finally {
      if (_valid(revision, id)) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  // ==========================================================
  // TOGGLE REMINDERS
  // ==========================================================

  Future<void> _toggleReminders(
      bool value,
      ) async {
    if (_working || _id.isEmpty) return;

    final revision = _revision;
    final id = _id;

    setState(() {
      _working = true;
    });

    try {
      await _request(
        'PUT',
        '${_path(id)}/reminder-preferences',
        body: {
          'in_app': value,
        },
      );

      if (!_valid(revision, id)) return;

      setState(() {
        _inAppReminders = value;
      });

      await _loadReminders(revision, id);

      _snack(
        value
            ? 'In-app reminders enabled.'
            : 'In-app reminders disabled.',
      );
    } catch (error) {
      if (_valid(revision, id)) {
        _snack(
          _message(error),
          error: true,
        );
      }
    } finally {
      if (_valid(revision, id)) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  // ==========================================================
  // DOSE HELPERS
  // ==========================================================

  String _doseKey(Map<String, dynamic> dose) {
    return _str(dose['id']);
  }

  bool _isReference(
      Map<String, dynamic> dose,
      ) {
    return dose['reference_only'] == true;
  }

  bool _canLink(
      Map<String, dynamic> dose,
      ) {
    return !_isReference(dose) &&
        _str(dose['publication_status']) ==
            'PUBLISHED' &&
        _str(dose['id']).isNotEmpty &&
        _str(dose['vaccine_id']).isNotEmpty;
  }

  String _doseTitle(
      Map<String, dynamic> dose,
      ) {
    final vaccine = _map(dose['vaccine']);

    return '${_str(vaccine['name_en'], 'Vaccine')} - '
        '${_str(dose['dose_name'], 'Dose')}';
  }

  // ==========================================================
  // INFORMATIONAL INDIA REFERENCE SCHEDULE
  // ==========================================================
  // Format:
  // programme|vaccine|dose|age|unit|label|route|instructions
  //
  // These are informational age references from the
  // supplied schedule, not published patient-specific dates.
  // ==========================================================

  static const String _referenceData = '''
UIP|BCG|Birth dose|0|days|At birth|ID|
UIP|OPV|Dose 0|0|days|At birth|Oral|
UIP|Hepatitis B|Birth dose|0|days|At birth|Injection|Within 24 hours of birth
UIP|OPV|Dose 1|6|weeks|6 weeks|Oral|
UIP|Pentavalent|Dose 1|6|weeks|6 weeks|Injection|
UIP|Rotavirus|Dose 1|6|weeks|6 weeks|Oral|
UIP|fIPV|Dose 1|6|weeks|6 weeks|ID|
UIP|PCV|Dose 1|6|weeks|6 weeks|Injection|
UIP|OPV|Dose 2|10|weeks|10 weeks|Oral|
UIP|Pentavalent|Dose 2|10|weeks|10 weeks|Injection|
UIP|Rotavirus|Dose 2|10|weeks|10 weeks|Oral|
UIP|OPV|Dose 3|14|weeks|14 weeks|Oral|
UIP|Pentavalent|Dose 3|14|weeks|14 weeks|Injection|
UIP|fIPV|Dose 2|14|weeks|14 weeks|ID|
UIP|Rotavirus|Dose 3|14|weeks|14 weeks|Oral|Check product/brand schedule
UIP|PCV|Dose 2|14|weeks|14 weeks|Injection|
UIP|MR|Dose 1|9|months|9 months|Injection|
UIP|JE|Dose 1|9|months|9 months|Injection|JE-endemic districts only
UIP|PCV|Booster|9|months|9 months|Injection|Availability and district programme dependent
UIP|MR|Dose 2|16|months|16–24 months|Injection|
UIP|JE|Dose 2|16|months|16–24 months|Injection|JE-endemic districts only
UIP|DPT|Booster 1|16|months|16–24 months|Injection|
UIP|OPV|Booster|16|months|16–24 months|Oral|
UIP|DPT|Booster 2|5|years|5–6 years|Injection|
UIP|Td|Dose at 10 years|10|years|10 years|Injection|
IAP|BCG|Birth dose|0|days|At birth|ID|
IAP|OPV|Birth dose|0|days|At birth|Oral|
IAP|Hepatitis B|Dose 1|0|days|At birth|Injection|Within 24 hours of birth
IAP|DTwP/DTaP|Dose 1|6|weeks|6 weeks|Injection|
IAP|IPV|Dose 1|6|weeks|6 weeks|Injection|
IAP|Hib|Dose 1|6|weeks|6 weeks|Injection|
IAP|Hepatitis B|Dose 2|6|weeks|6 weeks|Injection|
IAP|Rotavirus|Dose 1|6|weeks|6 weeks|Oral|
IAP|PCV|Dose 1|6|weeks|6 weeks|Injection|
IAP|DTwP/DTaP|Dose 2|10|weeks|10 weeks|Injection|
IAP|IPV|Dose 2|10|weeks|10 weeks|Injection|
IAP|Hib|Dose 2|10|weeks|10 weeks|Injection|
IAP|Hepatitis B|Dose 3|10|weeks|10 weeks|Injection|
IAP|Rotavirus|Dose 2|10|weeks|10 weeks|Oral|
IAP|PCV|Dose 2|10|weeks|10 weeks|Injection|
IAP|DTwP/DTaP|Dose 3|14|weeks|14 weeks|Injection|
IAP|IPV|Dose 3|14|weeks|14 weeks|Injection|
IAP|Hib|Dose 3|14|weeks|14 weeks|Injection|
IAP|Hepatitis B|Dose 4|14|weeks|14 weeks|Injection|Dose 4 where included in combination vaccine
IAP|Rotavirus|Dose 3|14|weeks|14 weeks|Oral|Dose 3 only if required by vaccine brand
IAP|PCV|Dose 3|14|weeks|14 weeks|Injection|
IAP|Influenza|Dose 1|6|months|6 months|Injection|Annual vaccination until 5 years; product and prior history matter
IAP|Typhoid (TCV)|Routine dose|6|months|From 6 months|Injection|May be given from 6 months; confirm schedule with pediatrician
IAP|Influenza|Dose 2|7|months|7 months|Injection|If first-time vaccination; at least 4 weeks after first dose
IAP|MMR|Dose 1|9|months|9 months|Injection|
IAP|Hepatitis A|Dose 1|12|months|12 months|Injection|Product can be single-dose live attenuated or two-dose inactivated
IAP|MMR|Dose 2|15|months|15 months|Injection|
IAP|Varicella|Dose 1|15|months|15 months|Injection|
IAP|PCV|Booster|15|months|15 months|Injection|
IAP|DTwP/DTaP|Booster 1|16|months|16–18 months|Injection|
IAP|Hib|Booster 1|16|months|16–18 months|Injection|
IAP|IPV|Booster 1|16|months|16–18 months|Injection|
IAP|Hepatitis A|Dose 2|18|months|18–19 months|Injection|For the inactivated two-dose formulation
IAP|Varicella|Dose 2|18|months|18–19 months|Injection|
IAP|DTwP/DTaP|Booster 2|4|years|4–6 years|Injection|
IAP|IPV|Booster 2|4|years|4–6 years|Injection|
IAP|MMR|Dose 3|4|years|4–6 years|Injection|
IAP|HPV|Age/sex/product dependent|9|years|9–12 years|Injection|Confirm sex, age, immune status, product approval and regimen with pediatrician
IAP|Tdap|Booster|10|years|10–12 years|Injection|Td may be used if Tdap unavailable/unaffordable, as advised by doctor
''';

  List<Map<String, dynamic>> _referenceSchedule() {
    final lines = _referenceData.trim().split('\n');
    final result = <Map<String, dynamic>>[];

    for (var i = 0; i < lines.length; i++) {
      final fields = lines[i].split('|');

      if (fields.length < 8 ||
          fields[0] != _programme) {
        continue;
      }

      result.add({
        'programme': fields[0],
        'id': 'fc-ref-2026-${i + 1}',
        'vaccine': {
          'name_en': fields[1],
        },
        'dose_name': fields[2],
        'age_start': int.tryParse(fields[3]) ?? 0,
        'age_unit': fields[4],
        'age_label': fields[5],
        'route': fields[6],
        'instructions': fields[7],
        'reference_only': true,
        'publication_status': 'REFERENCE_ONLY',
        'status': 'REFERENCE',
      });
    }

    return result;
  }

  List<Map<String, dynamic>> get _displayDoses {
    if (_doses.isNotEmpty) {
      return _doses;
    }

    if (_loadingSchedule) {
      return [];
    }

    return _referenceSchedule();
  }

  double _ageInDays(
      Map<String, dynamic> dose,
      ) {
    final count = dose['age_start'];

    if (count is! num) return 99999;

    switch (_str(dose['age_unit'])) {
      case 'days':
        return count.toDouble();
      case 'weeks':
        return count * 7.0;
      case 'months':
        return count * 30.44;
      case 'years':
        return count * 365.25;
      default:
        return 99999;
    }
  }

  List<Map<String, dynamic>> get _orderedDoses {
    final result =
    List<Map<String, dynamic>>.from(
      _displayDoses,
    );

    result.sort((a, b) {
      final age = _ageInDays(a).compareTo(
        _ageInDays(b),
      );

      if (age != 0) return age;

      final date = _str(a['recommended_date'])
          .compareTo(
        _str(b['recommended_date']),
      );

      if (date != 0) return date;

      if (_isReference(a) && _isReference(b)) {
        return _doseKey(a).compareTo(
          _doseKey(b),
        );
      }

      return _doseTitle(a).compareTo(
        _doseTitle(b),
      );
    });

    return result;
  }

  Map<String, dynamic>? _historyForDose(
      Map<String, dynamic> dose,
      ) {
    final scheduleId = _doseKey(dose);
    final target = _doseTitle(dose).toLowerCase();

    for (final record in _records) {
      if (_str(record['status']).toLowerCase() !=
          'completed') {
        continue;
      }

      if (!_isReference(dose) &&
          _str(record['schedule_id']) == scheduleId) {
        return record;
      }

      if (_str(record['title']).toLowerCase() ==
          target &&
          (_isReference(dose) ||
              _str(record['schedule_id']).isEmpty)) {
        return record;
      }
    }

    return null;
  }

  bool _isDoctorRecord(
      Map<String, dynamic> record,
      ) {
    return _str(record['verification_status']) ==
        'DOCTOR_REPORTED' ||
        _str(record['source_role']) == 'DOCTOR';
  }

  // ==========================================================
  // SAVE INLINE VACCINATION RECORD
  // ==========================================================

  Future<bool> _saveExpandedDose(
      Map<String, dynamic> dose,
      Map<String, dynamic>? existing,
      Map<String, dynamic> fields,
      ) async {
    if (_working ||
        _loadingHistory ||
        _historyError != null ||
        _id.isEmpty) {
      return false;
    }

    if (existing != null &&
        _isDoctorRecord(existing)) {
      _snack(
        'Doctor-entered records are read-only.',
        error: true,
      );

      return false;
    }

    final payload = <String, dynamic>{
      'title': _doseTitle(dose),
      'status': 'Completed',
      ...fields,
    };

    if (existing != null) {
      final recordId = _str(existing['id']);

      if (recordId.isEmpty) {
        _snack(
          'Vaccination history record ID is missing.',
          error: true,
        );

        return false;
      }

      return _mutateRecord(
        'PATCH',
        '/${Uri.encodeComponent(recordId)}',
        payload,
        'Vaccination details updated.',
      );
    }

    if (_canLink(dose)) {
      payload['schedule_id'] = dose['id'];
      payload['vaccine_id'] = dose['vaccine_id'];
    }

    return _mutateRecord(
      'POST',
      '',
      payload,
      'Vaccination details saved.',
    );
  }

  // ==========================================================
  // EDIT HISTORY RECORD
  // ==========================================================

  Future<void> _editRecord(
      Map<String, dynamic> record, {
        bool dateOnly = false,
      }) async {
    if (_working) return;

    if (_isDoctorRecord(record)) {
      _snack(
        'Doctor-reported records cannot be edited by a parent.',
        error: true,
      );
      return;
    }

    final id = _str(record['id']);

    if (id.isEmpty) {
      _snack(
        'Record ID unavailable.',
        error: true,
      );
      return;
    }

    final result =
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RecordDialog(
        birthDate: _dob,
        original: record,
        initialTitle: _str(
          record['title'],
          'Vaccination',
        ),
        lockTitle:
        _str(record['schedule_id']).isNotEmpty ||
            dateOnly,
        completedOnly: dateOnly,
        dateOnly: dateOnly,
      ),
    );

    if (result == null || !mounted) return;

    await _mutateRecord(
      'PATCH',
      '/${Uri.encodeComponent(id)}',
      result,
      'Vaccination record updated.',
    );
  }

  // ==========================================================
  // DELETE HISTORY RECORD
  // ==========================================================

  Future<void> _deleteRecord(
      Map<String, dynamic> record,
      ) async {
    if (_working) return;

    if (_isDoctorRecord(record)) {
      _snack(
        'Doctor-reported records cannot be deleted by a parent.',
        error: true,
      );
      return;
    }

    final id = _str(record['id']);
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Remove vaccination record?',
          ),
          content: Text(
            'Remove "${_str(record['title'], 'Vaccination')}" '
                'from this child’s history? '
                'This does not delete the child profile. '
                'The record will no longer appear in the app.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: _VColor.red,
              ),
              child: const Text('Remove record'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await _mutateRecord(
      'DELETE',
      '/${Uri.encodeComponent(id)}',
      null,
      'Vaccination record removed.',
    );
  }

  // ==========================================================
  // COMMON RECORD API MUTATION
  // ==========================================================

  Future<bool> _mutateRecord(
      String method,
      String suffix,
      Map<String, dynamic>? data,
      String success,
      ) async {
    final revision = _revision;
    final id = _id;

    setState(() {
      _working = true;
    });

    try {
      await _request(
        method,
        '${_path(id)}/vaccinations/history$suffix',
        body: data,
      );

      if (!_valid(revision, id)) return false;

      _snack(success);

      await Future.wait<void>([
        _loadHistory(revision, id),
        _loadSchedule(revision, id, _programme),
        _loadReminders(revision, id),
      ]);

      return true;
    } catch (error) {
      if (_valid(revision, id)) {
        _snack(
          '${_message(error)} '
              'Check history before retrying.',
          error: true,
        );
      }

      return false;
    } finally {
      if (_valid(revision, id)) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  // ==========================================================
  // MAIN SCREEN
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _VColor.bg,
      appBar: AppBar(
        title: const Text(
          'Vaccination',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: _VColor.navy,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _VColor.navy,
        actions: [
          IconButton(
            tooltip: 'Refresh vaccination data',
            onPressed: _working ? null : _reloadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reloadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            16,
            18,
            16,
            30,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 960,
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  _hero(),

                  if (_childError != null) ...[
                    const SizedBox(height: 10),
                    _notice(
                      _childError!,
                      danger: true,
                    ),
                  ],

                  const SizedBox(height: 16),

                  _programmes(),

                  const SizedBox(height: 16),

                  // All / Completed / Upcoming / Overdue
                  _scheduleOverview(),

                  const SizedBox(height: 16),

                  _ageCards(),

                  const SizedBox(height: 20),

                  _historySection(),

                  const SizedBox(height: 16),

                  _preferencesSection(),

                  const SizedBox(height: 16),

                  _reminderSection(),

                  const SizedBox(height: 16),

                  const Text(
                    'Unpublished dates are references only. '
                        'Recorded doses are parent-reported, not '
                        'doctor-verified. Ask a pediatrician '
                        'about missed doses or catch-up schedules.',
                    style: TextStyle(
                      color: _VColor.muted,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // REUSABLE CARD
  // ==========================================================

  Widget _card({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: _VColor.border,
        ),
      ),
      child: child,
    );
  }

  Widget _notice(
      String message, {
        bool danger = false,
      }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger
            ? const Color(0xFFFFF0F1)
            : _VColor.pale,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            danger
                ? Icons.error_outline_rounded
                : Icons.info_outline,
            size: 19,
            color: danger
                ? _VColor.red
                : _VColor.blue,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _VColor.navy,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CHILD HEADER
  // ==========================================================

  Widget _hero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE6F1FF),
            Color(0xFFEAF6F0),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.child_care_rounded,
              color: _VColor.green,
              size: 35,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  _str(
                    _child?['full_name'],
                    _loadingChild
                        ? 'Loading child...'
                        : 'Child vaccinations',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _VColor.navy,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _ageText,
                  style: const TextStyle(
                    color: _VColor.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'DOB: ${_formatDate(_child?['date_of_birth'])}',
                  style: const TextStyle(
                    color: _VColor.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // UIP / IAP SELECTOR
  // ==========================================================

  Widget _programmes() {
    return _card(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'Vaccination programme',
            style: TextStyle(
              color: _VColor.navy,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final programme in [
                'UIP',
                'IAP',
              ]) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _working
                        ? null
                        : () {
                      _switchProgramme(programme);
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor:
                      _programme == programme
                          ? _VColor.pale
                          : Colors.white,
                      foregroundColor: _VColor.navy,
                      side: BorderSide(
                        color: _programme == programme
                            ? _VColor.blue
                            : _VColor.border,
                      ),
                      padding:
                      const EdgeInsets.symmetric(
                        vertical: 13,
                      ),
                    ),
                    child: Text(
                      programme == 'UIP'
                          ? 'UIP • Government'
                          : 'IAP • Pediatrician',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                if (programme == 'UIP')
                  const SizedBox(width: 9),
              ],
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'The two programmes are separate. '
                'Records are not medical certification.',
            style: TextStyle(
              color: _VColor.muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // FILTER BAR - EXACTLY FOUR FILTERS
  // ==========================================================

  Widget _scheduleOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loadingSchedule)
          const LinearProgressIndicator(
            minHeight: 3,
          ),

        if (_scheduleError != null) ...[
          const SizedBox(height: 6),
          _notice(
            _scheduleError!,
            danger: true,
          ),
        ],

        if (!_loadingSchedule &&
            _displayDoses.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final option in const [
                  ('all', 'All'),
                  ('completed', 'Completed'),
                  ('upcoming', 'Upcoming'),
                  ('overdue', 'Overdue'),
                ]) ...[
                  ChoiceChip(
                    label: Text(
                      option.$2,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    selected: _filter == option.$1,
                    selectedColor: _VColor.pale,
                    backgroundColor: Colors.white,
                    checkmarkColor: _VColor.blue,
                    side: BorderSide(
                      color: _filter == option.$1
                          ? _VColor.blue
                          : _VColor.border,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(10),
                    ),
                    onSelected: (_) {
                      setState(() {
                        _filter = option.$1;
                        _expandedDoseKey = null;
                      });
                    },
                  ),

                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================================
  // AGE GROUPS
  // ==========================================================

  Widget _ageCards() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        const Text(
          'Vaccinations by age group',
          style: TextStyle(
            color: _VColor.navy,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Select a vaccine to record its actual '
              'vaccination date.',
          style: TextStyle(
            color: _VColor.muted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        for (int band = 0;
        band < _ageGroupLabels.length;
        band++) ...[
          _ageCard(band),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ==========================================================
  // SINGLE AGE CARD
  // ==========================================================

  Widget _ageCard(int band) {
    final items = _orderedDoses
        .where(
          (dose) =>
      _bandFor(dose) == band &&
          _matchesFilter(dose),
    )
        .toList();

    final isCurrent = _currentBand == band;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isCurrent
              ? _VColor.blue
              : _VColor.border,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: ExpansionTile(
        key: ValueKey(
          '$_id-$_programme-$band-'
              '${_currentBand ?? -1}',
        ),
        initiallyExpanded:
        _displayDoses.isNotEmpty && isCurrent,
        tilePadding:
        const EdgeInsets.symmetric(
          horizontal: 12,
        ),
        childrenPadding:
        const EdgeInsets.fromLTRB(
          10,
          0,
          10,
          10,
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          backgroundColor: _VColor.pale,
          child: Text(
            '${band + 1}',
            style: const TextStyle(
              color: _VColor.blue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(
          _ageGroupLabels[band],
          style: const TextStyle(
            color: _VColor.navy,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          isCurrent
              ? 'Current age group • '
              '${items.length} vaccine doses'
              : '${items.length} vaccine doses',
          style: const TextStyle(
            color: _VColor.muted,
            fontSize: 11,
          ),
        ),
        children: [
          const Divider(
            color: _VColor.border,
          ),
          if (_displayDoses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _loadingSchedule
                    ? 'Loading vaccination plan...'
                    : _scheduleError != null
                    ? 'Schedule unavailable due '
                    'to a loading error.'
                    : 'No entries available '
                    'for this age band.',
                style: const TextStyle(
                  color: _VColor.muted,
                  fontSize: 12,
                ),
              ),
            )
          else if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'No matching entries in this age band. '
                    'This does not confirm vaccination '
                    'is complete.',
                style: TextStyle(
                  color: _VColor.muted,
                  fontSize: 12,
                ),
              ),
            )
          else
            for (final dose in items) ...[
              _doseCard(dose),
              const SizedBox(height: 6),
            ],
        ],
      ),
    );
  }

  // ==========================================================
  // VACCINATION DATE DISPLAY
  // ==========================================================

  String _routineWindow(
      Map<String, dynamic> dose,
      ) {
    final start = _formatDate(
      dose['recommended_date'],
    );

    final end = _formatDate(
      dose['window_end'],
    );

    if (start == 'Not available' ||
        end == 'Not available') {
      return 'Not published';
    }

    return start == end
        ? start
        : '$start – $end';
  }

  Widget _compactDoseDetail(
      String label,
      String value,
      ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: _VColor.muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _VColor.navy,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // VACCINATION DOSE CARD
  // ==========================================================

  Widget _doseCard(
      Map<String, dynamic> dose,
      ) {
    final vaccine = _map(dose['vaccine']);
    final record = _historyForDose(dose);

    final isReadOnly = record != null &&
        _isDoctorRecord(record);

    final doseKey =
        '$_id/$_programme/${_doseKey(dose)}';

    final isExpanded =
        _expandedDoseKey == doseKey;

    final recommendedDate = _formatDate(
      dose['recommended_date'],
    );

    final hasRecommendedDate =
        recommendedDate != 'Not available';

    final ageLabel = _str(
      dose['age_label'],
      'Not available',
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpanded
              ? _VColor.blue
              : _VColor.border,
          width: isExpanded ? 1.25 : 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.stretch,
        children: [
          Material(
            color: _VColor.bg,
            child: InkWell(
              onTap: _working
                  ? null
                  : () {
                setState(() {
                  _expandedDoseKey =
                  isExpanded
                      ? null
                      : doseKey;
                });
              },
              child: Padding(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_str(vaccine['name_en'], 'Vaccine')} • '
                                '${_str(dose['dose_name'], 'Dose')}',
                            style: const TextStyle(
                              color: _VColor.navy,
                              fontWeight:
                              FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),

                        if (record != null) ...[
                          const Tooltip(
                            message:
                            'Administration date saved. '
                                'This is not medical verification.',
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: _VColor.blue,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],

                        Icon(
                          isExpanded
                              ? Icons
                              .keyboard_arrow_up_rounded
                              : Icons
                              .keyboard_arrow_down_rounded,
                          size: 23,
                          color: _VColor.muted,
                        ),
                      ],
                    ),

                    const SizedBox(height: 7),

                    _compactDoseDetail(
                      hasRecommendedDate
                          ? 'Recommended date'
                          : 'Recommended age',
                      hasRecommendedDate
                          ? recommendedDate
                          : ageLabel,
                    ),

                    _compactDoseDetail(
                      hasRecommendedDate &&
                          recommendedDate ==
                              _formatDate(
                                dose['window_end'],
                              )
                          ? 'Routine date'
                          : 'Routine window',
                      _routineWindow(dose),
                    ),
                  ],
                ),
              ),
            ),
          ),

          AnimatedSize(
            duration:
            const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                const Divider(
                  height: 1,
                  color: _VColor.border,
                ),

                if (_loadingHistory)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child:
                    LinearProgressIndicator(),
                  )
                else if (_historyError != null)
                  Padding(
                    padding:
                    const EdgeInsets.all(12),
                    child: _notice(
                      'Could not load vaccination '
                          'history. Refresh before '
                          'adding a record.',
                      danger: true,
                    ),
                  )
                else
                  _InlineVaccinationForm(
                    key: ValueKey(
                      'form/$doseKey/'
                          '${_str(record?['id'])}',
                    ),
                    title: _doseTitle(dose),
                    birthDate: _dob,
                    existing: record,
                    readOnly: isReadOnly,
                    busy: _working,
                    onSave: (fields) async {
                      final saved =
                      await _saveExpandedDose(
                        dose,
                        record,
                        fields,
                      );

                      if (saved &&
                          mounted &&
                          _expandedDoseKey ==
                              doseKey) {
                        setState(() {
                          _expandedDoseKey = null;
                        });
                      }
                    },
                    onDelete: record == null ||
                        isReadOnly
                        ? null
                        : () async {
                      await _deleteRecord(
                        record,
                      );
                    },
                    onClose: () {
                      if (!_working) {
                        setState(() {
                          _expandedDoseKey = null;
                        });
                      }
                    },
                  ),
              ],
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // REUSABLE DETAIL ROW
  // ==========================================================

  Widget _detail(
      String title,
      String value,
      ) {
    if (value.isEmpty ||
        value == 'Not available') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 117,
            child: Text(
              title,
              style: const TextStyle(
                color: _VColor.muted,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _VColor.navy,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // VACCINATION HISTORY
  // ==========================================================

  Widget _historySection() {
    return _card(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'Vaccination history',
            style: TextStyle(
              color: _VColor.navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 5),

          const Text(
            'Parent-entered records are not medically '
                'verified. Doctor-authored entries are read-only.',
            style: TextStyle(
              color: _VColor.muted,
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 12),

          if (_loadingHistory)
            const LinearProgressIndicator(),

          if (_historyError != null)
            _notice(
              _historyError!,
              danger: true,
            ),

          if (!_loadingHistory &&
              _historyError == null &&
              _records.isEmpty)
            const Text(
              'No vaccination history recorded yet.',
              style: TextStyle(
                color: _VColor.muted,
              ),
            ),

          if (!_loadingHistory &&
              _historyError == null)
            for (final record in _records) ...[
              Container(
                margin:
                const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _VColor.bg,
                  borderRadius:
                  BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.fact_check_outlined,
                      color: _VColor.green,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            _str(
                              record['title'],
                              'Vaccine record',
                            ),
                            style: const TextStyle(
                              fontWeight:
                              FontWeight.w700,
                              color: _VColor.navy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_formatDate(record['date'])} '
                                '• ${_str(record['status'], 'Recorded')}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _VColor.muted,
                            ),
                          ),
                        ],
                      ),
                    ),

                    IconButton(
                      tooltip:
                      'Edit vaccination record',
                      onPressed: (_working ||
                          _isDoctorRecord(record))
                          ? null
                          : () {
                        _editRecord(record);
                      },
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: _VColor.blue,
                      ),
                    ),

                    IconButton(
                      tooltip:
                      'Remove vaccination record',
                      onPressed: (_working ||
                          _isDoctorRecord(record))
                          ? null
                          : () {
                        _deleteRecord(record);
                      },
                      icon: const Icon(
                        Icons.delete_outline,
                        color: _VColor.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  // ==========================================================
  // VACCINATION PREFERENCES
  // ==========================================================

  Widget _preferencesSection() {
    return _card(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Vaccination preferences',
                  style: TextStyle(
                    color: _VColor.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _working ||
                    _loadingContext
                    ? null
                    : _saveContext,
                icon: const Icon(
                  Icons.tune_rounded,
                  size: 17,
                ),
                label: const Text('Set details'),
              ),
            ],
          ),

          if (_loadingContext)
            const LinearProgressIndicator(),

          if (_contextError != null)
            _notice(
              _contextError!,
              danger: true,
            ),

          if (!_loadingContext &&
              _contextError == null) ...[
            _detail(
              'Country',
              _str(
                _contextData['country'],
                'Not selected',
              ),
            ),

            _detail(
              'State',
              _str(
                _contextData['state'],
                'Not provided',
              ),
            ),

            _detail(
              'District',
              _str(
                _contextData['district'],
                'Not provided',
              ),
            ),

            _detail(
              'Gender',
              _str(
                _contextData['gender'],
                'Unknown',
              ),
            ),

            _detail(
              'History status',
              _str(
                _contextData['history_status'],
                'UNKNOWN',
              ),
            ),

            const SizedBox(height: 5),

            const Text(
              'These details affect eligibility review. '
                  'Missing information must not be treated '
                  'as medical clearance.',
              style: TextStyle(
                color: _VColor.muted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // VACCINATION REMINDERS
  // ==========================================================

  Widget _reminderSection() {
    return _card(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'Vaccination reminders',
            style: TextStyle(
              color: _VColor.navy,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 5),

          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'In-app reminders',
              style: TextStyle(
                fontSize: 13,
              ),
            ),
            subtitle: const Text(
              'Email reminders require separate '
                  'opt-in. SMS is not available.',
              style: TextStyle(
                fontSize: 11,
                color: _VColor.muted,
              ),
            ),
            value: _inAppReminders,
            onChanged: _working ||
                _loadingReminders ||
                _reminderError != null
                ? null
                : _toggleReminders,
          ),

          if (_loadingReminders)
            const LinearProgressIndicator(),

          if (_reminderError != null)
            _notice(
              _reminderError!,
              danger: true,
            ),

          if (!_loadingReminders &&
              _reminderError == null &&
              _reminders.isEmpty)
            const Text(
              'No reminders currently available.',
              style: TextStyle(
                color: _VColor.muted,
                fontSize: 12,
              ),
            ),

          if (!_loadingReminders &&
              _reminderError == null)
            for (final reminder in _reminders.take(5))
              Padding(
                padding:
                const EdgeInsets.symmetric(
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      size: 19,
                      color: _VColor.blue,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${_str(reminder['title'], 'Vaccination reminder')} '
                            '• ${_formatDate(reminder['date'])}',
                        style: const TextStyle(
                          color: _VColor.navy,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ============================================================
// INLINE VACCINATION FORM
// ============================================================

class _InlineVaccinationForm extends StatefulWidget {
  final String title;
  final DateTime? birthDate;
  final Map<String, dynamic>? existing;
  final bool readOnly;
  final bool busy;
  final Future<void> Function(
      Map<String, dynamic> fields,
      ) onSave;
  final Future<void> Function()? onDelete;
  final VoidCallback onClose;

  const _InlineVaccinationForm({
    super.key,
    required this.title,
    required this.birthDate,
    required this.existing,
    required this.readOnly,
    required this.busy,
    required this.onSave,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<_InlineVaccinationForm> createState() =>
      _InlineVaccinationFormState();
}

class _InlineVaccinationFormState
    extends State<_InlineVaccinationForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _provider;
  late final TextEditingController _vaccinator;
  late final TextEditingController _batch;
  late final TextEditingController _notes;

  DateTime? _vaccinatedOn;

  @override
  void initState() {
    super.initState();

    final existing =
        widget.existing ?? <String, dynamic>{};

    _vaccinatedOn = DateTime.tryParse(
      (existing['date'] ?? '').toString(),
    );

    _provider = TextEditingController(
      text: (existing['provider'] ?? '').toString(),
    );

    _vaccinator = TextEditingController(
      text: (existing['vaccinator'] ?? '').toString(),
    );

    _batch = TextEditingController(
      text:
      (existing['batch_number'] ?? '').toString(),
    );

    _notes = TextEditingController(
      text: (existing['notes'] ?? '').toString(),
    );
  }

  @override
  void didUpdateWidget(
      covariant _InlineVaccinationForm oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.existing != widget.existing &&
        widget.existing != null &&
        !widget.busy) {
      final record = widget.existing!;

      _vaccinatedOn = DateTime.tryParse(
        (record['date'] ?? '').toString(),
      );

      _provider.text =
          (record['provider'] ?? '').toString();

      _vaccinator.text =
          (record['vaccinator'] ?? '').toString();

      _batch.text =
          (record['batch_number'] ?? '').toString();

      _notes.text =
          (record['notes'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    _provider.dispose();
    _vaccinator.dispose();
    _batch.dispose();
    _notes.dispose();

    super.dispose();
  }

  String _apiDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _visibleDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Future<void> _pickDate() async {
    if (widget.readOnly || widget.busy) return;

    final today = DateUtils.dateOnly(
      DateTime.now(),
    );

    final dob = widget.birthDate;

    final first = dob != null
        ? DateUtils.dateOnly(dob)
        : DateTime(1900);

    if (first.isAfter(today)) return;

    var initial = _vaccinatedOn ?? today;

    if (initial.isBefore(first)) {
      initial = first;
    }

    if (initial.isAfter(today)) {
      initial = today;
    }

    final chosen = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: today,
      helpText: 'ACTUAL VACCINATION DATE',
    );

    if (mounted && chosen != null) {
      setState(() {
        _vaccinatedOn = chosen;
      });
    }
  }

  void _submit() {
    if (widget.busy || widget.readOnly) return;

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final date = _vaccinatedOn;

    if (date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please choose the actual vaccination date.',
          ),
        ),
      );

      return;
    }

    final today = DateUtils.dateOnly(
      DateTime.now(),
    );

    if (date.isAfter(today) ||
        (widget.birthDate != null &&
            date.isBefore(
              DateUtils.dateOnly(widget.birthDate!),
            ))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vaccination date must be between '
                'birth and today.',
          ),
        ),
      );

      return;
    }

    FocusScope.of(context).unfocus();

    widget.onSave({
      'date': _apiDate(date),
      'provider': _provider.text.trim(),
      'vaccinator': _vaccinator.text.trim(),
      'batch_number': _batch.text.trim(),
      'notes': _notes.text.trim(),
    });
  }

  Widget _optionalField(
      TextEditingController controller,
      String title,
      int maxLength, {
        int lines = 1,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        enabled: !widget.readOnly && !widget.busy,
        maxLength: maxLength,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: title,
          border: const OutlineInputBorder(),
          isDense: true,
          counterText: '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
      const EdgeInsets.fromLTRB(12, 13, 12, 13),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null
                  ? 'Enter vaccination details'
                  : widget.readOnly
                  ? 'Recorded details • doctor-entered'
                  : 'View / edit vaccination details',
              style: const TextStyle(
                color: _VColor.navy,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.readOnly ||
                    widget.busy
                    ? null
                    : _pickDate,
                icon: const Icon(
                  Icons.calendar_month_outlined,
                  size: 18,
                ),
                label: Text(
                  _vaccinatedOn == null
                      ? 'Select actual vaccination date *'
                      : 'Vaccinated on '
                      '${_visibleDate(_vaccinatedOn!)}',
                  style: const TextStyle(
                    fontSize: 12,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            _optionalField(
              _provider,
              'Hospital / clinic (optional)',
              160,
            ),

            _optionalField(
              _vaccinator,
              'Vaccinator name (optional)',
              160,
            ),

            _optionalField(
              _batch,
              'Vaccine batch number (optional)',
              100,
            ),

            _optionalField(
              _notes,
              'Additional notes (optional)',
              2000,
              lines: 3,
            ),

            const Text(
              'This is a recorded vaccination history '
                  'entry, not a medical verification or '
                  'catch-up recommendation.',
              style: TextStyle(
                fontSize: 10,
                color: _VColor.muted,
              ),
            ),

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment:
              WrapCrossAlignment.center,
              children: [
                if (!widget.readOnly)
                  FilledButton.icon(
                    onPressed:
                    widget.busy ? null : _submit,
                    icon: const Icon(
                      Icons.save_outlined,
                      size: 17,
                    ),
                    label: Text(
                      widget.existing == null
                          ? 'Save vaccination'
                          : 'Save changes',
                    ),
                  ),

                if (widget.onDelete != null &&
                    !widget.readOnly)
                  OutlinedButton.icon(
                    onPressed: widget.busy
                        ? null
                        : widget.onDelete,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 17,
                    ),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _VColor.red,
                    ),
                  ),

                TextButton(
                  onPressed:
                  widget.busy ? null : widget.onClose,
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// VACCINATION HISTORY RECORD DIALOG
// ============================================================

class _RecordDialog extends StatefulWidget {
  final DateTime? birthDate;
  final String initialTitle;
  final Map<String, dynamic>? original;
  final bool lockTitle;
  final bool completedOnly;
  final bool dateOnly;

  const _RecordDialog({
    required this.birthDate,
    required this.initialTitle,
    this.original,
    this.lockTitle = false,
    this.completedOnly = false,
    this.dateOnly = false,
  });

  @override
  State<_RecordDialog> createState() =>
      _RecordDialogState();
}

class _RecordDialogState
    extends State<_RecordDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _provider;
  late final TextEditingController _vaccinator;
  late final TextEditingController _batch;
  late final TextEditingController _notes;

  String _status = 'Completed';

  DateTime? _date;

  @override
  void initState() {
    super.initState();

    final old = widget.original ?? {};

    _title = TextEditingController(
      text: widget.initialTitle,
    );

    _provider = TextEditingController(
      text: _value(old['provider']),
    );

    _vaccinator = TextEditingController(
      text: _value(old['vaccinator']),
    );

    _batch = TextEditingController(
      text: _value(old['batch_number']),
    );

    _notes = TextEditingController(
      text: _value(old['notes']),
    );

    final status = _value(old['status']);

    if (!widget.dateOnly &&
        [
          'Completed',
          'Planned',
          'Missed',
        ].contains(status)) {
      _status = status;
    }

    final rawDate = old['date'];

    if (rawDate is String) {
      _date = DateTime.tryParse(rawDate);
    }
  }

  static String _value(dynamic input) {
    return input?.toString() ?? '';
  }

  @override
  void dispose() {
    _title.dispose();
    _provider.dispose();
    _vaccinator.dispose();
    _batch.dispose();
    _notes.dispose();

    super.dispose();
  }

  String _dateApi(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(
      DateTime.now(),
    );

    final first = widget.birthDate == null
        ? DateTime(today.year - 13, 1, 1)
        : DateUtils.dateOnly(widget.birthDate!);

    final last = _status == 'Planned'
        ? DateTime(today.year + 5, 12, 31)
        : today;

    if (first.isAfter(last)) return;

    DateTime initial = _date ?? today;

    if (initial.isBefore(first)) {
      initial = first;
    }

    if (initial.isAfter(last)) {
      initial = last;
    }

    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: _status == 'Planned'
          ? 'PLANNED VACCINATION DATE'
          : 'VACCINATION RECORD DATE',
    );

    if (selected != null && mounted) {
      setState(() {
        _date = selected;
      });
    }
  }

  void _submit() {
    if (!widget.dateOnly &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final date = _date;

    if (date == null) {
      _showError('Choose a record date.');
      return;
    }

    final today = DateUtils.dateOnly(
      DateTime.now(),
    );

    if (widget.birthDate != null &&
        date.isBefore(
          DateUtils.dateOnly(widget.birthDate!),
        )) {
      _showError(
        'Record date cannot be before '
            'the child’s birth.',
      );

      return;
    }

    if (_status != 'Planned' &&
        date.isAfter(today)) {
      _showError(
        'Completed or missed doses '
            'cannot have future dates.',
      );

      return;
    }

    Navigator.of(context).pop(
      <String, dynamic>{
        'title': _title.text.trim(),
        'date': _dateApi(date),
        'status': _status,
        'provider': _provider.text.trim(),
        'vaccinator': _vaccinator.text.trim(),
        'batch_number': _batch.text.trim(),
        'notes': _notes.text.trim(),
      },
    );
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  Widget _field(
      TextEditingController controller,
      String label,
      int limit,
      ) {
    return TextFormField(
      controller: controller,
      maxLength: limit,
      decoration: InputDecoration(
        labelText: '$label (optional)',
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dateOnly) {
      return AlertDialog(
        title: Text(
          widget.original == null
              ? 'Record vaccination date'
              : 'Edit vaccination date',
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                widget.initialTitle,
                style: const TextStyle(
                  color: _VColor.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                  ),
                  label: Text(
                    _date == null
                        ? 'Choose vaccination date'
                        : _dateApi(_date!),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Enter the actual vaccination date. '
                    'This is a parent-reported record.',
                style: TextStyle(
                  color: _VColor.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('Save date'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(
        widget.original == null
            ? 'Record vaccination'
            : 'Edit vaccination record',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Records are parent-reported, '
                      'not verified by a doctor.',
                  style: TextStyle(
                    fontSize: 11,
                    color: _VColor.muted,
                  ),
                ),

                const SizedBox(height: 13),

                TextFormField(
                  controller: _title,
                  readOnly: widget.lockTitle,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Vaccine / dose',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    return (value ?? '').trim().isEmpty
                        ? 'Vaccine name required'
                        : null;
                  },
                ),

                if (widget.completedOnly)
                  const Padding(
                    padding:
                    EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Status: Completed (parent-reported)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _VColor.green,
                      ),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Record status',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      'Completed',
                      'Planned',
                      'Missed',
                    ].map((value) {
                      return DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _status = value;
                        });
                      }
                    },
                  ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(
                    Icons.calendar_today_outlined,
                  ),
                  label: Text(
                    _date == null
                        ? 'Select vaccination date (required)'
                        : 'Vaccination date: '
                        '${_dateApi(_date!)}',
                  ),
                ),

                const SizedBox(height: 11),

                _field(
                  _provider,
                  'Clinic / hospital',
                  160,
                ),

                const SizedBox(height: 10),

                _field(
                  _vaccinator,
                  'Vaccinator name',
                  160,
                ),

                const SizedBox(height: 10),

                _field(
                  _batch,
                  'Batch number',
                  100,
                ),

                const SizedBox(height: 10),

                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save record'),
        ),
      ],
    );
  }
}

// ============================================================
// VACCINATION CONTEXT / PREFERENCES DIALOG
// ============================================================

class _ContextDialog extends StatefulWidget {
  final Map<String, dynamic> initial;

  const _ContextDialog({
    required this.initial,
  });

  @override
  State<_ContextDialog> createState() =>
      _ContextDialogState();
}

class _ContextDialogState
    extends State<_ContextDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _stateName;
  late final TextEditingController _district;

  String _gender = 'Unknown';
  String _history = 'UNKNOWN';

  bool _email = false;

  @override
  void initState() {
    super.initState();

    _stateName = TextEditingController(
      text: '${widget.initial['state'] ?? ''}',
    );

    _district = TextEditingController(
      text: '${widget.initial['district'] ?? ''}',
    );

    final gender =
        '${widget.initial['gender'] ?? 'Unknown'}';

    if ([
      'Unknown',
      'Girls',
      'Boys',
    ].contains(gender)) {
      _gender = gender;
    }

    final history =
        '${widget.initial['history_status'] ?? 'UNKNOWN'}';

    if ([
      'UNKNOWN',
      'PARENT_REPORTED',
    ].contains(history)) {
      _history = history;
    }

    _email =
        widget.initial['email_reminders'] == true;
  }

  @override
  void dispose() {
    _stateName.dispose();
    _district.dispose();

    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ??
        false)) {
      return;
    }

    Navigator.pop(
      context,
      <String, dynamic>{
        'country': 'IN',
        'state': _stateName.text.trim(),
        'district': _district.text.trim(),
        'gender': _gender,
        'history_status': _history,
        'email_reminders': _email,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Vaccination preferences',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const Text(
                  'Location is an eligibility hint. '
                      'Do not guess unknown details.',
                  style: TextStyle(
                    fontSize: 11,
                    color: _VColor.muted,
                  ),
                ),

                const SizedBox(height: 13),

                const Text(
                  'Country: India',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 10),

                TextFormField(
                  controller: _stateName,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'State (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 8),

                TextFormField(
                  controller: _district,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'District (optional)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if ((value ?? '')
                        .trim()
                        .isNotEmpty &&
                        _stateName.text
                            .trim()
                            .isEmpty) {
                      return 'Enter the state before '
                          'entering a district.';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(
                    labelText:
                    'Child gender (for schedule rules)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    'Unknown',
                    'Girls',
                    'Boys',
                  ].map((value) {
                    return DropdownMenuItem(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _gender = value;
                      });
                    }
                  },
                ),

                const SizedBox(height: 12),

                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I have reviewed the vaccination history',
                    style: TextStyle(
                      fontSize: 12,
                    ),
                  ),
                  subtitle: const Text(
                    'Only mark checked when known '
                        'history has been provided.',
                    style: TextStyle(
                      fontSize: 11,
                    ),
                  ),
                  value:
                  _history == 'PARENT_REPORTED',
                  onChanged: (value) {
                    setState(() {
                      _history = value == true
                          ? 'PARENT_REPORTED'
                          : 'UNKNOWN';
                    });
                  },
                ),

                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Opt in to email reminders',
                    style: TextStyle(
                      fontSize: 12,
                    ),
                  ),
                  subtitle: const Text(
                    'Requires a verified email '
                        'and eligible published policy.',
                    style: TextStyle(
                      fontSize: 11,
                    ),
                  ),
                  value: _email,
                  onChanged: (value) {
                    setState(() {
                      _email = value ?? false;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text(
            'Save preferences',
          ),
        ),
      ],
    );
  }
}
