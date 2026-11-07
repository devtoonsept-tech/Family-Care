import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';
import 'add_child_screen.dart';

// ============================================================
// FAMILYCARE+ - CHILD PROFILE SCREEN
// ============================================================
//
// EXISTING FLASK APIs:
//
// GET  /api/v1/patients/profiles/{profile_id}
//
// POST /api/v1/patients/profiles/{profile_id}/connect-doctor
//
// GET  /api/v1/patients/profiles/{profile_id}/reports
//
// FEATURES:
// - Child profile information
// - Automatic age calculation
// - Guardian and parent information
// - Emergency contacts
// - Connect doctor using referral ID
// - Healthcare service navigation
// - Medical report summary
// - Loading and refresh
// - Account owner name from signed-in signup account
// - All children + Add Child action
// - Backend Edit/Delete, doctor disconnect and activity overview
//
// ============================================================

// ============================================================
// COLORS
// ============================================================

class ChildProfileColors {
  static const Color navy = Color(0xFF143C60);
  static const Color text = Color(0xFF263F45);
  static const Color muted = Color(0xFF81918C);

  static const Color background = Color(0xFFF2F7FD);
  static const Color white = Colors.white;
  static const Color border = Color(0xFFE4E9E6);

  static const Color green = Color(0xFF347D61);
  static const Color blue = Color(0xFF2381F4);
  static const Color pink = Color(0xFFD68788);
  static const Color purple = Color(0xFF8963C4);
  static const Color orange = Color(0xFFCB955C);

  static const Color lightGreen = Color(0xFFEAF5ED);
  static const Color lightBlue = Color(0xFFEAF5FF);
  static const Color cream = Color(0xFFFFFDF8);

  static const Color error = Color(0xFFB7434E);
}

// ============================================================
// API EXCEPTION
// ============================================================

class ChildProfileApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const ChildProfileApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}

// ============================================================
// MAIN CHILD PROFILE SCREEN
// ============================================================

class ChildProfileScreen extends StatefulWidget {
  final String profileId;
  final String apiBaseUrl;

  // Existing navigation callback.
  //
  // Supported sections:
  // vaccination
  // medical-history
  // growth
  // doctor-consultation
  // care-notes
  // health-reports

  final void Function(
      BuildContext context,
      String section,
      String profileId,
      )? onOpenSection;

  const ChildProfileScreen({
    super.key,
    required this.profileId,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.onOpenSection,
  });

  @override
  State<ChildProfileScreen> createState() =>
      _ChildProfileScreenState();
}

// ============================================================
// STATE
// ============================================================

class _ChildProfileScreenState
    extends State<ChildProfileScreen> {
  final http.Client _httpClient = http.Client();

  // ----------------------------------------------------------
  // PROFILE DATA
  // ----------------------------------------------------------

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _account;
  List<Map<String, dynamic>> _children = [];
  List<Map<String, dynamic>> _doctorEntries = [];
  int _doctorEntryTotal = 0;
  String? _accountError;
  String? _childrenError;
  String? _doctorOverviewError;
  bool _loadingAccount = true;
  bool _loadingChildren = true;
  bool _loadingDoctorOverview = false;
  bool _isUpdating = false;
  bool _isDeleting = false;
  bool _isDisconnectingDoctor = false;
  int _accountRequest = 0;
  int _childrenRequest = 0;
  int _doctorOverviewRequest = 0;

  List<Map<String, dynamic>> _recentReports = [];

  int _reportCount = 0;

  // ----------------------------------------------------------
  // LOADING STATES
  // ----------------------------------------------------------

  bool _isLoading = true;
  bool _loadingReports = false;
  bool _isConnectingDoctor = false;

  // ----------------------------------------------------------
  // ERROR STATES
  // ----------------------------------------------------------

  String? _errorMessage;
  String? _reportsError;

  // Prevent stale requests from updating a different child.
  int _requestVersion = 0;

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

  String get _profileEndpoint =>
      '/api/v1/patients/profiles/'
          '${Uri.encodeComponent(widget.profileId)}';

  // ==========================================================
  // INITIALIZATION
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _loadChildProfile();
    _loadAccount();
    _loadChildren();
  }

  @override
  void didUpdateWidget(
      covariant ChildProfileScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.profileId != widget.profileId ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _requestVersion++;

      _profile = null;
      _recentReports = [];
      _reportCount = 0;

      _errorMessage = null;
      _reportsError = null;

      _loadingReports = false;
      _isConnectingDoctor = false;

      _loadChildProfile();
      _doctorEntries = [];
      _doctorEntryTotal = 0;
      if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
        _loadAccount();
        _loadChildren();
      }
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    _accountRequest++;
    _childrenRequest++;
    _doctorOverviewRequest++;
    _httpClient.close();

    super.dispose();
  }

  // ==========================================================
  // REQUEST VERSION VALIDATION
  // ==========================================================

  bool _isCurrentRequest(
      int version,
      String requestedProfileId,
      ) {
    return mounted &&
        version == _requestVersion &&
        widget.profileId == requestedProfileId;
  }

  // ==========================================================
  // TEXT HELPERS
  // ==========================================================

  String _stringValue(
      dynamic value, {
        String fallback = 'Not added',
      }) {
    if (value == null) return fallback;

    final result = value.toString().trim();

    return result.isEmpty ? fallback : result;
  }

  String get _childName {
    return _stringValue(
      _profile?['full_name'],
      fallback: 'Child Profile',
    );
  }

  // ==========================================================
  // CHILD DATE OF BIRTH
  // ==========================================================

  DateTime? get _dateOfBirth {
    final rawValue = _profile?['date_of_birth'];

    if (rawValue is! String) return null;

    return DateTime.tryParse(rawValue);
  }

  // ==========================================================
  // DATE FORMATTING
  // ==========================================================

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not recorded';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatServerDate(dynamic value) {
    if (value is! String) return 'Not available';

    final parsedDate = DateTime.tryParse(value);

    if (parsedDate == null) return 'Not available';

    return _formatDate(parsedDate.toLocal());
  }

  // ==========================================================
  // AGE CALCULATION
  // ==========================================================

  String _calculateAge(DateTime? birthDate) {
    if (birthDate == null) {
      return 'Not available';
    }

    final today = DateUtils.dateOnly(DateTime.now());
    final birth = DateUtils.dateOnly(birthDate);

    if (birth.isAfter(today)) {
      return 'Invalid date';
    }

    int calculatedYears = today.year - birth.year;
    int calculatedMonths = today.month - birth.month;

    if (today.day < birth.day) {
      calculatedMonths--;
    }

    if (calculatedMonths < 0) {
      calculatedYears--;
      calculatedMonths += 12;
    }

    if (calculatedYears == 0 &&
        calculatedMonths == 0) {
      return '${today.difference(birth).inDays} days';
    }

    if (calculatedYears == 0) {
      return '$calculatedMonths months';
    }

    if (calculatedMonths == 0) {
      return '$calculatedYears years';
    }

    return '$calculatedYears years, '
        '$calculatedMonths months';
  }

  // ==========================================================
  // CONNECTED DOCTOR
  // ==========================================================

  Map<String, dynamic>? get _connectedDoctor {
    final rawDoctor = _profile?['doctor'];

    if (rawDoctor is Map) {
      return Map<String, dynamic>.from(rawDoctor);
    }

    return null;
  }

  // ==========================================================
  // EMERGENCY CONTACTS
  // ==========================================================

  List<Map<String, dynamic>> get _emergencyContacts {
    final rawContacts = _profile?['emergency_contacts'];

    if (rawContacts is! List) return [];

    return rawContacts
        .whereType<Map>()
        .map(
          (contact) =>
      Map<String, dynamic>.from(contact),
    )
        .toList();
  }

  // ==========================================================
  // AUTHENTICATED BACKEND REQUEST
  // ==========================================================

  Future<Map<String, dynamic>> _apiRequest(
      String method,
      String endpoint, {
        Map<String, dynamic>? body,
      }) async {
    final token = await FamilyCareSession.accessToken();

    if (token == null || token.trim().isEmpty) {
      throw const ChildProfileApiException(
        statusCode: 401,
        code: 'not_authenticated',
        message:
        'Please log in again to access this child profile.',
      );
    }

    final uri = Uri.parse('$_baseUrl$endpoint');

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
    };

    late http.Response response;

    if (method == 'GET') {
      response = await _httpClient
          .get(
        uri,
        headers: headers,
      )
          .timeout(
        const Duration(seconds: 30),
      );
    } else if (method == 'POST') {
      response = await _httpClient
          .post(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      )
          .timeout(
        const Duration(seconds: 30),
      );
    } else if (method == 'PATCH') {
      response = await _httpClient.patch(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      ).timeout(const Duration(seconds: 30));
    } else if (method == 'DELETE') {
      response = await _httpClient.delete(
        uri,
        headers: headers,
      ).timeout(const Duration(seconds: 30));
    } else {
      throw const ChildProfileApiException(
        statusCode: 0,
        code: 'unsupported_method',
        message: 'Unsupported API request method.',
      );
    }

    if (response.statusCode == 204 && response.bodyBytes.isEmpty) {
      return <String, dynamic>{};
    }

    Map<String, dynamic> result;

    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (decoded is! Map) {
        throw const FormatException();
      }

      result = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const ChildProfileApiException(
        statusCode: 0,
        code: 'invalid_response',
        message: 'Invalid response received from server.',
      );
    } on TypeError {
      throw const ChildProfileApiException(
        statusCode: 0,
        code: 'invalid_response',
        message: 'Invalid response received from server.',
      );
    }

    // --------------------------------------------------------
    // HANDLE HTTP ERRORS
    // --------------------------------------------------------

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final errorData = result['error'];

      String errorCode = 'request_failed';

      String errorMessage =
          'Request failed. Please try again.';

      if (errorData is Map) {
        if (errorData['code'] is String) {
          errorCode = errorData['code'] as String;
        }

        if (errorData['message'] is String) {
          final serverMessage =
          (errorData['message'] as String).trim();

          if (serverMessage.isNotEmpty) {
            errorMessage = serverMessage;
          }
        }
      }

      if (response.statusCode == 401) {
        errorMessage =
        'Your session has expired. Please log in again.';
      }

      if (response.statusCode == 403) {
        errorMessage =
        'You are not authorized to access this profile.';
      }

      throw ChildProfileApiException(
        statusCode: response.statusCode,
        code: errorCode,
        message: errorMessage,
      );
    }

    return result;
  }

  // ==========================================================
  // ERROR HANDLING
  // ==========================================================

  String _errorText(Object error) {
    if (error is ChildProfileApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'Server response timed out. Please retry.';
    }

    if (error is http.ClientException) {
      return 'Could not connect to the server.';
    }

    if (error is PlatformException) {
      return 'Unable to read your login session.';
    }

    return 'Something went wrong. Please try again.';
  }

  // ==========================================================
  // SNACKBAR
  // ==========================================================

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
              ? ChildProfileColors.error
              : ChildProfileColors.navy,
          content: Text(message),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ==========================================================
  // SIGNED-IN ACCOUNT IDENTITY - GET /api/v1/patients/me
  // This is the registration name, not a child/guardian guess.
  // ==========================================================

  Future<void> _loadAccount() async {
    final requestId = ++_accountRequest;
    if (!mounted) return;
    setState(() {
      _loadingAccount = true;
      _accountError = null;
    });
    try {
      final data = await _apiRequest('GET', '/api/v1/patients/me');
      if (data['user'] is! Map) {
        throw const ChildProfileApiException(
          statusCode: 0,
          code: 'invalid_account',
          message: 'Account details were not returned.',
        );
      }
      if (!mounted || requestId != _accountRequest) return;
      setState(() {
        _account = Map<String, dynamic>.from(data['user'] as Map);
      });
    } catch (error) {
      if (!mounted || requestId != _accountRequest) return;
      setState(() => _accountError = _errorText(error));
    } finally {
      if (mounted && requestId == _accountRequest) {
        setState(() => _loadingAccount = false);
      }
    }
  }

  // ==========================================================
  // ALL CHILD PROFILES FOR SAME ACCOUNT
  // ==========================================================

  Future<void> _loadChildren() async {
    final requestId = ++_childrenRequest;
    if (!mounted) return;
    setState(() {
      _loadingChildren = true;
      _childrenError = null;
    });
    try {
      final children = <Map<String, dynamic>>[];
      for (int page = 1; page <= 100; page++) {
        final data = await _apiRequest(
          'GET', '/api/v1/children?page=$page&per_page=100',
        );
        if (data['items'] is! List) {
          throw const ChildProfileApiException(
            statusCode: 0,
            code: 'invalid_children',
            message: 'Invalid children list received.',
          );
        }
        final batch = (data['items'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        children.addAll(batch);
        if (!mounted || requestId != _childrenRequest) return;
        final total = data['total'];
        if (batch.length < 100 ||
            (total is num && children.length >= total)) break;
      }
      if (!mounted || requestId != _childrenRequest) return;
      setState(() => _children = children);
    } catch (error) {
      if (!mounted || requestId != _childrenRequest) return;
      setState(() => _childrenError = _errorText(error));
    } finally {
      if (mounted && requestId == _childrenRequest) {
        setState(() => _loadingChildren = false);
      }
    }
  }

  Future<void> _addChild() async {
    if (_isUpdating || _isDeleting) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AddChildScreen(apiBaseUrl: _baseUrl),
      ),
    );
    if (!mounted) return;
    await _loadChildren();
  }

  Future<void> _openAnotherChild(String profileId) async {
    if (profileId == widget.profileId) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChildProfileScreen(
          profileId: profileId,
          apiBaseUrl: _baseUrl,
          onOpenSection: widget.onOpenSection,
        ),
      ),
    );
    if (!mounted) return;
    await _loadChildren();
  }

  // ==========================================================
  // LOAD CHILD PROFILE
  // GET /api/v1/patients/profiles/{profile_id}
  // ==========================================================

  Future<void> _loadChildProfile() async {
    if (!mounted) return;

    final requestVersion = ++_requestVersion;
    final requestedProfileId = widget.profileId;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiRequest(
        'GET',
        _profileEndpoint,
      );

      final rawProfile = response['profile'];

      if (rawProfile is! Map) {
        throw const ChildProfileApiException(
          statusCode: 0,
          code: 'invalid_profile',
          message:
          'The server returned an invalid child profile.',
        );
      }

      final profile =
      Map<String, dynamic>.from(rawProfile);

      // Ensure this is a Child Care profile.
      if (profile['module'] != 'child') {
        throw const ChildProfileApiException(
          statusCode: 422,
          code: 'incorrect_module',
          message:
          'The selected profile is not a Child Care profile.',
        );
      }

      if (profile['id']?.toString() !=
          requestedProfileId) {
        throw const ChildProfileApiException(
          statusCode: 0,
          code: 'profile_mismatch',
          message:
          'The returned profile does not match the selected child.',
        );
      }

      if (!_isCurrentRequest(
        requestVersion,
        requestedProfileId,
      )) {
        return;
      }

      setState(() {
        _profile = profile;
        _isLoading = false;

        _recentReports = [];
        _reportCount = 0;
        _reportsError = null;
      });

      // Reports load separately.
      // Slow report requests will not block profile UI.
      await _loadReportSummary(
        expectedVersion: requestVersion,
      );
    } catch (error) {
      if (!_isCurrentRequest(
        requestVersion,
        requestedProfileId,
      )) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = _errorText(error);

        _profile = null;
        _recentReports = [];
        _reportCount = 0;
      });
    }
  }

  // ==========================================================
  // LOAD HEALTH REPORT SUMMARY
  // GET /api/v1/patients/profiles/{profile_id}/reports
  // ==========================================================

  Future<void> _loadReportSummary({
    int? expectedVersion,
  }) async {
    if (_profile == null) return;

    final requestVersion =
        expectedVersion ?? _requestVersion;

    final requestedProfileId = widget.profileId;

    if (!_isCurrentRequest(
      requestVersion,
      requestedProfileId,
    )) {
      return;
    }

    setState(() {
      _loadingReports = true;
      _reportsError = null;
    });

    try {
      final response = await _apiRequest(
        'GET',
        '$_profileEndpoint/reports?page=1&per_page=3',
      );

      final rawItems = response['items'];

      if (rawItems is! List) {
        throw const ChildProfileApiException(
          statusCode: 0,
          code: 'invalid_reports',
          message: 'Invalid report list from server.',
        );
      }

      final reports = <Map<String, dynamic>>[];

      for (final item in rawItems) {
        if (item is Map) {
          reports.add(
            Map<String, dynamic>.from(item),
          );
        }
      }

      final total = response['total'];

      if (!_isCurrentRequest(
        requestVersion,
        requestedProfileId,
      )) {
        return;
      }

      setState(() {
        _recentReports = reports;

        _reportCount = total is num
            ? total.toInt()
            : reports.length;

        _reportsError = null;
      });
    } catch (error) {
      if (!_isCurrentRequest(
        requestVersion,
        requestedProfileId,
      )) {
        return;
      }

      setState(() {
        _recentReports = [];
        _reportsError = _errorText(error);
      });
    } finally {
      if (_isCurrentRequest(
        requestVersion,
        requestedProfileId,
      )) {
        setState(() {
          _loadingReports = false;
        });
      }
    }
  }

  // ==========================================================
  // CONNECT DOCTOR
  // POST /api/v1/patients/profiles/{id}/connect-doctor
  // ==========================================================

  Future<void> _showConnectDoctorDialog() async {
    if (_isConnectingDoctor ||
        _isLoading ||
        _profile == null ||
        _connectedDoctor != null) {
      return;
    }

    final referralId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return const _ChildDoctorReferralDialog();
      },
    );

    if (!mounted ||
        referralId == null ||
        referralId.isEmpty) {
      return;
    }

    final requestedProfileId = widget.profileId;
    final requestVersion = _requestVersion;

    setState(() {
      _isConnectingDoctor = true;
    });

    try {
      final response = await _apiRequest(
        'POST',
        '$_profileEndpoint/connect-doctor',
        body: {
          'referral_id': referralId,
        },
      );

      final rawProfile = response['profile'];

      if (rawProfile is! Map) {
        throw const ChildProfileApiException(
          statusCode: 0,
          code: 'invalid_response',
          message:
          'Doctor connection may have succeeded. '
              'Refresh the profile before retrying.',
        );
      }

      final profile =
      Map<String, dynamic>.from(rawProfile);

      if (profile['module'] != 'child' ||
          profile['id']?.toString() !=
              requestedProfileId) {
        throw const ChildProfileApiException(
          statusCode: 0,
          code: 'profile_mismatch',
          message:
          'Unexpected child profile returned. Please refresh.',
        );
      }

      if (!_isCurrentRequest(
        requestVersion,
        requestedProfileId,
      )) {
        return;
      }

      setState(() {
        _profile = profile;
      });

      _showMessage('Doctor connected successfully!');
    } catch (error) {
      if (!_isCurrentRequest(
        requestVersion,
        requestedProfileId,
      )) {
        return;
      }

      _showMessage(
        _errorText(error),
        error: true,
      );
    } finally {
      if (_isCurrentRequest(
        requestVersion,
        requestedProfileId,
      )) {
        setState(() {
          _isConnectingDoctor = false;
        });
      }
    }
  }

  // ==========================================================
  // EDIT PROFILE - V5 REQUIRES FULL REPLACEMENT FIELDS
  // ==========================================================

  Future<void> _editChildProfile() async {
    if (_profile == null || _isUpdating || _isDeleting) return;
    final profileId = widget.profileId;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChildProfileEditDialog(profile: _profile!),
    );
    if (!mounted || payload == null || widget.profileId != profileId) return;
    setState(() => _isUpdating = true);
    try {
      final result = await _apiRequest(
        'PATCH', _profileEndpoint, body: payload,
      );
      if (!mounted || widget.profileId != profileId) return;
      if (result['profile'] is Map) {
        setState(() {
          _profile = Map<String, dynamic>.from(result['profile'] as Map);
        });
      }
      _showMessage('Child profile updated successfully.');
      await Future.wait<void>([_loadChildProfile(), _loadChildren()]);
    } catch (error) {
      if (mounted && widget.profileId == profileId) {
        _showMessage(_errorText(error), error: true);
      }
    } finally {
      if (mounted && widget.profileId == profileId) {
        setState(() => _isUpdating = false);
      }
    }
  }

  // ==========================================================
  // DELETE PROFILE - SOFT DELETE WITH CONFIRMATION
  // ==========================================================

  Future<void> _deleteChildProfile() async {
    if (_profile == null || _isUpdating || _isDeleting) return;
    final profileId = widget.profileId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove child profile?'),
        content: Text(
          'Remove $_childName from your care workspace? '
              'The backend retains private records for audit/retention, '
              'but they will no longer be accessible through this workspace. '
              'This action cannot be undone in the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ChildProfileColors.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove child'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || widget.profileId != profileId) return;
    setState(() => _isDeleting = true);
    try {
      await _apiRequest('DELETE', _profileEndpoint);
      if (!mounted || widget.profileId != profileId) return;
      _showMessage('Child profile removed from your workspace.');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted && widget.profileId == profileId) {
        _showMessage(_errorText(error), error: true);
      }
    } finally {
      if (mounted && widget.profileId == profileId) {
        setState(() => _isDeleting = false);
      }
    }
  }

  // ==========================================================
  // DISCONNECT DOCTOR
  // ==========================================================

  Future<void> _disconnectDoctor() async {
    if (_connectedDoctor == null || _isDisconnectingDoctor) return;
    final id = widget.profileId;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect doctor?'),
        content: const Text(
          'This will remove the doctor connection for this child. '
              'Doctor access will be recalculated by the backend.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true || widget.profileId != id) return;
    setState(() => _isDisconnectingDoctor = true);
    try {
      final result = await _apiRequest('DELETE', '$_profileEndpoint/doctor');
      if (!mounted || widget.profileId != id) return;
      if (result['profile'] is Map) {
        setState(() => _profile = Map<String, dynamic>.from(result['profile'] as Map));
      }
      _doctorEntries = [];
      _doctorEntryTotal = 0;
      _showMessage('Doctor disconnected successfully.');
      await _loadChildProfile();
    } catch (error) {
      if (mounted && widget.profileId == id) {
        _showMessage(_errorText(error), error: true);
      }
    } finally {
      if (mounted && widget.profileId == id) {
        setState(() => _isDisconnectingDoctor = false);
      }
    }
  }

  // ==========================================================
  // DOCTOR-GENERATED HEALTH RECORD OVERVIEW
  // ==========================================================

  Future<void> _showDoctorOverview() async {
    if (_connectedDoctor == null || _loadingDoctorOverview) return;
    final id = widget.profileId;
    final version = ++_doctorOverviewRequest;
    setState(() {
      _loadingDoctorOverview = true;
      _doctorOverviewError = null;
    });
    try {
      final result = await _apiRequest(
        'GET', '$_profileEndpoint/doctor-overview?page=1&per_page=20',
      );
      if (!mounted || version != _doctorOverviewRequest || id != widget.profileId) return;
      _doctorEntries = result['items'] is List
          ? (result['items'] as List).whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry)).toList()
          : [];
      _doctorEntryTotal = result['total'] is num
          ? (result['total'] as num).toInt() : _doctorEntries.length;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: .75,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Doctor Care Overview',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Text('$_doctorEntryTotal doctor-created records',
                  style: const TextStyle(color: ChildProfileColors.muted)),
              const SizedBox(height: 10),
              if (_doctorEntries.isEmpty)
                const ListTile(title: Text('No doctor-created records yet.')),
              for (final entry in _doctorEntries)
                ListTile(
                  leading: const Icon(Icons.medical_information_outlined,
                      color: ChildProfileColors.green),
                  title: Text(_stringValue(entry['title'], fallback: 'Care record')),
                  subtitle: Text(
                    '${_stringValue(entry['kind'], fallback: 'Record')}  •  '
                        '${_stringValue(entry['date'], fallback: 'Date not recorded')}'
                    'Doctor-reported • Read-only',
                  ),
                ),
              const SizedBox(height: 12),
              const Text('Doctor records shown here are read-only for parents.',
                  style: TextStyle(fontSize: 11, color: ChildProfileColors.muted)),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted && version == _doctorOverviewRequest && id == widget.profileId) {
        setState(() => _doctorOverviewError = _errorText(error));
        _showMessage(_doctorOverviewError!, error: true);
      }
    } finally {
      if (mounted && version == _doctorOverviewRequest && id == widget.profileId) {
        setState(() => _loadingDoctorOverview = false);
      }
    }
  }

  // ==========================================================
  // OPEN CHILD HEALTHCARE SECTION
  // ==========================================================

  void _openSection(String section) {
    if (_profile == null) return;

    final callback = widget.onOpenSection;

    if (callback != null) {
      callback(
        context,
        section,
        widget.profileId,
      );

      return;
    }

    _showMessage(
      'Navigation to this Child Care section '
          'is not connected yet.',
    );
  }

  // ==========================================================
  // MAIN BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChildProfileColors.background,

      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ChildProfileColors.navy,
        elevation: 0,

        title: const Text(
          'Child Profile',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),

        actions: [
          PopupMenuButton<String>(
            tooltip: 'Profile actions',
            enabled: _profile != null && !_isUpdating && !_isDeleting,
            onSelected: (action) {
              if (action == 'Edit') _editChildProfile();
              if (action == 'Delete') _deleteChildProfile();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'Edit', child: Text('Edit Child Profile')),
              PopupMenuItem(value: 'Delete', child: Text('Remove Child Profile')),
            ],
          ),

          IconButton(
            tooltip: 'Refresh Child Profile',
            onPressed: _isLoading
                ? null
                : _loadChildProfile,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),

          const SizedBox(width: 5),
        ],
      ),

      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  // ==========================================================
  // MAIN BODY
  // ==========================================================

  Widget _buildBody() {
    if (_isLoading && _profile == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: ChildProfileColors.green,
        ),
      );
    }

    if (_profile == null) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      onRefresh: _loadChildProfile,
      color: ChildProfileColors.green,

      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),

        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 20,
        ),

        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 1100,
            ),

            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                _buildBreadcrumb(),

                const SizedBox(height: 15),

                _buildAccountIdentity(),

                const SizedBox(height: 16),

                _buildChildrenOverview(),

                const SizedBox(height: 16),

                _buildProfileHero(),

                const SizedBox(height: 18),

                // Basic and guardian information.
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 760) {
                      return Row(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,

                        children: [
                          Expanded(
                            child: _buildBasicInformation(),
                          ),

                          const SizedBox(width: 16),

                          Expanded(
                            child: _buildGuardianInformation(),
                          ),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        _buildBasicInformation(),

                        const SizedBox(height: 16),

                        _buildGuardianInformation(),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),

                _buildEmergencyContacts(),

                const SizedBox(height: 16),

                _buildDoctorInformation(),

                const SizedBox(height: 18),

                _buildQuickAccess(),

                const SizedBox(height: 18),

                _buildHealthReports(),

                const SizedBox(height: 24),

                const Center(
                  child: Text(
                    'FamilyCare+ • Healthier Families. '
                        'Brighter Tomorrows.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: ChildProfileColors.muted,
                    ),
                  ),
                ),

                const SizedBox(height: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // ERROR STATE
  // ==========================================================

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: ChildProfileColors.error,
            ),

            const SizedBox(height: 12),

            const Text(
              'Unable to load child profile',
              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: ChildProfileColors.navy,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              _errorMessage ??
                  'Profile information is not available.',
              textAlign: TextAlign.center,

              style: const TextStyle(
                color: ChildProfileColors.muted,
              ),
            ),

            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: _loadChildProfile,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // BREADCRUMB
  // ==========================================================

  Widget _buildBreadcrumb() {
    return const Row(
      children: [
        Text(
          'Child Care',
          style: TextStyle(
            fontSize: 12,
            color: ChildProfileColors.muted,
          ),
        ),

        SizedBox(width: 6),

        Icon(
          Icons.chevron_right_rounded,
          size: 17,
          color: ChildProfileColors.muted,
        ),

        SizedBox(width: 6),

        Text(
          'Child Profile',
          style: TextStyle(
            fontSize: 12,
            color: ChildProfileColors.green,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // ACCOUNT OWNER - NAME FROM SIGNUP /patients/me
  // ==========================================================

  Widget _buildAccountIdentity() {
    return _sectionCard(
      title: 'Account Holder',
      subtitle: 'Registered FamilyCare+ account',
      icon: Icons.account_circle_outlined,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingAccount)
            const LinearProgressIndicator(color: ChildProfileColors.green)
          else if (_accountError != null)
            Row(children: [
              const Icon(Icons.error_outline, color: ChildProfileColors.error),
              const SizedBox(width: 8),
              Expanded(child: Text('Account details unavailable: $_accountError')),
              TextButton(onPressed: _loadAccount, child: const Text('Retry')),
            ])
          else ...[
              _detailRow(
                label: 'Full Name',
                value: _stringValue(_account?['full_name']),
                icon: Icons.person_outline_rounded,
              ),
              const Divider(color: ChildProfileColors.border),
              _detailRow(
                label: 'Email',
                value: _stringValue(_account?['email']),
                icon: Icons.email_outlined,
              ),
              const Divider(color: ChildProfileColors.border),
              _detailRow(
                label: 'Mobile',
                value: _stringValue(_account?['phone_number']),
                icon: Icons.phone_outlined,
              ),
            ],
          const SizedBox(height: 7),
          _infoBox('This is your signed-in account identity. Child profiles '
              'are linked to the account automatically; adding a child does '
              'not change your signup name.'),
        ],
      ),
    );
  }

  // ==========================================================
  // CHILD LIST + ADD CHILD BELOW ACCOUNT IDENTITY
  // ==========================================================

  Widget _buildChildrenOverview() {
    return _sectionCard(
      title: 'Your Children',
      subtitle: 'Profiles belonging to this account',
      icon: Icons.family_restroom_rounded,
      trailing: IconButton(
        tooltip: 'Refresh children',
        onPressed: _loadingChildren ? null : _loadChildren,
        icon: const Icon(Icons.refresh_rounded,
            color: ChildProfileColors.green),
      ),
      content: Column(
        children: [
          if (_loadingChildren)
            const LinearProgressIndicator(color: ChildProfileColors.green)
          else if (_childrenError != null)
            _infoBox('Could not load children: $_childrenError')
          else if (_children.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No child profiles found.',
                    style: TextStyle(color: ChildProfileColors.muted)),
              )
            else ...[
                for (final child in _children) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: ChildProfileColors.lightGreen,
                      child: Icon(Icons.child_care, color: ChildProfileColors.green),
                    ),
                    title: Text(_stringValue(child['full_name'], fallback: 'Child'),
                        style: const TextStyle(fontWeight: FontWeight.w700,
                            color: ChildProfileColors.navy)),
                    subtitle: Text('DOB: ${_stringValue(child['date_of_birth'], fallback: 'Not recorded')}'),
                    trailing: child['id'] == widget.profileId
                        ? const Text('Current', style: TextStyle(
                        color: ChildProfileColors.green, fontWeight: FontWeight.w700))
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      final id = child['id']?.toString() ?? '';
                      if (id.isNotEmpty) _openAnotherChild(id);
                    },
                  ),
                  if (child != _children.last)
                    const Divider(color: ChildProfileColors.border),
                ],
              ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isUpdating || _isDeleting ? null : _addChild,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add Another Child'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ChildProfileColors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // PROFILE HERO
  // ==========================================================

  Widget _buildProfileHero() {
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

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Text(
            'YOUR LITTLE ONE. YOUR CARE.',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w800,
              color: ChildProfileColors.green,
            ),
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              const CircleAvatar(
                radius: 37,
                backgroundColor: Color(0xFFDDEDE3),

                child: Icon(
                  Icons.child_care_rounded,
                  size: 42,
                  color: ChildProfileColors.green,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Text(
                      _childName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: ChildProfileColors.navy,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      _calculateAge(_dateOfBirth),

                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ChildProfileColors.green,
                      ),
                    ),

                    const SizedBox(height: 4),

                    const Text(
                      'Child Health Profile',
                      style: TextStyle(
                        fontSize: 11,
                        color: ChildProfileColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.all(12),

            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),

            child: const Row(
              children: [
                Icon(
                  Icons.favorite_outline_rounded,
                  size: 18,
                  color: ChildProfileColors.pink,
                ),

                SizedBox(width: 9),

                Expanded(
                  child: Text(
                    'Growing healthy, one little step '
                        'at a time.',

                    style: TextStyle(
                      fontSize: 12,
                      color: ChildProfileColors.text,
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

  // ==========================================================
  // REUSABLE SECTION CARD
  // ==========================================================

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget content,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),

        border: Border.all(
          color: ChildProfileColors.border,
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
                  color: ChildProfileColors.lightGreen,
                  borderRadius: BorderRadius.circular(11),
                ),

                child: Icon(
                  icon,
                  size: 22,
                  color: ChildProfileColors.green,
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
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: ChildProfileColors.navy,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,

                      style: const TextStyle(
                        fontSize: 11,
                        color: ChildProfileColors.muted,
                      ),
                    ),
                  ],
                ),
              ),

              if (trailing != null) trailing,
            ],
          ),

          const SizedBox(height: 17),

          content,
        ],
      ),
    );
  }

  // ==========================================================
  // REUSABLE DETAIL ROW
  // ==========================================================

  Widget _detailRow({
    required String label,
    required String value,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 9,
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 17,
              color: ChildProfileColors.green,
            ),

            const SizedBox(width: 8),
          ],

          SizedBox(
            width: 100,

            child: Text(
              label,

              style: const TextStyle(
                fontSize: 12,
                color: ChildProfileColors.muted,
              ),
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: SelectableText(
              value,

              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ChildProfileColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // BASIC INFORMATION
  // ==========================================================

  Widget _buildBasicInformation() {
    return _sectionCard(
      title: 'Basic Information',
      subtitle: 'Registered child details',
      icon: Icons.badge_outlined,

      content: Column(
        children: [
          _detailRow(
            label: 'Full Name',
            value: _childName,
            icon: Icons.person_outline_rounded,
          ),

          const Divider(
            color: ChildProfileColors.border,
          ),

          _detailRow(
            label: 'Birth Date',
            value: _formatDate(_dateOfBirth),
            icon: Icons.cake_outlined,
          ),

          const Divider(
            color: ChildProfileColors.border,
          ),

          _detailRow(
            label: 'Age',
            value: _calculateAge(_dateOfBirth),
            icon: Icons.calendar_today_outlined,
          ),

          const Divider(
            color: ChildProfileColors.border,
          ),

          _detailRow(
            label: 'Profile Type',

            value: _stringValue(
              _profile?['profile_type'],
              fallback: 'Member',
            ),

            icon: Icons.family_restroom_outlined,
          ),

          const Divider(
            color: ChildProfileColors.border,
          ),

          _detailRow(
            label: 'Created On',

            value: _formatServerDate(
              _profile?['created_at'],
            ),

            icon: Icons.event_available_outlined,
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // GUARDIAN INFORMATION
  // ==========================================================

  Widget _buildGuardianInformation() {
    final parentId = _profile?['parent_profile_id'];

    final hasParent = parentId != null &&
        parentId.toString().trim().isNotEmpty;

    return _sectionCard(
      title: 'Guardian Information',
      subtitle: 'Family and guardian connection',
      icon: Icons.family_restroom_outlined,

      content: Column(
        children: [
          _detailRow(
            label: 'Guardian Name',
            value: _stringValue(_profile?['guardian_name']),
            icon: Icons.person_outline_rounded,
          ),
          const Divider(color: ChildProfileColors.border),
          _detailRow(
            label: 'Mobile',

            value: _stringValue(
              _profile?['guardian_contact'],
            ),

            icon: Icons.phone_android_outlined,
          ),

          const Divider(
            color: ChildProfileColors.border,
          ),

          _detailRow(
            label: 'Parent Profile',
            value: hasParent ? 'Connected' : 'Not linked',
            icon: Icons.people_outline_rounded,
          ),

          const SizedBox(height: 12),

          _infoBox(
            hasParent
                ? 'This child is linked to a parent '
                'profile in your account.'
                : 'A parent profile has not been linked. '
                'Guardian contact can still be used.',
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // EMERGENCY CONTACTS
  // ==========================================================

  Widget _buildEmergencyContacts() {
    final contacts = _emergencyContacts;

    return _sectionCard(
      title: 'Emergency Contacts',
      subtitle: 'People saved for emergencies',
      icon: Icons.contact_emergency_outlined,

      content: contacts.isEmpty
          ? _emptyState(
        icon: Icons.contact_phone_outlined,
        title: 'No emergency contacts',

        message:
        'No contacts have been saved for this child.',
      )
          : Column(
        children: [
          for (int index = 0;
          index < contacts.length;
          index++) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),

              decoration: BoxDecoration(
                color: ChildProfileColors.cream,
                borderRadius: BorderRadius.circular(12),

                border: Border.all(
                  color: ChildProfileColors.border,
                ),
              ),

              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,

                children: [
                  Text(
                    _stringValue(
                      contacts[index]['name'],
                      fallback:
                      'Emergency Contact ${index + 1}',
                    ),

                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ChildProfileColors.navy,
                    ),
                  ),

                  const SizedBox(height: 8),

                  _detailRow(
                    label: 'Relationship',

                    value: _stringValue(
                      contacts[index]['relationship'],
                    ),
                  ),

                  const Divider(
                    color: ChildProfileColors.border,
                  ),

                  _detailRow(
                    label: 'Mobile',

                    value: _stringValue(
                      contacts[index]['mobile_number'],
                    ),
                  ),
                ],
              ),
            ),

            if (index < contacts.length - 1)
              const SizedBox(height: 11),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // CONNECTED DOCTOR INFORMATION
  // ==========================================================

  Widget _buildDoctorInformation() {
    final doctor = _connectedDoctor;

    return _sectionCard(
      title: 'Connected Doctor',
      subtitle: 'Doctor associated with this child',
      icon: Icons.medical_services_outlined,

      content: doctor == null
          ? Column(
        children: [
          _emptyState(
            icon: Icons.medical_services_outlined,
            title: 'No doctor connected',

            message:
            'Use an approved doctor referral ID to connect.',
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,

            child: FilledButton.icon(
              onPressed: _isConnectingDoctor
                  ? null
                  : _showConnectDoctorDialog,

              icon: _isConnectingDoctor
                  ? const SizedBox(
                height: 17,
                width: 17,

                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(
                Icons.person_add_alt_1_rounded,
              ),

              label: Text(
                _isConnectingDoctor
                    ? 'Connecting...'
                    : 'Connect Doctor',
              ),

              style: FilledButton.styleFrom(
                backgroundColor:
                ChildProfileColors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      )
          : Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),

            decoration: BoxDecoration(
              color: ChildProfileColors.lightGreen,
              borderRadius: BorderRadius.circular(12),
            ),

            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white,

                  child: Icon(
                    Icons.medical_services_rounded,
                    color: ChildProfileColors.green,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,

                    children: [
                      Text(
                        _stringValue(
                          doctor['full_name'],
                          fallback: 'Connected Doctor',
                        ),

                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: ChildProfileColors.navy,
                        ),
                      ),

                      const SizedBox(height: 4),

                      const Text(
                        'Connected to child profile',

                        style: TextStyle(
                          fontSize: 11,
                          color: ChildProfileColors.green,
                        ),
                      ),
                    ],
                  ),
                ),

                const Icon(
                  Icons.verified_rounded,
                  color: ChildProfileColors.green,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _detailRow(
            label: 'Referral ID',

            value: _stringValue(
              doctor['referral_id'],
            ),
          ),

          const Divider(
            color: ChildProfileColors.border,
          ),

          _detailRow(
            label: 'Email',

            value: _stringValue(
              doctor['email'],
            ),
          ),

          const Divider(
            color: ChildProfileColors.border,
          ),

          _detailRow(
            label: 'Mobile',

            value: _stringValue(
              doctor['mobile_number'],
            ),
          ),

          const SizedBox(height: 12),

          _infoBox(
            'This doctor is linked to the child profile. '
                'Access to health information follows '
                'backend permissions.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              OutlinedButton.icon(
                onPressed: _loadingDoctorOverview ? null : _showDoctorOverview,
                icon: const Icon(Icons.medical_information_outlined),
                label: Text(_loadingDoctorOverview ? 'Loading...' : 'Doctor Care Overview'),
              ),
              TextButton.icon(
                onPressed: _isDisconnectingDoctor ? null : _disconnectDoctor,
                icon: const Icon(Icons.link_off_rounded, color: ChildProfileColors.error),
                label: const Text('Disconnect Doctor',
                    style: TextStyle(color: ChildProfileColors.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CHILD HEALTHCARE SERVICES
  // ==========================================================

  Widget _buildQuickAccess() {
    const services = <_ChildService>[
      _ChildService(
        'Vaccination',
        'Doses & schedules',
        Icons.vaccines_outlined,
        ChildProfileColors.green,
        'vaccination',
      ),

      _ChildService(
        'Medical History',
        'Past health records',
        Icons.assignment_outlined,
        ChildProfileColors.purple,
        'medical-history',
      ),

      _ChildService(
        'Growth & Nutrition',
        'Height, weight & BMI',
        Icons.monitor_weight_outlined,
        ChildProfileColors.blue,
        'growth',
      ),

      _ChildService(
        'Doctor Consultation',
        'Connected care',
        Icons.medical_services_outlined,
        ChildProfileColors.orange,
        'doctor-consultation',
      ),

      _ChildService(
        'Child Care & Notes',
        'Daily observations',
        Icons.favorite_outline_rounded,
        ChildProfileColors.pink,
        'care-notes',
      ),

      _ChildService(
        'Health Reports',
        'Saved medical reports',
        Icons.description_outlined,
        ChildProfileColors.green,
        'health-reports',
      ),
    ];

    return _sectionCard(
      title: 'Healthcare Services',
      subtitle: 'Choose a service for this child',
      icon: Icons.grid_view_rounded,

      content: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;

          final columns = availableWidth >= 850
              ? 3
              : availableWidth >= 500
              ? 2
              : 1;

          const gap = 10.0;

          final itemWidth =
              (availableWidth - gap * (columns - 1)) /
                  columns;

          return Wrap(
            spacing: gap,
            runSpacing: gap,

            children: [
              for (final service in services)
                SizedBox(
                  width: itemWidth,
                  child: _buildServiceCard(service),
                ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================================
  // SINGLE SERVICE CARD
  // ==========================================================

  Widget _buildServiceCard(_ChildService service) {
    return Material(
      color: ChildProfileColors.cream,
      borderRadius: BorderRadius.circular(13),

      child: InkWell(
        borderRadius: BorderRadius.circular(13),

        onTap: () {
          _openSection(service.section);
        },

        child: Container(
          constraints: const BoxConstraints(
            minHeight: 87,
          ),

          padding: const EdgeInsets.all(12),

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),

            border: Border.all(
              color: ChildProfileColors.border,
            ),
          ),

          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),

                decoration: BoxDecoration(
                  color: ChildProfileColors.lightBlue,
                  borderRadius: BorderRadius.circular(11),
                ),

                child: Icon(
                  service.icon,
                  size: 22,
                  color: service.color,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  mainAxisAlignment:
                  MainAxisAlignment.center,

                  children: [
                    Text(
                      service.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: ChildProfileColors.text,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      service.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(
                        fontSize: 10,
                        color: ChildProfileColors.muted,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 5),

              Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: service.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // HEALTH REPORTS SUMMARY
  // ==========================================================

  Widget _buildHealthReports() {
    return _sectionCard(
      title: 'Health Reports',
      subtitle: 'Recent medical report uploads',
      icon: Icons.description_outlined,

      trailing: IconButton(
        tooltip: 'Refresh Reports',

        onPressed: _loadingReports || _isLoading
            ? null
            : () {
          _loadReportSummary();
        },

        icon: const Icon(
          Icons.refresh_rounded,
          color: ChildProfileColors.green,
        ),
      ),

      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),

            decoration: BoxDecoration(
              color: ChildProfileColors.lightBlue,
              borderRadius: BorderRadius.circular(12),
            ),

            child: Row(
              children: [
                const Icon(
                  Icons.folder_copy_outlined,
                  size: 27,
                  color: ChildProfileColors.blue,
                ),

                const SizedBox(width: 13),

                Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    const Text(
                      'Total Reports',

                      style: TextStyle(
                        fontSize: 11,
                        color: ChildProfileColors.muted,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _loadingReports
                          ? 'Loading...'
                          : _reportsError != null
                          ? 'Unavailable'
                          : '$_reportCount',

                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: ChildProfileColors.navy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 15),

          if (_loadingReports)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(18),

                child: CircularProgressIndicator(
                  color: ChildProfileColors.green,
                ),
              ),
            )
          else if (_reportsError != null)
            _infoBox(
              'Reports could not be loaded. '
                  'Tap refresh to retry.',
            )
          else if (_recentReports.isEmpty)
              _emptyState(
                icon: Icons.folder_open_outlined,
                title: 'No reports uploaded',

                message:
                'Reports uploaded for this child will appear here.',
              )
            else
              Column(
                children: [
                  for (final report in _recentReports)
                    Container(
                      margin: const EdgeInsets.only(
                        bottom: 10,
                      ),

                      padding: const EdgeInsets.all(12),

                      decoration: BoxDecoration(
                        color: ChildProfileColors.cream,
                        borderRadius: BorderRadius.circular(12),

                        border: Border.all(
                          color: ChildProfileColors.border,
                        ),
                      ),

                      child: Row(
                        children: [
                          const Icon(
                            Icons.insert_drive_file_outlined,
                            size: 24,
                            color: ChildProfileColors.green,
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,

                              children: [
                                Text(
                                  _stringValue(
                                    report['name'],
                                    fallback: 'Medical Report',
                                  ),

                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,

                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: ChildProfileColors.text,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                Text(
                                  _formatServerDate(
                                    report['created_at'],
                                  ),

                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: ChildProfileColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,

            child: OutlinedButton.icon(
              onPressed: () {
                _openSection('health-reports');
              },

              icon: const Icon(
                Icons.arrow_forward_rounded,
              ),

              label: const Text(
                'View All Health Reports',
              ),

              style: OutlinedButton.styleFrom(
                foregroundColor: ChildProfileColors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // EMPTY STATE
  // ==========================================================

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 22,
      ),

      decoration: BoxDecoration(
        color: ChildProfileColors.cream,
        borderRadius: BorderRadius.circular(12),

        border: Border.all(
          color: ChildProfileColors.border,
        ),
      ),

      child: Column(
        children: [
          Icon(
            icon,
            size: 32,
            color: ChildProfileColors.green,
          ),

          const SizedBox(height: 9),

          Text(
            title,
            textAlign: TextAlign.center,

            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ChildProfileColors.navy,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            message,
            textAlign: TextAlign.center,

            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: ChildProfileColors.muted,
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
      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(
        color: ChildProfileColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: ChildProfileColors.green,
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              message,

              style: const TextStyle(
                fontSize: 11,
                height: 1.5,
                color: ChildProfileColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CHILD SERVICE MODEL
// ============================================================

class _ChildService {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String section;

  const _ChildService(
      this.title,
      this.subtitle,
      this.icon,
      this.color,
      this.section,
      );
}

// ============================================================
// DOCTOR REFERRAL DIALOG
// ============================================================

class _ChildDoctorReferralDialog extends StatefulWidget {
  const _ChildDoctorReferralDialog();

  @override
  State<_ChildDoctorReferralDialog> createState() =>
      _ChildDoctorReferralDialogState();
}

// ============================================================
// DOCTOR REFERRAL DIALOG STATE
// ============================================================

class _ChildDoctorReferralDialogState
    extends State<_ChildDoctorReferralDialog> {
  final GlobalKey<FormState> _formKey =
  GlobalKey<FormState>();

  final TextEditingController _referralController =
  TextEditingController();

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _referralController.dispose();
    super.dispose();
  }

  // ==========================================================
  // SUBMIT REFERRAL ID
  // ==========================================================

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(
      _referralController.text.trim(),
    );
  }

  // ==========================================================
  // DIALOG BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),

      title: const Text(
        'Connect Doctor',

        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: ChildProfileColors.navy,
        ),
      ),

      content: SingleChildScrollView(
        child: SizedBox(
          width: 340,

          child: Form(
            key: _formKey,

            child: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                const Text(
                  'Enter the referral ID of an approved '
                      'FamilyCare+ doctor.',

                  style: TextStyle(
                    color: ChildProfileColors.muted,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _referralController,
                  autofocus: true,

                  textCapitalization:
                  TextCapitalization.characters,

                  textInputAction: TextInputAction.done,

                  onFieldSubmitted: (_) {
                    _submit();
                  },

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
                      color: ChildProfileColors.green,
                    ),

                    border: OutlineInputBorder(
                      borderRadius:
                      BorderRadius.circular(12),
                    ),
                  ),

                  validator: (value) {
                    final referralId =
                    (value ?? '').trim();

                    if (!RegExp(
                      r'^[A-Za-z0-9]{1,160}$',
                    ).hasMatch(referralId)) {
                      return 'Enter a valid referral ID';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 13),

                const Text(
                  'Connecting a doctor may give them access '
                      'to linked care information and medical '
                      'reports under backend permissions.',

                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: ChildProfileColors.muted,
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
            backgroundColor: ChildProfileColors.green,
            foregroundColor: Colors.white,
          ),

          child: const Text('Connect Doctor'),
        ),
      ],
    );
  }
}

// ============================================================
// EDIT CHILD PROFILE DIALOG - FULL BACKEND V5 PAYLOAD
// ============================================================

class _EditableEmergencyContact {
  final TextEditingController name;
  final TextEditingController mobile;
  final TextEditingController relationship;

  _EditableEmergencyContact({Map<String, dynamic>? initial})
      : name = TextEditingController(text: '${initial?['name'] ?? ''}'),
        mobile = TextEditingController(text: '${initial?['mobile_number'] ?? ''}'),
        relationship = TextEditingController(text: '${initial?['relationship'] ?? ''}');

  Map<String, dynamic> toJson() => {
    'name': name.text.trim(),
    'mobile_number': mobile.text.trim(),
    'relationship': relationship.text.trim(),
  };

  void dispose() {
    name.dispose();
    mobile.dispose();
    relationship.dispose();
  }
}

class _ChildProfileEditDialog extends StatefulWidget {
  final Map<String, dynamic> profile;

  const _ChildProfileEditDialog({required this.profile});

  @override
  State<_ChildProfileEditDialog> createState() => _ChildProfileEditDialogState();
}

class _ChildProfileEditDialogState extends State<_ChildProfileEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _guardianName;
  late final TextEditingController _guardianMobile;
  final List<_EditableEmergencyContact> _contacts = [];
  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: '${widget.profile['full_name'] ?? ''}');
    _guardianName = TextEditingController(text: '${widget.profile['guardian_name'] ?? ''}');
    _guardianMobile = TextEditingController(text: '${widget.profile['guardian_contact'] ?? ''}');
    _birthDate = DateTime.tryParse('${widget.profile['date_of_birth'] ?? ''}');
    final contacts = widget.profile['emergency_contacts'];
    if (contacts is List) {
      for (final entry in contacts.take(5)) {
        if (entry is Map) {
          _contacts.add(_EditableEmergencyContact(
            initial: Map<String, dynamic>.from(entry),
          ));
        }
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _guardianName.dispose();
    _guardianMobile.dispose();
    for (final contact in _contacts) {
      contact.dispose();
    }
    super.dispose();
  }

  DateTime get _today => DateUtils.dateOnly(DateTime.now());

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

  String? _nameValidation(String? input) {
    final value = (input ?? '').trim();
    if (value.isEmpty) return 'Name required';
    if (value.length > 120) return 'Maximum 120 characters';
    return null;
  }

  String? _optionalNameValidation(String? input) {
    if ((input ?? '').trim().length > 120) return 'Maximum 120 characters';
    return null;
  }

  String? _mobileValidation(String? input, {bool required = false}) {
    final value = (input ?? '').trim();
    if (value.isEmpty && !required) return null;
    if (!RegExp(r'^\+?[1-9][0-9]{7,14}$').hasMatch(value)) {
      return 'Enter mobile with country code, e.g. +919876543210';
    }
    return null;
  }

  Future<void> _selectDob() async {
    final now = _today;
    final first = DateTime(now.year - 13, now.month, now.day)
        .add(const Duration(days: 1));
    final initial = _birthDate != null && !_birthDate!.isBefore(first)
        && !_birthDate!.isAfter(now) ? _birthDate! : now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: now,
      helpText: 'CHILD DATE OF BIRTH',
    );
    if (date != null && mounted) setState(() => _birthDate = date);
  }

  void _addContact() {
    if (_contacts.length >= 5) return;
    setState(() => _contacts.add(_EditableEmergencyContact()));
  }

  void _removeContact(_EditableEmergencyContact contact) {
    setState(() => _contacts.remove(contact));
    WidgetsBinding.instance.addPostFrameCallback((_) => contact.dispose());
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final dob = _birthDate;
    if (dob == null || dob.isAfter(_today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid date of birth.')),
      );
      return;
    }
    final age = _today.year - dob.year -
        ((_today.month < dob.month ||
            (_today.month == dob.month && _today.day < dob.day)) ? 1 : 0);
    if (age > 12 || age < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Child age must be 0 to 12 years.')),
      );
      return;
    }
    Navigator.of(context).pop(<String, dynamic>{
      'full_name': _name.text.trim(),
      'date_of_birth': _isoDate(dob),
      'guardian_name': _guardianName.text.trim(),
      'guardian_contact': _guardianMobile.text.trim(),
      'emergency_contacts': _contacts.map((entry) => entry.toJson()).toList(),
    });
  }

  Widget _field(
      TextEditingController controller,
      String label, {
        String? Function(String?)? validator,
        TextInputType keyboardType = TextInputType.text,
        int? maxLength,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _contactCard(_EditableEmergencyContact contact, int index) {
    return Container(
      key: ObjectKey(contact),
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: ChildProfileColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: Text('Emergency Contact ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton(
              tooltip: 'Remove emergency contact',
              onPressed: () => _removeContact(contact),
              icon: const Icon(Icons.close, color: ChildProfileColors.error),
            ),
          ]),
          _field(contact.name, 'Name', validator: _nameValidation,
              maxLength: 120),
          _field(contact.relationship, 'Relationship',
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Relationship required'
                  : (value ?? '').trim().length > 50
                  ? 'Maximum 50 characters' : null,
              maxLength: 50),
          _field(contact.mobile, 'Mobile number (country code)',
              keyboardType: TextInputType.phone,
              validator: (value) => _mobileValidation(value, required: true),
              maxLength: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Edit Child Profile'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Changes will update this child in your account. '
                    'All existing emergency contacts are loaded for editing.',
                    style: TextStyle(fontSize: 11, color: ChildProfileColors.muted)),
                const SizedBox(height: 14),
                _field(_name, 'Child full name', validator: _nameValidation,
                    maxLength: 120),
                OutlinedButton.icon(
                  onPressed: _selectDob,
                  icon: const Icon(Icons.cake_outlined),
                  label: Text(_birthDate == null
                      ? 'Select Date of Birth' : _isoDate(_birthDate!)),
                ),
                const SizedBox(height: 14),
                _field(_guardianName, 'Guardian full name',
                    validator: _optionalNameValidation, maxLength: 120),
                _field(_guardianMobile, 'Guardian mobile (with country code)',
                    keyboardType: TextInputType.phone,
                    validator: (value) => _mobileValidation(value),
                    maxLength: 20),
                const Divider(height: 26),
                Row(children: [
                  const Expanded(child: Text('Emergency Contacts',
                      style: TextStyle(fontWeight: FontWeight.w800))),
                  TextButton.icon(
                    onPressed: _contacts.length >= 5 ? null : _addContact,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                  ),
                ]),
                if (_contacts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No emergency contacts.',
                        style: TextStyle(color: ChildProfileColors.muted)),
                  ),
                for (var i = 0; i < _contacts.length; i++)
                  _contactCard(_contacts[i], i),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}
