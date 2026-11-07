
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

class DoctorClinicalRecordsScreen extends StatefulWidget {
  const DoctorClinicalRecordsScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.initialProfile,
    this.initialChild,
    this.onBack,
    this.onOpenReports,
  });

  final String apiBaseUrl;
  final Map<String, dynamic>? initialProfile;
  final Map<String, dynamic>? initialChild;
  final VoidCallback? onBack;
  final ValueChanged<Map<String, dynamic>>? onOpenReports;

  @override
  State<DoctorClinicalRecordsScreen> createState() =>
      _DoctorClinicalRecordsScreenState();
}

class _ClinicalColors {
  static const ink = Color(0xFF264A51);
  static const green = Color(0xFF367D69);
  static const blue = Color(0xFF477F99);
  static const mint = Color(0xFFE8F7EF);
  static const ice = Color(0xFFECF5FA);
  static const background = Color(0xFFF6FAF9);
  static const border = Color(0xFFDCEAE7);
  static const muted = Color(0xFF70848A);
  static const red = Color(0xFFAE555B);
}

class _ClinicalApiError implements Exception {
  const _ClinicalApiError(this.message, this.status);

  final String message;
  final int status;

  @override
  String toString() => message;
}

String _crText(dynamic value) => (value ?? '').toString().trim();

Map<String, dynamic> _crMap(dynamic value) => value is Map
    ? Map<String, dynamic>.from(value)
    : <String, dynamic>{};

List<Map<String, dynamic>> _crRows(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

int _crCount(dynamic value, int fallback) => value is num
    ? value.toInt()
    : int.tryParse(_crText(value)) ?? fallback;

class _DoctorClinicalRecordsScreenState
    extends State<DoctorClinicalRecordsScreen> {
  static const int _pageSize = 20;

  static const Set<String> _childKinds = {
    'vaccination',
    'growth',
    'nutrition',
    'care',
    'consultation_request',
  };

  final http.Client _client = http.Client();
  final TextEditingController _profileSearch = TextEditingController();
  final TextEditingController _recordSearch = TextEditingController();

  bool _checking = true;
  bool _approved = false;
  bool _loadingProfiles = false;
  bool _openingProfile = false;
  bool _loadingRecords = false;
  bool _openingReports = false;

  String _doctorId = '';
  String _moduleFilter = 'all';
  String _kindFilter = 'all';

  String? _authError;
  String? _profilesError;
  String? _recordsError;

  Map<String, dynamic>? _selected;
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _records = [];

  int _profilePage = 0;
  int _profileTotal = 0;
  int _recordPage = 0;
  int _recordTotal = 0;
  int _recordRowsFetched = 0;

  int _authStamp = 0;
  int _profilesStamp = 0;
  int _selectionStamp = 0;
  int _recordsStamp = 0;

  bool get _busy =>
      _loadingProfiles ||
          _openingProfile ||
          _loadingRecords ||
          _openingReports;

  String get _profileId => _crText(_selected?['id']);

  String get _base {
    var value = widget.apiBaseUrl.trim();

    if (value.isEmpty) {
      value = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:5001'
          : 'http://127.0.0.1:5001';
    }

    value = value.replaceFirst(RegExp(r'/+$'), '');

    if (value.endsWith('/api/v1/doctors')) return value;
    if (value.endsWith('/api/v1')) return '$value/doctors';

    return '$value/api/v1/doctors';
  }

  @override
  void initState() {
    super.initState();
    _profileSearch.addListener(_onSearch);
    _recordSearch.addListener(_onSearch);
    _verify();
  }

  @override
  void didUpdateWidget(
      covariant DoctorClinicalRecordsScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    final oldId = _crText(
      (oldWidget.initialProfile ?? oldWidget.initialChild)?['id'],
    );

    final newId = _crText(
      (widget.initialProfile ?? widget.initialChild)?['id'],
    );

    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _verify();
    } else if (_approved && oldId != newId) {
      if (newId.isEmpty) {
        _backToProfiles();
      } else {
        _openProfile(newId);
      }
    }
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authStamp++;
    _profilesStamp++;
    _selectionStamp++;
    _recordsStamp++;

    _profileSearch.removeListener(_onSearch);
    _recordSearch.removeListener(_onSearch);

    _profileSearch.dispose();
    _recordSearch.dispose();
    _client.close();

    super.dispose();
  }

  String _friendly(Object error) {
    if (error is _ClinicalApiError) return error.message;

    if (error is TimeoutException) {
      return 'Request timed out. Please retry.';
    }

    if (error is http.ClientException) {
      return 'Unable to reach FamilyCare+. Check the API connection.';
    }

    if (error is FormatException) {
      return 'Unexpected server response.';
    }

    return 'Unable to load clinical records. Please try again.';
  }

  void _notice(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor:
          isError ? _ClinicalColors.red : _ClinicalColors.ink,
          content: Text(message),
        ),
      );
  }

  Future<Map<String, dynamic>> _get(
      String path, {
        Map<String, String>? query,
      }) async {
    final role = await FamilyCareSession.role();
    final token = await FamilyCareSession.accessToken();
    final expiresAt = await FamilyCareSession.accessTokenExpiresAt();

    if (_crText(role).toUpperCase() != 'DOCTOR' ||
        token == null ||
        token.trim().isEmpty ||
        expiresAt == null ||
        !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const _ClinicalApiError(
        'Your doctor session expired. Please sign in again.',
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

    Map<String, dynamic> data = {};

    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));

        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        } else if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          throw const FormatException('Expected a JSON object.');
        }
      } on FormatException {
        if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          rethrow;
        }
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final issue = data['error'];

      final fromApi = issue is Map
          ? _crText(issue['message'])
          : _crText(issue);

      final fallback = switch (response.statusCode) {
        401 => 'Session expired. Please sign in again.',
        403 => 'Records permission was denied or revoked.',
        404 => 'This profile or its records are no longer available.',
        429 => 'Too many requests. Please retry shortly.',
        _ => 'Request failed (HTTP ${response.statusCode}).',
      };

      throw _ClinicalApiError(
        fromApi.isEmpty ? fallback : fromApi,
        response.statusCode,
      );
    }

    if (data.isEmpty) {
      throw const FormatException('Empty JSON response.');
    }

    return data;
  }

  // General Doctor records API supports Child and explicitly shared Adult
  // records. Women and tab-specific Adult data use separate workspaces.
  bool _hasScope(Map<String, dynamic> profile, String scope) {
    if (_crText(profile['module']).toLowerCase() == 'child') {
      return true;
    }

    if (_crText(profile['module']).toLowerCase() != 'adult') {
      return false;
    }

    final grant = _crMap(profile['access_permissions']);

    if (grant['active'] != true ||
        _doctorId.isEmpty ||
        _crText(grant['doctor_id']) != _doctorId) {
      return false;
    }

    final scopes = grant['scopes'];

    if (scopes is! List || !scopes.contains(scope)) {
      return false;
    }

    final expiryText = _crText(grant['expires_at']);

    if (expiryText.isNotEmpty) {
      final expiry = DateTime.tryParse(expiryText);

      if (expiry == null ||
          !expiry.toUtc().isAfter(DateTime.now().toUtc())) {
        return false;
      }
    }

    return true;
  }

  void _blocked(String message) {
    _authStamp++;
    _profilesStamp++;
    _selectionStamp++;
    _recordsStamp++;

    if (!mounted) return;

    setState(() {
      _checking = false;
      _approved = false;
      _authError = message;
      _doctorId = '';
      _selected = null;
      _profiles = [];
      _records = [];

      _loadingProfiles = false;
      _openingProfile = false;
      _loadingRecords = false;
    });
  }

  Future<void> _verify() async {
    final stamp = ++_authStamp;

    _profilesStamp++;
    _selectionStamp++;
    _recordsStamp++;

    setState(() {
      _checking = true;
      _approved = false;

      _authError = null;
      _profilesError = null;
      _recordsError = null;

      _selected = null;
      _profiles = [];
      _records = [];

      _profilePage = 0;
      _profileTotal = 0;
      _recordPage = 0;
      _recordTotal = 0;
      _recordRowsFetched = 0;

      _loadingProfiles = false;
      _loadingRecords = false;
      _openingProfile = false;
    });

    try {
      final response = await _get('/me');
      final doctor = _crMap(response['user']);

      if (_crText(doctor['role']).toUpperCase() != 'DOCTOR' ||
          _crText(doctor['approval_status']).toUpperCase() != 'APPROVED' ||
          _crText(doctor['account_status']).toUpperCase() != 'ACTIVE' ||
          _crText(doctor['id']).isEmpty) {
        throw const _ClinicalApiError(
          'Only approved, active doctors can view clinical records.',
          403,
        );
      }

      if (!mounted || stamp != _authStamp) return;

      setState(() {
        _doctorId = _crText(doctor['id']);
        _approved = true;
        _checking = false;
      });

      final initialId = _crText(
        (widget.initialProfile ?? widget.initialChild)?['id'],
      );

      if (initialId.isEmpty) {
        await _loadProfiles(reset: true);
      } else {
        await _openProfile(initialId);
      }
    } catch (error) {
      if (mounted && stamp == _authStamp) {
        _blocked(_friendly(error));
      }
    }
  }

  Future<void> _loadProfiles({required bool reset}) async {
    if (!_approved || _loadingProfiles) return;

    final stamp = ++_profilesStamp;
    final page = reset ? 1 : _profilePage + 1;
    final module = _moduleFilter;

    setState(() {
      _loadingProfiles = true;
      _profilesError = null;

      if (reset) {
        _profiles = [];
        _profilePage = 0;
        _profileTotal = 0;
      }
    });

    try {
      final response = await _get(
        '/care-profiles',
        query: {
          'page': '$page',
          'per_page': '$_pageSize',
          if (module != 'all') 'module': module,
        },
      );

      if (response['items'] is! List) {
        throw const FormatException('Invalid care profile list.');
      }

      if (!mounted ||
          stamp != _profilesStamp ||
          module != _moduleFilter) {
        return;
      }

      final incoming = _crRows(response['items']).where((p) {
        return _crText(p['id']).isNotEmpty && _hasScope(p, 'records');
      });

      setState(() {
        final seen = <String>{};

        _profiles = [
          if (!reset) ..._profiles,
          ...incoming,
        ].where(
              (p) => seen.add(_crText(p['id'])),
        ).toList();

        _profilePage = page;
        _profileTotal = _crCount(response['total'], _profiles.length);
      });
    } catch (error) {
      if (!mounted || stamp != _profilesStamp) return;

      if (error is _ClinicalApiError && error.status == 401) {
        _blocked(_friendly(error));
      } else {
        setState(() => _profilesError = _friendly(error));
      }
    } finally {
      if (mounted && stamp == _profilesStamp) {
        setState(() => _loadingProfiles = false);
      }
    }
  }

  void _changeModule(String value) {
    if (!_approved ||
        value == _moduleFilter ||
        _loadingProfiles) {
      return;
    }

    _profilesStamp++;

    setState(() {
      _moduleFilter = value;
      _profiles = [];
      _profilePage = 0;
      _profileTotal = 0;
      _profilesError = null;
      _profileSearch.clear();
    });

    _loadProfiles(reset: true);
  }

  Future<void> _openProfile(String id) async {
    if (!_approved || _openingProfile || id.isEmpty) return;

    final stamp = ++_selectionStamp;
    _recordsStamp++;

    setState(() {
      _openingProfile = true;
      _profilesError = null;
      _recordsError = null;

      _selected = null;
      _records = [];

      _recordPage = 0;
      _recordTotal = 0;
      _recordRowsFetched = 0;
      _loadingRecords = false;
    });

    try {
      final response = await _get(
        '/care-profiles/${Uri.encodeComponent(id)}',
      );

      final profile = _crMap(response['profile']);

      if (_crText(profile['id']) != id ||
          !_hasScope(profile, 'records')) {
        throw const _ClinicalApiError(
          'Active records permission is required for this profile.',
          403,
        );
      }

      if (!mounted || stamp != _selectionStamp) return;

      setState(() {
        _selected = profile;
        _kindFilter = 'all';
        _recordSearch.clear();
        _openingProfile = false;
      });

      await _loadRecords(reset: true);
    } catch (error) {
      if (!mounted || stamp != _selectionStamp) return;

      if (error is _ClinicalApiError && error.status == 401) {
        _blocked(_friendly(error));
      } else {
        setState(() {
          _profilesError = _friendly(error);
          _selected = null;
        });

        _notice(_friendly(error), isError: true);
      }
    } finally {
      if (mounted && stamp == _selectionStamp) {
        setState(() => _openingProfile = false);
      }
    }
  }

  Future<void> _loadRecords({required bool reset}) async {
    if (!_approved ||
        _selected == null ||
        _loadingRecords) {
      return;
    }

    final id = _profileId;

    if (!_hasScope(_selected!, 'records')) {
      _backToProfiles();
      _notice('Records permission has expired.', isError: true);
      return;
    }

    final stamp = ++_recordsStamp;
    final page = reset ? 1 : _recordPage + 1;

    setState(() {
      _loadingRecords = true;
      _recordsError = null;

      if (reset) {
        _records = [];
        _recordPage = 0;
        _recordTotal = 0;
        _recordRowsFetched = 0;
      }
    });

    try {
      final response = await _get(
        '/care-profiles/${Uri.encodeComponent(id)}/records',
        query: {
          'page': '$page',
          'per_page': '$_pageSize',
        },
      );

      if (response['items'] is! List) {
        throw const FormatException('Invalid clinical record list.');
      }

      if (!mounted ||
          stamp != _recordsStamp ||
          id != _profileId) {
        return;
      }

      final raw = _crRows(response['items']);
      final child = _crText(_selected?['module']) == 'child';

      // The server applies scopes and record_kinds restrictions first.
      final filtered = child
          ? raw.where(
            (r) => _childKinds.contains(
          _crText(r['kind']).toLowerCase(),
        ),
      )
          : raw;

      setState(() {
        final ids = <String>{};

        _records = [
          if (!reset) ..._records,
          ...filtered,
        ].where(
              (r) =>
          _crText(r['id']).isNotEmpty &&
              ids.add(_crText(r['id'])),
        ).toList();

        _recordPage = page;
        _recordRowsFetched =
            (reset ? 0 : _recordRowsFetched) + raw.length;

        _recordTotal = _crCount(
          response['total'],
          _recordRowsFetched,
        );
      });
    } catch (error) {
      if (!mounted ||
          stamp != _recordsStamp ||
          id != _profileId) {
        return;
      }

      if (error is _ClinicalApiError && error.status == 401) {
        _blocked(_friendly(error));
      } else if (error is _ClinicalApiError &&
          (error.status == 403 || error.status == 404)) {
        _backToProfiles();
        _notice(_friendly(error), isError: true);
      } else {
        setState(() => _recordsError = _friendly(error));
      }
    } finally {
      if (mounted && stamp == _recordsStamp) {
        setState(() => _loadingRecords = false);
      }
    }
  }

  Future<void> _openReports() async {
    if (_selected == null ||
        widget.onOpenReports == null ||
        _openingReports) {
      return;
    }

    final id = _profileId;

    setState(() => _openingReports = true);

    try {
      final response = await _get(
        '/care-profiles/${Uri.encodeComponent(id)}',
      );

      final fresh = _crMap(response['profile']);

      if (_crText(fresh['id']) != id ||
          !_hasScope(fresh, 'reports')) {
        throw const _ClinicalApiError(
          'Reports access is not granted or has expired.',
          403,
        );
      }

      if (mounted && _profileId == id) {
        widget.onOpenReports!(fresh);
      }
    } catch (error) {
      if (error is _ClinicalApiError && error.status == 401) {
        _blocked(_friendly(error));
      } else {
        _notice(_friendly(error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _openingReports = false);
      }
    }
  }

  void _backToProfiles() {
    _selectionStamp++;
    _recordsStamp++;

    if (!mounted) return;

    setState(() {
      _selected = null;
      _records = [];

      _recordPage = 0;
      _recordTotal = 0;
      _recordRowsFetched = 0;

      _recordsError = null;
      _loadingRecords = false;
      _openingProfile = false;
      _kindFilter = 'all';
    });

    if (_profiles.isEmpty) {
      _loadProfiles(reset: true);
    }
  }

  void _back() {
    if (_selected != null) {
      _backToProfiles();
    } else if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _refresh() async {
    if (!_approved || _busy) return;

    if (_selected == null) {
      await _loadProfiles(reset: true);
    } else {
      await _openProfile(_profileId);
    }
  }

  List<Map<String, dynamic>> get _visibleProfiles {
    final search = _profileSearch.text.trim().toLowerCase();

    return _profiles.where((p) {
      return search.isEmpty ||
          [
            _crText(p['full_name']),
            _crText(p['guardian_name']),
            _crText(p['module']),
          ].any(
                (v) => v.toLowerCase().contains(search),
          );
    }).toList();
  }

  List<String> get _kinds {
    final result = _records
        .map((r) => _crText(r['kind']).toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return result;
  }

  List<Map<String, dynamic>> get _visibleRecords {
    final search = _recordSearch.text.trim().toLowerCase();

    return _records.where((r) {
      if (_kindFilter != 'all' &&
          _crText(r['kind']).toLowerCase() != _kindFilter) {
        return false;
      }

      if (search.isEmpty) return true;

      return [
        r['title'],
        r['kind'],
        r['date'],
        r['status'],
        r['notes'],
        r['category'],
        r['context'],
        r['history_type'],
        r['reading_context'],
        r['strength'],
        r['result_status'],
      ].any(
            (v) => _crText(v).toLowerCase().contains(search),
      );
    }).toList();
  }

  String _moduleLabel(String module) => switch (module.toLowerCase()) {
    'child' => 'Child',
    'adult' => 'Adult Health',
    _ => 'Care Profile',
  };

  String _kindLabel(String kind) => switch (kind.toLowerCase()) {
    'bp' => 'Blood Pressure',
    'glucose' => 'Blood Sugar',
    'lipids' => 'Cholesterol / Lipids',
    'medicine' => 'Medication',
    'history' => 'Medical History',
    'vaccination' => 'Vaccination',
    'growth' => 'Growth',
    'nutrition' => 'Nutrition',
    'care' => 'Care Notes',
    'screening' => 'Screening',
    'lifestyle' => 'Lifestyle',
    'consultation_request' => 'Consultation Request',
    'reminder' => 'Reminder',
    _ => kind.isEmpty
        ? 'Clinical Record'
        : kind.replaceAll('_', ' '),
  };

  IconData _kindIcon(String kind) => switch (kind.toLowerCase()) {
    'vaccination' => Icons.vaccines_outlined,
    'bp' => Icons.monitor_heart_outlined,
    'glucose' => Icons.water_drop_outlined,
    'growth' => Icons.show_chart,
    'nutrition' => Icons.restaurant_outlined,
    'medicine' => Icons.medication_outlined,
    'history' => Icons.history_edu_outlined,
    'consultation_request' => Icons.medical_services_outlined,
    'lifestyle' => Icons.directions_walk_outlined,
    'screening' => Icons.fact_check_outlined,
    'reminder' => Icons.notifications_none,
    _ => Icons.description_outlined,
  };

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _ClinicalColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _banner(String title, String subtitle) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          _ClinicalColors.mint,
          _ClinicalColors.ice,
        ],
      ),
      border: Border.all(color: _ClinicalColors.border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.assignment_outlined,
          color: _ClinicalColors.green,
          size: 30,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ClinicalColors.ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: _ClinicalColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _info(String label, dynamic value) {
    final text = _crText(value);

    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 119,
            child: Text(
              label,
              style: const TextStyle(
                color: _ClinicalColors.muted,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(
                color: _ClinicalColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message, VoidCallback retry) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: _card(
      Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: _ClinicalColors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _ClinicalColors.red,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    ),
  );

  Widget _empty(String title, String detail) => _card(
    Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 27,
        horizontal: 8,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.folder_open_outlined,
            color: _ClinicalColors.blue,
            size: 37,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _ClinicalColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: _ClinicalColors.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _search(
      TextEditingController controller,
      String hint,
      ) =>
      TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(
            Icons.search,
            color: _ClinicalColors.green,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
            onPressed: controller.clear,
            icon: const Icon(Icons.close),
          ),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: _ClinicalColors.border,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: _ClinicalColors.green,
            ),
          ),
        ),
      );

  Widget _chip(
      String label,
      bool selected,
      VoidCallback onTap,
      ) =>
      ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: Colors.white,
        selectedColor: _ClinicalColors.mint,
        side: const BorderSide(
          color: _ClinicalColors.border,
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected
              ? _ClinicalColors.green
              : _ClinicalColors.muted,
        ),
      );

  Widget _profilesView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _banner(
        'Clinical Records',
        'View connected Child and authorized Adult medical history.',
      ),
      const SizedBox(height: 13),
      _card(
        const Text(
          'Read-only medical history. Adult records require an active records '
              'grant. Women’s Health and tab-specific Adult sharing use their '
              'separate secure workspaces.',
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: _ClinicalColors.muted,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          _chip(
            'All',
            _moduleFilter == 'all',
                () => _changeModule('all'),
          ),
          _chip(
            'Child',
            _moduleFilter == 'child',
                () => _changeModule('child'),
          ),
          _chip(
            'Adult',
            _moduleFilter == 'adult',
                () => _changeModule('adult'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _search(
        _profileSearch,
        'Search loaded care profiles',
      ),
      const SizedBox(height: 8),
      const Text(
        'Search filters loaded profiles only.',
        style: TextStyle(
          fontSize: 11,
          color: _ClinicalColors.muted,
        ),
      ),
      const SizedBox(height: 12),
      if (_profilesError != null)
        _errorCard(
          _profilesError!,
              () => _loadProfiles(reset: true),
        ),
      if (_loadingProfiles || _openingProfile)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: CircularProgressIndicator(
              color: _ClinicalColors.green,
            ),
          ),
        )
      else if (_visibleProfiles.isEmpty)
        _empty(
          'No accessible profiles',
          'Only connected children and adults with a valid records grant appear here.',
        )
      else
        for (final profile in _visibleProfiles)
          _profileTile(profile),
      if (!_loadingProfiles &&
          _profilePage * _pageSize < _profileTotal)
        OutlinedButton.icon(
          onPressed: () => _loadProfiles(reset: false),
          icon: const Icon(Icons.expand_more),
          label: const Text('Load More Profiles'),
        ),
    ],
  );

  Widget _profileTile(Map<String, dynamic> profile) {
    final module = _crText(profile['module']).toLowerCase();
    final isChild = module == 'child';
    final name = _crText(profile['full_name']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _openingProfile
              ? null
              : () => _openProfile(_crText(profile['id'])),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              border: Border.all(color: _ClinicalColors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: isChild
                      ? _ClinicalColors.mint
                      : _ClinicalColors.ice,
                  child: Icon(
                    isChild
                        ? Icons.child_care_outlined
                        : Icons.monitor_heart_outlined,
                    color: isChild
                        ? _ClinicalColors.green
                        : _ClinicalColors.blue,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Care profile' : name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _ClinicalColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _moduleLabel(module),
                        style: const TextStyle(
                          fontSize: 12,
                          color: _ClinicalColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _ClinicalColors.green,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordsView() {
    final profile = _selected!;

    if (!_hasScope(profile, 'records')) {
      return _empty(
        'Permission expired',
        'Go back and refresh. These records are no longer shared.',
      );
    }

    final module = _crText(profile['module']).toLowerCase();
    final grant = _crMap(profile['access_permissions']);
    final allowed = grant['record_kinds'];

    final allowedLabel = allowed is List
        ? allowed.map(_crText).join(', ')
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _banner(
          _crText(profile['full_name']).isEmpty
              ? 'Shared Records'
              : _crText(profile['full_name']),
          '${_moduleLabel(module)} • Read-only clinical history',
        ),
        const SizedBox(height: 12),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Care Information',
                style: TextStyle(
                  color: _ClinicalColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              _info('Date of birth', profile['date_of_birth']),
              _info('Gender', profile['gender']),
              if (module == 'child') ...[
                _info('Guardian', profile['guardian_name']),
                _info('Contact', profile['guardian_contact']),
              ],
              Text(
                allowedLabel.isEmpty
                    ? 'Only server-authorized records are listed.'
                    : 'Permitted record types: $allowedLabel',
                style: const TextStyle(
                  fontSize: 11,
                  color: _ClinicalColors.muted,
                ),
              ),
              if (widget.onOpenReports != null &&
                  _hasScope(profile, 'reports')) ...[
                const SizedBox(height: 7),
                TextButton.icon(
                  onPressed: _openingReports ? null : _openReports,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Open Shared Reports'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          const Text(
            'These entries may be parent- or self-reported. They are not '
                'automatically clinically verified. Editing and deleting are '
                'not available through the Doctor records API.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: _ClinicalColors.muted,
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Shared Clinical Entries',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: _ClinicalColors.ink,
          ),
        ),
        const SizedBox(height: 11),
        _search(
          _recordSearch,
          'Search loaded records',
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: _chip(
                  'All',
                  _kindFilter == 'all',
                      () => setState(() => _kindFilter = 'all'),
                ),
              ),
              for (final kind in _kinds)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: _chip(
                    _kindLabel(kind),
                    _kindFilter == kind,
                        () => setState(() => _kindFilter = kind),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Search and filters apply to loaded records only.',
          style: TextStyle(
            fontSize: 11,
            color: _ClinicalColors.muted,
          ),
        ),
        const SizedBox(height: 12),
        if (_recordsError != null)
          _errorCard(
            _recordsError!,
                () => _loadRecords(reset: true),
          ),
        if (_loadingRecords)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(
                color: _ClinicalColors.green,
              ),
            ),
          )
        else if (_visibleRecords.isEmpty)
          _empty(
            'No matching records',
            'No loaded entries match the current filters and permissions.',
          )
        else
          for (final record in _visibleRecords)
            _recordTile(record),
        if (!_loadingRecords &&
            _recordPage * _pageSize < _recordTotal)
          OutlinedButton.icon(
            onPressed: () => _loadRecords(reset: false),
            icon: const Icon(Icons.expand_more),
            label: const Text('Load More Records'),
          ),
      ],
    );
  }

  Widget _recordTile(Map<String, dynamic> record) {
    final kind = _crText(record['kind']);
    final name = _crText(record['title']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            if (_selected != null &&
                _hasScope(_selected!, 'records')) {
              _showDetails(record);
            } else {
              _notice(
                'Record permission expired. Refresh the screen.',
                isError: true,
              );
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              border: Border.all(color: _ClinicalColors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _ClinicalColors.ice,
                  child: Icon(
                    _kindIcon(kind),
                    color: _ClinicalColors.blue,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? _kindLabel(kind) : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _ClinicalColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_kindLabel(kind)} • ${_crText(record['date'])}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _ClinicalColors.muted,
                        ),
                      ),
                      if (_crText(record['status']).isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          _crText(record['status']),
                          style: const TextStyle(
                            fontSize: 11,
                            color: _ClinicalColors.green,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _ClinicalColors.green,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> record) {
    final kind = _crText(record['kind']);
    final name = _crText(record['title']);

    // Only display fields returned by the authorized endpoint.
    // The Doctor records endpoint does not guarantee a version field.
    final fields = <(String, dynamic)>[
      ('Type', _kindLabel(kind)),
      ('Date', record['date']),
      ('Status', record['status']),
      ('Verification', record['verification_status']),
      ('Recorded by', record['author_name']),
      ('Provider', record['provider']),
      ('Vaccinator', record['vaccinator']),
      ('Batch number', record['batch_number']),
      ('Next date', record['nextDate']),
      ('Weight (kg)', record['weight']),
      ('Height (cm)', record['height']),
      ('Meal', record['meal']),
      ('Systolic', record['systolic']),
      ('Diastolic', record['diastolic']),
      ('Pulse', record['pulse']),
      ('Arm', record['arm']),
      ('Position', record['position']),
      ('Measurement time', record['measurement_time']),
      ('Glucose', record['glucose']),
      ('Glucose units', record['units']),
      ('Reading context', record['reading_context']),
      ('Minutes after meal', record['meal_minutes']),
      ('Total cholesterol', record['total']),
      ('LDL', record['ldl']),
      ('HDL', record['hdl']),
      ('Triglycerides', record['triglycerides']),
      ('Medicine strength', record['strength']),
      ('Dose', record['dose']),
      ('Frequency', record['frequency']),
      ('Medication start', record['start_date']),
      ('Medication end', record['end_date']),
      ('Adherence', record['adherence']),
      ('Follow-up', record['follow_up']),
      ('Screening result', record['result_status']),
      ('History type', record['history_type']),
      ('Activity minutes', record['minutes']),
      ('Sleep hours', record['sleep_hours']),
      ('Context', record['context']),
      ('Category', record['category']),
      ('Linked report ID', record['report_id']),
      ('Notes', record['notes']),
      if (record.containsKey('version'))
        ('Version', record['version']),
    ].where((field) => _crText(field.$2).isNotEmpty).toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * 0.82,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 26),
          children: [
            Row(
              children: [
                Icon(
                  _kindIcon(kind),
                  color: _ClinicalColors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name.isEmpty ? _kindLabel(kind) : name,
                    style: const TextStyle(
                      fontSize: 18,
                      color: _ClinicalColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Shared clinical record • Read-only',
              style: TextStyle(
                fontSize: 12,
                color: _ClinicalColors.muted,
              ),
            ),
            const Divider(
              height: 25,
              color: _ClinicalColors.border,
            ),
            for (final field in fields)
              _info(field.$1, field.$2),
            const SizedBox(height: 8),
            const Text(
              'Patient or parent-reported values may not have been '
                  'independently verified. Review clinical context before use.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: _ClinicalColors.muted,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockedView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_person_outlined,
            color: _ClinicalColors.blue,
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            'Approved Doctor Required',
            style: TextStyle(
              fontSize: 18,
              color: _ClinicalColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            _authError ??
                'Sign in with an approved, active doctor account.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ClinicalColors.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 15),
          FilledButton.icon(
            onPressed: _verify,
            style: FilledButton.styleFrom(
              backgroundColor: _ClinicalColors.green,
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry Verification'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _ClinicalColors.background,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _ClinicalColors.ink,
      elevation: 0,
      leading: IconButton(
        onPressed: _back,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: Text(
        _selected == null
            ? 'Clinical Records'
            : 'Shared Records',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _approved && !_busy ? _refresh : null,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _checking
        ? const Center(
      child: CircularProgressIndicator(
        color: _ClinicalColors.green,
      ),
    )
        : !_approved
        ? _blockedView()
        : RefreshIndicator(
      color: _ClinicalColors.green,
      onRefresh: _refresh,
      child: ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16,
          17,
          16,
          30,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 960,
              ),
              child: _selected == null
                  ? _profilesView()
                  : _recordsView(),
            ),
          ),
        ],
      ),
    ),
  );
}
