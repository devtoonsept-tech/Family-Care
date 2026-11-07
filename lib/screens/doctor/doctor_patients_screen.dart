
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';
import 'doctor_child_care_screen.dart';
import 'doctor_vaccination_screen.dart';
import 'doctor_consultation_screen.dart';
import 'doctor_clinical_records_screen.dart';
import 'doctor_prescriptions_screen.dart';
import 'doctor_reports_screen.dart';

class DoctorPatientsScreen extends StatefulWidget {
  const DoctorPatientsScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.onBack,
    this.onOpenSection,
  });

  final String apiBaseUrl;
  final VoidCallback? onBack;
  final void Function(Map<String, dynamic> profile, String section)?
  onOpenSection;

  @override
  State<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
}

class _PatientColors {
  static const ink = Color(0xFF264A51);
  static const green = Color(0xFF367D69);
  static const blue = Color(0xFF477F99);
  static const mint = Color(0xFFE8F7EF);
  static const ice = Color(0xFFECF5FA);
  static const page = Color(0xFFF6FAF9);
  static const border = Color(0xFFDCEAE7);
  static const muted = Color(0xFF70848A);
  static const danger = Color(0xFFAE555B);
}

class _PatientApiError implements Exception {
  const _PatientApiError(this.message, [this.status = 0]);

  final String message;
  final int status;

  @override
  String toString() => message;
}

String _pt(dynamic value) => (value ?? '').toString().trim();

Map<String, dynamic> _pm(dynamic value) => value is Map
    ? Map<String, dynamic>.from(value)
    : <String, dynamic>{};

List<Map<String, dynamic>> _pl(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

int _pn(dynamic value, [int fallback = 0]) => value is num
    ? value.toInt()
    : int.tryParse(_pt(value)) ?? fallback;

class _DoctorPatientsScreenState extends State<DoctorPatientsScreen> {
  static const _pageSize = 20;

  final _client = http.Client();
  final _search = TextEditingController();

  bool _checking = true;
  bool _approved = false;
  bool _profilesTab = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _opening = false;
  bool _navigating = false;

  String _doctorId = '';
  String _module = 'all';
  String? _authError;
  String? _listError;
  String? _sharedWarning;

  int _authVersion = 0;
  int _listVersion = 0;
  int _openVersion = 0;
  int _accountsPage = 0;
  int _accountsTotal = 0;
  int _carePage = 0;
  int _careTotal = 0;

  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _legacyCare = [];
  List<Map<String, dynamic>> _sharedAdults = [];
  List<Map<String, dynamic>> _sharedWomen = [];

  String get _base {
    var value = widget.apiBaseUrl.trim();

    if (value.isEmpty) {
      value = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:5001'
          : 'http://127.0.0.1:5001';
    }

    value = value.replaceFirst(RegExp(r'/+$'), '');

    for (final suffix in ['/api/v1/doctors', '/api/v1']) {
      if (value.endsWith(suffix)) {
        return value.substring(0, value.length - suffix.length);
      }
    }

    return value;
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    _verify();
  }

  @override
  void didUpdateWidget(covariant DoctorPatientsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) _verify();
  }

  @override
  void dispose() {
    _authVersion++;
    _listVersion++;
    _openVersion++;
    _search.removeListener(_onSearch);
    _search.dispose();
    _client.close();
    super.dispose();
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  String _friendly(Object error) {
    if (error is _PatientApiError) return error.message;
    if (error is TimeoutException) return 'Request timed out. Please retry.';
    if (error is http.ClientException) {
      return 'Unable to reach FamilyCare+. Check your connection.';
    }
    if (error is FormatException) return 'Unexpected server response.';
    return 'Unable to complete this request. Please try again.';
  }

  void _notice(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? _PatientColors.danger : _PatientColors.ink,
        ),
      );
  }

  Future<Map<String, dynamic>> _get(
      String path, {
        Map<String, String>? query,
      }) async {
    final role = await FamilyCareSession.role();
    final token = await FamilyCareSession.accessToken();
    final expiry = await FamilyCareSession.accessTokenExpiresAt();

    if (_pt(role).toUpperCase() != 'DOCTOR' ||
        token == null ||
        token.trim().isEmpty ||
        expiry == null ||
        !expiry.isAfter(DateTime.now().toUtc())) {
      throw const _PatientApiError(
        'Doctor session expired. Please sign in again.',
        401,
      );
    }

    final url = Uri.parse('$_base$path').replace(queryParameters: query);
    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'X-Auth-Transport': 'bearer',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 30));

    Map<String, dynamic> body = {};
    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) {
          body = Map<String, dynamic>.from(decoded);
        } else if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const FormatException('Expected JSON object.');
        }
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final issue = body['error'];
      final server = issue is Map ? _pt(issue['message']) : _pt(issue);
      final fallback = switch (response.statusCode) {
        401 => 'Session expired or revoked. Sign in again.',
        403 => 'Access missing, expired or revoked.',
        404 => 'Patient or care profile unavailable.',
        409 => 'The record changed. Refresh and retry.',
        429 => 'Too many requests. Try again shortly.',
        _ => 'Request failed (HTTP ${response.statusCode}).',
      };
      throw _PatientApiError(
        server.isNotEmpty ? server : fallback,
        response.statusCode,
      );
    }

    if (body.isEmpty) throw const FormatException('Empty JSON response.');
    return body;
  }

  void _block(String message) {
    _authVersion++;
    _listVersion++;
    _openVersion++;
    if (!mounted) return;
    setState(() {
      _checking = false;
      _approved = false;
      _loading = false;
      _loadingMore = false;
      _opening = false;
      _authError = message;
      _accounts = [];
      _legacyCare = [];
      _sharedAdults = [];
      _sharedWomen = [];
    });
  }

  Future<void> _verify() async {
    final version = ++_authVersion;
    _listVersion++;
    _openVersion++;

    setState(() {
      _checking = true;
      _approved = false;
      _loading = false;
      _loadingMore = false;
      _authError = null;
      _listError = null;
      _sharedWarning = null;
      _accounts = [];
      _legacyCare = [];
      _sharedAdults = [];
      _sharedWomen = [];
      _accountsPage = 0;
      _accountsTotal = 0;
      _carePage = 0;
      _careTotal = 0;
    });

    try {
      final response = await _get('/api/v1/doctors/me');
      final user = _pm(response['user']);
      if (_pt(user['role']).toUpperCase() != 'DOCTOR' ||
          _pt(user['approval_status']).toUpperCase() != 'APPROVED' ||
          _pt(user['account_status']).toUpperCase() != 'ACTIVE' ||
          _pt(user['id']).isEmpty) {
        throw const _PatientApiError(
          'Only approved and active doctors can view connected patients.',
          403,
        );
      }

      if (!mounted || version != _authVersion) return;
      setState(() {
        _doctorId = _pt(user['id']);
        _checking = false;
        _approved = true;
      });
      await _load(reset: true);
    } catch (error) {
      if (mounted && version == _authVersion) _block(_friendly(error));
    }
  }

  Future<Map<String, dynamic>> _safeGet(
      String path, {
        Map<String, String>? query,
      }) async {
    try {
      return {'data': await _get(path, query: query)};
    } catch (error) {
      return {'error': error};
    }
  }

  Future<void> _load({required bool reset}) async {
    if (!_approved || _loading || _loadingMore || _opening) return;
    final version = ++_listVersion;
    final profiles = _profilesTab;
    final page = reset
        ? 1
        : (profiles ? _carePage : _accountsPage) + 1;

    setState(() {
      _loading = reset;
      _loadingMore = !reset;
      _listError = null;
      if (reset) {
        if (profiles) {
          _legacyCare = [];
          _sharedAdults = [];
          _sharedWomen = [];
          _carePage = 0;
          _careTotal = 0;
          _sharedWarning = null;
        } else {
          _accounts = [];
          _accountsPage = 0;
          _accountsTotal = 0;
        }
      }
    });

    try {
      if (!profiles) {
        final response = await _get(
          '/api/v1/doctors/patients',
          query: {'page': '$page', 'per_page': '$_pageSize'},
        );
        if (response['items'] is! List) {
          throw const FormatException('Invalid connected patients list.');
        }
        if (!mounted || version != _listVersion || _profilesTab) return;
        setState(() {
          final unique = <String>{};
          _accounts = [
            if (!reset) ..._accounts,
            ..._pl(response['items']),
          ].where((p) => _pt(p['id']).isNotEmpty && unique.add(_pt(p['id'])))
              .toList();
          _accountsPage = page;
          _accountsTotal = _pn(response['total'], _accounts.length);
        });
      } else {
        // The standard Doctor directory lists Child and legacy Adult profiles.
        // Explicit Adult/Women tab sharing is listed by separate APIs.
        final tasks = <Future<Map<String, dynamic>>>[
          _safeGet(
            '/api/v1/doctors/care-profiles',
            query: {'page': '$page', 'per_page': '$_pageSize'},
          ),
          if (reset) _safeGet('/api/v1/adult-access/shared'),
          if (reset) _safeGet('/api/v1/women/shared'),
        ];
        final responses = await Future.wait(tasks);
        if (!mounted || version != _listVersion || !_profilesTab) return;

        for (final result in responses) {
          final error = result['error'];
          if (error is _PatientApiError && error.status == 401) {
            _block(_friendly(error));
            return;
          }
        }

        final legacy = _pm(responses[0]['data']);
        final generalError = responses[0]['error'];
        final warnings = <String>[];

        if (generalError != null) {
          warnings.add('Care profiles: ${_friendly(generalError)}');
        } else if (legacy['items'] is! List) {
          warnings.add('Care profiles: invalid list response.');
        }

        if (reset) {
          for (var i = 1; i < 3; i++) {
            final label = i == 1 ? 'Adult sharing' : 'Women sharing';
            final error = responses[i]['error'];
            final payload = _pm(responses[i]['data']);
            if (error != null) {
              warnings.add('$label: ${_friendly(error)}');
            } else if (payload['items'] is! List) {
              warnings.add('$label: invalid list response.');
            }
          }
        }

        setState(() {
          if (generalError == null && legacy['items'] is List) {
            final unique = <String>{};
            _legacyCare = [
              if (!reset) ..._legacyCare,
              ..._pl(legacy['items']),
            ].where((p) => _pt(p['id']).isNotEmpty && unique.add(_pt(p['id'])))
                .toList();
            _carePage = page;
            _careTotal = _pn(legacy['total'], _legacyCare.length);
          }

          if (reset) {
            final adult = _pm(responses[1]['data']);
            final women = _pm(responses[2]['data']);
            _sharedAdults = adult['items'] is List ? _pl(adult['items']) : [];
            _sharedWomen = women['items'] is List ? _pl(women['items']) : [];
            _sharedWarning = warnings.isEmpty ? null : warnings.join('\n');
          } else if (warnings.isNotEmpty) {
            _listError = warnings.join('\n');
          }
        });
      }
    } catch (error) {
      if (!mounted || version != _listVersion) return;
      if (error is _PatientApiError && error.status == 401) {
        _block(_friendly(error));
      } else {
        setState(() => _listError = _friendly(error));
      }
    } finally {
      if (mounted && version == _listVersion) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _switchTab(bool profiles) {
    if (_profilesTab == profiles || !_approved || _opening) return;
    _listVersion++;
    setState(() {
      _profilesTab = profiles;
      _module = 'all';
      _search.clear();
      _loading = false;
      _loadingMore = false;
      _listError = null;
    });
    _load(reset: true);
  }

  List<Map<String, dynamic>> get _careItems {
    final merged = <String, Map<String, dynamic>>{};

    for (final profile in _legacyCare) {
      final id = _pt(profile['id']);
      if (id.isNotEmpty && _pt(profile['module']) != 'women') {
        merged[id] = {...profile, '_workspace': 'legacy'};
      }
    }

    for (final profile in _sharedAdults) {
      final id = _pt(profile['id']);
      if (id.isEmpty) continue;
      merged[id] = {
        ...?merged[id],
        'id': id,
        'full_name': _pt(profile['name']).isNotEmpty
            ? profile['name']
            : merged[id]?['full_name'],
        'module': 'adult',
        'permissions': _pm(profile['permissions']),
        '_workspace': 'adult',
      };
    }

    for (final profile in _sharedWomen) {
      final id = _pt(profile['id']);
      if (id.isEmpty) continue;
      merged[id] = {
        'id': id,
        'full_name': _pt(profile['name']),
        'module': 'women',
        'permissions': _pm(profile['permissions']),
        '_workspace': 'women',
      };
    }

    return merged.values.toList();
  }

  List<Map<String, dynamic>> get _visible {
    final query = _search.text.toLowerCase().trim();
    final source = _profilesTab ? _careItems : _accounts;
    return source.where((item) {
      if (_profilesTab &&
          _module != 'all' &&
          _pt(item['module']).toLowerCase() != _module) {
        return false;
      }
      if (query.isEmpty) return true;
      return [
        item['full_name'],
        item['email'],
        item['phone_number'],
        item['guardian_name'],
        item['module'],
        item['profile_type'],
      ].any((field) => _pt(field).toLowerCase().contains(query));
    }).toList();
  }

  bool get _hasMore => _profilesTab
      ? _carePage * _pageSize < _careTotal
      : _accountsPage * _pageSize < _accountsTotal;

  bool _legacyScope(Map<String, dynamic> profile, String scope) {
    final module = _pt(profile['module']).toLowerCase();
    if (module == 'child') return true;
    if (module != 'adult') return false;

    final grant = _pm(profile['access_permissions']);
    // Backend legacy doctor access can exist without a configured grant.
    if (grant.isEmpty) return true;
    if (grant['active'] != true ||
        _pt(grant['doctor_id']) != _doctorId) return false;

    final expiry = DateTime.tryParse(_pt(grant['expires_at']));
    if (expiry != null && !expiry.toUtc().isAfter(DateTime.now().toUtc())) {
      return false;
    }
    final scopes = grant['scopes'];
    return scopes is List && scopes.contains(scope);
  }

  Future<void> _openProfile(Map<String, dynamic> summary) async {
    if (_opening || _navigating || !_approved) return;
    final id = _pt(summary['id']);
    if (id.isEmpty) return;
    final version = ++_openVersion;
    setState(() => _opening = true);

    try {
      final workspace = _pt(summary['_workspace']);
      if (workspace == 'adult' || workspace == 'women') {
        final result = await _get(
          '/api/v1/${workspace == 'adult' ? 'adult-access' : 'women'}/'
              'profiles/${Uri.encodeComponent(id)}/workspace',
        );
        if (!mounted || version != _openVersion) return;
        final profile = _pm(result['profile']);
        final permissions = _pm(result['permissions']);
        if (_pt(profile['id']) != id || permissions.isEmpty) {
          throw const _PatientApiError('Private workspace access unavailable.', 403);
        }
        setState(() => _opening = false);
        await _showScopedWorkspace(
          summary: summary,
          profile: profile,
          permissions: permissions,
          records: _pl(result['records']),
          expiresAt: _pt(result['access_expires_at']),
        );
      } else {
        final result = await _get(
          '/api/v1/doctors/care-profiles/${Uri.encodeComponent(id)}',
        );
        if (!mounted || version != _openVersion) return;
        final profile = _pm(result['profile']);
        final module = _pt(profile['module']).toLowerCase();
        if (_pt(profile['id']) != id ||
            (module != 'child' && module != 'adult')) {
          throw const _PatientApiError('This profile is not accessible.', 403);
        }
        if (module == 'adult' &&
            !_legacyScope(profile, 'records') &&
            !_legacyScope(profile, 'reports')) {
          throw const _PatientApiError('No active Adult record/report scope.', 403);
        }
        setState(() => _opening = false);
        await _showLegacyProfile(profile);
      }
    } catch (error) {
      if (!mounted || version != _openVersion) return;
      if (error is _PatientApiError && error.status == 401) {
        _block(_friendly(error));
      } else {
        _notice(_friendly(error), error: true);
      }
    } finally {
      if (mounted && version == _openVersion) {
        setState(() => _opening = false);
      }
    }
  }

  Future<void> _navigate(
      Map<String, dynamic> profile,
      String section,
      ) async {
    if (!mounted || _navigating || !_approved) return;

    setState(() => _navigating = true);
    try {
      if (widget.onOpenSection != null) {
        widget.onOpenSection!(profile, section);
        return;
      }

      final module = _pt(profile['module']).toLowerCase();
      Widget screen;
      switch (section) {
        case 'records':
          screen = DoctorClinicalRecordsScreen(
            apiBaseUrl: _base,
            initialProfile: profile,
          );
        case 'reports':
          screen = DoctorReportsScreen(
            apiBaseUrl: _base,
            initialProfile: profile,
          );
        case 'prescriptions':
          screen = DoctorPrescriptionsScreen(
            apiBaseUrl: _base,
            initialProfile: profile,
          );
        case 'vaccination':
          if (module != 'child') return;
          screen = DoctorVaccinationScreen(
            apiBaseUrl: _base,
            initialChild: profile,
          );
        case 'child-care':
          if (module != 'child') return;
          screen = DoctorChildCareScreen(
            apiBaseUrl: _base,
            initialChild: profile,
          );
        case 'consultation':
          screen = DoctorConsultationScreen(
            apiBaseUrl: _base,
            initialChild: profile,
          );
        default:
          throw const _PatientApiError('Section not connected.');
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => screen),
      );
    } catch (error) {
      _notice(_friendly(error), error: true);
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  void _openFromSheet(
      BuildContext sheetContext,
      Map<String, dynamic> profile,
      String section,
      ) {
    Navigator.pop(sheetContext);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigate(profile, section);
    });
  }

  Future<void> _showLegacyProfile(Map<String, dynamic> profile) async {
    final module = _pt(profile['module']).toLowerCase();
    final child = module == 'child';
    final canRecords = _legacyScope(profile, 'records');
    final canReports = _legacyScope(profile, 'reports');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: _PatientColors.page,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * .84,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 27),
          children: [
            _sheetTitle(
              _pt(profile['full_name']).isEmpty
                  ? 'Care Profile'
                  : _pt(profile['full_name']),
              child ? 'Child Care' : 'Adult Health • Legacy sharing',
            ),
            const SizedBox(height: 13),
            _panel(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detail('Date of birth', profile['date_of_birth']),
                _detail('Gender', profile['gender']),
                _detail('Profile type', profile['profile_type']),
                if (child) ...[
                  _detail('Guardian', profile['guardian_name']),
                  _detail('Guardian contact', profile['guardian_contact']),
                ],
              ],
            )),
            const SizedBox(height: 14),
            const Text(
              'Available clinical modules',
              style: TextStyle(
                color: _PatientColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 9),
            _panel(const Text(
              'Only server-authorized modules can be opened. Every screen checks '
                  'patient permissions again before loading records.',
              style: TextStyle(
                color: _PatientColors.muted,
                fontSize: 12,
                height: 1.45,
              ),
            )),
            const SizedBox(height: 11),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canRecords)
                  _actionChip(sheet, profile, 'records', 'Clinical Records',
                      Icons.assignment_outlined),
                if (canReports)
                  _actionChip(sheet, profile, 'reports', 'Reports',
                      Icons.folder_open_outlined),
                if (child) ...[
                  _actionChip(sheet, profile, 'child-care', 'Child Care',
                      Icons.child_care_outlined),
                  _actionChip(sheet, profile, 'vaccination', 'Vaccination',
                      Icons.vaccines_outlined),
                  _actionChip(sheet, profile, 'prescriptions', 'Prescriptions',
                      Icons.medication_outlined),
                  _actionChip(sheet, profile, 'consultation', 'Consultations',
                      Icons.medical_services_outlined),
                ],
              ],
            ),
            if (!child && !canRecords && !canReports)
              const Text('No active clinical scopes available.'),
          ],
        ),
      ),
    );
  }

  Future<void> _showScopedWorkspace({
    required Map<String, dynamic> summary,
    required Map<String, dynamic> profile,
    required Map<String, dynamic> permissions,
    required List<Map<String, dynamic>> records,
    required String expiresAt,
  }) async {
    final module = _pt(summary['module']).toLowerCase();
    final name = _pt(profile['name']).isNotEmpty
        ? _pt(profile['name'])
        : _pt(summary['full_name']);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: _PatientColors.page,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * .88,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 5, 18, 28),
          children: [
            _sheetTitle(name, module == 'women'
                ? "Women's Health • Private workspace"
                : 'Adult Health • Private workspace'),
            const SizedBox(height: 12),
            _panel(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detail('Date of birth', profile['dob']),
                if (expiresAt.isNotEmpty)
                  _detail('Access expires', _date(expiresAt)),
                const Text(
                  'Access is determined by the active per-tab grant. '
                      'Unshared sections are not loaded.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _PatientColors.muted,
                    height: 1.45,
                  ),
                ),
              ],
            )),
            const SizedBox(height: 14),
            const Text(
              'Allowed health sections',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _PatientColors.ink,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final entry in permissions.entries)
                  Chip(
                    avatar: Icon(
                      _pt(entry.value) == 'edit'
                          ? Icons.edit_outlined
                          : Icons.visibility_outlined,
                      size: 15,
                      color: _PatientColors.green,
                    ),
                    label: Text('${_label(entry.key)} • ${_pt(entry.value)}'),
                    side: const BorderSide(color: _PatientColors.border),
                    backgroundColor: Colors.white,
                  ),
              ],
            ),
            if ((module == 'adult' &&
                const {'view', 'edit'}.contains(permissions['reports'])) ||
                (module == 'women' &&
                    const {'view', 'edit'}.contains(permissions['records']))) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _openFromSheet(
                  sheet,
                  {
                    ...summary,
                    'id': profile['id'],
                    'module': module,
                    'full_name': name,
                    'permissions': permissions,
                  },
                  'prescriptions',
                ),
                icon: const Icon(Icons.medication_outlined),
                label: const Text('Structured Prescriptions'),
              ),
            ],
            const SizedBox(height: 15),
            Text(
              'Shared clinical entries (${records.length})',
              style: const TextStyle(
                color: _PatientColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 9),
            if (records.isEmpty)
              _empty('No entries in the authorized sections yet.')
            else
              for (final record in records.take(50))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _workspaceRecord(record),
                ),
            if (records.length > 50)
              const Text(
                'Displaying the first 50 authorized entries in this preview.',
                style: TextStyle(fontSize: 11, color: _PatientColors.muted),
              ),
            const SizedBox(height: 9),
            const Text(
              'This preview is read-only. No record is modified or shared '
                  'outside its approved workspace.',
              style: TextStyle(
                color: _PatientColors.muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspaceRecord(Map<String, dynamic> record) {
    final details = _pm(record['data']);
    final fields = details.isNotEmpty ? details : record;
    final kind = _pt(record['kind']).isNotEmpty
        ? _pt(record['kind'])
        : _pt(record['section']);
    final title = _pt(fields['title']).isNotEmpty
        ? _pt(fields['title'])
        : _label(kind);
    final date = _pt(fields['date']);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _PatientColors.border),
        borderRadius: BorderRadius.circular(13),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.description_outlined,
            color: _PatientColors.blue),
        title: Text(title, style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          color: _PatientColors.ink,
        )),
        subtitle: Text(
          '${_label(kind)}${date.isEmpty ? '' : ' • $date'}',
          style: const TextStyle(fontSize: 11, color: _PatientColors.muted),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 11),
        children: [
          const Divider(color: _PatientColors.border),
          for (final field in fields.entries)
            if (!const {'id', 'profile_id', 'author_id', 'version'}
                .contains(field.key) && _pt(field.value).isNotEmpty)
              _detail(_label(field.key), field.value),
        ],
      ),
    );
  }

  String _label(String value) {
    const labels = {
      'bp': 'Blood Pressure',
      'glucose': 'Blood Sugar',
      'lipids': 'Cholesterol',
      'medicine': 'Medicines',
      'health': 'General Health',
      'cycle': 'Period & Cycle',
      'pcos': 'PCOS',
      'pregnancy': 'Pregnancy Care',
      'fertility': 'Fertility',
      'records': 'Medical Records',
      'reports': 'Medical Reports',
      'screening': 'Screening',
      'consultation_request': 'Consultation',
      'history': 'Medical History',
    };
    return labels[value] ??
        value.replaceAll('_', ' ').split(' ')
            .where((word) => word.isNotEmpty)
            .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
            .join(' ');
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(_pt(value))?.toLocal();
    if (parsed == null) return _pt(value);
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  void _showAccount(Map<String, dynamic> account) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: _PatientColors.page,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetTitle(
              _pt(account['full_name']).isEmpty
                  ? 'Patient Account'
                  : _pt(account['full_name']),
              'Connected patient • Account details only',
            ),
            const SizedBox(height: 12),
            _panel(Column(children: [
              _detail('Email', account['email']),
              _detail('Phone', account['phone_number']),
              _detail('Public ID', account['public_id']),
            ])),
            const SizedBox(height: 11),
            const Text(
              'Connecting a patient account does not automatically grant '
                  'access to every family member or medical record. '
                  'Check Care Profiles for explicit access.',
              style: TextStyle(
                color: _PatientColors.muted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetTitle(String title, String subtitle) => Row(
    children: [
      const CircleAvatar(
        backgroundColor: _PatientColors.mint,
        child: Icon(Icons.person_outline, color: _PatientColors.green),
      ),
      const SizedBox(width: 11),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(
            fontSize: 18,
            color: _PatientColors.ink,
            fontWeight: FontWeight.w800,
          )),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(
            fontSize: 12,
            color: _PatientColors.muted,
          )),
        ],
      )),
    ],
  );

  Widget _actionChip(
      BuildContext sheet,
      Map<String, dynamic> profile,
      String section,
      String label,
      IconData icon,
      ) => OutlinedButton.icon(
    onPressed: _navigating ? null : () => _openFromSheet(sheet, profile, section),
    icon: Icon(icon, size: 17),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: _PatientColors.green,
      side: const BorderSide(color: _PatientColors.border),
    ),
  );

  Widget _detail(String label, dynamic value) {
    final text = _pt(value);
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 112, child: Text(label,
              style: const TextStyle(fontSize: 11, color: _PatientColors.muted))),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(text,
              style: const TextStyle(fontSize: 12, color: _PatientColors.ink,
                  fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _PatientColors.border),
      borderRadius: BorderRadius.circular(15),
    ),
    child: child,
  );

  Widget _banner() => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [
        _PatientColors.mint,
        _PatientColors.ice,
      ]),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _PatientColors.border),
    ),
    child: Row(children: [
      const Icon(Icons.groups_2_outlined,
          color: _PatientColors.green, size: 31),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Connected Care', style: TextStyle(
            color: _PatientColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          )),
          const SizedBox(height: 4),
          Text(
            _profilesTab
                ? 'Child, Adult and Women care profiles shared with you'
                : 'Patient accounts connected with your practice',
            style: const TextStyle(
              color: _PatientColors.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      )),
    ]),
  );

  Widget _tab(String label, bool active, VoidCallback onTap, IconData icon) =>
      Expanded(child: Material(
        color: active ? _PatientColors.green : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: active
                  ? _PatientColors.green : _PatientColors.border),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: active
                  ? Colors.white : _PatientColors.green),
              const SizedBox(width: 6),
              Flexible(child: Text(label, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? Colors.white : _PatientColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              )),
            ]),
          ),
        ),
      ));

  Widget _filters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: [
      for (final entry in const [
        ('all', 'All'),
        ('child', 'Child'),
        ('adult', 'Adult'),
        ('women', 'Women'),
      ])
        Padding(
          padding: const EdgeInsets.only(right: 7),
          child: ChoiceChip(
            label: Text(entry.$2),
            selected: _module == entry.$1,
            selectedColor: _PatientColors.mint,
            backgroundColor: Colors.white,
            side: const BorderSide(color: _PatientColors.border),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: _module == entry.$1
                  ? _PatientColors.green : _PatientColors.muted,
            ),
            onSelected: (_) => setState(() => _module = entry.$1),
          ),
        ),
    ]),
  );

  Widget _listTile(Map<String, dynamic> item) {
    final care = _profilesTab;
    final module = _pt(item['module']).toLowerCase();
    final workspace = _pt(item['_workspace']);
    final name = _pt(item['full_name']);
    final subtitle = !care
        ? _pt(item['email'])
        : module == 'child'
        ? 'Child Care'
        : module == 'adult'
        ? 'Adult Health'
        : "Women's Health";
    final extra = !care
        ? _pt(item['phone_number'])
        : workspace == 'adult' || workspace == 'women'
        ? 'Explicit tab access • Private workspace'
        : 'Connected care profile • Scope-controlled';
    final icon = !care
        ? Icons.person_outline
        : switch (module) {
      'child' => Icons.child_care_outlined,
      'adult' => Icons.monitor_heart_outlined,
      'women' => Icons.favorite_outline,
      _ => Icons.folder_shared_outlined,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _opening || _navigating
              ? null
              : care ? () => _openProfile(item) : () => _showAccount(item),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _PatientColors.border),
            ),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: care && module == 'women'
                    ? _PatientColors.ice : _PatientColors.mint,
                child: Icon(icon, color: care && module == 'women'
                    ? _PatientColors.blue : _PatientColors.green),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? 'Care Profile' : name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _PatientColors.ink,
                          fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _PatientColors.muted,
                          fontSize: 12)),
                  if (extra.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(extra, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _PatientColors.muted,
                            fontSize: 11)),
                  ],
                ],
              )),
              if (_opening)
                const SizedBox(width: 17, height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: _PatientColors.green))
              else
                const Icon(Icons.chevron_right_rounded,
                    color: _PatientColors.green),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _empty(String message) => _panel(Padding(
    padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 10),
    child: Column(children: [
      const Icon(Icons.person_search_outlined,
          color: _PatientColors.blue, size: 37),
      const SizedBox(height: 10),
      Text(message, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12,
              color: _PatientColors.muted, height: 1.45)),
    ]),
  ));

  Widget _errorCard(String message, VoidCallback retry) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _panel(Row(children: [
      const Icon(Icons.error_outline, color: _PatientColors.danger),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(
          color: _PatientColors.danger, fontSize: 12))),
      IconButton(onPressed: retry, icon: const Icon(Icons.refresh)),
    ])),
  );

  Widget _content() {
    final visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _banner(),
        const SizedBox(height: 13),
        Row(children: [
          _tab('Patients', !_profilesTab, () => _switchTab(false),
              Icons.people_outline),
          const SizedBox(width: 9),
          _tab('Care Profiles', _profilesTab, () => _switchTab(true),
              Icons.folder_shared_outlined),
        ]),
        const SizedBox(height: 12),
        _panel(Text(
          _profilesTab
              ? 'Child profiles come from the connected care directory. '
              'Adult and Women tab grants are loaded from their separate '
              'private sharing APIs.'
              : 'A connected patient account does not automatically unlock '
              'health records of family members.',
          style: const TextStyle(fontSize: 12,
              color: _PatientColors.muted, height: 1.45),
        )),
        if (_profilesTab) ...[
          const SizedBox(height: 12),
          _filters(),
        ],
        const SizedBox(height: 13),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: _profilesTab
                ? 'Search loaded care profiles'
                : 'Search loaded patient accounts',
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.search, color: _PatientColors.green),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(onPressed: _search.clear,
                icon: const Icon(Icons.close)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _PatientColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _PatientColors.green),
            ),
          ),
        ),
        const SizedBox(height: 7),
        const Text('Search filters loaded results. Use Load More for older pages.',
            style: TextStyle(fontSize: 11, color: _PatientColors.muted)),
        const SizedBox(height: 12),
        if (_listError != null)
          _errorCard(_listError!, () => _load(reset: true)),
        if (_profilesTab && _sharedWarning != null)
          _errorCard(_sharedWarning!, () => _load(reset: true)),
        if (_loading || _opening)
          const Padding(padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator(
                  color: _PatientColors.green)))
        else if (visible.isEmpty)
          _empty(_profilesTab
              ? 'No authorized care profiles match this filter.'
              : 'No connected patient accounts match this search.')
        else
          for (final item in visible) _listTile(item),
        if (!_loading && _hasMore) ...[
          const SizedBox(height: 5),
          OutlinedButton.icon(
            onPressed: _loadingMore ? null : () => _load(reset: false),
            icon: _loadingMore
                ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.expand_more),
            label: Text(_loadingMore ? 'Loading...' : 'Load More'),
          ),
        ],
        const SizedBox(height: 15),
        const Text('FamilyCare+ • Patient access is always checked by the backend.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _PatientColors.muted, fontSize: 11)),
      ],
    );
  }

  void _back() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Widget _blocked() => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.lock_person_outlined,
          color: _PatientColors.blue, size: 48),
      const SizedBox(height: 12),
      const Text('Approved Doctor Required', style: TextStyle(
        color: _PatientColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      )),
      const SizedBox(height: 8),
      Text(_authError ?? 'Sign in with an approved doctor account.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _PatientColors.muted,
              height: 1.45)),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _verify,
        style: FilledButton.styleFrom(
            backgroundColor: _PatientColors.green),
        icon: const Icon(Icons.refresh),
        label: const Text('Retry Verification'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => LoginScreen(apiBaseUrl: _base),
          ),
              (_) => false,
        ),
        child: const Text('Go to Login'),
      ),
    ]),
  ));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _PatientColors.page,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _PatientColors.ink,
      leading: IconButton(
        onPressed: _back,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('My Patients', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w800)),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading || _loadingMore || _opening
              ? null
              : _approved
              ? () => _load(reset: true)
              : _verify,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _checking
        ? const Center(child: CircularProgressIndicator(
        color: _PatientColors.green))
        : !_approved
        ? _blocked()
        : RefreshIndicator(
      color: _PatientColors.green,
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: _content(),
          )),
        ],
      ),
    ),
  );
}
