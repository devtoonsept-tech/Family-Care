
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

// ============================================================
// FamilyCare+ - Growth & Nutrition
//
// Backend:
// GET    /api/v1/children/{id}/growth
// POST   /api/v1/children/{id}/growth
// PATCH  /api/v1/children/{id}/growth/{recordId}
// DELETE /api/v1/children/{id}/growth/{recordId}
//
// GET    /api/v1/children/{id}/nutrition
// POST   /api/v1/children/{id}/nutrition
// PATCH  /api/v1/children/{id}/nutrition/{recordId}
// DELETE /api/v1/children/{id}/nutrition/{recordId}
//
// Uses the authenticated FamilyCareSession.
// No extra chart library is required.
//
// Parent-entered records are the source of the charts.
// BMI is numerical only, not a clinical classification.
// ============================================================

class GrowthNutritionColors {
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
  static const pink = Color(0xFFD68788);
  static const red = Color(0xFFB7434E);

  static const lightGreen = Color(0xFFEAF5ED);
  static const lightBlue = Color(0xFFEAF5FF);
  static const lightOrange = Color(0xFFFFF4E7);
}

class GrowthDateFormatter {
  static const months = [
    'Jan', 'Feb', 'Mar', 'Apr',
    'May', 'Jun', 'Jul', 'Aug',
    'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String format(DateTime date) =>
      '${date.day} ${months[date.month - 1]} ${date.year}';

  static String short(DateTime date) =>
      '${date.day} ${months[date.month - 1]}';

  static String api(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

  static DateTime parse(dynamic value) {
    final parsed = DateTime.tryParse(
      (value ?? '').toString(),
    );

    if (parsed == null) {
      throw const FormatException(
        'Invalid record date received from server.',
      );
    }

    return parsed;
  }
}

// ============================================================
// MODELS - KEEP PUBLIC NAMES FOR DASHBOARD COMPATIBILITY
// ============================================================

class GrowthMeasurementRecord {
  final String id;
  final String profileId;
  final DateTime measuredAt;
  final double? heightCm;
  final double? weightKg;
  final String notes;

  // The backend exposes DOCTOR_REPORTED for entries authored by a doctor.
  // The family must not be shown edit/delete controls for these entries.
  final bool isDoctorAuthored;

  const GrowthMeasurementRecord({
    required this.id,
    required this.profileId,
    required this.measuredAt,
    this.heightCm,
    this.weightKg,
    this.notes = '',
    this.isDoctorAuthored = false,
  });

  double? get bmi {
    final h = heightCm;
    final w = weightKg;

    if (h == null || w == null || h <= 0 || w <= 0) {
      return null;
    }

    final meters = h / 100;
    return w / (meters * meters);
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
  }

  factory GrowthMeasurementRecord.fromApi(
      Map<String, dynamic> json,
      String profileId,
      ) {
    return GrowthMeasurementRecord(
      id: (json['id'] ?? '').toString(),
      profileId: profileId,
      measuredAt: GrowthDateFormatter.parse(json['date']),
      heightCm: _number(json['height']),
      weightKg: _number(json['weight']),
      notes: (json['notes'] ?? '').toString(),
      isDoctorAuthored: json['verification_status'] == 'DOCTOR_REPORTED' ||
          json['source_role'] == 'DOCTOR',
    );
  }

  Map<String, dynamic> toApiPayload() {
    return {
      'title': 'Growth Measurement',
      'date': GrowthDateFormatter.api(measuredAt),
      'height': heightCm?.toString() ?? '',
      'weight': weightKg?.toString() ?? '',
      'notes': notes.trim(),
    };
  }
}

enum NutritionMealType {
  breakfast,
  lunch,
  dinner,
  snack,
  other,
}

extension NutritionMealDetails on NutritionMealType {
  String get label {
    switch (this) {
      case NutritionMealType.breakfast:
        return 'Breakfast';
      case NutritionMealType.lunch:
        return 'Lunch';
      case NutritionMealType.dinner:
        return 'Dinner';
      case NutritionMealType.snack:
        return 'Snack';
      case NutritionMealType.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case NutritionMealType.breakfast:
        return Icons.wb_sunny_outlined;
      case NutritionMealType.lunch:
        return Icons.lunch_dining_outlined;
      case NutritionMealType.dinner:
        return Icons.dinner_dining_outlined;
      case NutritionMealType.snack:
        return Icons.cookie_outlined;
      case NutritionMealType.other:
        return Icons.restaurant_outlined;
    }
  }

  Color get color {
    switch (this) {
      case NutritionMealType.breakfast:
        return GrowthNutritionColors.orange;
      case NutritionMealType.lunch:
        return GrowthNutritionColors.green;
      case NutritionMealType.dinner:
        return GrowthNutritionColors.purple;
      case NutritionMealType.snack:
        return GrowthNutritionColors.pink;
      case NutritionMealType.other:
        return GrowthNutritionColors.blue;
    }
  }
}

class NutritionDiaryRecord {
  final String id;
  final String profileId;
  final DateTime date;
  final NutritionMealType mealType;
  final String foodDetails;
  final String portion;
  final String notes;
  final bool isDoctorAuthored;

  const NutritionDiaryRecord({
    required this.id,
    required this.profileId,
    required this.date,
    required this.mealType,
    required this.foodDetails,
    this.portion = '',
    this.notes = '',
    this.isDoctorAuthored = false,
  });

  factory NutritionDiaryRecord.fromApi(
      Map<String, dynamic> json,
      String profileId,
      ) {
    final meal = (json['meal'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    final type = NutritionMealType.values.firstWhere(
          (item) => item.label.toLowerCase() == meal,
      orElse: () => NutritionMealType.other,
    );

    return NutritionDiaryRecord(
      id: (json['id'] ?? '').toString(),
      profileId: profileId,
      date: GrowthDateFormatter.parse(json['date']),
      mealType: type,
      foodDetails: (json['title'] ?? '').toString(),
      // Backend v5 retains the free-text portion in its generic category field.
      // A dedicated portion field should be introduced in a future API version.
      portion: (json['category'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      isDoctorAuthored: json['verification_status'] == 'DOCTOR_REPORTED' ||
          json['source_role'] == 'DOCTOR',
    );
  }

  Map<String, dynamic> toApiPayload() {
    return {
      'title': foodDetails.trim(),
      'date': GrowthDateFormatter.api(date),
      'meal': mealType.label,
      'category': portion.trim(),
      'notes': notes.trim(),
    };
  }
}

enum GrowthChartMetric {
  all,
  height,
  weight,
  bmi,
}

extension GrowthChartMetricDetails on GrowthChartMetric {
  String get label {
    switch (this) {
      case GrowthChartMetric.all:
        return 'All Metrics';
      case GrowthChartMetric.height:
        return 'Height';
      case GrowthChartMetric.weight:
        return 'Weight';
      case GrowthChartMetric.bmi:
        return 'BMI';
    }
  }

  Color get color {
    switch (this) {
      case GrowthChartMetric.all:
        return GrowthNutritionColors.green;
      case GrowthChartMetric.height:
        return GrowthNutritionColors.blue;
      case GrowthChartMetric.weight:
        return GrowthNutritionColors.orange;
      case GrowthChartMetric.bmi:
        return GrowthNutritionColors.purple;
    }
  }

  String get unit {
    switch (this) {
      case GrowthChartMetric.height:
        return 'cm';
      case GrowthChartMetric.weight:
        return 'kg';
      case GrowthChartMetric.all:
      case GrowthChartMetric.bmi:
        return '';
    }
  }
}

enum GrowthNutritionTab {
  growth,
  nutrition,
}

// ============================================================
// API
// ============================================================

class GrowthNutritionApiException implements Exception {
  final String message;
  final int statusCode;

  const GrowthNutritionApiException(
      this.message, {
        this.statusCode = 0,
      });

  @override
  String toString() => message;
}

class _GrowthNutritionApi {
  final String baseUrl;
  final String profileId;

  final http.Client _client = http.Client();

  _GrowthNutritionApi({
    required this.baseUrl,
    required this.profileId,
  });

  String _path(String module, [String? recordId]) {
    final childId = Uri.encodeComponent(profileId);
    final root = '/api/v1/children/$childId/$module';

    if (recordId == null) return root;

    return '$root/${Uri.encodeComponent(recordId)}';
  }

  void dispose() => _client.close();

  Future<Map<String, String>> _headers() async {
    final token = await FamilyCareSession.accessToken();

    if (token == null || token.trim().isEmpty) {
      throw const GrowthNutritionApiException(
        'Login session is missing. Please sign in again.',
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

  Future<Map<String, dynamic>> request(
      String method,
      String path, {
        Map<String, dynamic>? body,
      }) async {
    final headers = await _headers();
    final uri = Uri.parse('$baseUrl$path');

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
        throw const GrowthNutritionApiException(
          'Unsupported request method.',
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
        throw GrowthNutritionApiException(
          'Invalid response received from server.',
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
        message = 'Session expired. Please sign in again.';
      }

      if (response.statusCode == 403) {
        message = 'Access to this child was denied.';
      }

      throw GrowthNutritionApiException(
        message,
        statusCode: response.statusCode,
      );
    }

    return data;
  }

  Future<List<Map<String, dynamic>>> listRecords(
      String module,
      ) async {
    final records = <Map<String, dynamic>>[];

    for (int page = 1; page <= 100; page++) {
      final result = await request(
        'GET',
        '${_path(module)}?page=$page&per_page=100',
      );

      final items = result['items'];

      if (items is! List) {
        throw const GrowthNutritionApiException(
          'Invalid records list received from server.',
        );
      }

      for (final item in items) {
        if (item is Map) {
          records.add(Map<String, dynamic>.from(item));
        }
      }

      final total = result['total'];

      if (items.length < 100 ||
          (total is num && records.length >= total)) {
        break;
      }
    }

    return records;
  }

  Future<void> saveRecord(
      String module,
      Map<String, dynamic> payload, {
        String? id,
      }) async {
    await request(
      id == null ? 'POST' : 'PATCH',
      _path(module, id),
      body: payload,
    );
  }

  Future<void> deleteRecord(
      String module,
      String id,
      ) async {
    await request('DELETE', _path(module, id));
  }
}

// ============================================================
// SCREEN
// ============================================================

class GrowthNutritionScreen extends StatefulWidget {
  final String profileId;
  final String childName;
  final DateTime? childDateOfBirth;
  final String apiBaseUrl;

  final List<GrowthMeasurementRecord> initialGrowthRecords;
  final List<NutritionDiaryRecord> initialNutritionRecords;

  final ValueChanged<List<GrowthMeasurementRecord>>?
  onGrowthRecordsChanged;

  final ValueChanged<List<NutritionDiaryRecord>>?
  onNutritionRecordsChanged;

  const GrowthNutritionScreen({
    super.key,
    required this.profileId,
    this.childName = 'Child',
    this.childDateOfBirth,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.initialGrowthRecords = const [],
    this.initialNutritionRecords = const [],
    this.onGrowthRecordsChanged,
    this.onNutritionRecordsChanged,
  });

  @override
  State<GrowthNutritionScreen> createState() =>
      _GrowthNutritionScreenState();
}

class _GrowthNutritionScreenState
    extends State<GrowthNutritionScreen> {
  final TextEditingController _nutritionSearch =
  TextEditingController();

  late _GrowthNutritionApi _api;

  List<GrowthMeasurementRecord> _growthRecords = [];
  List<NutritionDiaryRecord> _nutritionRecords = [];

  DateTime? _serverChildDateOfBirth;
  String? _serverChildName;

  DateTime? get _effectiveChildDob =>
      widget.childDateOfBirth ?? _serverChildDateOfBirth;

  String get _effectiveChildName {
    final passed = widget.childName.trim();
    if (passed.isNotEmpty && passed != 'Child') return passed;
    return _serverChildName ?? 'Child';
  }

  GrowthNutritionTab _selectedTab =
      GrowthNutritionTab.growth;

  GrowthChartMetric _selectedMetric =
      GrowthChartMetric.all;

  NutritionMealType? _mealFilter;

  int _selectedMonths = 12;
  int _generation = 0;

  bool _loading = true;
  bool _busy = false;

  String? _loadError;

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

    _api = _GrowthNutritionApi(
      baseUrl: _baseUrl,
      profileId: widget.profileId,
    );

    _nutritionSearch.addListener(_onSearchChanged);
    _loadRecords();
    _loadChildDetailsIfNeeded();
  }

  @override
  void didUpdateWidget(
      covariant GrowthNutritionScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.profileId != widget.profileId ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _generation++;

      _api.dispose();
      _api = _GrowthNutritionApi(
        baseUrl: _baseUrl,
        profileId: widget.profileId,
      );

      _growthRecords = [];
      _nutritionRecords = [];
      _serverChildDateOfBirth = null;
      _serverChildName = null;
      _busy = false;
      _loadError = null;

      _selectedTab = GrowthNutritionTab.growth;
      _selectedMetric = GrowthChartMetric.all;
      _selectedMonths = 12;
      _mealFilter = null;

      _nutritionSearch.clear();
      _loadRecords();
      _loadChildDetailsIfNeeded();
    }
  }

  @override
  void dispose() {
    _generation++;
    _api.dispose();

    _nutritionSearch.removeListener(_onSearchChanged);
    _nutritionSearch.dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  String _friendlyError(Object error) {
    if (error is GrowthNutritionApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'Server response timed out.';
    }

    if (error is http.ClientException) {
      return 'Cannot connect to FamilyCare+ server.';
    }

    if (error is FormatException) {
      return 'Server returned invalid record data.';
    }

    return 'Something went wrong. Please retry.';
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
              ? GrowthNutritionColors.red
              : GrowthNutritionColors.navy,
          content: Text(value),
        ),
      );
  }

  // ==========================================================
  // FETCH CHILD DETAILS IF DASHBOARD DID NOT PASS DOB
  // ==========================================================

  Future<void> _loadChildDetailsIfNeeded() async {
    if (widget.childDateOfBirth != null &&
        widget.childName.trim().isNotEmpty &&
        widget.childName.trim() != 'Child') {
      return;
    }

    final profileId = widget.profileId;
    final api = _api;

    try {
      final response = await api.request(
        'GET',
        '/api/v1/children/${Uri.encodeComponent(profileId)}',
      );
      if (!mounted || widget.profileId != profileId || _api != api) return;

      final child = response['child'];
      if (child is! Map) return;

      final dob = DateTime.tryParse((child['date_of_birth'] ?? '').toString());
      final name = (child['full_name'] ?? '').toString().trim();

      setState(() {
        _serverChildDateOfBirth = dob;
        _serverChildName = name.isEmpty ? null : name;
      });
    } catch (_) {
      // The growth/nutrition APIs remain usable even if this optional
      // profile lookup fails. The server independently checks record dates.
    }
  }

  // ==========================================================
  // LOAD BOTH MODULES FROM FLASK
  // ==========================================================

  Future<bool> _loadRecords({
    bool showLoader = true,
  }) async {
    final generation = ++_generation;
    final profileId = widget.profileId;
    final api = _api;

    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final responses = await Future.wait([
        api.listRecords('growth'),
        api.listRecords('nutrition'),
      ]);

      final growth = responses[0]
          .map(
            (json) => GrowthMeasurementRecord.fromApi(
          json,
          profileId,
        ),
      )
          .toList();

      final nutrition = responses[1]
          .map(
            (json) => NutritionDiaryRecord.fromApi(
          json,
          profileId,
        ),
      )
          .toList();

      if (!mounted ||
          generation != _generation ||
          profileId != widget.profileId) {
        return false;
      }

      setState(() {
        _growthRecords = growth;
        _nutritionRecords = nutrition;

        _loading = false;
        _loadError = null;
      });

      widget.onGrowthRecordsChanged?.call(
        List<GrowthMeasurementRecord>.unmodifiable(growth),
      );

      widget.onNutritionRecordsChanged?.call(
        List<NutritionDiaryRecord>.unmodifiable(nutrition),
      );

      return true;
    } catch (error) {
      if (!mounted ||
          generation != _generation ||
          profileId != widget.profileId) {
        return false;
      }

      setState(() {
        _loading = false;
        // A refresh failure after a confirmed mutation must not hide
        // already loaded records or disable all editing indefinitely.
        if (showLoader) {
          _loadError = _friendlyError(error);
        }
      });

      return false;
    }
  }

  // ==========================================================
  // GROWTH DATA
  // ==========================================================

  List<GrowthMeasurementRecord> get _sortedGrowth {
    final result =
    List<GrowthMeasurementRecord>.from(_growthRecords);

    result.sort(
          (a, b) => a.measuredAt.compareTo(b.measuredAt),
    );

    return result;
  }

  List<GrowthMeasurementRecord> get _filteredGrowth {
    final records = _sortedGrowth;

    if (_selectedMonths == 0) return records;

    final now = DateTime.now();

    final cutoff = DateTime(
      now.year,
      now.month - _selectedMonths,
      now.day,
    );

    return records
        .where(
          (record) => !record.measuredAt.isBefore(cutoff),
    )
        .toList();
  }

  double? _metricValue(
      GrowthMeasurementRecord record,
      GrowthChartMetric metric,
      ) {
    switch (metric) {
      case GrowthChartMetric.height:
        return record.heightCm;
      case GrowthChartMetric.weight:
        return record.weightKg;
      case GrowthChartMetric.bmi:
        return record.bmi;
      case GrowthChartMetric.all:
        return null;
    }
  }

  double? _latestValue(GrowthChartMetric metric) {
    for (final record in _sortedGrowth.reversed) {
      final value = _metricValue(record, metric);
      if (value != null) return value;
    }

    return null;
  }

  // ==========================================================
  // NUTRITION DATA
  // ==========================================================

  List<NutritionDiaryRecord> get _filteredNutrition {
    final query =
    _nutritionSearch.text.trim().toLowerCase();

    final result = _nutritionRecords.where((record) {
      if (_mealFilter != null &&
          record.mealType != _mealFilter) {
        return false;
      }

      if (query.isEmpty) return true;

      return [
        record.foodDetails,
        record.portion,
        record.notes,
        record.mealType.label,
      ].any(
            (value) => value.toLowerCase().contains(query),
      );
    }).toList();

    result.sort((a, b) => b.date.compareTo(a.date));

    return result;
  }

  // ==========================================================
  // ADD / EDIT GROWTH
  // ==========================================================

  Future<void> _openGrowthEditor({
    GrowthMeasurementRecord? existing,
  }) async {
    if (_busy || _loading || _loadError != null) return;
    if (existing?.isDoctorAuthored == true) {
      _message('Doctor-entered measurements are read-only.', error: true);
      return;
    }

    final profileId = widget.profileId;

    final record =
    await showModalBottomSheet<GrowthMeasurementRecord>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GrowthMeasurementEditor(
        profileId: profileId,
        childName: _effectiveChildName,
        childDateOfBirth: _effectiveChildDob,
        existing: existing,
        newRecordId: '',
      ),
    );

    if (!mounted ||
        record == null ||
        profileId != widget.profileId) {
      return;
    }

    setState(() => _busy = true);

    try {
      await _api.saveRecord(
        'growth',
        record.toApiPayload(),
        id: existing?.id,
      );

      if (!mounted || profileId != widget.profileId) {
        return;
      }

      final refreshed = await _loadRecords(
        showLoader: false,
      );

      if (!mounted) return;

      _message(
        refreshed
            ? existing == null
            ? 'Measurement saved to FamilyCare+.'
            : 'Measurement updated successfully.'
            : 'Measurement saved by server; refresh the list to display it.',
      );
    } catch (error) {
      if (mounted && profileId == widget.profileId) {
        _message(_friendlyError(error), error: true);
      }
    } finally {
      if (mounted && profileId == widget.profileId) {
        setState(() => _busy = false);
      }
    }
  }

  // ==========================================================
  // ADD / EDIT NUTRITION
  // ==========================================================

  Future<void> _openNutritionEditor({
    NutritionDiaryRecord? existing,
  }) async {
    if (_busy || _loading || _loadError != null) return;
    if (existing?.isDoctorAuthored == true) {
      _message('Doctor-entered meal entries are read-only.', error: true);
      return;
    }

    final profileId = widget.profileId;

    final record =
    await showModalBottomSheet<NutritionDiaryRecord>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NutritionDiaryEditor(
        profileId: profileId,
        childName: _effectiveChildName,
        childDateOfBirth: _effectiveChildDob,
        existing: existing,
        newRecordId: '',
      ),
    );

    if (!mounted ||
        record == null ||
        profileId != widget.profileId) {
      return;
    }

    setState(() => _busy = true);

    try {
      await _api.saveRecord(
        'nutrition',
        record.toApiPayload(),
        id: existing?.id,
      );

      if (!mounted || profileId != widget.profileId) {
        return;
      }

      final refreshed = await _loadRecords(
        showLoader: false,
      );

      if (!mounted) return;

      _message(
        refreshed
            ? existing == null
            ? 'Meal entry saved to FamilyCare+.'
            : 'Meal entry updated successfully.'
            : 'Meal saved by server; refresh the list to display it.',
      );
    } catch (error) {
      if (mounted && profileId == widget.profileId) {
        _message(_friendlyError(error), error: true);
      }
    } finally {
      if (mounted && profileId == widget.profileId) {
        setState(() => _busy = false);
      }
    }
  }

  // ==========================================================
  // DELETE RECORDS
  // ==========================================================

  Future<bool> _confirmDelete(
      String title,
      String message,
      ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            style: TextButton.styleFrom(
              foregroundColor: GrowthNutritionColors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _deleteGrowth(
      GrowthMeasurementRecord record,
      ) async {
    if (_busy || _loadError != null) return;
    if (record.isDoctorAuthored) {
      _message('Doctor-entered records cannot be deleted.', error: true);
      return;
    }

    final confirmed = await _confirmDelete(
      'Delete measurement?',
      'Delete the measurement from '
          '${GrowthDateFormatter.format(record.measuredAt)}?',
    );

    if (!mounted || !confirmed) return;

    final profileId = widget.profileId;

    setState(() => _busy = true);

    try {
      await _api.deleteRecord('growth', record.id);

      if (!mounted || profileId != widget.profileId) {
        return;
      }

      final refreshed = await _loadRecords(
        showLoader: false,
      );

      if (mounted) {
        _message(
          refreshed
              ? 'Measurement deleted.'
              : 'Server confirmed deletion; refresh the list to update it.',
        );
      }
    } catch (error) {
      if (mounted && profileId == widget.profileId) {
        _message(_friendlyError(error), error: true);
      }
    } finally {
      if (mounted && profileId == widget.profileId) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteNutrition(
      NutritionDiaryRecord record,
      ) async {
    if (_busy || _loadError != null) return;
    if (record.isDoctorAuthored) {
      _message('Doctor-entered records cannot be deleted.', error: true);
      return;
    }

    final confirmed = await _confirmDelete(
      'Delete meal entry?',
      'Delete this ${record.mealType.label.toLowerCase()} '
          'entry from the saved diary?',
    );

    if (!mounted || !confirmed) return;

    final profileId = widget.profileId;

    setState(() => _busy = true);

    try {
      await _api.deleteRecord('nutrition', record.id);

      if (!mounted || profileId != widget.profileId) {
        return;
      }

      final refreshed = await _loadRecords(
        showLoader: false,
      );

      if (mounted) {
        _message(
          refreshed
              ? 'Meal entry deleted.'
              : 'Server confirmed deletion; refresh the list to update it.',
        );
      }
    } catch (error) {
      if (mounted && profileId == widget.profileId) {
        _message(_friendlyError(error), error: true);
      }
    } finally {
      if (mounted && profileId == widget.profileId) {
        setState(() => _busy = false);
      }
    }
  }

  // ==========================================================
  // SCREEN UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GrowthNutritionColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: GrowthNutritionColors.navy,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Growth & Nutrition',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _busy
                ? null
                : () => _loadRecords(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton:
      _loading || _busy || _loadError != null
          ? null
          : FloatingActionButton.extended(
        backgroundColor:
        GrowthNutritionColors.blue,
        foregroundColor: Colors.white,
        onPressed: () {
          if (_selectedTab ==
              GrowthNutritionTab.growth) {
            _openGrowthEditor();
          } else {
            _openNutritionEditor();
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(
          _selectedTab == GrowthNutritionTab.growth
              ? 'Measurement'
              : 'Meal Entry',
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
          child: CircularProgressIndicator(
            color: GrowthNutritionColors.blue,
          ),
        )
            : RefreshIndicator(
          onRefresh: () async {
            await _loadRecords();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              16, 20, 16, 105,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1150,
                  ),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      _breadcrumb(),
                      const SizedBox(height: 17),
                      _hero(),
                      const SizedBox(height: 16),
                      _storageNotice(),
                      if (_busy) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(
                          color: GrowthNutritionColors.blue,
                          minHeight: 3,
                        ),
                      ],
                      const SizedBox(height: 20),
                      _tabs(),
                      const SizedBox(height: 20),
                      if (_loadError != null)
                        _errorPanel()
                      else if (_selectedTab ==
                          GrowthNutritionTab.growth)
                        _growthContent()
                      else
                        _nutritionContent(),
                      const SizedBox(height: 24),
                      _healthNotice(),
                      const SizedBox(height: 24),
                      const Center(
                        child: Text(
                          'FamilyCare+ • Your family. '
                              'Your care.',
                          style: TextStyle(
                            fontSize: 11,
                            color: GrowthNutritionColors.muted,
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
            color: GrowthNutritionColors.muted,
            fontSize: 12,
          ),
        ),
        SizedBox(width: 7),
        Icon(
          Icons.chevron_right_rounded,
          color: GrowthNutritionColors.muted,
          size: 17,
        ),
        SizedBox(width: 7),
        Text(
          'Growth & Nutrition',
          style: TextStyle(
            color: GrowthNutritionColors.green,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF4FF),
            Color(0xFFF0F7F1),
          ],
        ),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LITTLE STEPS. BIG MILESTONES.',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.6,
                    color: GrowthNutritionColors.green,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 11),
                const Text(
                  'Growing Together',
                  style: TextStyle(
                    color: GrowthNutritionColors.navy,
                    fontFamily: 'serif',
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Track ${_effectiveChildName}\'s growth '
                      'and everyday nutrition.',
                  style: const TextStyle(
                    color: GrowthNutritionColors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          const CircleAvatar(
            radius: 33,
            backgroundColor: Color(0xFFE0EFE5),
            child: Icon(
              Icons.spa_outlined,
              size: 36,
              color: GrowthNutritionColors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _storageNotice() {
    return _notice(
      'Growth and nutrition records are stored in '
          'FamilyCare+ when the server confirms the request. '
          'You can refresh to retrieve saved records.',
      GrowthNutritionColors.lightBlue,
      GrowthNutritionColors.blue,
    );
  }

  Widget _tabs() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: GrowthNutritionColors.border,
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          _tabButton(
            'Growth',
            Icons.show_chart_rounded,
            GrowthNutritionTab.growth,
          ),
          _tabButton(
            'Nutrition',
            Icons.restaurant_menu_rounded,
            GrowthNutritionTab.nutrition,
          ),
        ],
      ),
    );
  }

  Widget _tabButton(
      String title,
      IconData icon,
      GrowthNutritionTab tab,
      ) {
    final selected = _selectedTab == tab;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _selectedTab = tab);
        },
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 13,
            horizontal: 6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? GrowthNutritionColors.green
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? Colors.white
                    : GrowthNutritionColors.muted,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : GrowthNutritionColors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorPanel() {
    return _card(
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 38,
            color: GrowthNutritionColors.red,
          ),
          const SizedBox(height: 10),
          Text(
            _loadError ?? 'Unable to load records.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GrowthNutritionColors.text,
            ),
          ),
          const SizedBox(height: 13),
          OutlinedButton.icon(
            onPressed: () => _loadRecords(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // GROWTH CONTENT
  // ==========================================================

  Widget _growthContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Growth & Health Overview',
          'Height, weight and BMI from recorded measurements.',
        ),
        const SizedBox(height: 17),
        _latestMeasurementCards(),
        const SizedBox(height: 20),
        _combinedChartCard(),
        const SizedBox(height: 20),
        _individualCharts(),
        const SizedBox(height: 20),
        _growthHistory(),
      ],
    );
  }

  Widget _latestMeasurementCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final gap = 11.0;

        final width = wide
            ? (constraints.maxWidth - 2 * gap) / 3
            : (constraints.maxWidth - gap) / 2;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _measurementCard(
              width,
              'Height',
              _latestValue(GrowthChartMetric.height),
              'cm',
              Icons.straighten_rounded,
              GrowthNutritionColors.blue,
            ),
            _measurementCard(
              width,
              'Weight',
              _latestValue(GrowthChartMetric.weight),
              'kg',
              Icons.monitor_weight_outlined,
              GrowthNutritionColors.orange,
            ),
            _measurementCard(
              width,
              'BMI',
              _latestValue(GrowthChartMetric.bmi),
              '',
              Icons.analytics_outlined,
              GrowthNutritionColors.purple,
            ),
          ],
        );
      },
    );
  }

  Widget _measurementCard(
      double width,
      String title,
      double? value,
      String unit,
      IconData icon,
      Color color,
      ) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 128),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GrowthNutritionColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: GrowthNutritionColors.muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value == null
                ? 'Not recorded'
                : '${value.toStringAsFixed(1)} $unit'.trim(),
            style: const TextStyle(
              fontSize: 20,
              color: GrowthNutritionColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // COMBINED GROWTH CHART
  // ==========================================================

  Widget _combinedChartCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Growth Trends',
            style: TextStyle(
              color: GrowthNutritionColors.navy,
              fontSize: 21,
              fontFamily: 'serif',
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Explore measurements over time.',
            style: TextStyle(
              color: GrowthNutritionColors.muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: GrowthChartMetric.values.map((metric) {
                final selected = _selectedMetric == metric;

                return Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    label: Text(metric.label),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: GrowthNutritionColors.blue,
                    labelStyle: TextStyle(
                      color: selected
                          ? Colors.white
                          : GrowthNutritionColors.text,
                      fontSize: 11,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _selectedMetric = metric;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Measurement Chart',
                  style: TextStyle(
                    color: GrowthNutritionColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              _periodSelector(),
            ],
          ),
          const SizedBox(height: 14),
          _chartArea(
            records: _filteredGrowth,
            metric: _selectedMetric,
            height: 270,
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 16,
            runSpacing: 9,
            children: [
              _legend(
                'Height (cm)',
                GrowthNutritionColors.blue,
              ),
              _legend(
                'Weight (kg)',
                GrowthNutritionColors.orange,
              ),
              _legend(
                'BMI',
                GrowthNutritionColors.purple,
              ),
            ],
          ),
          if (_selectedMetric == GrowthChartMetric.all) ...[
            const SizedBox(height: 12),
            const Text(
              'Each metric is normalized independently '
                  'in the combined chart. Line heights must '
                  'not be compared numerically across units.',
              style: TextStyle(
                fontSize: 10,
                height: 1.5,
                color: GrowthNutritionColors.muted,
              ),
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _openGrowthEditor(),
            icon: const Icon(Icons.add_chart_rounded),
            label: const Text('Add Measurement'),
          ),
        ],
      ),
    );
  }

  Widget _periodSelector() {
    return DropdownButton<int>(
      value: _selectedMonths,
      underline: const SizedBox.shrink(),
      isDense: true,
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
          setState(() => _selectedMonths = value);
        }
      },
    );
  }

  // ==========================================================
  // INDIVIDUAL CHARTS
  // ==========================================================

  Widget _individualCharts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Individual Growth Charts',
          'Each measurement has its own scale.',
        ),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, constraints) {
            final charts = [
              _smallChartCard(
                'Height',
                'Centimeters (cm)',
                GrowthChartMetric.height,
              ),
              _smallChartCard(
                'Weight',
                'Kilograms (kg)',
                GrowthChartMetric.weight,
              ),
              _smallChartCard(
                'BMI',
                'Calculated BMI',
                GrowthChartMetric.bmi,
              ),
            ];

            if (constraints.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: charts[0]),
                  const SizedBox(width: 12),
                  Expanded(child: charts[1]),
                  const SizedBox(width: 12),
                  Expanded(child: charts[2]),
                ],
              );
            }

            return Column(
              children: [
                charts[0],
                const SizedBox(height: 12),
                charts[1],
                const SizedBox(height: 12),
                charts[2],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _smallChartCard(
      String title,
      String subtitle,
      GrowthChartMetric metric,
      ) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor:
                metric.color.withValues(alpha: 0.10),
                child: Icon(
                  metric == GrowthChartMetric.height
                      ? Icons.straighten_rounded
                      : metric == GrowthChartMetric.weight
                      ? Icons.monitor_weight_outlined
                      : Icons.analytics_outlined,
                  color: metric.color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: GrowthNutritionColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: GrowthNutritionColors.muted,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 14),
          _chartArea(
            records: _filteredGrowth,
            metric: metric,
            height: 190,
          ),
        ],
      ),
    );
  }

  Widget _chartArea({
    required List<GrowthMeasurementRecord> records,
    required GrowthChartMetric metric,
    required double height,
  }) {
    final hasData = records.any((record) {
      if (metric == GrowthChartMetric.all) {
        return record.heightCm != null ||
            record.weightKg != null;
      }

      return _metricValue(record, metric) != null;
    });

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCF8),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: GrowthNutritionColors.border,
        ),
      ),
      child: !hasData
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 33,
              color: metric.color.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 10),
            const Text(
              'Watch their story grow',
              style: TextStyle(
                color: GrowthNutritionColors.green,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'No ${metric == GrowthChartMetric.all ? 'growth' : metric.label.toLowerCase()} '
                  'data recorded yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: GrowthNutritionColors.muted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(10),
        child: CustomPaint(
          painter: _GrowthChartPainter(
            records: records,
            metric: metric,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  // ==========================================================
  // GROWTH HISTORY
  // ==========================================================

  Widget _growthHistory() {
    final records = _sortedGrowth.reversed.toList();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'Measurement History',
            'Date-wise height, weight and BMI records.',
          ),
          const SizedBox(height: 18),
          if (records.isEmpty)
            _emptyState(
              Icons.straighten_rounded,
              'No measurements yet',
              'Add height and weight to start tracking growth.',
              'Add Measurement',
                  () => _openGrowthEditor(),
            )
          else
            for (final record in records)
              _growthRecordCard(record),
        ],
      ),
    );
  }

  Widget _growthRecordCard(
      GrowthMeasurementRecord record,
      ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GrowthNutritionColors.cream,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: GrowthNutritionColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                size: 19,
                color: GrowthNutritionColors.green,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  GrowthDateFormatter.format(
                    record.measuredAt,
                  ),
                  style: const TextStyle(
                    color: GrowthNutritionColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                tooltip: record.isDoctorAuthored
                    ? 'Doctor-entered record (read-only)'
                    : 'Edit measurement',
                onPressed: _busy || record.isDoctorAuthored
                    ? null
                    : () => _openGrowthEditor(
                  existing: record,
                ),
                icon: const Icon(
                  Icons.edit_outlined,
                  color: GrowthNutritionColors.blue,
                ),
              ),
              IconButton(
                tooltip: record.isDoctorAuthored
                    ? 'Doctor-entered record (read-only)'
                    : 'Delete measurement',
                onPressed: _busy || record.isDoctorAuthored
                    ? null
                    : () => _deleteGrowth(record),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: GrowthNutritionColors.red,
                ),
              ),
            ],
          ),
          if (record.isDoctorAuthored) ...[
            const SizedBox(height: 5),
            const Text(
              'Doctor-entered • read-only',
              style: TextStyle(
                color: GrowthNutritionColors.purple,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (record.heightCm != null)
                _valueChip(
                  'Height',
                  '${record.heightCm!.toStringAsFixed(1)} cm',
                  GrowthNutritionColors.blue,
                ),
              if (record.weightKg != null)
                _valueChip(
                  'Weight',
                  '${record.weightKg!.toStringAsFixed(1)} kg',
                  GrowthNutritionColors.orange,
                ),
              if (record.bmi != null)
                _valueChip(
                  'BMI',
                  record.bmi!.toStringAsFixed(1),
                  GrowthNutritionColors.purple,
                ),
            ],
          ),
          if (record.notes.isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              record.notes,
              style: const TextStyle(
                color: GrowthNutritionColors.muted,
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
  // NUTRITION CONTENT
  // ==========================================================

  Widget _nutritionContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Nutrition Diary',
          'Keep a daily record of meals and feeding.',
        ),
        const SizedBox(height: 17),
        _nutritionSummary(),
        const SizedBox(height: 20),
        _nutritionDiary(),
      ],
    );
  }

  Widget _nutritionSummary() {
    final today = DateUtils.dateOnly(DateTime.now());

    final todayCount = _nutritionRecords
        .where((entry) => DateUtils.isSameDay(entry.date, today))
        .length;

    final uniqueDays = _nutritionRecords
        .map(
          (entry) =>
      DateUtils.dateOnly(entry.date).millisecondsSinceEpoch,
    )
        .toSet()
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 11) / 2;

        return Row(
          children: [
            _nutritionStat(
              width,
              'Meals Today',
              '$todayCount',
              Icons.restaurant_outlined,
              GrowthNutritionColors.green,
            ),
            const SizedBox(width: 11),
            _nutritionStat(
              width,
              'Days Recorded',
              '$uniqueDays',
              Icons.calendar_today_outlined,
              GrowthNutritionColors.purple,
            ),
          ],
        );
      },
    );
  }

  Widget _nutritionStat(
      double width,
      String label,
      String value,
      IconData icon,
      Color color,
      ) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GrowthNutritionColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: GrowthNutritionColors.navy,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: GrowthNutritionColors.muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _nutritionDiary() {
    final records = _filteredNutrition;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Meal Records',
            style: TextStyle(
              color: GrowthNutritionColors.navy,
              fontFamily: 'serif',
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Meals entered for your child.',
            style: TextStyle(
              color: GrowthNutritionColors.muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 17),
          TextField(
            controller: _nutritionSearch,
            decoration: InputDecoration(
              hintText: 'Search food or notes...',
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: GrowthNutritionColors.green,
              ),
              suffixIcon: _nutritionSearch.text.isNotEmpty
                  ? IconButton(
                tooltip: 'Clear search',
                onPressed: _nutritionSearch.clear,
                icon: const Icon(Icons.close_rounded),
              )
                  : null,
              filled: true,
              fillColor: GrowthNutritionColors.cream,
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
                _mealChip('All Meals', null),
                for (final type in NutritionMealType.values)
                  _mealChip(type.label, type),
              ],
            ),
          ),
          const SizedBox(height: 19),
          if (records.isEmpty)
            _emptyState(
              Icons.restaurant_outlined,
              'No meal records found',
              _nutritionRecords.isEmpty
                  ? 'Start recording your child\'s meals.'
                  : 'Try another search or meal category.',
              'Add Meal',
                  () => _openNutritionEditor(),
            )
          else
            for (final record in records)
              _nutritionRecordCard(record),
        ],
      ),
    );
  }

  Widget _mealChip(
      String title,
      NutritionMealType? type,
      ) {
    final selected = _mealFilter == type;

    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        label: Text(title),
        selected: selected,
        showCheckmark: false,
        selectedColor: GrowthNutritionColors.blue,
        labelStyle: TextStyle(
          color: selected
              ? Colors.white
              : GrowthNutritionColors.text,
          fontSize: 11,
        ),
        onSelected: (_) {
          setState(() => _mealFilter = type);
        },
      ),
    );
  }

  Widget _nutritionRecordCard(
      NutritionDiaryRecord record,
      ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GrowthNutritionColors.cream,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: GrowthNutritionColors.border,
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
                  color: record.mealType.color.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  record.mealType.icon,
                  color: record.mealType.color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.mealType.label,
                      style: const TextStyle(
                        color: GrowthNutritionColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      GrowthDateFormatter.format(record.date),
                      style: const TextStyle(
                        color: GrowthNutritionColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: record.isDoctorAuthored
                    ? 'Doctor-entered record (read-only)'
                    : 'Edit meal',
                onPressed: _busy || record.isDoctorAuthored
                    ? null
                    : () => _openNutritionEditor(
                  existing: record,
                ),
                icon: const Icon(
                  Icons.edit_outlined,
                  color: GrowthNutritionColors.blue,
                ),
              ),
              IconButton(
                tooltip: record.isDoctorAuthored
                    ? 'Doctor-entered record (read-only)'
                    : 'Delete meal',
                onPressed: _busy || record.isDoctorAuthored
                    ? null
                    : () => _deleteNutrition(record),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: GrowthNutritionColors.red,
                ),
              ),
            ],
          ),
          if (record.isDoctorAuthored) ...[
            const SizedBox(height: 5),
            const Text(
              'Doctor-entered • read-only',
              style: TextStyle(
                color: GrowthNutritionColors.purple,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 13),
          Text(
            record.foodDetails,
            style: const TextStyle(
              color: GrowthNutritionColors.text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          if (record.portion.isNotEmpty) ...[
            const SizedBox(height: 8),
            _detail('Portion', record.portion),
          ],
          if (record.notes.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              record.notes,
              style: const TextStyle(
                color: GrowthNutritionColors.muted,
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
  // SHARED UI COMPONENTS
  // ==========================================================

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: GrowthNutritionColors.border,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(
      String title,
      String subtitle,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: GrowthNutritionColors.navy,
            fontFamily: 'serif',
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          style: const TextStyle(
            color: GrowthNutritionColors.muted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 4,
          backgroundColor: color,
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: GrowthNutritionColors.muted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _valueChip(
      String label,
      String value,
      Color color,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            color: GrowthNutritionColors.muted,
            fontSize: 11,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: GrowthNutritionColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(
      IconData icon,
      String title,
      String message,
      String button,
      VoidCallback onPressed,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 35,
      ),
      decoration: BoxDecoration(
        color: GrowthNutritionColors.cream,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: GrowthNutritionColors.border,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 42,
            color: GrowthNutritionColors.green,
          ),
          const SizedBox(height: 13),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GrowthNutritionColors.navy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GrowthNutritionColors.muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 19),
          FilledButton.icon(
            onPressed: _busy ? null : onPressed,
            icon: const Icon(Icons.add_rounded),
            label: Text(button),
            style: FilledButton.styleFrom(
              backgroundColor: GrowthNutritionColors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
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
                color: GrowthNutritionColors.text,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthNotice() {
    return _notice(
      'Growth and nutrition records are user-entered. '
          'BMI for children must be assessed using age- '
          'and sex-specific references. These charts do not '
          'diagnose growth or nutrition problems. Consult '
          'a pediatrician for concerns about feeding '
          'or development.',
      GrowthNutritionColors.lightGreen,
      GrowthNutritionColors.green,
    );
  }
}

// ============================================================
// CUSTOM GROWTH CHART PAINTER
// ============================================================

class _GrowthChartPainter extends CustomPainter {
  final List<GrowthMeasurementRecord> records;
  final GrowthChartMetric metric;

  const _GrowthChartPainter({
    required this.records,
    required this.metric,
  });

  double? _value(
      GrowthMeasurementRecord record,
      GrowthChartMetric current,
      ) {
    switch (current) {
      case GrowthChartMetric.height:
        return record.heightCm;
      case GrowthChartMetric.weight:
        return record.weightKg;
      case GrowthChartMetric.bmi:
        return record.bmi;
      case GrowthChartMetric.all:
        return null;
    }
  }

  void _drawText(
      Canvas canvas,
      String text,
      Offset offset, {
        Color color = GrowthNutritionColors.muted,
        double fontSize = 10,
      }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (records.isEmpty) return;

    final leftMargin =
    metric == GrowthChartMetric.all ? 17.0 : 45.0;

    final graph = Rect.fromLTWH(
      leftMargin,
      12,
      math.max(1.0, size.width - leftMargin - 17),
      math.max(1.0, size.height - 42),
    );

    final gridPaint = Paint()
      ..color = const Color(0xFFE5EAE5)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = graph.top + graph.height * i / 4;

      canvas.drawLine(
        Offset(graph.left, y),
        Offset(graph.right, y),
        gridPaint,
      );
    }

    final metrics = metric == GrowthChartMetric.all
        ? [
      GrowthChartMetric.height,
      GrowthChartMetric.weight,
      GrowthChartMetric.bmi,
    ]
        : [metric];

    final sorted = List<GrowthMeasurementRecord>.from(
      records,
    )..sort(
          (a, b) => a.measuredAt.compareTo(b.measuredAt),
    );

    final firstDate = sorted.first.measuredAt;
    final lastDate = sorted.last.measuredAt;

    final totalTime = lastDate
        .difference(firstDate)
        .inMilliseconds;

    for (final current in metrics) {
      final points = <({DateTime date, double value})>[];

      for (final record in sorted) {
        final number = _value(record, current);

        if (number != null && number.isFinite) {
          points.add((
          date: record.measuredAt,
          value: number,
          ));
        }
      }

      if (points.isEmpty) continue;

      final values = points
          .map((point) => point.value)
          .toList();

      final rawMin = values.reduce(math.min);
      final rawMax = values.reduce(math.max);

      final range = rawMax - rawMin;

      final padding = range == 0
          ? math.max(1.0, rawMax.abs() * 0.05)
          : range * 0.12;

      final minY = rawMin - padding;
      final maxY = rawMax + padding;
      final spanY = maxY - minY;

      if (metric != GrowthChartMetric.all) {
        for (int i = 0; i <= 4; i++) {
          final value = maxY - spanY * i / 4;

          _drawText(
            canvas,
            value.toStringAsFixed(1),
            Offset(
              0,
              graph.top + graph.height * i / 4 - 6,
            ),
            fontSize: 9,
          );
        }
      }

      final linePaint = Paint()
        ..color = current.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final dotPaint = Paint()
        ..color = current.color
        ..style = PaintingStyle.fill;

      final path = Path();

      for (int i = 0; i < points.length; i++) {
        final point = points[i];

        final xRatio = totalTime == 0
            ? 0.5
            : point.date
            .difference(firstDate)
            .inMilliseconds /
            totalTime;

        final normalizedY = rawMax == rawMin
            ? 0.5
            : (point.value - rawMin) /
            (rawMax - rawMin);

        final yRatio = metric == GrowthChartMetric.all
            ? 0.10 + 0.80 * normalizedY
            : (point.value - minY) / spanY;

        final x = graph.left +
            xRatio.clamp(0.0, 1.0).toDouble() * graph.width;

        final y = graph.bottom -
            yRatio.clamp(0.0, 1.0).toDouble() * graph.height;

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(path, linePaint);

      for (final point in points) {
        final xRatio = totalTime == 0
            ? 0.5
            : point.date
            .difference(firstDate)
            .inMilliseconds /
            totalTime;

        final normalizedY = rawMax == rawMin
            ? 0.5
            : (point.value - rawMin) /
            (rawMax - rawMin);

        final yRatio = metric == GrowthChartMetric.all
            ? 0.10 + 0.80 * normalizedY
            : (point.value - minY) / spanY;

        canvas.drawCircle(
          Offset(
            graph.left +
                xRatio.clamp(0.0, 1.0).toDouble() * graph.width,
            graph.bottom -
                yRatio.clamp(0.0, 1.0).toDouble() * graph.height,
          ),
          3.7,
          dotPaint,
        );
      }
    }

    _drawText(
      canvas,
      GrowthDateFormatter.short(firstDate),
      Offset(graph.left, graph.bottom + 13),
      fontSize: 9,
    );

    if (!DateUtils.isSameDay(firstDate, lastDate)) {
      final lastLabel =
      GrowthDateFormatter.short(lastDate);

      _drawText(
        canvas,
        lastLabel,
        Offset(
          graph.right - lastLabel.length * 5.3,
          graph.bottom + 13,
        ),
        fontSize: 9,
      );
    }
  }

  @override
  bool shouldRepaint(
      covariant _GrowthChartPainter oldDelegate,
      ) {
    return oldDelegate.metric != metric ||
        oldDelegate.records != records;
  }
}

// ============================================================
// GROWTH MEASUREMENT EDITOR
// ============================================================

class _GrowthMeasurementEditor extends StatefulWidget {
  final String profileId;
  final String childName;
  final DateTime? childDateOfBirth;
  final String newRecordId;
  final GrowthMeasurementRecord? existing;

  const _GrowthMeasurementEditor({
    required this.profileId,
    required this.childName,
    required this.newRecordId,
    this.childDateOfBirth,
    this.existing,
  });

  @override
  State<_GrowthMeasurementEditor> createState() =>
      _GrowthMeasurementEditorState();
}

class _GrowthMeasurementEditorState
    extends State<_GrowthMeasurementEditor> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _notes;

  late DateTime _date;

  bool _submitted = false;

  @override
  void initState() {
    super.initState();

    _height = TextEditingController(
      text: widget.existing?.heightCm?.toString() ?? '',
    );

    _weight = TextEditingController(
      text: widget.existing?.weightKg?.toString() ?? '',
    );

    _notes = TextEditingController(
      text: widget.existing?.notes ?? '',
    );

    _date = widget.existing?.measuredAt ??
        DateUtils.dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());

    final birth = widget.childDateOfBirth;

    final firstDate = birth != null &&
        !birth.isAfter(today)
        ? DateUtils.dateOnly(birth)
        : DateTime(1900);

    var initial = _date;

    if (initial.isBefore(firstDate)) {
      initial = firstDate;
    }

    if (initial.isAfter(today)) {
      initial = today;
    }

    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: today,
      helpText: 'SELECT MEASUREMENT DATE',
    );

    if (!mounted || selected == null) return;

    setState(() => _date = selected);
  }

  String? _validateNumber(
      String? raw,
      String label,
      double maximum,
      ) {
    final text = (raw ?? '').trim();

    if (text.isEmpty) return '$label is required';

    final value = double.tryParse(text);

    if (value == null ||
        !value.isFinite ||
        value <= 0 ||
        value > maximum) {
      return 'Enter valid $label';
    }

    return null;
  }

  void _save() {
    setState(() => _submitted = true);

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final today = DateUtils.dateOnly(DateTime.now());
    final birth = widget.childDateOfBirth;
    if (_date.isAfter(today) ||
        (birth != null && _date.isBefore(DateUtils.dateOnly(birth)))) {
      _showError('Measurement date must be between birth and today.');
      return;
    }

    final height = double.tryParse(_height.text.trim());
    final weight = double.tryParse(_weight.text.trim());

    if (height == null || weight == null) {
      _showError('Enter both height and weight.');
      return;
    }

    Navigator.of(context).pop(
      GrowthMeasurementRecord(
        id: widget.existing?.id ?? widget.newRecordId,
        profileId: widget.profileId,
        measuredAt: _date,
        heightCm: height,
        weightKg: weight,
        notes: _notes.text.trim(),
      ),
    );
  }

  void _showError(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: GrowthNutritionColors.red,
        content: Text(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _editorSheet(
      context,
      Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _editorHeading(
              widget.existing == null
                  ? 'Add Measurement'
                  : 'Edit Measurement',
              'For ${widget.childName}',
            ),
            const SizedBox(height: 22),
            _dateButton(
              'Measurement Date',
              _date,
              _pickDate,
            ),
            const SizedBox(height: 17),
            _editorTextField(
              label: 'Height (cm)',
              hint: 'Enter height in centimeters',
              controller: _height,
              icon: Icons.straighten_rounded,
              numeric: true,
              maxLength: 12,
              validator: (value) => _validateNumber(
                value,
                'height (0–250 cm)',
                250,
              ),
            ),
            const SizedBox(height: 16),
            _editorTextField(
              label: 'Weight (kg)',
              hint: 'Enter weight in kilograms',
              controller: _weight,
              icon: Icons.monitor_weight_outlined,
              numeric: true,
              maxLength: 12,
              validator: (value) => _validateNumber(
                value,
                'weight (0–300 kg)',
                300,
              ),
            ),
            const SizedBox(height: 16),
            _editorTextField(
              label: 'Notes (Optional)',
              hint: 'Add measurement observations',
              controller: _notes,
              icon: Icons.notes_outlined,
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 15),
            const Text(
              'Both height and weight are required '
                  'by the current backend. BMI will be '
                  'calculated automatically from these values.',
              style: TextStyle(
                color: GrowthNutritionColors.muted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            _saveButton(
              widget.existing == null
                  ? 'Add Measurement'
                  : 'Save Changes',
              _save,
            ),
            _cancelButton(context),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// NUTRITION DIARY EDITOR
// ============================================================

class _NutritionDiaryEditor extends StatefulWidget {
  final String profileId;
  final String childName;
  final DateTime? childDateOfBirth;
  final String newRecordId;
  final NutritionDiaryRecord? existing;

  const _NutritionDiaryEditor({
    required this.profileId,
    required this.childName,
    required this.newRecordId,
    this.childDateOfBirth,
    this.existing,
  });

  @override
  State<_NutritionDiaryEditor> createState() =>
      _NutritionDiaryEditorState();
}

class _NutritionDiaryEditorState
    extends State<_NutritionDiaryEditor> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _food;
  late final TextEditingController _portion;
  late final TextEditingController _notes;

  late DateTime _date;
  late NutritionMealType _mealType;

  bool _submitted = false;

  @override
  void initState() {
    super.initState();

    _food = TextEditingController(
      text: widget.existing?.foodDetails ?? '',
    );

    _portion = TextEditingController(
      text: widget.existing?.portion ?? '',
    );

    _notes = TextEditingController(
      text: widget.existing?.notes ?? '',
    );

    _date = widget.existing?.date ??
        DateUtils.dateOnly(DateTime.now());

    _mealType =
        widget.existing?.mealType ??
            NutritionMealType.breakfast;
  }

  @override
  void dispose() {
    _food.dispose();
    _portion.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());

    final birth = widget.childDateOfBirth;

    final firstDate = birth != null &&
        !birth.isAfter(today)
        ? DateUtils.dateOnly(birth)
        : DateTime(1900);

    var initial = _date;

    if (initial.isBefore(firstDate)) {
      initial = firstDate;
    }

    if (initial.isAfter(today)) {
      initial = today;
    }

    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: today,
      helpText: 'SELECT MEAL DATE',
    );

    if (!mounted || selected == null) return;

    setState(() => _date = selected);
  }

  void _save() {
    setState(() => _submitted = true);

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final today = DateUtils.dateOnly(DateTime.now());
    final birth = widget.childDateOfBirth;
    if (_date.isAfter(today) ||
        (birth != null && _date.isBefore(DateUtils.dateOnly(birth)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meal date must be between birth and today.')),
      );
      return;
    }

    Navigator.of(context).pop(
      NutritionDiaryRecord(
        id: widget.existing?.id ?? widget.newRecordId,
        profileId: widget.profileId,
        date: _date,
        mealType: _mealType,
        foodDetails: _food.text.trim(),
        portion: _portion.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _editorSheet(
      context,
      Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _editorHeading(
              widget.existing == null
                  ? 'Add Meal Entry'
                  : 'Edit Meal Entry',
              'Nutrition diary for ${widget.childName}',
            ),
            const SizedBox(height: 22),
            _dateButton(
              'Meal Date',
              _date,
              _pickDate,
            ),
            const SizedBox(height: 18),
            const Text(
              'Meal Type',
              style: TextStyle(
                color: GrowthNutritionColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            DropdownButtonFormField<NutritionMealType>(
              initialValue: _mealType,
              isExpanded: true,
              decoration: _editorDecoration(
                'Select meal type',
                Icons.restaurant_menu_outlined,
              ),
              items: NutritionMealType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.label),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _mealType = value);
                }
              },
            ),
            const SizedBox(height: 17),
            _editorTextField(
              label: 'Food / Meal Details',
              hint: 'What did your child eat?',
              controller: _food,
              icon: Icons.restaurant_outlined,
              maxLines: 3,
              maxLength: 160,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Food details are required';
                }
                return null;
              },
            ),
            const SizedBox(height: 17),
            _editorTextField(
              label: 'Portion (Optional)',
              hint: 'e.g. 1 small bowl',
              controller: _portion,
              icon: Icons.rice_bowl_outlined,
              maxLength: 100,
            ),
            const SizedBox(height: 17),
            _editorTextField(
              label: 'Notes (Optional)',
              hint: 'Any observations?',
              controller: _notes,
              icon: Icons.notes_outlined,
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 20),
            const Text(
              'This diary records food entered by '
                  'parents. It does not calculate nutrient '
                  'adequacy or prescribe a feeding plan.',
              style: TextStyle(
                color: GrowthNutritionColors.muted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 23),
            _saveButton(
              widget.existing == null
                  ? 'Add Meal Entry'
                  : 'Save Changes',
              _save,
            ),
            _cancelButton(context),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SHARED EDITOR WIDGETS
// ============================================================

Widget _editorSheet(
    BuildContext context,
    Widget child,
    ) {
  return Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Container(
      constraints: BoxConstraints(
        maxHeight:
        MediaQuery.sizeOf(context).height * 0.88,
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
            20, 25, 20, 30,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 600,
              ),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _editorHeading(
    String title,
    String subtitle,
    ) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: GrowthNutritionColors.navy,
          fontSize: 23,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        subtitle,
        style: const TextStyle(
          color: GrowthNutritionColors.muted,
          fontSize: 12,
        ),
      ),
    ],
  );
}

InputDecoration _editorDecoration(
    String hint,
    IconData icon,
    ) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(
      icon,
      color: GrowthNutritionColors.green,
    ),
    filled: true,
    fillColor: GrowthNutritionColors.cream,
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
        color: GrowthNutritionColors.border,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(
        color: GrowthNutritionColors.green,
        width: 1.7,
      ),
    ),
  );
}

Widget _editorTextField({
  required String label,
  required String hint,
  required TextEditingController controller,
  required IconData icon,
  bool numeric = false,
  int maxLines = 1,
  int maxLength = 120,
  String? Function(String?)? validator,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: GrowthNutritionColors.text,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 9),
      TextFormField(
        controller: controller,
        validator: validator,
        maxLines: maxLines,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(
          decimal: true,
        )
            : TextInputType.text,
        inputFormatters: [
          if (numeric)
            FilteringTextInputFormatter.allow(
              RegExp(r'[0-9.]'),
            ),
          LengthLimitingTextInputFormatter(maxLength),
        ],
        decoration: _editorDecoration(hint, icon),
      ),
    ],
  );
}

Widget _dateButton(
    String title,
    DateTime date,
    VoidCallback onPressed,
    ) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: GrowthNutritionColors.text,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      const SizedBox(height: 9),
      InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(13),
        child: InputDecorator(
          decoration: _editorDecoration(
            'Select date',
            Icons.calendar_month_outlined,
          ),
          child: Text(
            GrowthDateFormatter.format(date),
            style: const TextStyle(
              color: GrowthNutritionColors.text,
              fontSize: 13,
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _saveButton(
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
        backgroundColor: GrowthNutritionColors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
      ),
    ),
  );
}

Widget _cancelButton(BuildContext context) {
  return SizedBox(
    width: double.infinity,
    child: TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    ),
  );
}