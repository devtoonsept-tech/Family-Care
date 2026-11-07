
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';
import 'add_child_screen.dart';
import 'child_profile_screen.dart';
import 'vaccination_screen.dart';
import 'medical_history_screen.dart';
import 'growth_nutrition_screen.dart';
import 'doctor_consultation_screen.dart';
import 'child_care_notes_screen.dart';
import 'health_reports_screen.dart';
import 'child_settings_screen.dart';

// ============================================================
// FAMILYCARE+ CHILD DASHBOARD
// ============================================================
//
// Child profile photos and gender fields are excluded.
// dashboard_child.png is a shared decorative image.
//
// Current backend supports profile creation and retrieval.
// Profile PATCH/DELETE APIs are not yet implemented.
// ============================================================

class ChildDashboardPalette {
  static const background = Color(0xFFF3F8FE);
  static const white = Colors.white;
  static const navy = Color(0xFF153B63);
  static const body = Color(0xFF30465A);
  static const muted = Color(0xFF71869B);
  static const line = Color(0xFFE1EBF4);

  static const blue = Color(0xFF2679E8);
  static const green = Color(0xFF30886F);
  static const purple = Color(0xFF8865BD);
  static const orange = Color(0xFFD7964B);
  static const pink = Color(0xFFD97F9D);
  static const red = Color(0xFFB94C55);
}

// ============================================================
// CHILD PROFILE MODEL
// ============================================================

class _ChildProfileInfo {
  final String id;
  final String name;
  final DateTime? dob;
  final Map<String, dynamic>? doctor;
  final String? ageDisplay;

  const _ChildProfileInfo({
    required this.id,
    required this.name,
    this.dob,
    this.doctor,
    this.ageDisplay,
  });

  factory _ChildProfileInfo.fromJson(
      Map<String, dynamic> json,
      ) {
    final doctorData = json['doctor'];
    final ageData = json['age'];

    return _ChildProfileInfo(
      id: '${json['id'] ?? ''}',
      name: '${json['full_name'] ?? ''}'.trim(),
      dob: DateTime.tryParse(
        '${json['date_of_birth'] ?? ''}',
      ),
      doctor: doctorData is Map
          ? Map<String, dynamic>.from(doctorData)
          : null,
      ageDisplay: ageData is Map
          ? ageData['display']?.toString()
          : null,
    );
  }
}

// ============================================================
// VACCINATION PREVIEW
// ============================================================

class _VaccinePreview {
  final String title;
  final DateTime date;
  final bool published;

  const _VaccinePreview(
      this.title,
      this.date,
      this.published,
      );
}

// ============================================================
// CHILD SERVICE MODEL
// ============================================================

class _DashboardItem {
  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
  final Color color;
  final Color background;

  const _DashboardItem(
      this.title,
      this.subtitle,
      this.route,
      this.icon,
      this.color,
      this.background,
      );
}

// ============================================================
// CHILD CARE SERVICES
// ============================================================

const _modules = <_DashboardItem>[
  _DashboardItem(
    'Vaccination',
    'Doses & dates',
    'vaccination',
    Icons.vaccines_outlined,
    ChildDashboardPalette.green,
    Color(0xFFE9F7EF),
  ),
  _DashboardItem(
    'Medical History',
    'Their health story',
    'medical-history',
    Icons.assignment_outlined,
    ChildDashboardPalette.purple,
    Color(0xFFF1ECFC),
  ),
  _DashboardItem(
    'Growth & Nutrition',
    'Track milestones',
    'growth',
    Icons.show_chart_rounded,
    ChildDashboardPalette.blue,
    Color(0xFFE8F5FE),
  ),
  _DashboardItem(
    'Doctor Consultation',
    'Connected care',
    'doctor-consultation',
    Icons.medical_services_outlined,
    ChildDashboardPalette.orange,
    Color(0xFFFFF4E6),
  ),
  _DashboardItem(
    'Child Care & Notes',
    'Everyday moments',
    'care-notes',
    Icons.favorite_outline_rounded,
    ChildDashboardPalette.pink,
    Color(0xFFFFEEF4),
  ),
  _DashboardItem(
    'Health Reports',
    'Files in one place',
    'health-reports',
    Icons.folder_copy_outlined,
    ChildDashboardPalette.green,
    Color(0xFFE9F5F1),
  ),
];

// ============================================================
// CHILD DASHBOARD SCREEN
// ============================================================

class ChildDashboardScreen extends StatefulWidget {
  final String apiBaseUrl;

  const ChildDashboardScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
  });

  @override
  State<ChildDashboardScreen> createState() =>
      _ChildDashboardScreenState();
}

// ============================================================
// BACKWARD COMPATIBILITY
// ============================================================

class ChildCareDashboardScreen
    extends ChildDashboardScreen {
  const ChildCareDashboardScreen({
    super.key,
    super.apiBaseUrl,
  });
}

// ============================================================
// CHILD DASHBOARD STATE
// ============================================================

class _ChildDashboardScreenState
    extends State<ChildDashboardScreen> {
  static const _heroAsset =
      'assets/images/dashboard_child.png';

  final _client = http.Client();

  final _scaffoldKey =
  GlobalKey<ScaffoldState>();

  final _search = TextEditingController();

  final List<_ChildProfileInfo> _children = [];

  // Existing editor callback caches.
  // These do not automatically imply backend persistence.

  // Vaccination is managed by VaccinationScreen using Flask APIs.
  // No obsolete local VaccinationRecord cache is kept here.

  final Map<String, List<MedicalHistoryRecord>>
  _medicalHistory = {};

  final Map<String, List<GrowthMeasurementRecord>>
  _growth = {};

  final Map<String, List<NutritionDiaryRecord>>
  _nutrition = {};

  final Map<String, List<DoctorConsultationRecord>>
  _consultations = {};

  final Map<String, List<ChildCareNote>>
  _notes = {};

  final Map<String, List<GrowthMeasurementRecord>>
  _serverGrowth = {};

  String? _selectedChildId;
  String? _loadError;
  String? _growthError;
  String? _vaccineMessage;
  String? _vaccineError;
  String? _remindersError;

  bool _loadingChildren = true;
  bool _loadingDetail = false;
  bool _loadingGrowth = false;
  bool _loadingVaccine = false;
  bool _loadingReminders = false;

  bool _inAppEnabled = true;
  bool _mutatingProfile = false;

  int _profileGeneration = 0;
  int _detailGeneration = 0;

  int? _reportCount;

  Map<String, dynamic>? _summary;

  List<Map<String, dynamic>> _reminders = [];

  _VaccinePreview? _nextVaccine;

  String _metric = 'all';
  int _months = 12;

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
        defaultTargetPlatform ==
            TargetPlatform.android) {
      return 'http://10.0.2.2:5001';
    }

    return 'http://127.0.0.1:5001';
  }

  // ==========================================================
  // SELECTED CHILD
  // ==========================================================

  _ChildProfileInfo? get _child {
    for (final child in _children) {
      if (child.id == _selectedChildId) {
        return child;
      }
    }

    return null;
  }

  String get _childName {
    return _child?.name ?? 'Your child';
  }

  // ==========================================================
  // INITIALIZATION
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _search.addListener(_searchChanged);
    _fetchChildren();
  }

  // ==========================================================
  // API URL CHANGES
  // ==========================================================

  @override
  void didUpdateWidget(
      covariant ChildDashboardScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _profileGeneration++;
      _detailGeneration++;

      _children.clear();
      _selectedChildId = null;
      _serverGrowth.clear();

      _fetchChildren();
    }
  }

  // ==========================================================
  // CLEANUP
  // ==========================================================

  @override
  void dispose() {
    _profileGeneration++;
    _detailGeneration++;

    _search.removeListener(_searchChanged);
    _search.dispose();

    _client.close();

    super.dispose();
  }

  void _searchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ==========================================================
  // NOTIFICATIONS
  // ==========================================================

  void _toast(
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
              ? ChildDashboardPalette.red
              : ChildDashboardPalette.navy,
          content: Text(message),
        ),
      );
  }

  String _errorText(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst(
      'TimeoutException: ',
      'Request timed out: ',
    );
  }

  // ==========================================================
  // AUTHENTICATED BACKEND REQUEST
  // ==========================================================
  //
  // GET is supported for child profile retrieval.
  // PATCH/DELETE require backend implementation.
  //
  // Never report success for non-2xx responses.
  // ==========================================================

  Future<Map<String, dynamic>> _request(
      String path, {
        String method = 'GET',
        Map<String, dynamic>? data,
      }) async {
    final token =
    await FamilyCareSession.accessToken();

    if (token == null || token.trim().isEmpty) {
      throw Exception(
        'Session expired. Please sign in again.',
      );
    }

    final url = Uri.parse('$_baseUrl$path');

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
      if (data != null)
        'Content-Type': 'application/json',
    };

    late http.Response response;

    switch (method) {
      case 'PATCH':
        response = await _client
            .patch(
          url,
          headers: headers,
          body: jsonEncode(data),
        )
            .timeout(
          const Duration(seconds: 35),
        );
        break;

      case 'DELETE':
        response = await _client
            .delete(
          url,
          headers: headers,
        )
            .timeout(
          const Duration(seconds: 35),
        );
        break;

      default:
        response = await _client
            .get(
          url,
          headers: headers,
        )
            .timeout(
          const Duration(seconds: 35),
        );
    }

    Map<String, dynamic> body = {};

    if (response.bodyBytes.isNotEmpty) {
      try {
        final value = jsonDecode(
          utf8.decode(response.bodyBytes),
        );

        if (value is Map) {
          body = Map<String, dynamic>.from(value);
        }
      } catch (_) {
        if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          throw const FormatException(
            'Invalid server response.',
          );
        }
      }
    }

    // ========================================================
    // ERROR RESPONSE
    // ========================================================

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      if (method != 'GET' &&
          (response.statusCode == 404 ||
              response.statusCode == 405)) {
        throw Exception(
          'Child profile $method is not enabled '
              'in the current backend. The server '
              'needs a matching API route.',
        );
      }

      if (response.statusCode == 401) {
        throw Exception(
          'Session expired. Please sign in again.',
        );
      }

      if (response.statusCode == 403) {
        throw Exception(
          'You do not have permission '
              'for this child.',
        );
      }

      final error = body['error'];

      final message = error is Map
          ? error['message']
          : body['message'];

      throw Exception(
        message?.toString() ??
            'Request failed '
                '(HTTP ${response.statusCode}).',
      );
    }

    body['_http_status'] = response.statusCode;

    return body;
  }

  // ==========================================================
  // LOAD CHILDREN
  // ==========================================================

  Future<void> _fetchChildren({
    String? preferredId,
  }) async {
    final generation = ++_profileGeneration;

    ++_detailGeneration;

    if (!mounted) return;

    setState(() {
      _loadingChildren = true;
      _loadError = null;
    });

    try {
      final loaded = <_ChildProfileInfo>[];
      final seen = <String>{};

      for (var page = 1; page <= 100; page++) {
        final payload = await _request(
          '/api/v1/patients/profiles'
              '?module=child&page=$page&per_page=100',
        );

        if (!mounted ||
            generation != _profileGeneration) {
          return;
        }

        final items = payload['items'];

        if (items is! List) {
          throw const FormatException(
            'Invalid child list.',
          );
        }

        for (final raw in items) {
          if (raw is! Map) continue;

          final json =
          Map<String, dynamic>.from(raw);

          if (json['module'] != 'child') {
            continue;
          }

          final child =
          _ChildProfileInfo.fromJson(json);

          if (child.id.isNotEmpty &&
              child.name.isNotEmpty &&
              seen.add(child.id)) {
            loaded.add(child);
          }
        }

        final total = payload['total'];

        if (items.isEmpty ||
            items.length < 100 ||
            (total is num &&
                page * 100 >= total.toInt())) {
          break;
        }
      }

      final candidate =
          preferredId ?? _selectedChildId;

      final selected =
      loaded.any((c) => c.id == candidate)
          ? candidate
          : (loaded.isEmpty
          ? null
          : loaded.first.id);

      if (!mounted ||
          generation != _profileGeneration) {
        return;
      }

      setState(() {
        _children
          ..clear()
          ..addAll(loaded);

        _selectedChildId = selected;
        _loadingChildren = false;
      });

      if (selected == null) {
        setState(() {
          _summary = null;
          _nextVaccine = null;
          _reportCount = null;
          _reminders = [];
        });
      } else {
        await _refreshChild(selected);
      }
    } catch (error) {
      if (!mounted ||
          generation != _profileGeneration) {
        return;
      }

      setState(() {
        _loadingChildren = false;
        _loadError = _errorText(error);
      });
    }
  }

  // ==========================================================
  // REQUEST GENERATION PROTECTION
  // ==========================================================

  bool _current(
      String id,
      int generation,
      ) {
    return mounted &&
        generation == _detailGeneration &&
        _selectedChildId == id;
  }

  // ==========================================================
  // REFRESH SELECTED CHILD
  // ==========================================================

  Future<void> _refreshChild(String id) async {
    final generation = ++_detailGeneration;

    if (!mounted) return;

    setState(() {
      _summary = null;
      _nextVaccine = null;
      _reportCount = null;
      _reminders = [];

      _vaccineMessage = null;
      _growthError = null;
      _vaccineError = null;
      _remindersError = null;

      _loadingDetail = true;
      _loadingGrowth = true;
      _loadingVaccine = true;
      _loadingReminders = true;
    });

    await Future.wait([
      _loadSummary(id, generation),
      _loadGrowth(id, generation),
      _loadVaccines(id, generation),
      _loadReminders(id, generation),
      _loadReportCount(id, generation),
    ]);
  }

  // ==========================================================
  // CHILD DASHBOARD SUMMARY
  // ==========================================================

  Future<void> _loadSummary(
      String id,
      int generation,
      ) async {
    try {
      final result = await _request(
        '/api/v1/children/'
            '${Uri.encodeComponent(id)}/dashboard',
      );

      if (!_current(id, generation)) return;

      setState(() {
        _summary = result;
        _loadingDetail = false;
      });
    } catch (_) {
      if (!_current(id, generation)) return;

      setState(() {
        _loadingDetail = false;
      });
    }
  }

  // ==========================================================
  // REPORT COUNT
  // ==========================================================

  Future<void> _loadReportCount(
      String id,
      int generation,
      ) async {
    try {
      final result = await _request(
        '/api/v1/patients/profiles/'
            '${Uri.encodeComponent(id)}'
            '/reports?page=1&per_page=1',
      );

      if (!_current(id, generation)) return;

      final total = result['total'];

      setState(() {
        _reportCount =
        total is num ? total.toInt() : null;
      });
    } catch (_) {
      if (!_current(id, generation)) return;

      setState(() {
        _reportCount = null;
      });
    }
  }

  // ==========================================================
  // VALID NUMERIC MEASUREMENT
  // ==========================================================

  double? _positive(dynamic value) {
    final number = double.tryParse(
      '${value ?? ''}',
    );

    return number != null &&
        number.isFinite &&
        number > 0
        ? number
        : null;
  }

  // ==========================================================
  // LOAD GROWTH
  // ==========================================================

  Future<void> _loadGrowth(
      String id,
      int generation,
      ) async {
    try {
      final records = <GrowthMeasurementRecord>[];

      for (var page = 1; page <= 100; page++) {
        final result = await _request(
          '/api/v1/children/'
              '${Uri.encodeComponent(id)}'
              '/growth?page=$page&per_page=100',
        );

        if (!_current(id, generation)) return;

        final items = result['items'];

        if (items is! List) {
          throw const FormatException(
            'Invalid growth list.',
          );
        }

        for (final raw in items) {
          if (raw is! Map) continue;

          final item =
          Map<String, dynamic>.from(raw);

          final date = DateTime.tryParse(
            '${item['date'] ?? ''}',
          );

          final height =
          _positive(item['height']);

          final weight =
          _positive(item['weight']);

          if (date == null ||
              (height == null && weight == null)) {
            continue;
          }

          records.add(
            GrowthMeasurementRecord(
              id: '${item['id'] ?? ''}',
              profileId: id,
              measuredAt: date,
              heightCm: height,
              weightKg: weight,
              notes: '${item['notes'] ?? ''}',
            ),
          );
        }

        final total = result['total'];

        if (items.isEmpty ||
            items.length < 100 ||
            (total is num &&
                page * 100 >= total.toInt())) {
          break;
        }
      }

      records.sort(
            (a, b) =>
            a.measuredAt.compareTo(b.measuredAt),
      );

      if (!_current(id, generation)) return;

      setState(() {
        _serverGrowth[id] = records;
        _loadingGrowth = false;
      });
    } catch (error) {
      if (!_current(id, generation)) return;

      setState(() {
        _growthError = _errorText(error);
        _loadingGrowth = false;
      });
    }
  }

  // ==========================================================
  // LOAD VACCINATION DATA
  // ==========================================================

  Future<void> _loadVaccines(
      String id,
      int generation,
      ) async {
    try {
      final result = await _request(
        '/api/v1/children/'
            '${Uri.encodeComponent(id)}'
            '/vaccinations/upcoming?schedule_type=UIP',
      );

      if (!_current(id, generation)) return;

      final state =
          '${result['status'] ?? ''}';

      final list = result['items'];

      if (list is! List) {
        throw const FormatException(
          'Invalid vaccine list.',
        );
      }

      final previews = <_VaccinePreview>[];

      for (final raw in list) {
        if (raw is! Map) continue;

        final item =
        Map<String, dynamic>.from(raw);

        final status =
            '${item['status'] ?? ''}';

        final isPublished =
            item['recommended_date'] != null &&
                state != 'NOT_AVAILABLE';

        if (isPublished &&
            status != 'UPCOMING' &&
            status != 'DUE') {
          continue;
        }

        if (!isPublished &&
            status != 'Planned') {
          continue;
        }

        final rawDate = isPublished
            ? item['recommended_date']
            : item['nextDate'] ?? item['date'];

        final date = DateTime.tryParse(
          '${rawDate ?? ''}',
        );

        if (date == null) continue;

        final vaccine = item['vaccine'];

        final name = vaccine is Map
            ? '${vaccine['name_en'] ?? ''}'.trim()
            : '';

        final title = name.isNotEmpty
            ? name
            : '${item['title'] ?? 'Vaccination'}';

        final dose =
        '${item['dose_name'] ?? ''}'.trim();

        previews.add(
          _VaccinePreview(
            dose.isEmpty
                ? title
                : '$title • $dose',
            date,
            isPublished,
          ),
        );
      }

      previews.sort(
            (a, b) => a.date.compareTo(b.date),
      );

      if (!_current(id, generation)) return;

      setState(() {
        _nextVaccine = previews.isEmpty
            ? null
            : previews.first;

        _vaccineMessage =
            '${result['message'] ?? ''}'.trim();

        if (state == 'NOT_AVAILABLE' &&
            previews.isEmpty &&
            _vaccineMessage!.isEmpty) {
          _vaccineMessage =
          'A medically reviewed schedule '
              'is not published yet.';
        }

        _loadingVaccine = false;
      });
    } catch (error) {
      if (!_current(id, generation)) return;

      setState(() {
        _loadingVaccine = false;
        _vaccineError = _errorText(error);
      });
    }
  }

  // ==========================================================
  // LOAD REMINDERS
  // ==========================================================

  Future<void> _loadReminders(
      String id,
      int generation,
      ) async {
    try {
      final data = await _request(
        '/api/v1/children/'
            '${Uri.encodeComponent(id)}/reminders',
      );

      if (!_current(id, generation)) return;

      final list = data['items'];

      if (list is! List) {
        throw const FormatException(
          'Invalid reminder list.',
        );
      }

      final preferences = data['preferences'];

      setState(() {
        _reminders = list
            .whereType<Map>()
            .map(
              (item) =>
          Map<String, dynamic>.from(item),
        )
            .toList();

        _inAppEnabled =
            preferences is! Map ||
                preferences['in_app'] != false;

        _loadingReminders = false;
      });
    } catch (error) {
      if (!_current(id, generation)) return;

      setState(() {
        _loadingReminders = false;
        _remindersError = _errorText(error);
      });
    }
  }

  // ==========================================================
  // SELECT CHILD
  // ==========================================================

  void _chooseChild(String? id) {
    if (id == null ||
        id == _selectedChildId) {
      return;
    }

    setState(() {
      _selectedChildId = id;
    });

    _refreshChild(id);
  }

  // ==========================================================
  // ADD CHILD
  // ==========================================================

  Future<void> _addChild() async {
    // AddChildScreen stays open after each save so the parent can
    // see all child cards. Keep the last created child ID to select
    // it after the screen closes.
    String? createdId;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AddChildScreen(
          apiBaseUrl: _baseUrl,
          onChildCreated: (createdProfile) {
            createdId = createdProfile['id']?.toString();
          },
        ),
      ),
    );

    if (!mounted) return;

    await _fetchChildren(
      preferredId: createdId ?? _selectedChildId,
    );
  }

  // ==========================================================
  // MANAGE CHILD PROFILE
  // ==========================================================

  Future<void> _manageChild() async {
    final child = _child;

    if (child == null) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.person_outline_rounded,
              ),
              title: Text(child.name),
              subtitle: const Text(
                'Manage child profile',
              ),
            ),

            ListTile(
              leading: const Icon(
                Icons.edit_outlined,
              ),
              title: const Text(
                'Edit Child Details',
              ),
              subtitle: const Text(
                'Name and date of birth',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _editChild(child);
              },
            ),

            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: ChildDashboardPalette.red,
              ),
              title: const Text(
                'Delete Child Profile',
                style: TextStyle(
                  color: ChildDashboardPalette.red,
                ),
              ),
              subtitle: const Text(
                'Requires an enabled backend deletion API',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteChild(child);
              },
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // EDIT CHILD
  // ==========================================================
  //
  // Profile editing requires PATCH support in Flask.
  // Do not update local records until server confirms.
  //
  // ==========================================================

  Future<void> _editChild(
      _ChildProfileInfo child,
      ) async {
    final form = GlobalKey<FormState>();

    final name = TextEditingController(
      text: child.name,
    );

    DateTime dob =
        child.dob ?? DateTime.now();

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) =>
            StatefulBuilder(
              builder: (
                  context,
                  setDialogState,
                  ) =>
                  AlertDialog(
                    title: const Text(
                      'Edit Child Details',
                    ),

                    content: Form(
                      key: form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: name,
                            maxLength: 120,
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                            ),
                            validator: (value) =>
                            value == null ||
                                value.trim().isEmpty
                                ? 'Enter the child name'
                                : null,
                          ),

                          const SizedBox(height: 10),

                          OutlinedButton.icon(
                            onPressed: _mutatingProfile
                                ? null
                                : () async {
                              final picked =
                              await showDatePicker(
                                context: dialogContext,
                                firstDate: DateTime(1900),
                                lastDate: DateTime.now(),
                                initialDate: dob,
                              );

                              if (picked != null) {
                                setDialogState(() {
                                  dob = picked;
                                });
                              }
                            },
                            icon: const Icon(
                              Icons.calendar_month_outlined,
                            ),
                            label: Text(
                              'DOB: ${_date(dob)}',
                            ),
                          ),

                          const SizedBox(height: 10),

                          const Text(
                            'The current backend does not '
                                'yet register an update route. '
                                'No change is saved unless '
                                'the server accepts it.',
                            style: TextStyle(
                              fontSize: 11,
                              color: ChildDashboardPalette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),

                    actions: [
                      TextButton(
                        onPressed: _mutatingProfile
                            ? null
                            : () => Navigator.pop(
                          dialogContext,
                        ),
                        child: const Text('Cancel'),
                      ),

                      FilledButton(
                        onPressed: _mutatingProfile
                            ? null
                            : () async {
                          if (form.currentState
                              ?.validate() !=
                              true) {
                            return;
                          }

                          setDialogState(() {
                            _mutatingProfile = true;
                          });

                          try {
                            await _request(
                              '/api/v1/patients/profiles/'
                                  '${Uri.encodeComponent(child.id)}',
                              method: 'PATCH',
                              data: {
                                'full_name':
                                name.text.trim(),
                                'date_of_birth':
                                _isoDate(dob),
                              },
                            );

                            if (!dialogContext.mounted) {
                              return;
                            }

                            Navigator.pop(
                              dialogContext,
                            );

                            await _fetchChildren(
                              preferredId: child.id,
                            );

                            _toast(
                              'Child details updated.',
                            );
                          } catch (error) {
                            _toast(
                              _errorText(error),
                              error: true,
                            );
                          } finally {
                            _mutatingProfile = false;

                            if (dialogContext.mounted) {
                              setDialogState(() {});
                            }
                          }
                        },
                        child: _mutatingProfile
                            ? const SizedBox.square(
                          dimension: 17,
                          child:
                          CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : const Text('Save'),
                      ),
                    ],
                  ),
            ),
      );
    } finally {
      name.dispose();
    }
  }

  // ==========================================================
  // DELETE CHILD
  // ==========================================================
  //
  // Requires backend DELETE endpoint.
  // Never remove records locally before server confirmation.
  // Deletion retention policy must be defined by backend.
  //
  // ==========================================================

  Future<void> _deleteChild(
      _ChildProfileInfo child,
      ) async {
    final confirm = TextEditingController();

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) =>
            StatefulBuilder(
              builder: (
                  context,
                  setDialogState,
                  ) =>
                  AlertDialog(
                    title: const Text(
                      'Delete Child Profile?',
                    ),

                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This may affect vaccination '
                              'history, reports, growth records '
                              'and doctor access for ${child.name}.',
                        ),

                        const SizedBox(height: 10),

                        const Text(
                          'The backend must define medical '
                              'record retention and deletion '
                              'handling. Nothing is deleted '
                              'locally first.',
                          style: TextStyle(
                            fontSize: 11,
                            color: ChildDashboardPalette.red,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          'Type "${child.name}" to confirm:',
                        ),

                        TextField(
                          controller: confirm,
                          onChanged: (_) {
                            setDialogState(() {});
                          },
                          decoration: const InputDecoration(
                            hintText: 'Child name',
                          ),
                        ),
                      ],
                    ),

                    actions: [
                      TextButton(
                        onPressed: _mutatingProfile
                            ? null
                            : () => Navigator.pop(
                          dialogContext,
                        ),
                        child: const Text('Cancel'),
                      ),

                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                          ChildDashboardPalette.red,
                        ),
                        onPressed: _mutatingProfile ||
                            confirm.text.trim() !=
                                child.name
                            ? null
                            : () async {
                          setDialogState(() {
                            _mutatingProfile = true;
                          });

                          try {
                            final result = await _request(
                              '/api/v1/patients/profiles/'
                                  '${Uri.encodeComponent(child.id)}',
                              method: 'DELETE',
                            );

                            if (!dialogContext.mounted) {
                              return;
                            }

                            Navigator.pop(
                              dialogContext,
                            );

                            if (result['_http_status'] ==
                                202) {
                              _toast(
                                'Deletion request accepted; '
                                    'status is pending.',
                              );
                            } else {
                              await _fetchChildren();

                              _toast(
                                'Child profile deletion '
                                    'confirmed by server.',
                              );
                            }
                          } catch (error) {
                            _toast(
                              _errorText(error),
                              error: true,
                            );
                          } finally {
                            _mutatingProfile = false;

                            if (dialogContext.mounted) {
                              setDialogState(() {});
                            }
                          }
                        },
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
            ),
      );
    } finally {
      confirm.dispose();
    }
  }

  // ==========================================================
  // OPEN CHILD CARE MODULE
  // ==========================================================

  Future<void> _openSection(
      String route, {
        String? childId,
      }) async {
    final id = childId ?? _selectedChildId;

    _ChildProfileInfo? child;

    for (final entry in _children) {
      if (entry.id == id) {
        child = entry;
        break;
      }
    }

    if (child == null) {
      _toast(
        'Add or select a child first.',
        error: true,
      );
      return;
    }

    final name = child.name;
    final dob = child.dob;

    late final Widget page;

    switch (route) {
    // ======================================================
    // CHILD PROFILE
    // ======================================================

      case 'profile':
        page = ChildProfileScreen(
          profileId: child.id,
          apiBaseUrl: _baseUrl,
          onOpenSection: (
              context,
              section,
              profileId,
              ) =>
              _openSection(
                section,
                childId: profileId,
              ),
        );
        break;

    // ======================================================
    // VACCINATION
    // ======================================================

      case 'vaccination':
      // VaccinationScreen now owns its API-backed schedules and
      // vaccination history. Old local editor arguments removed.
        page = VaccinationScreen(
          childId: child.id,
          apiBaseUrl: _baseUrl,
        );
        break;

    // ======================================================
    // MEDICAL HISTORY
    // ======================================================

      case 'medical-history':
        page = MedicalHistoryScreen(
          profileId: child.id,
          childName: name,
          childDateOfBirth: dob,
          initialRecords: List.of(
            _medicalHistory[child.id] ?? [],
          ),
          onRecordsChanged: (records) {
            _medicalHistory[child!.id] =
                List.of(records);

            if (mounted) {
              setState(() {});
            }
          },
        );
        break;

    // ======================================================
    // GROWTH & NUTRITION
    // ======================================================

      case 'growth':
        page = GrowthNutritionScreen(
          profileId: child.id,
          childName: name,
          childDateOfBirth: dob,
          initialGrowthRecords: List.of(
            _growth[child.id] ?? [],
          ),
          initialNutritionRecords: List.of(
            _nutrition[child.id] ?? [],
          ),
          onGrowthRecordsChanged: (records) {
            _growth[child!.id] =
                List.of(records);

            if (mounted) {
              setState(() {});
            }
          },
          onNutritionRecordsChanged: (records) {
            _nutrition[child!.id] =
                List.of(records);

            if (mounted) {
              setState(() {});
            }
          },
        );
        break;

    // ======================================================
    // DOCTOR CONSULTATION
    // ======================================================

      case 'doctor-consultation':
        page = DoctorConsultationScreen(
          profileId: child.id,
          childName: name,
          childDateOfBirth: dob,
          apiBaseUrl: _baseUrl,
          initialRecords: List.of(
            _consultations[child.id] ?? [],
          ),
          onRecordsChanged: (records) {
            _consultations[child!.id] =
                List.of(records);

            if (mounted) {
              setState(() {});
            }
          },
        );
        break;

    // ======================================================
    // CARE NOTES
    // ======================================================

      case 'care-notes':
        page = ChildCareNotesScreen(
          profileId: child.id,
          childName: name,
          childDateOfBirth: dob,
          apiBaseUrl: _baseUrl,
          initialNotes: List.of(
            _notes[child.id] ?? [],
          ),
          onNotesChanged: (records) {
            _notes[child!.id] =
                List.of(records);

            if (mounted) {
              setState(() {});
            }
          },
        );
        break;

    // ======================================================
    // HEALTH REPORTS
    // ======================================================

      case 'health-reports':
        page = HealthReportsScreen(
          profileId: child.id,
          childName: name,
          apiBaseUrl: _baseUrl,
        );
        break;

    // ======================================================
    // SETTINGS
    // ======================================================

      case 'settings':
        page = ChildSettingsScreen(
          profileId: child.id,
          apiBaseUrl: _baseUrl,
          onOpenSection: (
              context,
              section,
              profileId,
              ) =>
              _openSection(
                section,
                childId: profileId,
              ),
        );
        break;

      default:
        return;
    }

    // Close mobile drawer if open.

    if (_scaffoldKey.currentState
        ?.isDrawerOpen ==
        true) {
      Navigator.of(context).pop();
    }

    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => page,
      ),
    );

    if (mounted) {
      await _fetchChildren(
        preferredId: _selectedChildId,
      );
    }
  }

  // ==========================================================
  // DATE HELPERS
  // ==========================================================

  String _date(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _isoDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // ==========================================================
  // AGE
  // ==========================================================

  String _age(DateTime? dob) {
    final serverAge = _child?.ageDisplay;

    if (serverAge != null &&
        serverAge.isNotEmpty) {
      return serverAge;
    }

    if (dob == null) {
      return 'Age not recorded';
    }

    final now =
    DateUtils.dateOnly(DateTime.now());

    if (dob.isAfter(now)) {
      return 'Age unavailable';
    }

    var years = now.year - dob.year;
    var months = now.month - dob.month;

    if (now.day < dob.day) {
      months--;
    }

    if (months < 0) {
      years--;
      months += 12;
    }

    return years == 0
        ? '$months months'
        : '$years years $months months';
  }

  // ==========================================================
  // GREETING
  // ==========================================================

  String get _greeting {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'GOOD MORNING';
    }

    if (hour < 17) {
      return 'GOOD AFTERNOON';
    }

    return 'GOOD EVENING';
  }

  // ==========================================================
  // GROWTH DATA
  // ==========================================================

  List<GrowthMeasurementRecord>
  get _growthRecords {
    final id = _selectedChildId;

    if (id == null) return [];

    if (_serverGrowth.containsKey(id)) {
      return _serverGrowth[id]!;
    }

    return _growth[id] ?? [];
  }

  bool get _localGrowthOnly {
    final id = _selectedChildId;

    return id != null &&
        !_serverGrowth.containsKey(id) &&
        (_growth[id]?.isNotEmpty ?? false);
  }

  // ==========================================================
  // LATEST MEASUREMENT
  // ==========================================================

  double? _latest(String metric) {
    final sorted =
    List<GrowthMeasurementRecord>.from(
      _growthRecords,
    )..sort(
          (a, b) =>
          b.measuredAt.compareTo(a.measuredAt),
    );

    for (final record in sorted) {
      final value = metric == 'height'
          ? record.heightCm
          : metric == 'weight'
          ? record.weightKg
          : record.bmi;

      if (value != null && value.isFinite) {
        return value;
      }
    }

    return null;
  }

  // ==========================================================
  // CHART DATE FILTER
  // ==========================================================

  List<GrowthMeasurementRecord>
  get _chartRecords {
    if (_months == 0) {
      return _growthRecords;
    }

    final now = DateTime.now();

    final cutoff = DateTime(
      now.year,
      now.month - _months,
      now.day,
    );

    return _growthRecords
        .where(
          (record) =>
      !record.measuredAt.isBefore(cutoff),
    )
        .toList();
  }

  // ==========================================================
  // VACCINATION PREVIEW
  // ==========================================================

  _VaccinePreview? get _vaccine {
    // Upcoming doses are only taken from the backend response.
    // Parent-entered history must not be treated as a clinical
    // recommendation or invent a new vaccination due date.
    return _nextVaccine;
  }

  // ==========================================================
  // REMINDERS DIALOG
  // ==========================================================

  void _reminderDialog() {
    if (_child == null) {
      _toast(
        'Select a child first.',
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          AlertDialog(
            title: const Text(
              'Health Reminders',
            ),

            content: SizedBox(
              width: 390,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    if (_loadingReminders)
                      const Text(
                        'Loading reminders...',
                      )
                    else if (_remindersError != null)
                      Text(
                        'Could not load reminders: '
                            '$_remindersError',
                      )
                    else if (!_inAppEnabled)
                        const Text(
                          'In-app reminders are disabled '
                              'in Child Settings.',
                        )
                      else if (_reminders.isEmpty)
                          const Text(
                            'No currently eligible reminders.',
                          )
                        else
                          for (final item
                          in _reminders.take(30))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.notifications_active_outlined,
                              ),
                              title: Text(
                                '${item['title'] ?? 'Reminder'}',
                              ),
                              subtitle: Text(
                                '${item['date'] ?? ''} • '
                                    '${item['status'] ?? ''}\n'
                                    '${item['source'] == 'PUBLISHED_SCHEDULE' ? 'Published schedule' : 'Parent-reported'}',
                              ),
                            ),

                    const SizedBox(height: 12),

                    const Text(
                      'Parent-reported dates are not '
                          'verified medical recommendations. '
                          'No SMS reminders are enabled.',
                      style: TextStyle(
                        fontSize: 11,
                        color: ChildDashboardPalette.muted,
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
                  _openSection('settings');
                },
                child: const Text('Settings'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  // ==========================================================
  // MAIN BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop =
            constraints.maxWidth >= 960;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor:
          ChildDashboardPalette.background,

          // ==================================================
          // MOBILE DRAWER
          // ==================================================

          drawer: desktop
              ? null
              : Drawer(
            child: _sidebar(
              isDrawer: true,
            ),
          ),

          // ==================================================
          // MOBILE APP BAR
          // ==================================================

          appBar: desktop
              ? null
              : AppBar(
            backgroundColor: Colors.white,
            foregroundColor:
            ChildDashboardPalette.navy,
            title: const Text(
              'FamilyCare+ | Child Care',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            actions: [
              IconButton(
                onPressed: _addChild,
                tooltip: 'Add Child',
                icon: const Icon(
                  Icons.person_add_alt_1_rounded,
                ),
              ),
              IconButton(
                onPressed: _reminderDialog,
                tooltip: 'Health Reminders',
                icon: const Icon(
                  Icons.notifications_none_rounded,
                ),
              ),
            ],
          ),

          // ==================================================
          // MOBILE BOTTOM NAVIGATION
          // ==================================================

          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (index) {
              if (index == 1) {
                _openSection('vaccination');
              }

              if (index == 2) {
                _openSection('growth');
              }

              if (index == 3) {
                _scaffoldKey.currentState
                    ?.openDrawer();
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(
                  Icons.dashboard_outlined,
                ),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(
                  Icons.vaccines_outlined,
                ),
                label: 'Vaccination',
              ),
              NavigationDestination(
                icon: Icon(
                  Icons.show_chart_rounded,
                ),
                label: 'Growth',
              ),
              NavigationDestination(
                icon: Icon(
                  Icons.menu_rounded,
                ),
                label: 'More',
              ),
            ],
          ),

          // ==================================================
          // BODY
          // ==================================================

          body: Row(
            children: [
              if (desktop)
                SizedBox(
                  width: 260,
                  child: _sidebar(
                    isDrawer: false,
                  ),
                ),

              Expanded(
                child: Column(
                  children: [
                    if (desktop) _toolbar(),

                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () =>
                            _fetchChildren(
                              preferredId:
                              _selectedChildId,
                            ),
                        child: _body(desktop),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================
  // SIDEBAR
  // ==========================================================

  Widget _sidebar({
    required bool isDrawer,
  }) {
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                18,
                8,
                14,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    color: ChildDashboardPalette.blue,
                  ),

                  const SizedBox(width: 8),

                  const Expanded(
                    child: Text(
                      'FamilyCare+',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: ChildDashboardPalette.navy,
                      ),
                    ),
                  ),

                  if (isDrawer)
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                      ),
                      onPressed: () =>
                          Navigator.pop(context),
                    ),
                ],
              ),
            ),

            const Divider(height: 1),

            // =================================================
            // FAMILY OVERVIEW
            // =================================================

            Padding(
              padding: const EdgeInsets.fromLTRB(
                12,
                12,
                12,
                5,
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.arrow_back_rounded,
                ),
                title: const Text(
                  'Family Overview',
                ),
                onTap: () {
                  if (isDrawer) {
                    Navigator.pop(context);
                  }

                  Navigator.of(context).maybePop();
                },
              ),
            ),

            const Padding(
              padding: EdgeInsets.fromLTRB(
                19,
                0,
                0,
                10,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'CHILD CARE',
                  style: TextStyle(
                    color: ChildDashboardPalette.muted,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),

            // =================================================
            // NAVIGATION ITEMS
            // =================================================

            Expanded(
              child: ListView(
                children: [
                  _sideTile(
                    'Dashboard',
                    Icons.dashboard_outlined,
                    null,
                    isDrawer,
                  ),

                  for (final item in _modules)
                    _sideTile(
                      item.title,
                      item.icon,
                      item.route,
                      isDrawer,
                    ),

                  _sideTile(
                    'Child Profile',
                    Icons.account_circle_outlined,
                    'profile',
                    isDrawer,
                  ),

                  _sideTile(
                    'Settings',
                    Icons.settings_outlined,
                    'settings',
                    isDrawer,
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // =================================================
            // CHILD AND ACCOUNT CONTROLS
            // =================================================

            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (_child != null)
                    ListTile(
                      leading: const Icon(
                        Icons.child_care_rounded,
                        color: ChildDashboardPalette.blue,
                      ),
                      title: Text(
                        _childName,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _age(_child?.dob),
                      ),
                      onTap: () =>
                          _openSection('profile'),
                    ),

                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _addChild,
                      icon: const Icon(
                        Icons.add_circle_outline,
                      ),
                      label: const Text(
                        'Add Another Child',
                      ),
                    ),
                  ),

                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(
                        Icons.logout_rounded,
                      ),
                      label: const Text(
                        'Sign Out',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // SIDEBAR TILE
  // ==========================================================

  Widget _sideTile(
      String title,
      IconData icon,
      String? route,
      bool drawer,
      ) {
    final selected = route == null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 2,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        tileColor: selected
            ? const Color(0xFFEAF3FF)
            : null,
        leading: Icon(
          icon,
          size: 20,
          color: selected
              ? ChildDashboardPalette.blue
              : ChildDashboardPalette.muted,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: selected
                ? ChildDashboardPalette.blue
                : ChildDashboardPalette.body,
            fontWeight: selected
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
        onTap: () {
          if (route == null) {
            if (drawer) {
              Navigator.pop(context);
            }
          } else {
            _openSection(route);
          }
        },
      ),
    );
  }

  // ==========================================================
  // DESKTOP TOOLBAR
  // ==========================================================

  Widget _toolbar() {
    return Container(
      height: 76,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: ChildDashboardPalette.line,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
      ),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 350,
              ),
              child: _searchField(),
            ),
          ),

          const SizedBox(width: 10),

          IconButton(
            onPressed: _reminderDialog,
            tooltip: 'Reminders',
            icon: const Icon(
              Icons.notifications_none_rounded,
            ),
          ),

          const SizedBox(width: 10),

          FilledButton.icon(
            onPressed: _addChild,
            icon: const Icon(
              Icons.add_rounded,
            ),
            label: const Text(
              'Add Child',
            ),
          ),

          const SizedBox(width: 12),

          SizedBox(
            width: 160,
            child: _childDropdown(),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SEARCH FIELD
  // ==========================================================

  Widget _searchField() {
    return TextField(
      controller: _search,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search Child Care services...',
        prefixIcon: const Icon(
          Icons.search_rounded,
        ),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
          onPressed: _search.clear,
          icon: const Icon(
            Icons.close_rounded,
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ==========================================================
  // CHILD DROPDOWN
  // ==========================================================

  Widget _childDropdown() {
    if (_children.isEmpty ||
        _selectedChildId == null) {
      return const Text(
        'No child selected',
        style: TextStyle(
          fontSize: 12,
          color: ChildDashboardPalette.muted,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: ChildDashboardPalette.line,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _selectedChildId,
          style: const TextStyle(
            fontSize: 12,
            color: ChildDashboardPalette.navy,
            fontWeight: FontWeight.w700,
          ),
          items: _children.map((child) {
            return DropdownMenuItem<String>(
              value: child.id,
              child: Text(
                child.name,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: _chooseChild,
        ),
      ),
    );
  }

  // ==========================================================
  // DASHBOARD BODY
  // ==========================================================

  Widget _body(bool desktop) {
    if (_loadingChildren &&
        _children.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // ========================================================
    // LOAD ERROR
    // ========================================================

    if (_loadError != null) {
      return ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),

          const Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: ChildDashboardPalette.orange,
          ),

          const SizedBox(height: 14),

          const Center(
            child: Text(
              'Could Not Load Your Children',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              _loadError!,
              textAlign: TextAlign.center,
            ),
          ),

          Center(
            child: OutlinedButton.icon(
              onPressed: _fetchChildren,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text(
                'Try Again',
              ),
            ),
          ),
        ],
      );
    }

    // ========================================================
    // NO CHILD PROFILES
    // ========================================================

    if (_children.isEmpty) {
      return ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 50),

          _panel(
            child: Column(
              children: [
                const Icon(
                  Icons.child_care_rounded,
                  size: 54,
                  color: ChildDashboardPalette.blue,
                ),

                const SizedBox(height: 14),

                const Text(
                  'Start Your Child Care Journey',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  'Add your first child to start tracking '
                      'medical records, growth and vaccinations.',
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 20),

                FilledButton.icon(
                  onPressed: _addChild,
                  icon: const Icon(
                    Icons.add_rounded,
                  ),
                  label: const Text(
                    'Add Your Child',
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // ========================================================
    // MAIN DASHBOARD CONTENT
    // ========================================================

    return ListView(
      physics:
      const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        desktop ? 26 : 14,
        18,
        desktop ? 26 : 14,
        38,
      ),
      children: [
        if (!desktop) ...[
          _searchField(),

          const SizedBox(height: 12),

          Row(
            children: [
              const Text(
                'Selected Child',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: _childDropdown(),
              ),

              IconButton(
                tooltip: 'Manage Child',
                onPressed: _manageChild,
                icon: const Icon(
                  Icons.more_vert_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
        ],

        // ======================================================
        // BREADCRUMB AND MANAGE BUTTON
        // ======================================================

        Row(
          children: [
            const Expanded(
              child: Text(
                'Child Care / Dashboard',
                style: TextStyle(
                  color: ChildDashboardPalette.muted,
                  fontSize: 12,
                ),
              ),
            ),

            TextButton.icon(
              onPressed: _manageChild,
              icon: const Icon(
                Icons.manage_accounts_outlined,
                size: 17,
              ),
              label: const Text(
                'Manage',
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        _hero(desktop),

        const SizedBox(height: 16),

        _summaryTiles(),

        const SizedBox(height: 25),

        _heading(
          'Explore Child Care',
          'Everything for your child '
              'in one caring place.',
        ),

        const SizedBox(height: 13),

        _shortcuts(),

        const SizedBox(height: 24),

        _growthOverview(),

        const SizedBox(height: 18),

        _dataNotice(),

        const SizedBox(height: 28),

        const Center(
          child: Text(
            'FamilyCare+ • Healthier Families. '
                'Brighter Tomorrows.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: ChildDashboardPalette.muted,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // CHILD DASHBOARD HERO
  // ==========================================================
  //
  // Shared decorative image:
  // assets/images/dashboard_child.png
  //
  // No per-child profile photo is requested.
  // ==========================================================

  Widget _hero(bool desktop) {
    final child = _child!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < 345;

        final height = desktop
            ? 240.0
            : (narrow ? 168.0 : 190.0);

        return Container(
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: ChildDashboardPalette.line,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10245C96),
                blurRadius: 15,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              // ================================================
              // LEFT CONTENT
              // ================================================

              Expanded(
                flex: desktop ? 11 : 10,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: desktop ? 26 : 12,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF102E52),
                        Color(0xFF1B5083),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting,
                        style: TextStyle(
                          fontSize:
                          desktop ? 12 : 9,
                          letterSpacing: 1.0,
                          fontWeight:
                          FontWeight.w700,
                          color: const Color(
                            0xFFB6EBDD,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'Hello, ${child.name}!',
                        maxLines: 2,
                        overflow:
                        TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: desktop
                              ? 28
                              : (narrow ? 17 : 19),
                          fontWeight:
                          FontWeight.w900,
                          height: 1.12,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Every little milestone matters.',
                        maxLines: 2,
                        overflow:
                        TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(
                            0xFFD9EAF8,
                          ),
                          fontSize:
                          desktop ? 13 : 10.5,
                          height: 1.35,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        _age(child.dob),
                        maxLines: 1,
                        overflow:
                        TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize:
                          desktop ? 12 : 10,
                          fontWeight:
                          FontWeight.w700,
                          color: const Color(
                            0xFF9BE3D0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ================================================
              // RIGHT IMAGE
              // ================================================

              Expanded(
                flex: 10,
                child: Image.asset(
                  _heroAsset,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (
                      context,
                      error,
                      stackTrace,
                      ) {
                    return const ColoredBox(
                      color: Color(0xFFE7F7F3),
                      child: Center(
                        child: Icon(
                          Icons.child_care_rounded,
                          size: 52,
                          color:
                          ChildDashboardPalette.blue,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================
  // SUMMARY TILES
  // ==========================================================

  Widget _summaryTiles() {
    final doctorName =
    '${_child?.doctor?['full_name'] ?? ''}'
        .trim();

    final vaccine = _vaccine;

    final vaccineText = _loadingVaccine
        ? 'Loading...'
        : vaccine != null
        ? vaccine.title
        : _vaccineError != null
        ? 'Unavailable'
        : (_vaccineMessage != null &&
        _vaccineMessage!.isNotEmpty)
        ? 'Schedule not published'
        : 'No upcoming recorded dose';

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
        constraints.maxWidth >= 780 ? 4 : 2;

        const gap = 11.0;

        final tileWidth = (constraints.maxWidth -
            gap * (columns - 1)) /
            columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _summaryTile(
              tileWidth,
              'Child Profile',
              _age(_child?.dob),
              Icons.child_care_outlined,
              ChildDashboardPalette.blue,
                  () => _openSection('profile'),
            ),

            _summaryTile(
              tileWidth,
              'Next Vaccination',
              vaccineText,
              Icons.vaccines_outlined,
              ChildDashboardPalette.green,
                  () => _openSection('vaccination'),
            ),

            _summaryTile(
              tileWidth,
              'Health Reports',
              _reportCount == null
                  ? 'Unavailable'
                  : '$_reportCount saved',
              Icons.folder_copy_outlined,
              ChildDashboardPalette.purple,
                  () => _openSection('health-reports'),
            ),

            _summaryTile(
              tileWidth,
              'Connected Doctor',
              doctorName.isEmpty
                  ? 'Not connected'
                  : doctorName,
              Icons.medical_services_outlined,
              ChildDashboardPalette.orange,
                  () => _openSection(
                'doctor-consultation',
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // SINGLE SUMMARY TILE
  // ==========================================================

  Widget _summaryTile(
      double width,
      String label,
      String value,
      IconData icon,
      Color color,
      VoidCallback tap,
      ) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: 124,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius:
              BorderRadius.circular(16),
              border: Border.all(
                color: ChildDashboardPalette.line,
              ),
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: color,
                  size: 23,
                ),

                const SizedBox(height: 13),

                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color:
                    ChildDashboardPalette.muted,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color:
                    ChildDashboardPalette.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // CHILD CARE SHORTCUTS
  // ==========================================================

  Widget _shortcuts() {
    final text =
    _search.text.trim().toLowerCase();

    final items = _modules
        .where(
          (module) =>
      text.isEmpty ||
          module.title
              .toLowerCase()
              .contains(text) ||
          module.subtitle
              .toLowerCase()
              .contains(text),
    )
        .toList();

    if (items.isEmpty) {
      return _panel(
        child: Column(
          children: [
            const Text(
              'No matching services',
            ),
            TextButton(
              onPressed: _search.clear,
              child: const Text(
                'Clear search',
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
        constraints.maxWidth >= 840 ? 3 : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics:
          const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate:
          SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 11,
            crossAxisSpacing: 11,
            mainAxisExtent:
            constraints.maxWidth < 430
                ? 150
                : 140,
          ),
          itemBuilder: (context, index) {
            final item = items[index];

            return Material(
              color: item.background,
              borderRadius:
              BorderRadius.circular(17),
              child: InkWell(
                onTap: () =>
                    _openSection(item.route),
                borderRadius:
                BorderRadius.circular(17),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            item.icon,
                            color: item.color,
                            size: 26,
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_outward_rounded,
                            color: item.color,
                            size: 17,
                          ),
                        ],
                      ),

                      const Spacer(),

                      Text(
                        item.title,
                        maxLines: 2,
                        overflow:
                        TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color:
                          ChildDashboardPalette.navy,
                          fontWeight:
                          FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow:
                        TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color:
                          ChildDashboardPalette.body,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================
  // GROWTH OVERVIEW
  // ==========================================================

  Widget _growthOverview() {
    final chart = _panel(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          _heading(
            'Growth & Health Overview',
            'Recorded height, weight and BMI trends',
          ),

          const SizedBox(height: 16),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('All Metrics', 'all'),
                _chip('Height', 'height'),
                _chip('Weight', 'weight'),
                _chip('BMI', 'bmi'),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'Measurement History',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              DropdownButton<int>(
                value: _months,
                items: const [
                  DropdownMenuItem(
                    value: 3,
                    child: Text('3 months'),
                  ),
                  DropdownMenuItem(
                    value: 6,
                    child: Text('6 months'),
                  ),
                  DropdownMenuItem(
                    value: 12,
                    child: Text('12 months'),
                  ),
                  DropdownMenuItem(
                    value: 0,
                    child: Text('All time'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _months = value;
                    });
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          _chart(),

          const SizedBox(height: 12),

          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _legend(
                'Height (cm)',
                ChildDashboardPalette.blue,
              ),
              _legend(
                'Weight (kg)',
                ChildDashboardPalette.orange,
              ),
              _legend(
                'BMI',
                ChildDashboardPalette.purple,
              ),
            ],
          ),

          if (_metric == 'all') ...[
            const SizedBox(height: 8),

            const Text(
              'Each metric is normalized separately '
                  'because height, weight and BMI '
                  'have different units.',
              style: TextStyle(
                fontSize: 10,
                color: ChildDashboardPalette.muted,
              ),
            ),
          ],

          if (_localGrowthOnly) ...[
            const SizedBox(height: 8),

            const Text(
              'These measurements are local to '
                  'this session; backend saving '
                  'has not been confirmed.',
              style: TextStyle(
                fontSize: 10,
                color: ChildDashboardPalette.orange,
              ),
            ),
          ],

          if (_growthError != null) ...[
            const SizedBox(height: 8),

            Text(
              'Growth API error: $_growthError',
              style: const TextStyle(
                fontSize: 10,
                color: ChildDashboardPalette.red,
              ),
            ),
          ],

          const SizedBox(height: 14),

          OutlinedButton.icon(
            onPressed: () =>
                _openSection('growth'),
            icon: const Icon(
              Icons.add_chart_rounded,
            ),
            label: const Text(
              'Manage Measurements',
            ),
          ),
        ],
      ),
    );

    // ========================================================
    // KEY INSIGHTS PANEL
    // ========================================================

    final insights = _panel(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          _heading(
            'Key Insights',
            'Latest entered measurements',
          ),

          const SizedBox(height: 16),

          _insight(
            'Height',
            _latest('height'),
            'cm',
            Icons.straighten_rounded,
            ChildDashboardPalette.blue,
          ),

          const Divider(height: 23),

          _insight(
            'Weight',
            _latest('weight'),
            'kg',
            Icons.monitor_weight_outlined,
            ChildDashboardPalette.orange,
          ),

          const Divider(height: 23),

          _insight(
            'BMI',
            _latest('bmi'),
            '',
            Icons.analytics_outlined,
            ChildDashboardPalette.purple,
          ),

          const SizedBox(height: 15),

          const Text(
            'BMI alone cannot assess a child’s '
                'health. Clinical growth assessment '
                'needs age- and sex-specific standards.',
            style: TextStyle(
              fontSize: 10,
              height: 1.5,
              color: ChildDashboardPalette.muted,
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 830) {
          return Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: chart,
              ),

              const SizedBox(width: 15),

              Expanded(
                flex: 3,
                child: insights,
              ),
            ],
          );
        }

        return Column(
          children: [
            chart,
            const SizedBox(height: 14),
            insights,
          ],
        );
      },
    );
  }

  // ==========================================================
  // GROWTH CHART
  // ==========================================================

  Widget _chart() {
    final records = _chartRecords;

    final hasData = records.any(
          (record) => _metric == 'all'
          ? record.heightCm != null ||
          record.weightKg != null ||
          record.bmi != null
          : _metric == 'height'
          ? record.heightCm != null
          : _metric == 'weight'
          ? record.weightKg != null
          : record.bmi != null,
    );

    return Container(
      height: 255,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FCFF),
        border: Border.all(
          color: ChildDashboardPalette.line,
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: _loadingGrowth &&
          records.isEmpty
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : !hasData
          ? Column(
        mainAxisAlignment:
        MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.show_chart_rounded,
            size: 40,
            color:
            ChildDashboardPalette.green,
          ),

          const SizedBox(height: 10),

          const Text(
            'Watch Their Story Grow',
            style: TextStyle(
              fontWeight:
              FontWeight.w800,
            ),
          ),

          const SizedBox(height: 7),

          const Text(
            'Add measurements to see a trend.',
            textAlign: TextAlign.center,
          ),

          TextButton.icon(
            onPressed: () =>
                _openSection('growth'),
            icon: const Icon(
              Icons.add_rounded,
            ),
            label: const Text(
              'Add Measurement',
            ),
          ),
        ],
      )
          : Padding(
        padding: const EdgeInsets.all(12),
        child: CustomPaint(
          painter:
          _DashboardGrowthPainter(
            records,
            _metric,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  // ==========================================================
  // CHART FILTER CHIP
  // ==========================================================

  Widget _chip(
      String label,
      String value,
      ) {
    final active = _metric == value;

    return Padding(
      padding: const EdgeInsets.only(
        right: 7,
      ),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        showCheckmark: false,
        backgroundColor: const Color(
          0xFFF0F4F8,
        ),
        selectedColor:
        ChildDashboardPalette.blue,
        labelStyle: TextStyle(
          color: active
              ? Colors.white
              : ChildDashboardPalette.body,
          fontSize: 11,
        ),
        onSelected: (_) {
          setState(() {
            _metric = value;
          });
        },
      ),
    );
  }

  // ==========================================================
  // CHART LEGEND
  // ==========================================================

  Widget _legend(
      String title,
      Color color,
      ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 4,
          backgroundColor: color,
        ),

        const SizedBox(width: 6),

        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            color: ChildDashboardPalette.muted,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // KEY INSIGHT
  // ==========================================================

  Widget _insight(
      String title,
      double? value,
      String unit,
      IconData icon,
      Color color,
      ) {
    return Row(
      children: [
        Icon(
          icon,
          color: color,
          size: 25,
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
                  fontSize: 11,
                  color:
                  ChildDashboardPalette.muted,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                value == null
                    ? 'Not recorded'
                    : '${value.toStringAsFixed(1)} $unit'
                    .trim(),
                style: const TextStyle(
                  fontSize: 15,
                  color:
                  ChildDashboardPalette.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // SAVED BACKEND DATA INFORMATION
  // ==========================================================

  Widget _dataNotice() {
    final counts = _summary?['counts'];

    final history = counts is Map
        ? counts['history']
        : null;

    final noteCount = counts is Map
        ? counts['care']
        : null;

    final vaccine = _vaccine;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.cloud_done_outlined,
                color: ChildDashboardPalette.blue,
              ),

              SizedBox(width: 9),

              Text(
                'FamilyCare+ Health Data',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color:
                  ChildDashboardPalette.navy,
                ),
              ),
            ],
          ),

          const SizedBox(height: 9),

          Text(
            _loadingDetail
                ? 'Loading saved child '
                'health summary...'
                : _summary == null
                ? 'Detailed child health '
                'summary is currently unavailable.'
                : 'Saved medical history: '
                '${history ?? 0} • '
                'Care notes: ${noteCount ?? 0}',
            style: const TextStyle(
              fontSize: 11,
              color: ChildDashboardPalette.body,
            ),
          ),

          const SizedBox(height: 8),

          if (vaccine != null)
            Text(
              '${vaccine.published ? 'Published schedule' : 'Parent-entered plan'}: '
                  '${vaccine.title} • ${_date(vaccine.date)}',
              style: const TextStyle(
                fontSize: 11,
                color: ChildDashboardPalette.green,
              ),
            )
          else if (_vaccineMessage != null &&
              _vaccineMessage!.isNotEmpty)
            Text(
              _vaccineMessage!,
              style: const TextStyle(
                fontSize: 11,
                color: ChildDashboardPalette.muted,
              ),
            ),

          if (_vaccineError != null)
            Text(
              'Vaccination data unavailable: '
                  '$_vaccineError',
              style: const TextStyle(
                fontSize: 11,
                color: ChildDashboardPalette.red,
              ),
            ),

          const SizedBox(height: 7),

          const Text(
            'Older module editors may still store '
                'unsaved in-session entries. '
                'Backend data is authoritative.',
            style: TextStyle(
              fontSize: 10,
              color: ChildDashboardPalette.muted,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SECTION HEADING
  // ==========================================================

  Widget _heading(
      String title,
      String subtitle,
      ) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: ChildDashboardPalette.navy,
          ),
        ),

        const SizedBox(height: 5),

        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 11,
            color: ChildDashboardPalette.muted,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // REUSABLE PANEL
  // ==========================================================

  Widget _panel({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: ChildDashboardPalette.line,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }

  // ==========================================================
  // SIGN OUT
  // ==========================================================

  Future<void> _signOut() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          AlertDialog(
            title: const Text('Sign out?'),
            content: const Text(
              'Sign out of FamilyCare+?',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                      dialogContext,
                      false,
                    ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(
                      dialogContext,
                      true,
                    ),
                child: const Text('Sign Out'),
              ),
            ],
          ),
    );

    if (yes != true || !mounted) return;

    await FamilyCareSession.clear();

    if (mounted) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil(
        '/login',
            (route) => false,
      );
    }
  }
}

// ============================================================
// CUSTOM GROWTH CHART PAINTER
// ============================================================

class _DashboardGrowthPainter
    extends CustomPainter {
  final List<GrowthMeasurementRecord> records;
  final String metric;

  const _DashboardGrowthPainter(
      this.records,
      this.metric,
      );

  // ==========================================================
  // MEASUREMENT VALUE
  // ==========================================================

  double? _value(
      GrowthMeasurementRecord record,
      String key,
      ) {
    switch (key) {
      case 'height':
        return record.heightCm;

      case 'weight':
        return record.weightKg;

      case 'bmi':
        return record.bmi;

      default:
        return null;
    }
  }

  // ==========================================================
  // METRIC COLOR
  // ==========================================================

  Color _color(String key) {
    switch (key) {
      case 'height':
        return ChildDashboardPalette.blue;

      case 'weight':
        return ChildDashboardPalette.orange;

      default:
        return ChildDashboardPalette.purple;
    }
  }

  // ==========================================================
  // DRAW TEXT
  // ==========================================================

  void _text(
      Canvas canvas,
      String value,
      Offset position,
      ) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: const TextStyle(
          fontSize: 9,
          color: ChildDashboardPalette.muted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      position,
    );
  }

  // ==========================================================
  // PAINT CHART
  // ==========================================================

  @override
  void paint(
      Canvas canvas,
      Size size,
      ) {
    if (records.isEmpty ||
        size.width < 50 ||
        size.height < 50) {
      return;
    }

    final sorted =
    List<GrowthMeasurementRecord>.from(records)
      ..sort(
            (a, b) =>
            a.measuredAt.compareTo(
              b.measuredAt,
            ),
      );

    final first =
        sorted.first.measuredAt;

    final last =
        sorted.last.measuredAt;

    final spanMs =
        last.difference(first).inMilliseconds;

    final area = Rect.fromLTWH(
      metric == 'all' ? 15 : 43,
      15,
      math.max(
        1.0,
        size.width -
            (metric == 'all' ? 32 : 60),
      ),
      math.max(
        1.0,
        size.height - 46,
      ),
    );

    // ========================================================
    // GRID
    // ========================================================

    final grid = Paint()
      ..color = const Color(0xFFE4ECF4)
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y =
          area.top + area.height * i / 4;

      canvas.drawLine(
        Offset(area.left, y),
        Offset(area.right, y),
        grid,
      );
    }

    // ========================================================
    // METRIC SELECTION
    // ========================================================

    final metrics = metric == 'all'
        ? ['height', 'weight', 'bmi']
        : [metric];

    for (final key in metrics) {
      final values = <({
      DateTime date,
      double value,
      })>[];

      for (final record in sorted) {
        final value = _value(record, key);

        if (value != null &&
            value.isFinite) {
          values.add((
          date: record.measuredAt,
          value: value,
          ));
        }
      }

      if (values.isEmpty) continue;

      // ======================================================
      // MIN / MAX
      // ======================================================

      final minValue = values
          .map((e) => e.value)
          .reduce(math.min);

      final maxValue = values
          .map((e) => e.value)
          .reduce(math.max);

      final range = maxValue - minValue;

      final pad = range == 0
          ? math.max(
        1.0,
        maxValue.abs() * 0.05,
      )
          : range * .15;

      final low = minValue - pad;
      final high = maxValue + pad;

      // ======================================================
      // SINGLE METRIC Y AXIS
      // ======================================================

      if (metric != 'all') {
        for (var i = 0; i <= 4; i++) {
          _text(
            canvas,
            (high -
                (high - low) * i / 4)
                .toStringAsFixed(1),
            Offset(
              0,
              area.top +
                  area.height * i / 4 -
                  6,
            ),
          );
        }
      }

      // ======================================================
      // LINE STYLING
      // ======================================================

      final pen = Paint()
        ..color = _color(key)
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final dot = Paint()
        ..color = _color(key);

      final path = Path();

      // ======================================================
      // POINTS
      // ======================================================

      for (var i = 0; i < values.length; i++) {
        final point = values[i];

        final fx = spanMs == 0
            ? .5
            : point.date
            .difference(first)
            .inMilliseconds /
            spanMs;

        final fy = metric == 'all'
            ? (range == 0
            ? .5
            : .1 +
            .8 *
                (point.value -
                    minValue) /
                range)
            : (point.value - low) /
            (high - low);

        final x = area.left +
            area.width *
                fx.clamp(0.0, 1.0);

        final y =
            area.bottom - area.height * fy;

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }

        canvas.drawCircle(
          Offset(x, y),
          3.2,
          dot,
        );
      }

      canvas.drawPath(
        path,
        pen,
      );
    }

    // ========================================================
    // DATE LABELS
    // ========================================================

    String label(DateTime date) {
      return '${date.day}/'
          '${date.month}/'
          '${date.year % 100}';
    }

    _text(
      canvas,
      label(first),
      Offset(
        area.left,
        area.bottom + 12,
      ),
    );

    if (!DateUtils.isSameDay(first, last)) {
      _text(
        canvas,
        label(last),
        Offset(
          math.max(
            area.left,
            area.right - 48,
          ),
          area.bottom + 12,
        ),
      );
    }
  }

  // ==========================================================
  // REPAINT
  // ==========================================================

  @override
  bool shouldRepaint(
      covariant _DashboardGrowthPainter old,
      ) {
    return old.metric != metric ||
        !listEquals(
          old.records,
          records,
        );
  }
}