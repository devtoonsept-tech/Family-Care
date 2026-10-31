
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
//
// Flask backend endpoints:
//
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
// Only published UIP/IAP schedules are shown.
// Parent-reported history is never clinical verification.
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
// COLORS
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
// MAIN STATE
// ============================================================

class _VaccinationScreenState
    extends State<VaccinationScreen> {
  final http.Client _client = http.Client();

  Map<String, dynamic>? _child;

  Map<String, dynamic> _contextData = {};
  Map<String, dynamic> _counts = {};
  Map<String, dynamic> _publication = {};

  List<Map<String, dynamic>> _doses = [];
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _reminders = [];

  String _programme = 'UIP';
  String _filter = 'all';

  String _scheduleStatus = 'NOT_AVAILABLE';
  String _scheduleMessage = '';

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
  // API BASE URL
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
        defaultTargetPlatform == TargetPlatform.android) {
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
      _child = null;
      _doses = [];
      _records = [];
      _reminders = [];

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

  // ==========================================================
  // REQUEST VALIDATION
  // ==========================================================

  bool _valid(
      int revision,
      String id,
      ) {
    return mounted &&
        revision == _revision &&
        _id == id;
  }

  // ==========================================================
  // AUTHENTICATED HTTP REQUEST
  // ==========================================================

  Future<Map<String, dynamic>> _request(
      String method,
      String path, {
        Map<String, dynamic>? body,
      }) async {
    final token =
    await FamilyCareSession.accessToken();

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
              .get(
            uri,
            headers: headers,
          )
              .timeout(
            const Duration(seconds: 30),
          );
          break;

        case 'POST':
          response = await _client
              .post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          )
              .timeout(
            const Duration(seconds: 30),
          );
          break;

        case 'PATCH':
          response = await _client
              .patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          )
              .timeout(
            const Duration(seconds: 30),
          );
          break;

        case 'PUT':
          response = await _client
              .put(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          )
              .timeout(
            const Duration(seconds: 30),
          );
          break;

        case 'DELETE':
          response = await _client
              .delete(
            uri,
            headers: headers,
          )
              .timeout(
            const Duration(seconds: 30),
          );
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
    } on PlatformException {
      throw const _ApiProblem(
        'Unable to access your login session.',
      );
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );
    } on FormatException {
      throw const _ApiProblem(
        'Server returned invalid JSON.',
      );
    }

    if (decoded is! Map) {
      throw const _ApiProblem(
        'Server returned an invalid response.',
      );
    }

    final data =
    Map<String, dynamic>.from(decoded);

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
  // LOAD ALL DATA
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
      _loadSchedule(
        revision,
        id,
        _programme,
      ),
      _loadHistory(revision, id),
      _loadContext(revision, id),
      _loadReminders(revision, id),
    ]);
  }

  // ==========================================================
  // GET CHILD PROFILE
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
  // GET PUBLISHED VACCINATION SCHEDULE
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
      _counts = {};
      _publication = {};

      _scheduleStatus = 'NOT_AVAILABLE';
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

        _counts = _map(
          response['counts'],
        );

        _publication = _map(
          response['publication'],
        );

        _scheduleStatus = _str(
          response['status'],
          'NOT_AVAILABLE',
        );

        _scheduleMessage = _str(
          response['message'],
        );
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
  // GET VACCINATION HISTORY
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

        final batch = _maps(
          response['items'],
        );

        items.addAll(batch);

        final total = response['total'];

        if (batch.isEmpty ||
            batch.length < 100 ||
            (total is num &&
                page * 100 >= total)) {
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
  // GET VACCINATION CONTEXT
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
  // GET REMINDERS
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
    return raw is List
        ? raw
        .whereType<Map>()
        .map(
          (item) =>
      Map<String, dynamic>.from(item),
    )
        .toList()
        : <Map<String, dynamic>>[];
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
  // CHILD DOB / AGE
  // ==========================================================

  DateTime? get _dob {
    final value = _child?['date_of_birth'];

    return value is String
        ? DateTime.tryParse(value)
        : null;
  }

  String get _ageText {
    final age = _map(
      _child?['age'],
    );

    return _str(
      age['display'],
      'Age not available',
    );
  }

  int? get _currentBand {
    final age = _map(
      _child?['age'],
    );

    final years = age['completed_years'];

    if (years is! num ||
        years < 0 ||
        years > 12) {
      return null;
    }

    return years >= 12 ? 11 : years.toInt();
  }

  // ==========================================================
  // GROUP PUBLISHED DOSES INTO 12 AGE CARDS
  //
  // Dates and clinical status come from Flask.
  // This function only chooses which UI card to use.
  //
  // The final card also includes doses starting at
  // exactly 12 years, within this 0-12-year view.
  // ==========================================================

  int? _bandFor(
      Map<String, dynamic> dose,
      ) {
    final dob = _dob;
    final raw = dose['recommended_date'];

    if (dob != null && raw is String) {
      final recommended =
      DateTime.tryParse(raw);

      if (recommended != null) {
        int years =
            recommended.year - dob.year;

        if (recommended.month < dob.month ||
            (recommended.month == dob.month &&
                recommended.day < dob.day)) {
          years--;
        }

        if (years < 0 || years > 12) {
          return null;
        }

        return years == 12 ? 11 : years;
      }
    }

    final start = dose['age_start'];

    if (start is! num) return null;

    final unit = _str(
      dose['age_unit'],
    );

    final years = switch (unit) {
      'years' => start.toDouble(),
      'months' => start / 12.0,
      'weeks' => start / 52.18,
      'days' => start / 365.25,
      _ => -1.0,
    };

    if (years < 0 || years > 12) {
      return null;
    }

    final band = years.floor();

    return band == 12 ? 11 : band;
  }

  // ==========================================================
  // FILTER SCHEDULE DOSES
  // ==========================================================

  bool _matchesFilter(
      Map<String, dynamic> dose,
      ) {
    if (_filter == 'all') return true;

    final status = _str(
      dose['status'],
    );

    if (_filter == 'review_required') {
      return status == 'REVIEW_REQUIRED';
    }

    if (_filter == 'not_applicable') {
      return status == 'NOT_APPLICABLE';
    }

    if (_filter == 'completed') {
      return status == 'COMPLETED';
    }

    final views = dose['views'];

    return views is List &&
        views.contains(_filter);
  }

  bool get _published {
    return !_loadingSchedule &&
        _scheduleError == null &&
        _scheduleStatus == 'AVAILABLE' &&
        _doses.isNotEmpty;
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
    });

    await _loadSchedule(
      _revision,
      _id,
      next,
    );
  }

  // ==========================================================
  // SAVE VACCINATION CONTEXT
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

    if (updated == null || !mounted) {
      return;
    }

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
        _loadSchedule(
          revision,
          id,
          _programme,
        ),
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
  // REMINDER TOGGLE
  // ==========================================================

  Future<void> _toggleReminders(
      bool value,
      ) async {
    if (_working || _id.isEmpty) {
      return;
    }

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

      await _loadReminders(
        revision,
        id,
      );

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
  // CREATE VACCINATION RECORD
  // ==========================================================

  Future<void> _createRecord(
      Map<String, dynamic> dose,
      ) async {
    if (_working || _id.isEmpty) {
      return;
    }

    final vaccine = _map(
      dose['vaccine'],
    );

    final title =
        '${_str(vaccine['name_en'], 'Vaccine')} - '
        '${_str(dose['dose_name'], 'Dose')}';

    final result =
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RecordDialog(
        birthDate: _dob,
        initialTitle: title,
        lockTitle: true,
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    final scheduleId = dose['id'];
    final vaccineId = dose['vaccine_id'];

    if (scheduleId is! String ||
        vaccineId is! String ||
        scheduleId.isEmpty ||
        vaccineId.isEmpty) {
      _snack(
        'Published dose identifiers are missing.',
        error: true,
      );
      return;
    }

    result['schedule_id'] = scheduleId;
    result['vaccine_id'] = vaccineId;

    await _mutateRecord(
      'POST',
      '',
      result,
      'Vaccination record saved as parent-reported.',
    );
  }

  // ==========================================================
  // EDIT VACCINATION RECORD
  // ==========================================================

  Future<void> _editRecord(
      Map<String, dynamic> record,
      ) async {
    if (_working) return;

    final id = _str(
      record['id'],
    );

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
        _str(record['schedule_id']).isNotEmpty,
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    await _mutateRecord(
      'PATCH',
      '/${Uri.encodeComponent(id)}',
      result,
      'Vaccination record updated.',
    );
  }

  // ==========================================================
  // DELETE VACCINATION RECORD
  // ==========================================================

  Future<void> _deleteRecord(
      Map<String, dynamic> record,
      ) async {
    if (_working) return;

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
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: _VColor.red,
              ),
              child: const Text(
                'Remove record',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _mutateRecord(
      'DELETE',
      '/${Uri.encodeComponent(id)}',
      null,
      'Vaccination record removed.',
    );
  }

  // ==========================================================
  // SHARED RECORD MUTATION
  // ==========================================================

  Future<void> _mutateRecord(
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

      if (!_valid(revision, id)) return;

      _snack(success);

      await Future.wait<void>([
        _loadHistory(revision, id),
        _loadSchedule(
          revision,
          id,
          _programme,
        ),
        _loadReminders(revision, id),
      ]);
    } catch (error) {
      if (_valid(revision, id)) {
        _snack(
          '${_message(error)} '
              'Check history before retrying.',
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
            onPressed:
            _working ? null : _reloadAll,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reloadAll,
        child: SingleChildScrollView(
          physics:
          const AlwaysScrollableScrollPhysics(),
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

                  const SizedBox(height: 16),

                  _programmes(),

                  const SizedBox(height: 16),

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

                  _notice(
                    'Vaccination doses and age windows '
                        'must come from medically reviewed, '
                        'published backend schedules. '
                        'A parent-reported completion is not '
                        'clinical verification. For missed '
                        'doses or special conditions, consult '
                        'the child’s doctor.',
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
        borderRadius:
        BorderRadius.circular(17),
        border: Border.all(
          color: _VColor.border,
        ),
      ),
      child: child,
    );
  }

  // ==========================================================
  // INFORMATION / ERROR NOTICE
  // ==========================================================

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
        borderRadius:
        BorderRadius.circular(12),
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
        borderRadius:
        BorderRadius.circular(18),
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
                  overflow:
                  TextOverflow.ellipsis,
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
                      _switchProgramme(
                        programme,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor:
                      _programme == programme
                          ? _VColor.pale
                          : Colors.white,
                      foregroundColor:
                      _VColor.navy,
                      side: BorderSide(
                        color:
                        _programme == programme
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
  // SCHEDULE OVERVIEW
  // ==========================================================

  Widget _scheduleOverview() {
    return _card(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'Published dose schedule',
            style: TextStyle(
              color: _VColor.navy,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 10),

          if (_loadingSchedule)
            const LinearProgressIndicator(),

          if (_scheduleError != null)
            _notice(
              _scheduleError!,
              danger: true,
            ),

          if (!_loadingSchedule &&
              _scheduleError == null &&
              !_published)
            _notice(
              _str(
                _publication['message'],
                'No medically reviewed vaccination '
                    'schedule is currently published '
                    'for $_programme.',
              ),
            ),

          if (_published) ...[
            _notice(
              _scheduleMessage.isNotEmpty
                  ? _scheduleMessage
                  : 'Showing published doses and '
                  'DOB-based windows returned '
                  'by the backend.',
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _countChip(
                  'Completed',
                  _counts['COMPLETED'],
                ),
                _countChip(
                  'Due',
                  _counts['DUE'],
                ),
                _countChip(
                  'Upcoming',
                  _counts['UPCOMING'],
                ),
                _countChip(
                  'Overdue',
                  _counts['OVERDUE'],
                ),
                _countChip(
                  'Review',
                  _counts['REVIEW_REQUIRED'],
                ),
              ],
            ),

            const SizedBox(height: 12),

            const Text(
              'Filter published doses',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _VColor.navy,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 4),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in const [
                    ['all', 'All'],
                    ['current', 'Current'],
                    ['upcoming', 'Upcoming'],
                    ['overdue', 'Overdue'],
                    ['completed', 'Completed'],
                    ['review_required', 'Review'],
                    ['not_applicable', 'N/A'],
                  ])
                    Padding(
                      padding:
                      const EdgeInsets.only(
                        right: 5,
                      ),
                      child: ChoiceChip(
                        label: Text(
                          entry[1],
                          style: const TextStyle(
                            fontSize: 11,
                          ),
                        ),
                        selected:
                        _filter == entry[0],
                        onSelected: (_) {
                          setState(() {
                            _filter = entry[0];
                          });
                        },
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

  Widget _countChip(
      String name,
      dynamic count,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: _VColor.bg,
        borderRadius:
        BorderRadius.circular(9),
      ),
      child: Text(
        '$name: ${count is num ? count.toInt() : '—'}',
        style: const TextStyle(
          color: _VColor.navy,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ==========================================================
  // ALL 12 AGE CARDS
  // ==========================================================

  Widget _ageCards() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        const Text(
          'Age-wise vaccination cards',
          style: TextStyle(
            color: _VColor.navy,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),

        const SizedBox(height: 5),

        const Text(
          'Tap an age band to view published '
              'doses for that period.',
          style: TextStyle(
            color: _VColor.muted,
            fontSize: 12,
          ),
        ),

        const SizedBox(height: 12),

        for (int band = 0;
        band < 12;
        band++) ...[
          _ageCard(band),

          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ==========================================================
  // SINGLE AGE GROUP CARD
  // ==========================================================

  Widget _ageCard(int band) {
    final items = _published
        ? _doses
        .where(
          (dose) =>
      _bandFor(dose) == band &&
          _matchesFilter(dose),
    )
        .toList()
        : <Map<String, dynamic>>[];

    final isCurrent =
        _currentBand == band;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(15),
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
        isCurrent && _published,
        tilePadding:
        const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 2,
        ),
        childrenPadding:
        const EdgeInsets.fromLTRB(
          12,
          0,
          12,
          14,
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
          '$band–${band + 1} years',
          style: const TextStyle(
            color: _VColor.navy,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          isCurrent
              ? 'Current age group • '
              '${items.length} doses'
              : _published
              ? '${items.length} published doses'
              : 'Schedule not published',
          style: const TextStyle(
            color: _VColor.muted,
            fontSize: 11,
          ),
        ),
        children: [
          const Divider(
            color: _VColor.border,
          ),

          if (!_published)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _loadingSchedule
                    ? 'Loading published schedule...'
                    : _scheduleError != null
                    ? 'Schedule unavailable due '
                    'to a loading error.'
                    : 'No published $_programme '
                    'dose schedule is available '
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
                'No matching published doses for '
                    'this age band. This does not confirm '
                    'vaccination is complete.',
                style: TextStyle(
                  color: _VColor.muted,
                  fontSize: 12,
                ),
              ),
            )
          else
            for (final dose in items) ...[
              _doseCard(dose),

              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  // ==========================================================
  // PUBLISHED VACCINE CARD
  // ==========================================================

  Widget _doseCard(
      Map<String, dynamic> dose,
      ) {
    final vaccine = _map(
      dose['vaccine'],
    );

    final status = _str(
      dose['status'],
      'UNKNOWN',
    );

    final reasons = dose['reasons'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _VColor.bg,
        borderRadius:
        BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            _str(
              vaccine['name_en'],
              'Vaccine',
            ),
            style: const TextStyle(
              color: _VColor.navy,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            _str(
              dose['dose_name'],
              'Dose',
            ),
            style: const TextStyle(
              color: _VColor.text,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 8),

          _statusTag(status),

          const SizedBox(height: 9),

          _detail(
            'Recommended age',
            _str(
              dose['age_label'],
            ),
          ),

          _detail(
            'Routine window',
            '${_formatDate(dose['recommended_date'])} '
                'to ${_formatDate(dose['window_end'])}',
          ),

          if (status == 'COMPLETED')
            _detail(
              'Parent-reported date',
              _formatDate(
                dose['completed_date'],
              ),
            ),

          _detail(
            'Route',
            _str(
              dose['route'],
            ),
          ),

          _detail(
            'Site',
            _str(
              dose['injection_site'],
            ),
          ),

          _detail(
            'Instructions',
            _str(
              dose['instructions'],
            ),
          ),

          if (reasons is List &&
              reasons.isNotEmpty) ...[
            const SizedBox(height: 7),

            for (final reason in reasons)
              if (reason is String)
                Padding(
                  padding:
                  const EdgeInsets.only(
                    bottom: 4,
                  ),
                  child: Text(
                    '• $reason',
                    style: const TextStyle(
                      color: _VColor.muted,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
          ],

          if (status != 'COMPLETED' &&
              status != 'NOT_APPLICABLE')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _working
                    ? null
                    : () {
                  _createRecord(dose);
                },
                icon: const Icon(
                  Icons.add_circle_outline,
                  size: 18,
                ),
                label: const Text(
                  'Record dose',
                  style: TextStyle(
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================================
  // STATUS LABEL
  // ==========================================================

  Widget _statusTag(
      String status,
      ) {
    final color = switch (status) {
      'COMPLETED' => _VColor.green,
      'OVERDUE' => _VColor.red,
      'REVIEW_REQUIRED' => _VColor.orange,
      'DUE' => _VColor.blue,
      _ => _VColor.muted,
    };

    final text = switch (status) {
      'COMPLETED' =>
      'Completed • parent-reported',
      'OVERDUE' =>
      'Routine window passed',
      'DUE' => 'Due now',
      'UPCOMING' => 'Upcoming',
      'REVIEW_REQUIRED' =>
      'Doctor review required',
      'NOT_APPLICABLE' =>
      'Not applicable',
      _ => 'Status unavailable',
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        borderRadius:
        BorderRadius.circular(7),
        color: color.withValues(
          alpha: 0.10,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
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
      padding: const EdgeInsets.only(
        bottom: 5,
      ),
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
  // VACCINATION HISTORY SECTION
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
            'Parent-entered records; '
                'not doctor-verified certificates.',
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
                margin: const EdgeInsets.only(
                  bottom: 8,
                ),
                padding: const EdgeInsets.all(
                  10,
                ),
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
                      onPressed: _working
                          ? null
                          : () {
                        _editRecord(
                          record,
                        );
                      },
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: _VColor.blue,
                      ),
                    ),

                    IconButton(
                      tooltip:
                      'Remove vaccination record',
                      onPressed: _working
                          ? null
                          : () {
                        _deleteRecord(
                          record,
                        );
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
                label: const Text(
                  'Set details',
                ),
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
            for (final reminder
            in _reminders.take(5))
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
// VACCINATION RECORD DIALOG
//
// Used for creating or editing parent-reported history.
// ============================================================

class _RecordDialog extends StatefulWidget {
  final DateTime? birthDate;
  final String initialTitle;
  final Map<String, dynamic>? original;
  final bool lockTitle;

  const _RecordDialog({
    required this.birthDate,
    required this.initialTitle,
    this.original,
    this.lockTitle = false,
  });

  @override
  State<_RecordDialog> createState() =>
      _RecordDialogState();
}

class _RecordDialogState
    extends State<_RecordDialog> {
  final _formKey =
  GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _provider;
  late final TextEditingController _vaccinator;
  late final TextEditingController _batch;
  late final TextEditingController _notes;

  String _status = 'Completed';

  DateTime? _date;

  // ==========================================================
  // INITIALIZE RECORD FORM
  // ==========================================================

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

    final status = _value(
      old['status'],
    );

    if ([
      'Completed',
      'Planned',
      'Missed',
    ].contains(status)) {
      _status = status;
    }

    final rawDate = old['date'];

    if (rawDate is String) {
      _date = DateTime.tryParse(
        rawDate,
      );
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

  // ==========================================================
  // PICK RECORD DATE
  // ==========================================================

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(
      DateTime.now(),
    );

    final first = widget.birthDate == null
        ? DateTime(
      today.year - 13,
      1,
      1,
    )
        : DateUtils.dateOnly(
      widget.birthDate!,
    );

    final last = _status == 'Planned'
        ? DateTime(
      today.year + 5,
      12,
      31,
    )
        : today;

    if (first.isAfter(last)) return;

    final selected = await showDatePicker(
      context: context,
      initialDate: _date != null &&
          !_date!.isBefore(first) &&
          !_date!.isAfter(last)
          ? _date!
          : today,
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

  // ==========================================================
  // SUBMIT RECORD
  // ==========================================================

  void _submit() {
    if (!(_formKey.currentState?.validate() ??
        false)) {
      return;
    }

    final date = _date;

    if (date == null) {
      _showError(
        'Choose a record date.',
      );
      return;
    }

    final today = DateUtils.dateOnly(
      DateTime.now(),
    );

    if (widget.birthDate != null &&
        date.isBefore(
          DateUtils.dateOnly(
            widget.birthDate!,
          ),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  // ==========================================================
  // BUILD RECORD DIALOG
  // ==========================================================

  @override
  Widget build(BuildContext context) {
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
              mainAxisSize:
              MainAxisSize.min,
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
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Vaccine / dose',
                    border:
                    OutlineInputBorder(),
                  ),
                  validator: (value) {
                    return (value ?? '')
                        .trim()
                        .isEmpty
                        ? 'Vaccine name required'
                        : null;
                  },
                ),

                DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Record status',
                    border:
                    OutlineInputBorder(),
                  ),
                  items: [
                    'Completed',
                    'Planned',
                    'Missed',
                  ]
                      .map(
                        (value) =>
                        DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ),
                  )
                      .toList(),
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
                        ? 'Select date'
                        : _dateApi(_date!),
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
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Notes (optional)',
                    border:
                    OutlineInputBorder(),
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
          child: const Text(
            'Save record',
          ),
        ),
      ],
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
        border:
        const OutlineInputBorder(),
      ),
    );
  }
}

// ============================================================
// VACCINATION CONTEXT DIALOG
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
  final _formKey =
  GlobalKey<FormState>();

  late final TextEditingController _stateName;
  late final TextEditingController _district;

  String _gender = 'Unknown';
  String _history = 'UNKNOWN';

  bool _email = false;

  // ==========================================================
  // INITIALIZE CONTEXT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _stateName = TextEditingController(
      text:
      '${widget.initial['state'] ?? ''}',
    );

    _district = TextEditingController(
      text:
      '${widget.initial['district'] ?? ''}',
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

  // ==========================================================
  // SAVE CONTEXT
  // ==========================================================

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

  // ==========================================================
  // BUILD CONTEXT DIALOG
  // ==========================================================

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
                  decoration:
                  const InputDecoration(
                    labelText:
                    'State (optional)',
                    border:
                    OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 8),

                TextFormField(
                  controller: _district,
                  maxLength: 120,
                  decoration:
                  const InputDecoration(
                    labelText:
                    'District (optional)',
                    border:
                    OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if ((value ?? '')
                        .trim()
                        .isNotEmpty &&
                        _stateName.text
                            .trim()
                            .isEmpty) {
                      return 'Enter the state '
                          'before entering a district.';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Child gender (for schedule rules)',
                    border:
                    OutlineInputBorder(),
                  ),
                  items: [
                    'Unknown',
                    'Girls',
                    'Boys',
                  ]
                      .map(
                        (value) =>
                        DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ),
                  )
                      .toList(),
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
                  contentPadding:
                  EdgeInsets.zero,
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
                  value: _history ==
                      'PARENT_REPORTED',
                  onChanged: (value) {
                    setState(() {
                      _history =
                      value == true
                          ? 'PARENT_REPORTED'
                          : 'UNKNOWN';
                    });
                  },
                ),

                CheckboxListTile(
                  contentPadding:
                  EdgeInsets.zero,
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
          child: const Text(
            'Cancel',
          ),
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
