
import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/login_screen.dart';

// ============================================================
// FamilyCare+ - Child Medical History
// ============================================================
//
// Current backend integration:
// - PDF / image upload
// - Saved reports
// - Secure original report access
// - OCR text extraction
// - Optional English translation with user consent
//
// Future backend integration:
// - Permanent category, title, report date and description
// - Automatic document language detection
// - AI-generated description
// - Report deletion and metadata update
//
// Extra report details are session-only until backend
// metadata APIs are implemented.
//
// Compatible with file_picker 12.x / 13.x.
// ============================================================

// ============================================================
// COLORS
// ============================================================

class MedicalHistoryColors {
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
  static const lightBlue = Color(0xFFEAF4FF);
  static const lightOrange = Color(0xFFFFF4E7);
}

// ============================================================
// LEGACY MODELS FOR DASHBOARD COMPATIBILITY
// ============================================================

enum MedicalHistoryType {
  illness,
  allergy,
  medication,
  surgery,
  hospitalization,
  injury,
  other,
}

enum MedicalHistoryStatus {
  current,
  past,
}

enum MedicalHistoryFilter {
  all,
  conditions,
  allergies,
  medications,
  procedures,
  hospitalVisits,
  other,
}

class MedicalHistoryRecord {
  final String id;
  final String profileId;
  final MedicalHistoryType type;
  final MedicalHistoryStatus status;
  final String title;
  final DateTime eventDate;
  final DateTime? endDate;

  final String doctorName;
  final String hospitalName;
  final String treatment;
  final String notes;

  const MedicalHistoryRecord({
    required this.id,
    required this.profileId,
    required this.type,
    required this.status,
    required this.title,
    required this.eventDate,
    this.endDate,
    this.doctorName = '',
    this.hospitalName = '',
    this.treatment = '',
    this.notes = '',
  });

  bool get isCurrent =>
      status == MedicalHistoryStatus.current;

  bool get isPast =>
      status == MedicalHistoryStatus.past;

  MedicalHistoryRecord copyWithStatus(
      MedicalHistoryStatus newStatus,
      ) {
    return MedicalHistoryRecord(
      id: id,
      profileId: profileId,
      type: type,
      status: newStatus,
      title: title,
      eventDate: eventDate,
      endDate: endDate,
      doctorName: doctorName,
      hospitalName: hospitalName,
      treatment: treatment,
      notes: notes,
    );
  }
}

// ============================================================
// REPORT CATEGORIES
// ============================================================

const List<String> _reportCategories = [
  'Blood Test',
  'Urine Test',
  'X-ray',
  'Ultrasound',
  'MRI / CT Scan',
  'Prescription',
  'Discharge Summary',
  'Vaccination Record',
  'Consultation',
  'Other',
];

// ============================================================
// OCR LANGUAGES
// ============================================================

const Map<String, String> _fallbackLanguages = {
  'en': 'English',
  'hi': 'Hindi',
  'mr': 'Marathi',
  'ne': 'Nepali',
  'sa': 'Sanskrit',
  'ta': 'Tamil',
  'te': 'Telugu',
  'ur': 'Urdu',
  'ar': 'Arabic',
  'fr': 'French',
  'de': 'German',
  'es': 'Spanish',
  'pt': 'Portuguese',
  'ru': 'Russian',
};

// ============================================================
// HELPERS
// ============================================================

String _formatDate(DateTime? date) {
  if (date == null) {
    return 'Not provided';
  }

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr',
    'May', 'Jun', 'Jul', 'Aug',
    'Sep', 'Oct', 'Nov', 'Dec',
  ];

  return '${date.day} '
      '${months[date.month - 1]} '
      '${date.year}';
}

String _formatSize(int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;

  final raw = value.toString().trim();

  if (raw.isEmpty) return null;

  return DateTime.tryParse(raw);
}

// ============================================================
// SAVED REPORT MODEL
// ============================================================

class _MedicalReport {
  final String id;
  final String name;
  final String contentType;
  final int sizeBytes;
  final DateTime? uploadedAt;

  const _MedicalReport({
    required this.id,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    this.uploadedAt,
  });

  bool get isImage => contentType.startsWith('image/');

  bool get isPdf =>
      contentType == 'application/pdf';

  factory _MedicalReport.fromJson(
      Map<String, dynamic> json,
      ) {
    final size = json['size_bytes'];

    return _MedicalReport(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Medical report').toString(),
      contentType:
      (json['content_type'] ?? '').toString(),
      sizeBytes: size is num ? size.toInt() : 0,
      uploadedAt: _parseDate(json['created_at']),
    );
  }
}

// ============================================================
// SESSION-ONLY REPORT METADATA
// ============================================================

class _MedicalReportDetails {
  final String category;
  final String title;
  final String description;
  final DateTime? reportDate;

  const _MedicalReportDetails({
    required this.category,
    required this.title,
    required this.description,
    this.reportDate,
  });
}

class _SelectedMedicalReport {
  final String? fileName;
  final Uint8List? bytes;
  final _MedicalReportDetails details;

  const _SelectedMedicalReport({
    required this.fileName,
    required this.bytes,
    required this.details,
  });
}

// ============================================================
// API EXCEPTION
// ============================================================

class _MedicalReportApiException implements Exception {
  final String message;
  final int statusCode;

  const _MedicalReportApiException(
      this.message, {
        this.statusCode = 0,
      });

  @override
  String toString() => message;
}

// ============================================================
// FLASK API CLIENT
// ============================================================

class _MedicalReportApi {
  final String baseUrl;
  final String profileId;

  final http.Client _client = http.Client();

  _MedicalReportApi({
    required this.baseUrl,
    required this.profileId,
  });

  String get reportsPath =>
      '/api/v1/patients/profiles/'
          '${Uri.encodeComponent(profileId)}/reports';

  String reportPath(String reportId) =>
      '$reportsPath/${Uri.encodeComponent(reportId)}';

  void dispose() {
    _client.close();
  }

  // ----------------------------------------------------------
  // AUTH HEADERS
  // ----------------------------------------------------------

  Future<Map<String, String>> _headers() async {
    final token = await FamilyCareSession.accessToken();

    if (token == null || token.trim().isEmpty) {
      throw const _MedicalReportApiException(
        'Your session is unavailable. Please log in again.',
        statusCode: 401,
      );
    }

    return {
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
    };
  }

  // ----------------------------------------------------------
  // RESPONSE HANDLING
  // ----------------------------------------------------------

  Map<String, dynamic> _decode(
      http.Response response,
      ) {
    Map<String, dynamic> result = {};

    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(
          utf8.decode(response.bodyBytes),
        );

        if (decoded is Map) {
          result = Map<String, dynamic>.from(decoded);
        } else {
          throw const FormatException();
        }
      } catch (_) {
        throw _MedicalReportApiException(
          'Invalid response from server.',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      String message =
          'Server request failed (${response.statusCode}).';

      final error = result['error'];

      if (error is Map &&
          error['message'] is String) {
        message = error['message'] as String;
      }

      if (response.statusCode == 401) {
        message = 'Session expired. Please log in again.';
      }

      if (response.statusCode == 403) {
        message =
        'You do not have permission to access this report.';
      }

      throw _MedicalReportApiException(
        message,
        statusCode: response.statusCode,
      );
    }

    return result;
  }

  // ----------------------------------------------------------
  // GET REQUEST
  // ----------------------------------------------------------

  Future<Map<String, dynamic>> get(
      String path,
      ) async {
    final response = await _client
        .get(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
    )
        .timeout(const Duration(seconds: 35));

    return _decode(response);
  }

  // ----------------------------------------------------------
  // POST JSON
  // ----------------------------------------------------------

  Future<Map<String, dynamic>> post(
      String path,
      Map<String, dynamic> body,
      ) async {
    final headers = await _headers();

    headers['Content-Type'] = 'application/json';

    final response = await _client
        .post(
      Uri.parse('$baseUrl$path'),
      headers: headers,
      body: jsonEncode(body),
    )
        .timeout(const Duration(seconds: 35));

    return _decode(response);
  }

  // ----------------------------------------------------------
  // MULTIPART REPORT UPLOAD
  // ----------------------------------------------------------

  Future<_MedicalReport> upload({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty ||
        bytes.length > 10 * 1024 * 1024) {
      throw const _MedicalReportApiException(
        'File must be non-empty and no larger than 10 MB.',
      );
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl$reportsPath'),
    );

    request.headers.addAll(await _headers());

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ),
    );

    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 100));

    final response = await http.Response.fromStream(
      streamedResponse,
    );

    final data = _decode(response);
    final rawReport = data['report'];

    if (rawReport is! Map) {
      throw const _MedicalReportApiException(
        'Upload completed, but report details were not returned. '
            'Refresh the reports list.',
      );
    }

    return _MedicalReport.fromJson(
      Map<String, dynamic>.from(rawReport),
    );
  }

  // ----------------------------------------------------------
  // SAVED REPORTS
  // ----------------------------------------------------------

  Future<List<_MedicalReport>> getReports() async {
    final reports = <_MedicalReport>[];

    for (int page = 1; page <= 100; page++) {
      final data = await get(
        '$reportsPath?page=$page&per_page=100',
      );

      final items = data['items'];

      if (items is! List) {
        throw const _MedicalReportApiException(
          'Server returned an invalid report list.',
        );
      }

      for (final item in items) {
        if (item is Map) {
          reports.add(
            _MedicalReport.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }

      final total = data['total'];

      if (items.length < 100 ||
          (total is num && reports.length >= total)) {
        break;
      }
    }

    return reports;
  }

  // ----------------------------------------------------------
  // ORIGINAL FILE DOWNLOAD URL
  // ----------------------------------------------------------

  Future<String> getDownloadUrl(
      String reportId,
      ) async {
    final data = await get(
      '${reportPath(reportId)}/download',
    );

    final report = data['report'];

    final url =
    report is Map ? report['url'] : null;

    if (url is! String ||
        !url.startsWith('https://')) {
      throw const _MedicalReportApiException(
        'Secure report link is unavailable. '
            'Please try again.',
      );
    }

    return url;
  }

  // ----------------------------------------------------------
  // OCR API
  // ----------------------------------------------------------

  Future<Map<String, dynamic>> getOcrOptions() {
    return get(
      '/api/v1/patients/report-text/options',
    );
  }

  Future<Map<String, dynamic>> getText(
      String reportId,
      ) {
    return get(
      '${reportPath(reportId)}/text',
    );
  }

  Future<Map<String, dynamic>> requestText({
    required String reportId,
    required String sourceLanguage,
    required bool translateToEnglish,
    required bool consent,
  }) {
    return post(
      '${reportPath(reportId)}/text',
      {
        'source_language': sourceLanguage,
        'translate_to_english': translateToEnglish,
        'external_translation_consent': consent,
      },
    );
  }
}

// ============================================================
// MAIN MEDICAL HISTORY SCREEN
// ============================================================

class MedicalHistoryScreen extends StatefulWidget {
  final String profileId;
  final String childName;
  final DateTime? childDateOfBirth;
  final String apiBaseUrl;

  // Existing constructor compatibility.
  final List<MedicalHistoryRecord> initialRecords;

  final ValueChanged<List<MedicalHistoryRecord>>?
  onRecordsChanged;

  const MedicalHistoryScreen({
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
  State<MedicalHistoryScreen> createState() =>
      _MedicalHistoryScreenState();
}

class _MedicalHistoryScreenState
    extends State<MedicalHistoryScreen> {
  final TextEditingController _searchController =
  TextEditingController();

  late _MedicalReportApi _api;

  List<_MedicalReport> _reports = [];

  // These details are NOT yet stored by Flask.
  final Map<String, _MedicalReportDetails>
  _sessionDetails = {};

  String _selectedCategory = 'All';

  bool _loading = true;
  bool _saving = false;

  String? _loadError;

  int _generation = 0;

  // ----------------------------------------------------------
  // API BASE URL
  // ----------------------------------------------------------

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

  // ----------------------------------------------------------
  // LIFECYCLE
  // ----------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _api = _MedicalReportApi(
      baseUrl: _baseUrl,
      profileId: widget.profileId,
    );

    _searchController.addListener(_onSearchChanged);

    _loadReports();
  }

  @override
  void didUpdateWidget(
      covariant MedicalHistoryScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.profileId != widget.profileId ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _generation++;

      _api.dispose();

      _api = _MedicalReportApi(
        baseUrl: _baseUrl,
        profileId: widget.profileId,
      );

      _reports = [];
      _sessionDetails.clear();

      _selectedCategory = 'All';
      _loadError = null;

      _searchController.clear();

      _loadReports();
    }
  }

  @override
  void dispose() {
    _generation++;

    _api.dispose();

    _searchController.removeListener(
      _onSearchChanged,
    );

    _searchController.dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ----------------------------------------------------------
  // MESSAGE
  // ----------------------------------------------------------

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
              ? MedicalHistoryColors.red
              : MedicalHistoryColors.navy,
          content: Text(message),
        ),
      );
  }

  String _friendlyError(Object error) {
    if (error is _MedicalReportApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'Server response timed out. Please try again.';
    }

    if (error is http.ClientException) {
      return 'Could not connect to the server.';
    }

    return 'Something went wrong. Please retry.';
  }

  // ==========================================================
  // LOAD REPORTS
  // ==========================================================

  Future<void> _loadReports() async {
    final requestId = ++_generation;

    final profileId = widget.profileId;

    if (!mounted) return;

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final reports = await _api.getReports();

      if (!mounted ||
          requestId != _generation ||
          widget.profileId != profileId) {
        return;
      }

      setState(() {
        _reports = reports;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          requestId != _generation ||
          widget.profileId != profileId) {
        return;
      }

      setState(() {
        _loading = false;
        _loadError = _friendlyError(error);
      });
    }
  }

  // ==========================================================
  // UPLOAD REPORT
  // ==========================================================

  Future<void> _uploadReport() async {
    if (_saving || _loading) return;

    final profileId = widget.profileId;

    final selection =
    await showModalBottomSheet<_SelectedMedicalReport>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return const _ReportFormSheet();
      },
    );

    if (!mounted ||
        selection == null ||
        widget.profileId != profileId) {
      return;
    }

    if (selection.fileName == null ||
        selection.bytes == null) {
      return;
    }

    setState(() => _saving = true);

    try {
      final report = await _api.upload(
        fileName: selection.fileName!,
        bytes: selection.bytes!,
      );

      if (!mounted ||
          widget.profileId != profileId) {
        return;
      }

      setState(() {
        _sessionDetails[report.id] =
            selection.details;

        _reports.removeWhere(
              (item) => item.id == report.id,
        );

        _reports.insert(0, report);
      });

      _showMessage(
        'Original report uploaded successfully. '
            'Custom details are temporary until the '
            'metadata API is available.',
      );

      if (!mounted) return;

      await _openReport(report);
    } catch (error) {
      if (mounted) {
        _showMessage(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted &&
          widget.profileId == profileId) {
        setState(() => _saving = false);
      }
    }
  }

  // ==========================================================
  // EDIT TEMPORARY REPORT DETAILS
  // ==========================================================

  Future<void> _editReportDetails(
      _MedicalReport report,
      ) async {
    if (_saving) return;

    final current =
        _sessionDetails[report.id] ??
            _MedicalReportDetails(
              category: 'Other',
              title: report.name,
              description: '',
              reportDate: null,
            );

    final edited =
    await showModalBottomSheet<_SelectedMedicalReport>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ReportFormSheet(
          existing: current,
        );
      },
    );

    if (!mounted || edited == null) return;

    setState(() {
      _sessionDetails[report.id] =
          edited.details;
    });

    _showMessage(
      'Report details updated for this app session. '
          'Database metadata update is not available yet.',
    );
  }

  // ==========================================================
  // REPORT VIEWER
  // ==========================================================

  Future<void> _openReport(
      _MedicalReport report,
      ) async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ReportViewerSheet(
          api: _api,
          report: report,
          details: _sessionDetails[report.id],
        );
      },
    );
  }

  // ==========================================================
  // SEARCH AND FILTER
  // ==========================================================

  List<_MedicalReport> get _filteredReports {
    final query =
    _searchController.text.trim().toLowerCase();

    return _reports.where((report) {
      final details = _sessionDetails[report.id];

      final category =
          details?.category ?? 'Other';

      if (_selectedCategory != 'All' &&
          category != _selectedCategory) {
        return false;
      }

      if (query.isEmpty) return true;

      return [
        report.name,
        details?.title ?? '',
        details?.category ?? '',
        details?.description ?? '',
      ].any(
            (value) =>
            value.toLowerCase().contains(query),
      );
    }).toList();
  }

  // ==========================================================
  // SUMMARY
  // ==========================================================

  int get _pdfCount => _reports
      .where((item) => item.isPdf)
      .length;

  int get _imageCount => _reports
      .where((item) => item.isImage)
      .length;

  // ==========================================================
  // MAIN SCREEN
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MedicalHistoryColors.background,

      appBar: AppBar(
        title: const Text(
          'Medical History',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: MedicalHistoryColors.navy,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh reports',
            onPressed:
            _loading || _saving
                ? null
                : _loadReports,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),

      floatingActionButton:
      _loading || _saving
          ? null
          : FloatingActionButton.extended(
        onPressed: _uploadReport,
        backgroundColor:
        MedicalHistoryColors.blue,
        foregroundColor: Colors.white,
        icon: const Icon(
          Icons.upload_file_outlined,
        ),
        label: const Text(
          'Upload Report',
        ),
      ),

      body: SafeArea(
        child: _loading
            ? const Center(
          child: CircularProgressIndicator(
            color: MedicalHistoryColors.blue,
          ),
        )
            : RefreshIndicator(
          onRefresh: _loadReports,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              16, 20, 16, 110,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints:
                  const BoxConstraints(
                    maxWidth: 1100,
                  ),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      _buildBreadcrumb(),

                      const SizedBox(height: 17),

                      _buildHero(),

                      const SizedBox(height: 17),

                      _medicalNotice(
                        'Original reports are stored '
                            'through the current backend. '
                            'Custom title, category, report '
                            'date and description currently '
                            'remain in this app session only.',
                        MedicalHistoryColors.lightOrange,
                        MedicalHistoryColors.orange,
                      ),

                      const SizedBox(height: 20),

                      if (_loadError != null)
                        _buildLoadError()
                      else ...[
                        _buildSummaryCards(),

                        const SizedBox(height: 20),

                        _buildReportsSection(),
                      ],

                      const SizedBox(height: 20),

                      _medicalNotice(
                        'OCR and machine translations '
                            'can misread medical values, '
                            'dosages and terminology. '
                            'Always compare important '
                            'information with the original '
                            'report and consult a qualified '
                            'healthcare professional.',
                        MedicalHistoryColors.lightGreen,
                        MedicalHistoryColors.green,
                      ),

                      const SizedBox(height: 24),

                      const Center(
                        child: Text(
                          'FamilyCare+ • Your family. '
                              'Your care.',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                            MedicalHistoryColors.muted,
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
  // BREADCRUMB
  // ==========================================================

  Widget _buildBreadcrumb() {
    return const Row(
      children: [
        Text(
          'Child Care',
          style: TextStyle(
            fontSize: 12,
            color: MedicalHistoryColors.muted,
          ),
        ),
        SizedBox(width: 6),
        Icon(
          Icons.chevron_right_rounded,
          color: MedicalHistoryColors.muted,
          size: 17,
        ),
        SizedBox(width: 6),
        Text(
          'Medical History',
          style: TextStyle(
            color: MedicalHistoryColors.green,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // HERO
  // ==========================================================

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF4FF),
            Color(0xFFF0F8F3),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: Color(0xFFDCEDE3),
            child: Icon(
              Icons.folder_shared_outlined,
              color: MedicalHistoryColors.green,
              size: 32,
            ),
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const Text(
                  'Medical Reports',
                  style: TextStyle(
                    color: MedicalHistoryColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Manage ${widget.childName}\'s '
                      'medical documents, reports and '
                      'English translations.',
                  style: const TextStyle(
                    color: MedicalHistoryColors.muted,
                    fontSize: 12,
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
  // SUMMARY CARDS
  // ==========================================================

  Widget _buildSummaryCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
        constraints.maxWidth >= 680 ? 3 : 2;

        const spacing = 10.0;

        final width =
            (constraints.maxWidth -
                spacing * (columns - 1)) /
                columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            _summaryCard(
              width: width,
              label: 'Total Reports',
              count: _reports.length,
              icon: Icons.folder_copy_outlined,
              color: MedicalHistoryColors.blue,
            ),
            _summaryCard(
              width: width,
              label: 'PDF Reports',
              count: _pdfCount,
              icon: Icons.picture_as_pdf_outlined,
              color: MedicalHistoryColors.red,
            ),
            _summaryCard(
              width: width,
              label: 'Images',
              count: _imageCount,
              icon: Icons.image_outlined,
              color: MedicalHistoryColors.green,
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCard({
    required double width,
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(
        minHeight: 112,
      ),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: MedicalHistoryColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(height: 12),
          Text(
            '$count',
            style: const TextStyle(
              color: MedicalHistoryColors.navy,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: MedicalHistoryColors.muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SAVED REPORTS
  // ==========================================================

  Widget _buildReportsSection() {
    final filtered = _filteredReports;

    return _medicalPanel(
      'Saved Medical Reports',
      Icons.description_outlined,
      Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          // SEARCH
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search report name or category...',
              prefixIcon: const Icon(
                Icons.search_rounded,
              ),
              suffixIcon:
              _searchController.text.isEmpty
                  ? null
                  : IconButton(
                tooltip: 'Clear search',
                onPressed:
                _searchController.clear,
                icon: const Icon(
                  Icons.close_rounded,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 15),

          // CATEGORY FILTERS
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                'All',
                ..._reportCategories,
              ].map((category) {
                final selected =
                    _selectedCategory == category;

                return Padding(
                  padding: const EdgeInsets.only(
                    right: 7,
                  ),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor:
                    MedicalHistoryColors.blue,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      color: selected
                          ? Colors.white
                          : MedicalHistoryColors.text,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _selectedCategory = category;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 18),

          if (filtered.isEmpty)
            _buildEmptyState()
          else
            for (final report in filtered) ...[
              _buildReportCard(report),
              const SizedBox(height: 12),
            ],

          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
              _saving ? null : _uploadReport,
              icon: const Icon(
                Icons.add_rounded,
              ),
              label: const Text(
                'Upload Medical Report',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // REPORT CARD
  // ==========================================================

  Widget _buildReportCard(
      _MedicalReport report,
      ) {
    final details = _sessionDetails[report.id];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: MedicalHistoryColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MedicalHistoryColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                report.isImage
                    ? Icons.image_outlined
                    : Icons.picture_as_pdf_outlined,
                color: report.isImage
                    ? MedicalHistoryColors.green
                    : MedicalHistoryColors.red,
                size: 30,
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      details?.title ?? report.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MedicalHistoryColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      '${details?.category ?? 'Uncategorized'}'
                          ' • ${_formatSize(report.sizeBytes)}',
                      style: const TextStyle(
                        color: MedicalHistoryColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            'Uploaded: '
                '${_formatDate(report.uploadedAt?.toLocal())}',
            style: const TextStyle(
              color: MedicalHistoryColors.muted,
              fontSize: 11,
            ),
          ),

          if (details?.reportDate != null) ...[
            const SizedBox(height: 6),
            Text(
              'Report date: '
                  '${_formatDate(details!.reportDate)}',
              style: const TextStyle(
                color: MedicalHistoryColors.muted,
                fontSize: 11,
              ),
            ),
          ],

          if (details != null &&
              details.description.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              details.description,
              style: const TextStyle(
                color: MedicalHistoryColors.text,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],

          if (details != null) ...[
            const SizedBox(height: 9),
            const Text(
              'Custom details are temporary '
                  '(database API pending).',
              style: TextStyle(
                color: MedicalHistoryColors.orange,
                fontSize: 10,
              ),
            ),
          ],

          const Divider(height: 23),

          Wrap(
            spacing: 7,
            runSpacing: 5,
            children: [
              TextButton.icon(
                onPressed: () => _openReport(report),
                icon: const Icon(
                  Icons.visibility_outlined,
                  size: 17,
                ),
                label: const Text(
                  'View / Translate',
                ),
              ),

              TextButton.icon(
                onPressed:
                _saving
                    ? null
                    : () => _editReportDetails(report),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 17,
                ),
                label: const Text(
                  'Edit Details',
                ),
              ),

              const Tooltip(
                message:
                'Report delete API will be added later.',
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: MedicalHistoryColors.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // EMPTY STATE
  // ==========================================================

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 32,
      ),
      decoration: BoxDecoration(
        color: MedicalHistoryColors.cream,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.folder_open_outlined,
            size: 48,
            color: MedicalHistoryColors.green,
          ),

          const SizedBox(height: 13),

          const Text(
            'No medical reports found',
            style: TextStyle(
              color: MedicalHistoryColors.navy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Upload a PDF or medical report image '
                'to start organizing your child\'s history.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MedicalHistoryColors.muted,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 16),

          FilledButton.icon(
            onPressed: _uploadReport,
            style: FilledButton.styleFrom(
              backgroundColor:
              MedicalHistoryColors.blue,
            ),
            icon: const Icon(
              Icons.upload_file_outlined,
            ),
            label: const Text('Upload Report'),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // LOAD ERROR
  // ==========================================================

  Widget _buildLoadError() {
    return _medicalPanel(
      'Unable to Load Reports',
      Icons.error_outline_rounded,
      Column(
        children: [
          Text(
            _loadError ?? 'Unknown error',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MedicalHistoryColors.red,
            ),
          ),

          const SizedBox(height: 14),

          OutlinedButton.icon(
            onPressed: _loadReports,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// UPLOAD / EDIT REPORT FORM
// ============================================================

class _ReportFormSheet extends StatefulWidget {
  final _MedicalReportDetails? existing;

  const _ReportFormSheet({
    this.existing,
  });

  @override
  State<_ReportFormSheet> createState() =>
      _ReportFormSheetState();
}

class _ReportFormSheetState
    extends State<_ReportFormSheet> {
  final _formKey = GlobalKey<FormState>();

  final ImagePicker _imagePicker = ImagePicker();

  late final TextEditingController _titleController;
  late final TextEditingController
  _descriptionController;

  String _selectedCategory = 'Other';

  DateTime? _reportDate;

  String? _selectedFileName;
  Uint8List? _selectedBytes;

  bool _picking = false;

  bool get _editing => widget.existing != null;

  // ==========================================================
  // INITIALIZATION
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.existing?.title ?? '',
    );

    _descriptionController = TextEditingController(
      text: widget.existing?.description ?? '',
    );

    _selectedCategory =
        widget.existing?.category ?? 'Other';

    _reportDate = widget.existing?.reportDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();

    super.dispose();
  }

  // ==========================================================
  // FORM ERROR
  // ==========================================================

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: MedicalHistoryColors.red,
        content: Text(message),
      ),
    );
  }

  // ==========================================================
  // SELECT PDF
  //
  // Fixed: FilePicker.platform removed in v11+.
  // This implementation targets v12/v13.
  // ==========================================================

  Future<void> _pickPdf() async {
    if (_picking) return;

    setState(() {
      _picking = true;
    });

    try {
      final PlatformFile? file =
      await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (file == null) return;

      if (!file.name.toLowerCase().endsWith('.pdf')) {
        _showError(
          'Please select a PDF file.',
        );
        return;
      }

      final bytes = await file.readAsBytes();

      if (!mounted) return;

      _setFile(file.name, bytes);
    } catch (error) {
      if (mounted) {
        _showError(
          'Unable to select PDF. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
        });
      }
    }
  }

  // ==========================================================
  // SELECT IMAGE
  // ==========================================================

  Future<void> _pickImage(
      ImageSource source,
      ) async {
    if (_picking) return;

    setState(() {
      _picking = true;
    });

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 90,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();

      if (!mounted) return;

      _setFile(image.name, bytes);
    } catch (error) {
      if (mounted) {
        _showError(
          'Unable to select image. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
        });
      }
    }
  }

  // ==========================================================
  // VALIDATE FILE
  // ==========================================================

  void _setFile(
      String fileName,
      Uint8List bytes,
      ) {
    if (bytes.isEmpty) {
      _showError('Selected file is empty.');
      return;
    }

    if (bytes.length > 10 * 1024 * 1024) {
      _showError(
        'Maximum report size is 10 MB.',
      );
      return;
    }

    final extension =
    fileName.split('.').last.toLowerCase();

    if (![
      'pdf',
      'jpg',
      'jpeg',
      'png',
      'webp',
    ].contains(extension)) {
      _showError(
        'Only PDF, JPG, PNG and WebP files are supported.',
      );
      return;
    }

    setState(() {
      _selectedFileName = fileName;
      _selectedBytes = bytes;

      if (_titleController.text.trim().isEmpty) {
        _titleController.text = fileName.replaceFirst(
          RegExp(r'\.[^.]+$'),
          '',
        );
      }
    });
  }

  // ==========================================================
  // REPORT DATE PICKER
  // ==========================================================

  Future<void> _selectReportDate() async {
    final today = DateUtils.dateOnly(
      DateTime.now(),
    );

    final selected = await showDatePicker(
      context: context,
      initialDate: _reportDate ?? today,
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'SELECT REPORT DATE',
    );

    if (!mounted || selected == null) return;

    setState(() {
      _reportDate = selected;
    });
  }

  // ==========================================================
  // SAVE FORM
  // ==========================================================

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (!_editing && _selectedBytes == null) {
      _showError(
        'Please select a PDF or image.',
      );
      return;
    }

    final details = _MedicalReportDetails(
      category: _selectedCategory,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      reportDate: _reportDate,
    );

    Navigator.of(context).pop(
      _SelectedMedicalReport(
        fileName: _selectedFileName,
        bytes: _selectedBytes,
        details: details,
      ),
    );
  }

  // ==========================================================
  // FORM UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return _medicalBottomSheet(
      context,
      Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _editing
                        ? 'Edit Report Details'
                        : 'Upload Medical Report',
                    style: const TextStyle(
                      color: MedicalHistoryColors.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 23,
                    ),
                  ),
                ),

                IconButton(
                  tooltip: 'Close',
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            const Text(
              'Upload your child\'s medical report '
                  'and describe what it is about.',
              style: TextStyle(
                color: MedicalHistoryColors.muted,
                fontSize: 12,
              ),
            ),

            // --------------------------------------------------
            // FILE PICKERS
            // --------------------------------------------------

            if (!_editing) ...[
              const SizedBox(height: 23),

              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                    _picking ? null : _pickPdf,
                    icon: const Icon(
                      Icons.picture_as_pdf_outlined,
                    ),
                    label: const Text('PDF'),
                  ),

                  OutlinedButton.icon(
                    onPressed: _picking
                        ? null
                        : () => _pickImage(
                      ImageSource.gallery,
                    ),
                    icon: const Icon(
                      Icons.photo_library_outlined,
                    ),
                    label: const Text('Gallery'),
                  ),

                  OutlinedButton.icon(
                    onPressed: _picking
                        ? null
                        : () => _pickImage(
                      ImageSource.camera,
                    ),
                    icon: const Icon(
                      Icons.camera_alt_outlined,
                    ),
                    label: const Text('Camera'),
                  ),
                ],
              ),

              const SizedBox(height: 13),

              if (_picking)
                const LinearProgressIndicator(),

              Text(
                _selectedFileName == null
                    ? 'PDF, JPG, PNG, WebP • Maximum 10 MB'
                    : 'Selected: $_selectedFileName '
                    '(${_formatSize(_selectedBytes?.length ?? 0)})',
                style: const TextStyle(
                  color: MedicalHistoryColors.muted,
                  fontSize: 11,
                ),
              ),
            ],

            const SizedBox(height: 22),

            // --------------------------------------------------
            // REPORT CATEGORY
            // --------------------------------------------------

            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              isExpanded: true,
              decoration: _medicalInputDecoration(
                'What is this report about?',
                Icons.category_outlined,
              ),
              items: _reportCategories.map((category) {
                return DropdownMenuItem<String>(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  _selectedCategory = value;
                });
              },
            ),

            const SizedBox(height: 16),

            // --------------------------------------------------
            // REPORT TITLE
            // --------------------------------------------------

            TextFormField(
              controller: _titleController,
              textCapitalization:
              TextCapitalization.words,
              inputFormatters: [
                LengthLimitingTextInputFormatter(150),
              ],
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Report title is required.';
                }

                return null;
              },
              decoration: _medicalInputDecoration(
                'Report Title *',
                Icons.title_outlined,
              ),
            ),

            const SizedBox(height: 16),

            // --------------------------------------------------
            // REPORT DATE
            // --------------------------------------------------

            InkWell(
              onTap: _selectReportDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: _medicalInputDecoration(
                  'Report Date (Optional)',
                  Icons.calendar_month_outlined,
                ),
                child: Text(
                  _reportDate == null
                      ? 'Select report date'
                      : _formatDate(_reportDate),
                  style: const TextStyle(
                    color: MedicalHistoryColors.text,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

            if (_reportDate != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _reportDate = null;
                    });
                  },
                  child: const Text(
                    'Clear Date',
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // --------------------------------------------------
            // REPORT DESCRIPTION
            // --------------------------------------------------

            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              textCapitalization:
              TextCapitalization.sentences,
              inputFormatters: [
                LengthLimitingTextInputFormatter(700),
              ],
              decoration: _medicalInputDecoration(
                'Description (Optional)',
                Icons.notes_outlined,
              ),
            ),

            const SizedBox(height: 14),

            _medicalNotice(
              'The automatic English description '
                  'feature will be connected when the '
                  'new backend API is ready. For now, '
                  'you can enter the description yourself. '
                  'Custom details are temporary.',
              MedicalHistoryColors.lightOrange,
              MedicalHistoryColors.orange,
            ),

            const SizedBox(height: 23),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                _picking ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor:
                  MedicalHistoryColors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 53),
                ),
                icon: const Icon(
                  Icons.save_outlined,
                ),
                label: Text(
                  _editing
                      ? 'Update Details'
                      : 'Upload Original Report',
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () =>
                    Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// REPORT VIEWER + OCR + ENGLISH TRANSLATION
// ============================================================

class _ReportViewerSheet extends StatefulWidget {
  final _MedicalReportApi api;
  final _MedicalReport report;
  final _MedicalReportDetails? details;

  const _ReportViewerSheet({
    required this.api,
    required this.report,
    this.details,
  });

  @override
  State<_ReportViewerSheet> createState() =>
      _ReportViewerSheetState();
}

class _ReportViewerSheetState
    extends State<_ReportViewerSheet> {
  Map<String, dynamic> _analysis = {};

  Map<String, String> _languages =
  Map<String, String>.from(_fallbackLanguages);

  String _sourceLanguage = 'en';

  bool _consent = false;
  bool _loading = true;
  bool _processing = false;
  bool _ocrConfigured = false;
  bool _showEnglish = true;

  String? _previewUrl;
  String? _errorMessage;

  int _pollGeneration = 0;

  // ==========================================================
  // OCR STATUS
  // ==========================================================

  String get _processingStatus =>
      (_analysis['status'] ?? 'NOT_REQUESTED')
          .toString();

  Map<String, dynamic> get _result {
    final value = _analysis['result'];

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return {};
  }

  // ==========================================================
  // LIFECYCLE
  // ==========================================================

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _pollGeneration++;
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: MedicalHistoryColors.navy,
        content: Text(message),
      ),
    );
  }

  // ==========================================================
  // LOAD OCR OPTIONS / SAVED TEXT
  // ==========================================================

  Future<void> _initialize() async {
    try {
      final options = await widget.api.getOcrOptions();

      final languages = options['languages'];

      if (languages is List) {
        final available = <String, String>{};

        for (final item in languages) {
          if (item is! Map) continue;

          final code = item['code'];
          final name = item['name'];

          if (code is String && name is String) {
            available[code] = name;
          }
        }

        if (available.isNotEmpty) {
          _languages = available;
        }
      }

      _ocrConfigured = options['configured'] == true;
    } catch (error) {
      _ocrConfigured = false;
    }

    try {
      final response = await widget.api.getText(
        widget.report.id,
      );

      final analysis = response['analysis'];

      if (analysis is Map) {
        _analysis =
        Map<String, dynamic>.from(analysis);

        final previousOptions = _analysis['options'];

        if (previousOptions is Map) {
          final previousLanguage =
          previousOptions['source_language'];

          if (previousLanguage is String &&
              _languages.containsKey(previousLanguage)) {
            _sourceLanguage = previousLanguage;
          }
        }
      }
    } catch (error) {
      _errorMessage = error.toString();
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    if (_processingStatus == 'QUEUED' ||
        _processingStatus == 'PROCESSING') {
      _pollStatus();
    }
  }

  // ==========================================================
  // OPEN ORIGINAL REPORT
  // ==========================================================

  Future<void> _openOriginal() async {
    try {
      final url = await widget.api.getDownloadUrl(
        widget.report.id,
      );

      if (!mounted) return;

      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        _showMessage(
          'Unable to open the original report.',
        );
      }
    } catch (error) {
      _showMessage(
        'Original report unavailable: $error',
      );
    }
  }

  // ==========================================================
  // PREVIEW IMAGE
  // ==========================================================

  Future<void> _previewImage() async {
    try {
      final url = await widget.api.getDownloadUrl(
        widget.report.id,
      );

      if (!mounted) return;

      setState(() {
        _previewUrl = url;
      });
    } catch (error) {
      _showMessage(
        'Unable to preview image: $error',
      );
    }
  }

  // ==========================================================
  // REQUEST OCR
  // ==========================================================

  Future<void> _requestOcr() async {
    if (_processing) return;

    final translate = _sourceLanguage != 'en';

    if (translate && !_consent) {
      _showMessage(
        'Please provide consent before '
            'sending extracted medical text to MyMemory.',
      );
      return;
    }

    setState(() {
      _processing = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.api.requestText(
        reportId: widget.report.id,
        sourceLanguage: _sourceLanguage,
        translateToEnglish: translate,
        consent: translate && _consent,
      );

      if (!mounted) return;

      final analysis = response['analysis'];

      if (analysis is Map) {
        setState(() {
          _analysis =
          Map<String, dynamic>.from(analysis);
        });
      }

      if (_processingStatus == 'QUEUED' ||
          _processingStatus == 'PROCESSING') {
        await _pollStatus();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  // ==========================================================
  // POLL OCR BACKGROUND JOB
  // ==========================================================

  Future<void> _pollStatus() async {
    final generation = ++_pollGeneration;

    for (int attempt = 0; attempt < 120; attempt++) {
      if (!mounted ||
          generation != _pollGeneration) {
        return;
      }

      if (_processingStatus != 'QUEUED' &&
          _processingStatus != 'PROCESSING') {
        return;
      }

      await Future<void>.delayed(
        const Duration(seconds: 3),
      );

      if (!mounted ||
          generation != _pollGeneration) {
        return;
      }

      try {
        final response = await widget.api.getText(
          widget.report.id,
        );

        final analysis = response['analysis'];

        if (analysis is Map &&
            mounted &&
            generation == _pollGeneration) {
          setState(() {
            _analysis =
            Map<String, dynamic>.from(analysis);
          });
        }
      } catch (error) {
        if (mounted &&
            generation == _pollGeneration) {
          setState(() {
            _errorMessage = error.toString();
          });
        }

        return;
      }
    }
  }

  // ==========================================================
  // VIEWER UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final result = _result;

    final englishText =
    (result['english_text'] ?? '').toString();

    final originalText =
    (result['original_text'] ?? '').toString();

    final displayedText =
    _showEnglish ? englishText : originalText;

    return _medicalBottomSheet(
      context,
      Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          // --------------------------------------------------
          // HEADER
          // --------------------------------------------------

          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                color: MedicalHistoryColors.green,
                size: 28,
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  widget.details?.title ??
                      widget.report.name,
                  style: const TextStyle(
                    color: MedicalHistoryColors.navy,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              IconButton(
                tooltip: 'Close',
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(
                  Icons.close_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            '${_formatSize(widget.report.sizeBytes)}'
                ' • Uploaded '
                '${_formatDate(widget.report.uploadedAt?.toLocal())}',
            style: const TextStyle(
              fontSize: 11,
              color: MedicalHistoryColors.muted,
            ),
          ),

          // --------------------------------------------------
          // SESSION DETAILS
          // --------------------------------------------------

          if (widget.details != null) ...[
            const SizedBox(height: 12),

            Text(
              'Category: ${widget.details!.category}',
              style: const TextStyle(
                color: MedicalHistoryColors.text,
                fontSize: 12,
              ),
            ),

            if (widget.details!.reportDate != null)
              Text(
                'Report date: '
                    '${_formatDate(widget.details!.reportDate)}',
                style: const TextStyle(
                  color: MedicalHistoryColors.text,
                  fontSize: 12,
                ),
              ),

            if (widget.details!.description.isNotEmpty) ...[
              const SizedBox(height: 8),

              Text(
                widget.details!.description,
                style: const TextStyle(
                  color: MedicalHistoryColors.text,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],

            const SizedBox(height: 8),

            const Text(
              'Custom details are session-only.',
              style: TextStyle(
                color: MedicalHistoryColors.orange,
                fontSize: 10,
              ),
            ),
          ],

          const SizedBox(height: 18),

          // --------------------------------------------------
          // ORIGINAL DOCUMENT
          // --------------------------------------------------

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _openOriginal,
                icon: const Icon(
                  Icons.open_in_new_outlined,
                ),
                label: Text(
                  widget.report.isImage
                      ? 'Open Original Image'
                      : 'Open Original PDF',
                ),
              ),

              if (widget.report.isImage)
                OutlinedButton.icon(
                  onPressed: _previewImage,
                  icon: const Icon(
                    Icons.image_outlined,
                  ),
                  label: const Text(
                    'Preview Image Here',
                  ),
                ),
            ],
          ),

          // --------------------------------------------------
          // IMAGE PREVIEW
          // --------------------------------------------------

          if (_previewUrl != null &&
              widget.report.isImage) ...[
            const SizedBox(height: 15),

            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _previewUrl!,
                height: 250,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (
                    context,
                    error,
                    stackTrace,
                    ) {
                  return const Padding(
                    padding: EdgeInsets.all(15),
                    child: Text(
                      'Image preview unavailable. '
                          'Please reload the image.',
                    ),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 22),

          // --------------------------------------------------
          // OCR HEADER
          // --------------------------------------------------

          const Text(
            'Read & Translate Report',
            style: TextStyle(
              color: MedicalHistoryColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),

          const SizedBox(height: 9),

          _medicalNotice(
            'English is the default reading view. '
                'Automatic language detection is not '
                'available in the current backend. '
                'Select the language printed on the '
                'document. The original file will '
                'remain unchanged.',
            MedicalHistoryColors.lightBlue,
            MedicalHistoryColors.blue,
          ),

          const SizedBox(height: 16),

          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                color: MedicalHistoryColors.blue,
              ),
            )
          else ...[
            // ------------------------------------------------
            // DOCUMENT LANGUAGE
            // ------------------------------------------------

            DropdownButtonFormField<String>(
              key: ValueKey(_sourceLanguage),
              initialValue:
              _languages.containsKey(_sourceLanguage)
                  ? _sourceLanguage
                  : _languages.keys.first,
              isExpanded: true,
              decoration: _medicalInputDecoration(
                'Document Language',
                Icons.language_rounded,
              ),
              items: _languages.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
              onChanged: _processing
                  ? null
                  : (value) {
                if (value == null) return;

                setState(() {
                  _sourceLanguage = value;
                  _consent = false;
                });
              },
            ),

            // ------------------------------------------------
            // TRANSLATION CONSENT
            // ------------------------------------------------

            if (_sourceLanguage != 'en') ...[
              const SizedBox(height: 13),

              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity:
                ListTileControlAffinity.leading,
                value: _consent,
                title: const Text(
                  'I consent to English translation',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                subtitle: const Text(
                  'Extracted medical text will be '
                      'sent to the external MyMemory '
                      'translation service. Translation '
                      'accuracy is not guaranteed.',
                  style: TextStyle(fontSize: 11),
                ),
                onChanged: _processing
                    ? null
                    : (value) {
                  setState(() {
                    _consent = value ?? false;
                  });
                },
              ),
            ],

            const SizedBox(height: 13),

            // ------------------------------------------------
            // OCR BUTTON
            // ------------------------------------------------

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                !_ocrConfigured || _processing
                    ? null
                    : _requestOcr,
                style: FilledButton.styleFrom(
                  backgroundColor:
                  MedicalHistoryColors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 52),
                ),
                icon: _processing
                    ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(
                  Icons.translate_rounded,
                ),
                label: Text(
                  _processing
                      ? 'Processing Report...'
                      : _sourceLanguage == 'en'
                      ? 'Extract English Text'
                      : 'Translate to English',
                ),
              ),
            ),

            if (!_ocrConfigured) ...[
              const SizedBox(height: 11),

              const Text(
                'OCR processor is not configured '
                    'or could not be verified. '
                    'Original report access remains available.',
                style: TextStyle(
                  color: MedicalHistoryColors.orange,
                  fontSize: 11,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ------------------------------------------------
            // OCR STATUS
            // ------------------------------------------------

            Text(
              'Processing status: $_processingStatus',
              style: const TextStyle(
                color: MedicalHistoryColors.text,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 9),

              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: MedicalHistoryColors.red,
                  fontSize: 11,
                ),
              ),
            ],

            if (_analysis['error'] is Map) ...[
              const SizedBox(height: 9),

              Text(
                ((_analysis['error'] as Map)['message'] ??
                    'Report processing failed.')
                    .toString(),
                style: const TextStyle(
                  color: MedicalHistoryColors.red,
                  fontSize: 11,
                ),
              ),
            ],

            // ------------------------------------------------
            // ENGLISH / ORIGINAL TEXT
            // ------------------------------------------------

            if (originalText.isNotEmpty ||
                englishText.isNotEmpty) ...[
              const SizedBox(height: 17),

              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('English'),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Original Text'),
                  ),
                ],
                selected: {_showEnglish},
                onSelectionChanged: (selection) {
                  setState(() {
                    _showEnglish = selection.first;
                  });
                },
              ),

              const SizedBox(height: 13),

              Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  minHeight: 110,
                ),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MedicalHistoryColors.cream,
                  borderRadius:
                  BorderRadius.circular(13),
                  border: Border.all(
                    color: MedicalHistoryColors.border,
                  ),
                ),
                child: SelectableText(
                  displayedText.trim().isEmpty
                      ? _showEnglish
                      ? 'English translation is '
                      'not available yet.'
                      : 'No original text was extracted.'
                      : displayedText,
                  style: const TextStyle(
                    color: MedicalHistoryColors.text,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),

              const SizedBox(height: 11),

              OutlinedButton.icon(
                onPressed: displayedText.trim().isEmpty
                    ? null
                    : () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: displayedText,
                    ),
                  );

                  _showMessage(
                    'Text copied. Please verify '
                        'against the original report.',
                  );
                },
                icon: const Icon(
                  Icons.copy_outlined,
                ),
                label: const Text('Copy Text'),
              ),
            ],
          ],

          const SizedBox(height: 18),

          _medicalNotice(
            'Automatic language detection and '
                'AI-generated report descriptions '
                'are planned for a later backend update. '
                'Always verify medical terms, doses '
                'and measurements against the original.',
            MedicalHistoryColors.lightOrange,
            MedicalHistoryColors.orange,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// REUSABLE BOTTOM SHEET
// ============================================================

Widget _medicalBottomSheet(
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
        MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(25),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20, 22, 20, 30,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 650,
              ),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

// ============================================================
// REUSABLE INPUT DECORATION
// ============================================================

InputDecoration _medicalInputDecoration(
    String label,
    IconData icon,
    ) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(
      icon,
      color: MedicalHistoryColors.green,
    ),
    filled: true,
    fillColor: MedicalHistoryColors.cream,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(
        color: MedicalHistoryColors.border,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(
        color: MedicalHistoryColors.green,
        width: 1.7,
      ),
    ),
  );
}

// ============================================================
// REUSABLE NOTICE
// ============================================================

Widget _medicalNotice(
    String message,
    Color background,
    Color iconColor,
    ) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(13),
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
              color: MedicalHistoryColors.text,
              fontSize: 11,
              height: 1.6,
            ),
          ),
        ),
      ],
    ),
  );
}

// ============================================================
// REUSABLE PANEL
// ============================================================

Widget _medicalPanel(
    String title,
    IconData icon,
    Widget child,
    ) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: MedicalHistoryColors.border,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: MedicalHistoryColors.green,
              size: 25,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: MedicalHistoryColors.navy,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
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
