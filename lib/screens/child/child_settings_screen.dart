
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

// ============================================================
// FAMILYCARE+ - CHILD SETTINGS SCREEN
// ============================================================
//
// GET  /api/v1/patients/profiles/{profileId}
// POST /api/v1/patients/profiles/{profileId}/connect-doctor
// GET  /api/v1/patients/profiles/{profileId}/reports
// GET  /api/v1/children/{childId}/reminders
// PUT  /api/v1/children/{childId}/reminder-preferences
// GET  /api/v1/children/{childId}/vaccination-context
// PUT  /api/v1/children/{childId}/vaccination-context
//
// Backend-supported settings:
// - Child profile details
// - Guardian and emergency contacts
// - Doctor connection via referral ID
// - Health report count
// - In-app reminder preferences
// - Vaccination email reminders
// - Contact visibility (UI only)
//
// Not implemented in current backend:
// - Edit/delete child profile
// - Edit emergency contacts
// - Disconnect doctor
// - Change parent connection
// ============================================================

class ChildSettingsColors {
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

class ChildSettingsApiException implements Exception {
  final String message;
  final int statusCode;

  const ChildSettingsApiException(
      this.message, {
        this.statusCode = 0,
      });

  @override
  String toString() => message;
}

// ============================================================
// API CLIENT
// ============================================================

class _ChildSettingsApi {
  final String baseUrl;
  final String profileId;

  final http.Client _client = http.Client();

  _ChildSettingsApi({
    required this.baseUrl,
    required this.profileId,
  });

  String get profilePath =>
      '/api/v1/patients/profiles/'
          '${Uri.encodeComponent(profileId)}';

  String get childPath =>
      '/api/v1/children/'
          '${Uri.encodeComponent(profileId)}';

  void dispose() => _client.close();

  Future<Map<String, String>> _headers() async {
    final token = await FamilyCareSession.accessToken();

    if (token == null || token.trim().isEmpty) {
      throw const ChildSettingsApiException(
        'Your login session is unavailable. '
            'Please sign in again.',
        statusCode: 401,
      );
    }

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
    };
  }

  String _serverError(http.Response response) {
    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (decoded is Map) {
        final error = decoded['error'];

        if (error is Map &&
            error['message'] is String) {
          return error['message'] as String;
        }

        if (error is String && error.isNotEmpty) {
          return error;
        }
      }
    } catch (_) {
      // Server errors may not contain JSON.
    }

    switch (response.statusCode) {
      case 401:
        return 'Session expired. Please sign in again.';
      case 403:
        return 'Access to this child profile is denied.';
      case 404:
        return 'Child profile or endpoint was not found.';
      case 409:
        return 'The change conflicts with existing data.';
      case 422:
        return 'The server rejected these settings. '
            'Please refresh.';
      default:
        return 'Request failed '
            '(HTTP ${response.statusCode}).';
    }
  }

  Future<Map<String, dynamic>> request(
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

      case 'PUT':
        response = await _client
            .put(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        )
            .timeout(const Duration(seconds: 35));
        break;

      default:
        throw const ChildSettingsApiException(
          'Unsupported API method.',
        );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw ChildSettingsApiException(
        _serverError(response),
        statusCode: response.statusCode,
      );
    }

    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (decoded is! Map) {
        throw const FormatException();
      }

      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const ChildSettingsApiException(
        'The server returned an invalid JSON response.',
      );
    }
  }

  Future<Map<String, dynamic>> profile() {
    return request('GET', profilePath);
  }

  Future<Map<String, dynamic>> connectDoctor(
      String referralId,
      ) {
    return request(
      'POST',
      '$profilePath/connect-doctor',
      body: {
        'referral_id': referralId,
      },
    );
  }

  Future<Map<String, dynamic>> reportSummary() {
    return request(
      'GET',
      '$profilePath/reports?page=1&per_page=1',
    );
  }

  Future<Map<String, dynamic>> reminders() {
    return request(
      'GET',
      '$childPath/reminders',
    );
  }

  Future<Map<String, dynamic>> setInAppReminders(
      bool enabled,
      ) {
    return request(
      'PUT',
      '$childPath/reminder-preferences',
      body: {
        'in_app': enabled,
      },
    );
  }

  Future<Map<String, dynamic>> vaccinationContext() {
    return request(
      'GET',
      '$childPath/vaccination-context',
    );
  }

  Future<Map<String, dynamic>> saveVaccinationContext(
      Map<String, dynamic> context,
      ) {
    return request(
      'PUT',
      '$childPath/vaccination-context',
      body: context,
    );
  }
}

// ============================================================
// MAIN SCREEN
// ============================================================

class ChildSettingsScreen extends StatefulWidget {
  final String profileId;
  final String apiBaseUrl;

  final void Function(
      BuildContext context,
      String section,
      String profileId,
      )? onOpenSection;

  const ChildSettingsScreen({
    super.key,
    required this.profileId,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.onOpenSection,
  });

  @override
  State<ChildSettingsScreen> createState() =>
      _ChildSettingsScreenState();
}

// ============================================================
// SCREEN STATE
// ============================================================

class _ChildSettingsScreenState
    extends State<ChildSettingsScreen> {
  late _ChildSettingsApi _api;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _vaccinationContext;

  int? _reportCount;
  int? _reminderCount;

  bool? _inAppReminders;
  bool? _emailReminders;

  bool _profileLoading = true;
  bool _reportsLoading = true;
  bool _remindersLoading = true;
  bool _vaccinationLoading = true;

  bool _connectingDoctor = false;
  bool _savingInApp = false;
  bool _savingEmail = false;

  bool _showContactDetails = false;

  String? _profileError;
  String? _reportsError;
  String? _remindersError;
  String? _vaccinationError;

  int _revision = 0;

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

  bool get _anySaveBusy =>
      _connectingDoctor || _savingInApp || _savingEmail;

  bool _stillCurrent(
      int revision,
      String profileId,
      ) {
    return mounted &&
        revision == _revision &&
        widget.profileId == profileId;
  }

  @override
  void initState() {
    super.initState();

    _api = _ChildSettingsApi(
      baseUrl: _baseUrl,
      profileId: widget.profileId,
    );

    _refreshAll();
  }

  @override
  void didUpdateWidget(
      covariant ChildSettingsScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.profileId != widget.profileId ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _revision++;

      _api.dispose();

      _api = _ChildSettingsApi(
        baseUrl: _baseUrl,
        profileId: widget.profileId,
      );

      _profile = null;
      _reportCount = null;
      _reminderCount = null;
      _vaccinationContext = null;
      _inAppReminders = null;
      _emailReminders = null;

      _showContactDetails = false;
      _connectingDoctor = false;
      _savingInApp = false;
      _savingEmail = false;

      _refreshAll();
    }
  }

  @override
  void dispose() {
    _revision++;
    _api.dispose();
    super.dispose();
  }

  // ==========================================================
  // DATA HELPERS
  // ==========================================================

  String _value(
      dynamic data, {
        String fallback = 'Not added',
      }) {
    final text = (data ?? '').toString().trim();

    return text.isEmpty ? fallback : text;
  }

  String get _childName {
    return _value(
      _profile?['full_name'],
      fallback: 'Child Profile',
    );
  }

  DateTime? get _dob {
    return DateTime.tryParse(
      (_profile?['date_of_birth'] ?? '').toString(),
    );
  }

  Map<String, dynamic>? get _doctor {
    final data = _profile?['doctor'];

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    return null;
  }

  List<Map<String, dynamic>> get _emergencyContacts {
    final raw = _profile?['emergency_contacts'];

    if (raw is! List) {
      return [];
    }

    return raw
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
    )
        .toList();
  }

  bool get _hasParentProfile {
    return _value(
      _profile?['parent_profile_id'],
      fallback: '',
    ).isNotEmpty;
  }

  String _date(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }

    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}';
  }

  String _createdDate(dynamic raw) {
    final date = DateTime.tryParse(
      (raw ?? '').toString(),
    );

    return _date(date?.toLocal());
  }

  String _age(DateTime? dob) {
    if (dob == null) {
      return 'Not available';
    }

    final today = DateUtils.dateOnly(DateTime.now());
    final birth = DateUtils.dateOnly(dob);

    if (birth.isAfter(today)) {
      return 'Invalid birth date';
    }

    int years = today.year - birth.year;
    int months = today.month - birth.month;

    if (today.day < birth.day) {
      months--;
    }

    if (months < 0) {
      years--;
      months += 12;
    }

    if (years == 0 && months == 0) {
      return '${today.difference(birth).inDays} days';
    }

    if (years == 0) {
      return '$months months';
    }

    if (months == 0) {
      return '$years years';
    }

    return '$years years $months months';
  }

  String _privateValue(dynamic raw) {
    final value = _value(raw);

    if (value == 'Not added') {
      return value;
    }

    return _showContactDetails
        ? value
        : 'Hidden for privacy';
  }

  // ==========================================================
  // ERROR HANDLING
  // ==========================================================

  String _friendlyError(Object error) {
    if (error is ChildSettingsApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'The server took too long to respond.';
    }

    if (error is http.ClientException) {
      return 'Unable to connect to the server.';
    }

    if (error is PlatformException) {
      return 'Could not access your login session.';
    }

    return 'Something went wrong. Please try again.';
  }

  void _message(
      String value, {
        bool error = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error
              ? ChildSettingsColors.red
              : ChildSettingsColors.navy,
          content: Text(value),
        ),
      );
  }

  // ==========================================================
  // LOAD DATA FROM FOUR API SOURCES
  // ==========================================================

  Future<void> _refreshAll() async {
    if (!mounted || _anySaveBusy) return;

    final revision = ++_revision;
    final profileId = widget.profileId;
    final api = _api;

    setState(() {
      _profileLoading = true;
      _reportsLoading = true;
      _remindersLoading = true;
      _vaccinationLoading = true;

      _profileError = null;
      _reportsError = null;
      _remindersError = null;
      _vaccinationError = null;
    });

    await Future.wait<void>([
      _loadProfile(api, revision, profileId),
      _loadReports(api, revision, profileId),
      _loadReminders(api, revision, profileId),
      _loadVaccination(api, revision, profileId),
    ]);
  }

  // ==========================================================
  // LOAD CHILD PROFILE
  // ==========================================================

  Future<void> _loadProfile(
      _ChildSettingsApi api,
      int revision,
      String profileId,
      ) async {
    try {
      final result = await api.profile();

      final raw = result['profile'];

      if (raw is! Map) {
        throw const ChildSettingsApiException(
          'Invalid child profile response.',
        );
      }

      final profile = Map<String, dynamic>.from(raw);

      if (profile['id']?.toString() != profileId ||
          profile['module'] != 'child') {
        throw const ChildSettingsApiException(
          'The selected profile is not a '
              'valid Child Care profile.',
        );
      }

      if (!_stillCurrent(revision, profileId)) return;

      setState(() {
        _profile = profile;
        _profileError = null;
        _profileLoading = false;
      });
    } catch (error) {
      if (!_stillCurrent(revision, profileId)) return;

      setState(() {
        _profile = null;
        _profileError = _friendlyError(error);
        _profileLoading = false;
      });
    }
  }

  // ==========================================================
  // LOAD HEALTH REPORT COUNT
  // ==========================================================

  Future<void> _loadReports(
      _ChildSettingsApi api,
      int revision,
      String profileId,
      ) async {
    try {
      final result = await api.reportSummary();
      final total = result['total'];

      if (total is! num) {
        throw const ChildSettingsApiException(
          'Report count not returned.',
        );
      }

      if (!_stillCurrent(revision, profileId)) return;

      setState(() {
        _reportCount = total.toInt();
        _reportsError = null;
        _reportsLoading = false;
      });
    } catch (error) {
      if (!_stillCurrent(revision, profileId)) return;

      setState(() {
        _reportCount = null;
        _reportsError = _friendlyError(error);
        _reportsLoading = false;
      });
    }
  }

  // ==========================================================
  // LOAD IN-APP REMINDERS
  // ==========================================================

  Future<void> _loadReminders(
      _ChildSettingsApi api,
      int revision,
      String profileId,
      ) async {
    try {
      final result = await api.reminders();

      final rawPreferences = result['preferences'];

      if (rawPreferences is! Map ||
          rawPreferences['in_app'] is! bool) {
        throw const ChildSettingsApiException(
          'Reminder preferences not returned '
              'by the server.',
        );
      }

      final total = result['total'];

      if (!_stillCurrent(revision, profileId)) return;

      setState(() {
        _inAppReminders =
        rawPreferences['in_app'] as bool;

        _reminderCount =
        total is num ? total.toInt() : null;

        _remindersError = null;
        _remindersLoading = false;
      });
    } catch (error) {
      if (!_stillCurrent(revision, profileId)) return;

      setState(() {
        _inAppReminders = null;
        _reminderCount = null;
        _remindersError = _friendlyError(error);
        _remindersLoading = false;
      });
    }
  }

  // ==========================================================
  // LOAD VACCINATION EMAIL PREFERENCES
  // ==========================================================

  Future<void> _loadVaccination(
      _ChildSettingsApi api,
      int revision,
      String profileId,
      ) async {
    try {
      final response =
      await api.vaccinationContext();

      final raw = response['context'];

      if (raw is! Map) {
        throw const ChildSettingsApiException(
          'Vaccination context not returned '
              'by the server.',
        );
      }

      final context =
      Map<String, dynamic>.from(raw);

      final email = context['email_reminders'];

      if (email != null && email is! bool) {
        throw const ChildSettingsApiException(
          'Invalid vaccination email preference.',
        );
      }

      if (!_stillCurrent(revision, profileId)) return;

      setState(() {
        _vaccinationContext = context;
        _emailReminders = email == true;
        _vaccinationError = null;
        _vaccinationLoading = false;
      });
    } catch (error) {
      if (!_stillCurrent(revision, profileId)) return;

      setState(() {
        _vaccinationContext = null;
        _emailReminders = null;
        _vaccinationError = _friendlyError(error);
        _vaccinationLoading = false;
      });
    }
  }

  // ==========================================================
  // SAVE IN-APP REMINDER PREFERENCE
  // ==========================================================

  Future<void> _changeInApp(bool newValue) async {
    if (_savingInApp ||
        _remindersLoading ||
        _inAppReminders == null) {
      return;
    }

    final revision = _revision;
    final profileId = widget.profileId;
    final api = _api;

    setState(() {
      _savingInApp = true;
    });

    try {
      final response =
      await api.setInAppReminders(newValue);

      if (response['in_app'] is! bool ||
          response['in_app'] != newValue) {
        throw const ChildSettingsApiException(
          'Reminder change could not be verified. '
              'Refresh to check.',
        );
      }

      final refreshed = await api.reminders();
      final preferences = refreshed['preferences'];

      if (preferences is! Map ||
          preferences['in_app'] != newValue) {
        throw const ChildSettingsApiException(
          'Preference was saved, but reload failed. '
              'Please refresh.',
        );
      }

      if (!_stillCurrent(revision, profileId)) return;

      setState(() {
        _inAppReminders = newValue;

        final count = refreshed['total'];

        _reminderCount =
        count is num ? count.toInt() : null;

        _remindersError = null;
      });

      _message(
        newValue
            ? 'In-app reminders enabled.'
            : 'In-app reminders disabled.',
      );
    } catch (error) {
      if (_stillCurrent(revision, profileId)) {
        _message(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (_stillCurrent(revision, profileId)) {
        setState(() {
          _savingInApp = false;
        });
      }
    }
  }

  // ==========================================================
  // PRESERVE VACCINATION CONTEXT
  // ==========================================================

  Map<String, dynamic> _preservedContextPayload(
      Map<String, dynamic> existing,
      bool emailReminders,
      ) {
    String textField(
        String name,
        String fallback,
        ) {
      final raw = existing[name];

      if (raw == null) return fallback;

      if (raw is! String) {
        throw ChildSettingsApiException(
          'Invalid $name in vaccination context.',
        );
      }

      return raw;
    }

    final country = textField('country', 'IN');
    final state = textField('state', '');
    final district = textField('district', '');
    final gender = textField('gender', 'Unknown');

    final history = textField(
      'history_status',
      'UNKNOWN',
    );

    if (country != 'IN' ||
        !['Unknown', 'Girls', 'Boys']
            .contains(gender) ||
        !['UNKNOWN', 'PARENT_REPORTED']
            .contains(history) ||
        state.length > 120 ||
        district.length > 120) {
      throw const ChildSettingsApiException(
        'Vaccination context contains values '
            'this app cannot safely update. '
            'Please review the vaccination screen.',
      );
    }

    return {
      'country': country,
      'state': state,
      'district': district,
      'gender': gender,
      'history_status': history,
      'email_reminders': emailReminders,
    };
  }

  // ==========================================================
  // EXPLICIT EMAIL OPT-IN
  // ==========================================================

  Future<bool> _confirmEmailOptIn() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Enable vaccination emails?',
          ),
          content: const Text(
            'You are opting in to vaccination '
                'schedule reminder emails sent to '
                'the verified account email, when '
                'the published schedule and backend '
                'delivery worker support them.\n\n'
                'No SMS or appointment notification '
                'is enabled by this switch.\n\n'
                'Do you want to continue?',
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
              child: const Text('Enable'),
            ),
          ],
        );
      },
    );

    return approved == true;
  }

  // ==========================================================
  // SAVE VACCINATION EMAIL PREFERENCE
  // ==========================================================

  Future<void> _changeVaccinationEmail(
      bool newValue,
      ) async {
    if (_savingEmail ||
        _vaccinationLoading ||
        _emailReminders == null) {
      return;
    }

    final revision = _revision;
    final profileId = widget.profileId;
    final api = _api;

    if (newValue) {
      final approved = await _confirmEmailOptIn();

      if (!approved ||
          !_stillCurrent(revision, profileId)) {
        return;
      }
    }

    if (!_stillCurrent(revision, profileId)) return;

    setState(() {
      _savingEmail = true;
    });

    try {
      // Fetch the latest saved context before PUT.
      // This endpoint replaces the entire context.

      final latest =
      await api.vaccinationContext();

      final rawContext = latest['context'];

      if (rawContext is! Map) {
        throw const ChildSettingsApiException(
          'Unable to read current vaccination '
              'settings. Nothing was changed.',
        );
      }

      final current =
      Map<String, dynamic>.from(rawContext);

      final payload = _preservedContextPayload(
        current,
        newValue,
      );

      final result =
      await api.saveVaccinationContext(payload);

      final rawSaved = result['context'];

      if (rawSaved is! Map ||
          rawSaved['email_reminders'] != newValue) {
        throw const ChildSettingsApiException(
          'Vaccination email preference could '
              'not be verified. Please refresh.',
        );
      }

      if (!_stillCurrent(revision, profileId)) return;

      setState(() {
        _vaccinationContext =
        Map<String, dynamic>.from(rawSaved);

        _emailReminders = newValue;
        _vaccinationError = null;
      });

      _message(
        newValue
            ? 'Vaccination email opt-in saved.'
            : 'Vaccination email reminders disabled.',
      );
    } catch (error) {
      if (_stillCurrent(revision, profileId)) {
        _message(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (_stillCurrent(revision, profileId)) {
        setState(() {
          _savingEmail = false;
        });
      }
    }
  }

  // ==========================================================
  // CONNECT DOCTOR
  // ==========================================================

  Future<void> _connectDoctor() async {
    if (_connectingDoctor ||
        _profileLoading ||
        _profile == null ||
        _doctor != null) {
      return;
    }

    final revision = _revision;
    final profileId = widget.profileId;
    final api = _api;

    final referralId = await showDialog<String>(
      context: context,
      builder: (_) => const _DoctorReferralDialog(),
    );

    if (referralId == null ||
        referralId.isEmpty ||
        !_stillCurrent(revision, profileId)) {
      return;
    }

    setState(() {
      _connectingDoctor = true;
    });

    try {
      final result =
      await api.connectDoctor(referralId);

      final raw = result['profile'];

      if (raw is! Map ||
          raw['id']?.toString() != profileId ||
          raw['module'] != 'child') {
        throw const ChildSettingsApiException(
          'Connection response was incomplete. '
              'Refresh before retrying.',
        );
      }

      if (!_stillCurrent(revision, profileId)) return;

      setState(() {
        _profile = Map<String, dynamic>.from(raw);
      });

      _message('Doctor connected successfully.');
    } catch (error) {
      if (_stillCurrent(revision, profileId)) {
        _message(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (_stillCurrent(revision, profileId)) {
        setState(() {
          _connectingDoctor = false;
        });
      }
    }
  }

  // ==========================================================
  // COPY CONTACT
  // ==========================================================

  Future<void> _copyContact(
      String value,
      String label,
      ) async {
    if (!_showContactDetails ||
        value.trim().isEmpty) {
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: value),
    );

    if (mounted) {
      _message('$label copied.');
    }
  }

  // ==========================================================
  // SECTION NAVIGATION
  // ==========================================================

  void _openSection(String section) {
    final callback = widget.onOpenSection;

    if (callback == null) {
      _message(
        'Section navigation will be connected '
            'from the child dashboard.',
      );
      return;
    }

    callback(
      context,
      section,
      widget.profileId,
    );
  }

  // ==========================================================
  // MAIN SCREEN BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChildSettingsColors.background,

      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ChildSettingsColors.navy,
        elevation: 0,

        title: const Text(
          'Child Settings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),

        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.arrow_back_rounded,
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Refresh Settings',
            onPressed:
            _anySaveBusy ? null : _refreshAll,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),

      body: SafeArea(
        child: _profileLoading && _profile == null
            ? const Center(
          child: CircularProgressIndicator(
            color: ChildSettingsColors.green,
          ),
        )
            : _profile == null
            ? _errorState()
            : RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            physics:
            const AlwaysScrollableScrollPhysics(),

            padding: const EdgeInsets.fromLTRB(
              16, 20, 16, 36,
            ),

            children: [
              Center(
                child: ConstrainedBox(
                  constraints:
                  const BoxConstraints(
                    maxWidth: 1120,
                  ),

                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,

                    children: [
                      _breadcrumb(),
                      const SizedBox(height: 18),
                      _hero(),
                      const SizedBox(height: 20),

                      _privacyVisibility(),
                      const SizedBox(height: 20),

                      _profileAndGuardian(),
                      const SizedBox(height: 20),

                      _emergencySection(),
                      const SizedBox(height: 20),

                      _doctorSection(),
                      const SizedBox(height: 20),

                      _healthDataSection(),
                      const SizedBox(height: 20),

                      _remindersSection(),
                      const SizedBox(height: 20),

                      _futureSettingsSection(),
                      const SizedBox(height: 20),

                      _privacySection(),
                      const SizedBox(height: 24),

                      const Center(
                        child: Text(
                          'FamilyCare+ • Healthier Families. '
                              'Brighter Tomorrows.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                            ChildSettingsColors.muted,
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

  // ==========================================================
  // ERROR STATE
  // ==========================================================

  Widget _errorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: ChildSettingsColors.orange,
              size: 48,
            ),

            const SizedBox(height: 13),

            const Text(
              'Unable to Load Child Settings',
              style: TextStyle(
                color: ChildSettingsColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 9),

            Text(
              _profileError ?? 'Please try again.',
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _refreshAll,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // BREADCRUMB
  // ==========================================================

  Widget _breadcrumb() {
    return const Row(
      children: [
        Text(
          'Child Care',
          style: TextStyle(
            fontSize: 12,
            color: ChildSettingsColors.muted,
          ),
        ),

        SizedBox(width: 7),

        Icon(
          Icons.chevron_right_rounded,
          size: 17,
          color: ChildSettingsColors.muted,
        ),

        SizedBox(width: 7),

        Text(
          'Settings',
          style: TextStyle(
            fontSize: 12,
            color: ChildSettingsColors.green,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // HERO
  // ==========================================================

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(22),
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
                  'YOUR FAMILY. YOUR CARE.',
                  style: TextStyle(
                    color: ChildSettingsColors.green,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Child Settings',
                  style: TextStyle(
                    color: ChildSettingsColors.navy,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'serif',
                  ),
                ),

                const SizedBox(height: 9),

                Text(
                  'Manage available settings for $_childName.',
                  style: const TextStyle(
                    color: ChildSettingsColors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          const CircleAvatar(
            radius: 34,
            backgroundColor: Color(0xFFDDEDE3),
            child: Icon(
              Icons.settings_outlined,
              color: ChildSettingsColors.green,
              size: 35,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONTACT VISIBILITY
  // ==========================================================

  Widget _privacyVisibility() {
    return Container(
      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: ChildSettingsColors.lightBlue,
        borderRadius: BorderRadius.circular(14),
      ),

      child: Row(
        children: [
          Icon(
            _showContactDetails
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: ChildSettingsColors.blue,
            size: 25,
          ),

          const SizedBox(width: 12),

          const Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  'Contact Information Privacy',
                  style: TextStyle(
                    color: ChildSettingsColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                SizedBox(height: 5),

                Text(
                  'Hide or reveal contact details '
                      'on this screen only.',
                  style: TextStyle(
                    color: ChildSettingsColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          Switch(
            value: _showContactDetails,
            activeThumbColor:
            ChildSettingsColors.green,
            onChanged: (value) {
              setState(() {
                _showContactDetails = value;
              });
            },
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // RESPONSIVE PROFILE AND GUARDIAN LAYOUT
  // ==========================================================

  Widget _profileAndGuardian() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 780) {
          return Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _profileSection(),
              ),

              const SizedBox(width: 17),

              Expanded(
                child: _guardianSection(),
              ),
            ],
          );
        }

        return Column(
          children: [
            _profileSection(),
            const SizedBox(height: 17),
            _guardianSection(),
          ],
        );
      },
    );
  }

  // ==========================================================
  // CHILD INFORMATION
  // ==========================================================

  Widget _profileSection() {
    return _sectionCard(
      title: 'Child Information',
      subtitle: 'Registered profile details',
      icon: Icons.child_care_rounded,

      child: Column(
        children: [
          _detailRow(
            'Full Name',
            _childName,
            icon: Icons.person_outline_rounded,
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _detailRow(
            'Date of Birth',
            _date(_dob),
            icon: Icons.cake_outlined,
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _detailRow(
            'Age',
            _age(_dob),
            icon: Icons.calendar_today_outlined,
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _detailRow(
            'Profile Type',
            _value(
              _profile?['profile_type'],
              fallback: 'Member',
            ),
            icon: Icons.badge_outlined,
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _detailRow(
            'Created',
            _createdDate(
              _profile?['created_at'],
            ),
            icon: Icons.event_available_outlined,
          ),

          const SizedBox(height: 12),

          _infoBox(
            'Child profile details are read-only '
                'until a profile update API is available.',
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // GUARDIAN INFORMATION
  // ==========================================================

  Widget _guardianSection() {
    final guardian = _value(
      _profile?['guardian_contact'],
      fallback: '',
    );

    return _sectionCard(
      title: 'Guardian Information',
      subtitle: 'Family and parent connections',
      icon: Icons.family_restroom_outlined,

      child: Column(
        children: [
          _detailRow(
            'Guardian Phone',
            _privateValue(
              _profile?['guardian_contact'],
            ),
            icon: Icons.phone_android_outlined,
            onCopy: _showContactDetails &&
                guardian.isNotEmpty
                ? () => _copyContact(
              guardian,
              'Guardian phone',
            )
                : null,
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _detailRow(
            'Parent Profile',
            _hasParentProfile
                ? 'Connected'
                : 'Not connected',
            icon: Icons.people_outline_rounded,
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _detailRow(
            'Emergency Contacts',
            '${_emergencyContacts.length} saved',
            icon: Icons.contact_emergency_outlined,
          ),

          const SizedBox(height: 12),

          _infoBox(
            'Guardian details come from the saved '
                'child profile. Editing them requires '
                'a backend update API.',
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // EMERGENCY CONTACTS
  // ==========================================================

  Widget _emergencySection() {
    final contacts = _emergencyContacts;

    return _sectionCard(
      title: 'Emergency Contacts',
      subtitle: 'Important family contact information',
      icon: Icons.contact_emergency_outlined,

      child: contacts.isEmpty
          ? _emptyInfo(
        Icons.contact_phone_outlined,
        'No emergency contacts',
        'No emergency contacts are saved '
            'for this profile.',
      )
          : Column(
        children: [
          for (int i = 0;
          i < contacts.length;
          i++) ...[
            _emergencyCard(
              contacts[i],
              i,
            ),

            if (i != contacts.length - 1)
              const SizedBox(height: 11),
          ],

          const SizedBox(height: 12),

          _infoBox(
            'Adding and editing emergency '
                'contacts requires a future backend API.',
          ),
        ],
      ),
    );
  }

  Widget _emergencyCard(
      Map<String, dynamic> contact,
      int index,
      ) {
    final phone = _value(
      contact['mobile_number'],
      fallback: '',
    );

    return Container(
      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(
        color: ChildSettingsColors.cream,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: ChildSettingsColors.border,
        ),
      ),

      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_pin_circle_outlined,
                color: ChildSettingsColors.green,
                size: 23,
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  _value(
                    contact['name'],
                    fallback:
                    'Emergency Contact ${index + 1}',
                  ),
                  style: const TextStyle(
                    color: ChildSettingsColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _detailRow(
            'Relationship',
            _value(
              contact['relationship'],
            ),
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _detailRow(
            'Mobile',
            _privateValue(
              contact['mobile_number'],
            ),
            onCopy: _showContactDetails &&
                phone.isNotEmpty
                ? () => _copyContact(
              phone,
              'Emergency contact',
            )
                : null,
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONNECTED DOCTOR
  // ==========================================================

  Widget _doctorSection() {
    final doctor = _doctor;

    return _sectionCard(
      title: 'Connected Doctor',
      subtitle: 'Doctor access and referral connection',
      icon: Icons.medical_services_outlined,

      child: doctor == null
          ? Column(
        children: [
          _emptyInfo(
            Icons.medical_services_outlined,
            'No doctor connected',
            'Connect an approved FamilyCare+ '
                'doctor using a referral ID.',
          ),

          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,

            child: FilledButton.icon(
              onPressed: _connectingDoctor
                  ? null
                  : _connectDoctor,

              icon: _connectingDoctor
                  ? const SizedBox(
                height: 17,
                width: 17,

                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : const Icon(
                Icons.person_add_alt_1_rounded,
              ),

              label: Text(
                _connectingDoctor
                    ? 'Connecting...'
                    : 'Connect Doctor',
              ),

              style: FilledButton.styleFrom(
                backgroundColor:
                ChildSettingsColors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      )
          : _doctorDetails(doctor),
    );
  }

  // ==========================================================
  // DOCTOR DETAILS
  // ==========================================================

  Widget _doctorDetails(
      Map<String, dynamic> doctor,
      ) {
    final email = _value(
      doctor['email'],
      fallback: '',
    );

    final phone = _value(
      doctor['mobile_number'],
      fallback: '',
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(15),

          decoration: BoxDecoration(
            color: ChildSettingsColors.lightGreen,
            borderRadius: BorderRadius.circular(13),
          ),

          child: Row(
            children: [
              const CircleAvatar(
                radius: 25,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.medical_services_rounded,
                  color: ChildSettingsColors.green,
                  size: 26,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Text(
                      _value(
                        doctor['full_name'],
                        fallback: 'Connected Doctor',
                      ),
                      style: const TextStyle(
                        color: ChildSettingsColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),

                    const SizedBox(height: 5),

                    const Text(
                      'Connected to this child profile',
                      style: TextStyle(
                        color: ChildSettingsColors.green,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.verified_rounded,
                color: ChildSettingsColors.green,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        _detailRow(
          'Referral ID',
          _value(doctor['referral_id']),
          icon: Icons.badge_outlined,
        ),

        const Divider(
          color: ChildSettingsColors.border,
        ),

        _detailRow(
          'Email',
          _privateValue(email),
          icon: Icons.email_outlined,
          onCopy: _showContactDetails &&
              email.isNotEmpty
              ? () => _copyContact(
            email,
            'Doctor email',
          )
              : null,
        ),

        const Divider(
          color: ChildSettingsColors.border,
        ),

        _detailRow(
          'Mobile',
          _privateValue(phone),
          icon: Icons.phone_outlined,
          onCopy: _showContactDetails &&
              phone.isNotEmpty
              ? () => _copyContact(
            phone,
            'Doctor mobile',
          )
              : null,
        ),

        const Divider(
          color: ChildSettingsColors.border,
        ),

        _detailRow(
          'Approval',
          _value(
            doctor['approval_status'],
          ),
          icon: Icons.verified_user_outlined,
        ),

        const SizedBox(height: 12),

        _infoBox(
          'The linked doctor may access the child '
              'profile and medical reports according '
              'to backend permissions. Doctor '
              'disconnection is not supported yet.',
        ),
      ],
    );
  }

  // ==========================================================
  // HEALTH REPORTS
  // ==========================================================

  Widget _healthDataSection() {
    return _sectionCard(
      title: 'Health Data & Records',
      subtitle: 'Saved medical information',
      icon: Icons.folder_copy_outlined,

      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),

            decoration: BoxDecoration(
              color: ChildSettingsColors.lightBlue,
              borderRadius: BorderRadius.circular(13),
            ),

            child: Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  color: ChildSettingsColors.blue,
                  size: 30,
                ),

                const SizedBox(width: 13),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'Saved Health Reports',
                        style: TextStyle(
                          color: ChildSettingsColors.muted,
                          fontSize: 11,
                        ),
                      ),

                      const SizedBox(height: 5),

                      if (_reportsLoading)
                        const LinearProgressIndicator()
                      else
                        Text(
                          _reportCount == null
                              ? 'Unavailable'
                              : '$_reportCount reports',

                          style: const TextStyle(
                            color: ChildSettingsColors.navy,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_reportsError != null) ...[
            const SizedBox(height: 9),

            Text(
              'Report count: $_reportsError',
              style: const TextStyle(
                fontSize: 11,
                color: ChildSettingsColors.red,
              ),
            ),
          ],

          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,

            child: OutlinedButton.icon(
              onPressed: () {
                _openSection('health-reports');
              },
              icon: const Icon(
                Icons.folder_open_outlined,
              ),
              label: const Text(
                'Open Health Reports',
              ),
            ),
          ),

          const SizedBox(height: 10),

          _infoBox(
            'Original documents can be viewed '
                'and uploaded in Health Reports. '
                'This shortcut uses the child dashboard '
                'navigation.',
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // HEALTH REMINDERS
  // ==========================================================

  Widget _remindersSection() {
    return _sectionCard(
      title: 'Health Reminders',
      subtitle: 'Manage saved reminder preferences',
      icon: Icons.notifications_active_outlined,

      child: Column(
        children: [
          _settingToggle(
            icon: Icons.notifications_outlined,
            title: 'In-App Reminders',
            description:
            'Show eligible recorded-date and '
                'published-schedule reminders '
                'inside FamilyCare+.',

            value: _inAppReminders,

            busy: _remindersLoading ||
                _savingInApp,

            error: _remindersError,
            onChanged: _changeInApp,
          ),

          if (_reminderCount != null) ...[
            const SizedBox(height: 7),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Available reminder entries: $_reminderCount',
                style: const TextStyle(
                  fontSize: 11,
                  color: ChildSettingsColors.muted,
                ),
              ),
            ),
          ],

          const Divider(
            height: 26,
            color: ChildSettingsColors.border,
          ),

          _settingToggle(
            icon: Icons.mark_email_read_outlined,

            title: 'Vaccination Email Reminders',

            description:
            'Optional email reminders to the verified '
                'account email, where supported by '
                'published schedules.',

            value: _emailReminders,

            busy: _vaccinationLoading ||
                _savingEmail,

            error: _vaccinationError,

            onChanged: _changeVaccinationEmail,
          ),

          const SizedBox(height: 15),

          _infoBox(
            'Email delivery requires explicit opt-in, '
                'an eligible published vaccination schedule '
                'and a functioning server worker. '
                'SMS reminders are not enabled. '
                'In-app reminders and vaccination emails '
                'have separate settings.',
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // API-BACKED TOGGLE
  // ==========================================================

  Widget _settingToggle({
    required IconData icon,
    required String title,
    required String description,
    required bool? value,
    required bool busy,
    required String? error,
    required ValueChanged<bool> onChanged,
  }) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,

      children: [
        Row(
          children: [
            Icon(
              icon,
              color: ChildSettingsColors.green,
              size: 23,
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,

                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: ChildSettingsColors.navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    description,
                    style: const TextStyle(
                      color: ChildSettingsColors.muted,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            if (busy)
              const SizedBox(
                width: 50,

                child: Center(
                  child: SizedBox(
                    height: 19,
                    width: 19,

                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                ),
              )
            else
              Switch(
                value: value ?? false,
                activeThumbColor:
                ChildSettingsColors.green,

                onChanged: value == null ||
                    _anySaveBusy
                    ? null
                    : onChanged,
              ),
          ],
        ),

        if (error != null) ...[
          const SizedBox(height: 10),

          Text(
            error,
            style: const TextStyle(
              color: ChildSettingsColors.red,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================================
  // FUTURE SETTINGS
  // ==========================================================

  Widget _futureSettingsSection() {
    return _sectionCard(
      title: 'Profile Management',
      subtitle: 'Features pending backend support',
      icon: Icons.manage_accounts_outlined,

      child: Column(
        children: [
          _futureSetting(
            Icons.edit_note_rounded,
            'Edit Child Profile',
            'Name and date-of-birth changes',
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _futureSetting(
            Icons.phone_android_outlined,
            'Update Guardian & Contacts',
            'Contact information changes',
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _futureSetting(
            Icons.family_restroom_outlined,
            'Change Parent Connection',
            'Manage linked parent profiles',
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _futureSetting(
            Icons.person_remove_outlined,
            'Disconnect Doctor',
            'Revoke doctor profile connection',
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _futureSetting(
            Icons.delete_outline_rounded,
            'Delete Child Profile',
            'Request removal of child records',
            color: ChildSettingsColors.red,
          ),

          const SizedBox(height: 12),

          _infoBox(
            'These controls are not active because '
                'their authenticated backend endpoints '
                'have not been implemented.',
          ),
        ],
      ),
    );
  }

  Widget _futureSetting(
      IconData icon,
      String title,
      String description, {
        Color color = ChildSettingsColors.green,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 12,
      ),

      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 23,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: ChildSettingsColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  description,
                  style: const TextStyle(
                    color: ChildSettingsColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          const Icon(
            Icons.lock_clock_outlined,
            size: 19,
            color: ChildSettingsColors.muted,
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // PRIVACY AND ACCESS
  // ==========================================================

  Widget _privacySection() {
    return _sectionCard(
      title: 'Privacy & Access',
      subtitle: 'Important information about child data',
      icon: Icons.shield_outlined,

      child: Column(
        children: [
          _privacyItem(
            Icons.lock_outline_rounded,
            'Authenticated Access',
            'Profile requests require a valid patient '
                'session and backend authorization.',
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _privacyItem(
            Icons.medical_services_outlined,
            'Connected Doctor',
            'The linked doctor can access profile '
                'and medical reports according to backend '
                'permissions. Disconnection is not '
                'currently available.',
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _privacyItem(
            Icons.visibility_off_outlined,
            'Contact Visibility',
            'Hiding numbers affects only this screen. '
                'It does not change backend permissions '
                'or protect clipboard copies.',
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _privacyItem(
            Icons.mark_email_read_outlined,
            'Reminder Consent',
            'Vaccination emails require an opt-in. '
                'Turning off emails does not change '
                'in-app reminder preferences.',
          ),

          const Divider(
            color: ChildSettingsColors.border,
          ),

          _privacyItem(
            Icons.settings_backup_restore_outlined,
            'Future Data Management',
            'Profile editing, doctor disconnection '
                'and deletion require additional '
                'authenticated backend APIs.',
          ),
        ],
      ),
    );
  }

  Widget _privacyItem(
      IconData icon,
      String title,
      String description,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 10,
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(
            icon,
            color: ChildSettingsColors.green,
            size: 21,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: ChildSettingsColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  description,
                  style: const TextStyle(
                    color: ChildSettingsColors.muted,
                    fontSize: 11,
                    height: 1.5,
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
  // REUSABLE SECTION CARD
  // ==========================================================

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ChildSettingsColors.border,
        ),

        boxShadow: const [
          BoxShadow(
            color: Color(0x082A4E73),
            blurRadius: 13,
            offset: Offset(0, 4),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),

                decoration: BoxDecoration(
                  color: ChildSettingsColors.lightGreen,
                  borderRadius:
                  BorderRadius.circular(11),
                ),

                child: Icon(
                  icon,
                  size: 23,
                  color: ChildSettingsColors.green,
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
                        color: ChildSettingsColors.navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: ChildSettingsColors.muted,
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

  // ==========================================================
  // DETAIL ROW
  // ==========================================================

  Widget _detailRow(
      String label,
      String value, {
        IconData? icon,
        VoidCallback? onCopy,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 10,
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: ChildSettingsColors.green,
              size: 18,
            ),

            const SizedBox(width: 9),
          ],

          SizedBox(
            width: 98,

            child: Text(
              label,
              style: const TextStyle(
                color: ChildSettingsColors.muted,
                fontSize: 11,
              ),
            ),
          ),

          const SizedBox(width: 7),

          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: ChildSettingsColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          if (onCopy != null)
            IconButton(
              tooltip: 'Copy $label',
              visualDensity: VisualDensity.compact,
              onPressed: onCopy,

              icon: const Icon(
                Icons.copy_rounded,
                size: 17,
                color: ChildSettingsColors.blue,
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================================
  // INFORMATION BOX
  // ==========================================================

  Widget _infoBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),

      decoration: BoxDecoration(
        color: ChildSettingsColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 19,
            color: ChildSettingsColors.green,
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: ChildSettingsColors.text,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // EMPTY INFORMATION
  // ==========================================================

  Widget _emptyInfo(
      IconData icon,
      String title,
      String description,
      ) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 27,
      ),

      decoration: BoxDecoration(
        color: ChildSettingsColors.cream,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: ChildSettingsColors.border,
        ),
      ),

      child: Column(
        children: [
          Icon(
            icon,
            color: ChildSettingsColors.green,
            size: 39,
          ),

          const SizedBox(height: 12),

          Text(
            title,
            style: const TextStyle(
              color: ChildSettingsColors.navy,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ChildSettingsColors.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DOCTOR REFERRAL DIALOG
// ============================================================

class _DoctorReferralDialog extends StatefulWidget {
  const _DoctorReferralDialog();

  @override
  State<_DoctorReferralDialog> createState() =>
      _DoctorReferralDialogState();
}

class _DoctorReferralDialogState
    extends State<_DoctorReferralDialog> {
  final _formKey = GlobalKey<FormState>();

  final _referral = TextEditingController();

  @override
  void dispose() {
    _referral.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ??
        false)) {
      return;
    }

    Navigator.of(context).pop(
      _referral.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),

      title: const Text(
        'Connect Doctor',
        style: TextStyle(
          color: ChildSettingsColors.navy,
          fontWeight: FontWeight.w800,
        ),
      ),

      content: SingleChildScrollView(
        child: SizedBox(
          width: 350,

          child: Form(
            key: _formKey,

            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                const Text(
                  'Enter the referral ID provided by '
                      'an approved FamilyCare+ doctor.',
                  style: TextStyle(
                    color: ChildSettingsColors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 18),

                TextFormField(
                  controller: _referral,
                  autofocus: true,

                  textCapitalization:
                  TextCapitalization.characters,

                  textInputAction: TextInputAction.done,

                  onFieldSubmitted: (_) => _submit(),

                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[A-Za-z0-9]'),
                    ),
                    LengthLimitingTextInputFormatter(160),
                  ],

                  decoration: InputDecoration(
                    labelText: 'Doctor Referral ID',

                    prefixIcon: const Icon(
                      Icons.verified_user_outlined,
                      color: ChildSettingsColors.green,
                    ),

                    border: OutlineInputBorder(
                      borderRadius:
                      BorderRadius.circular(12),
                    ),
                  ),

                  validator: (raw) {
                    final value = (raw ?? '').trim();

                    if (!RegExp(
                      r'^[A-Za-z0-9]{1,160}$',
                    ).hasMatch(value)) {
                      return 'Enter a valid referral ID';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 14),

                const Text(
                  'Connecting a doctor grants access '
                      'to the linked child profile and '
                      'medical reports under backend '
                      'permissions.',
                  style: TextStyle(
                    color: ChildSettingsColors.muted,
                    fontSize: 11,
                    height: 1.5,
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
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),

        FilledButton(
          onPressed: _submit,

          style: FilledButton.styleFrom(
            backgroundColor:
            ChildSettingsColors.green,
            foregroundColor: Colors.white,
          ),

          child: const Text('Connect Doctor'),
        ),
      ],
    );
  }
}
