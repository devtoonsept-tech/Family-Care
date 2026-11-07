import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../auth/login_screen.dart';

// ============================================================
// FAMILYCARE+ - CHILD HEALTH REPORTS
// ============================================================
//
// CURRENT FLASK APIs:
//
// GET  /api/v1/patients/profiles/{profileId}
// GET  /api/v1/patients/profiles/{profileId}/reports
// POST /api/v1/patients/profiles/{profileId}/reports
//
// GET  /api/v1/patients/profiles/{profileId}/reports/
//      {reportId}/download
//
// GET  /api/v1/patients/report-text/options
//
// GET  /api/v1/patients/profiles/{profileId}/reports/
//      {reportId}/text
//
// POST /api/v1/patients/profiles/{profileId}/reports/
//      {reportId}/text
//
// FEATURES:
// - Authenticated patient/child report access
// - PDF, JPG, PNG and WebP upload
// - 10 MB maximum file size
// - File signature validation
// - Private original file access
// - Cloudinary signed URL support
// - Legacy database file support
// - Image preview with zoom
// - Original PDF opening
// - Save to device
// - Report search and file filters
// - Server pagination
// - OCR text extraction
// - Optional English translation
// - Original / English text viewing
// - Explicit external translation consent
// - OCR status polling
// - Retry and refresh
// - Child profile switching protection
//
// CURRENT LIMITATIONS:
// - No report-delete API
// - No automatic source-language detection
// - No AI report classification/description API
// - Report category can be edited through Backend v5 PATCH API
// - No custom report title/date/description persistence API
// - OCR maximum: 5 PDF pages
// - English translation uses MyMemory
//
// Compatible with file_picker 12.x / 13.x.
// ============================================================

// ============================================================
// COLORS
// ============================================================

class HealthReportsColors {
  static const navy = Color(0xFF143C60);
  static const text = Color(0xFF263F45);
  static const muted = Color(0xFF81918C);

  static const background = Color(0xFFF2F7FD);
  static const white = Colors.white;
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
// FILE FILTER
// ============================================================

enum HealthReportFilter {
  all,
  pdf,
  images,
}

// ============================================================
// REPORT MODEL
// ============================================================

// These values are the exact Backend v5 report-category enum.
const List<String> _healthReportCategories = <String>[
  'Lab tests',
  'Prescriptions',
  'Scans',
  'Vaccination',
  'Others',
];

class ChildHealthReport {
  final String id;
  final String profileId;
  final String name;
  final String contentType;
  final int sizeBytes;
  final DateTime? createdAt;
  // Category is persisted server-side; not a diagnosis.
  final String category;
  // True only when the account holder explicitly reviewed this category.
  final bool categoryReviewed;

  const ChildHealthReport({
    required this.id,
    required this.profileId,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    required this.createdAt,
    required this.category,
    required this.categoryReviewed,
  });

  bool get isPdf {
    return contentType.toLowerCase() ==
        'application/pdf' ||
        name.toLowerCase().endsWith('.pdf');
  }

  bool get isImage {
    final type = contentType.toLowerCase();

    return type == 'image/jpeg' ||
        type == 'image/png' ||
        type == 'image/webp';
  }

  IconData get icon {
    if (isPdf) {
      return Icons.picture_as_pdf_outlined;
    }
    return Icons.image_outlined;
  }

  Color get color {
    return isPdf
        ? HealthReportsColors.red
        : HealthReportsColors.blue;
  }

  factory ChildHealthReport.fromJson(
      Map<String, dynamic> json,
      ) {
    final size = json['size_bytes'];

    final rawDate = json['created_at'];

    return ChildHealthReport(
      id: (json['id'] ?? '').toString(),
      profileId:
      (json['profile_id'] ?? '').toString(),
      name:
      (json['name'] ?? 'Medical Report').toString(),
      contentType:
      (json['content_type'] ?? '').toString(),
      sizeBytes: size is num ? size.toInt() : 0,
      category: _healthReportCategories.contains(json['category'])
          ? json['category'] as String
          : 'Others',
      categoryReviewed: json['category_reviewed'] == true,
      createdAt: rawDate is String
          ? DateTime.tryParse(rawDate)?.toLocal()
          : null,
    );
  }
}

// ============================================================
// FORMAT HELPERS
// ============================================================

class HealthReportFormatter {
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

  static String date(DateTime? date) {
    if (date == null) {
      return 'Date unavailable';
    }

    return '${date.day} '
        '${months[date.month - 1]} '
        '${date.year}';
  }

  static String fileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

// ============================================================
// API EXCEPTION
// ============================================================

class HealthReportsApiException implements Exception {
  final String message;
  final int statusCode;

  const HealthReportsApiException(
      this.message, {
        this.statusCode = 0,
      });

  @override
  String toString() => message;
}

// ============================================================
// FLASK API CLIENT
// ============================================================

class _HealthReportsApi {
  final String baseUrl;
  final String profileId;

  final http.Client _client = http.Client();

  static const maxReportBytes = 10 * 1024 * 1024;

  _HealthReportsApi({
    required this.baseUrl,
    required this.profileId,
  });

  String get profilePath =>
      '/api/v1/patients/profiles/'
          '${Uri.encodeComponent(profileId)}';

  String get reportsPath => '$profilePath/reports';

  String reportPath(String reportId) {
    return '$reportsPath/'
        '${Uri.encodeComponent(reportId)}';
  }

  String textPath(String reportId) {
    return '${reportPath(reportId)}/text';
  }

  void dispose() {
    _client.close();
  }

  // ==========================================================
  // AUTH
  // ==========================================================

  Future<Map<String, String>> _headers() async {
    final token =
    await FamilyCareSession.accessToken();

    if (token == null || token.trim().isEmpty) {
      throw const HealthReportsApiException(
        'Login session unavailable. '
            'Please sign in again.',
        statusCode: 401,
      );
    }

    return {
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
    };
  }

  // ==========================================================
  // SERVER ERROR
  // ==========================================================

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
      // Error responses may not be JSON.
    }

    switch (response.statusCode) {
      case 401:
        return 'Session expired. Please sign in again.';
      case 403:
        return 'You do not have access to this report.';
      case 404:
        return 'Report or child profile not found.';
      case 413:
        return 'Maximum file size is 10 MB.';
      case 415:
        return 'Unsupported file type.';
      case 422:
        return 'Please check the selected options.';
      case 429:
        return 'Translation rate limit reached. '
            'Please try again later.';
      case 503:
        return 'OCR or storage service is unavailable.';
      default:
        return 'Server request failed '
            '(HTTP ${response.statusCode}).';
    }
  }

  // ==========================================================
  // DECODE JSON
  // ==========================================================

  Map<String, dynamic> _decodeJson(
      http.Response response,
      ) {
    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw HealthReportsApiException(
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
      throw const HealthReportsApiException(
        'Invalid JSON response from the server.',
      );
    }
  }

  // ==========================================================
  // GET JSON
  // ==========================================================

  Future<Map<String, dynamic>> getJson(
      String path,
      ) async {
    final response = await _client
        .get(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
    )
        .timeout(const Duration(seconds: 40));

    return _decodeJson(response);
  }

  // ==========================================================
  // POST JSON
  // ==========================================================

  Future<Map<String, dynamic>> postJson(
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
        .timeout(const Duration(seconds: 40));

    return _decodeJson(response);
  }

  // ==========================================================
  // GET CHILD PROFILE
  // ==========================================================

  Future<String?> loadChildName() async {
    final response = await getJson(profilePath);

    final rawProfile = response['profile'];

    if (rawProfile is! Map) {
      throw const HealthReportsApiException(
        'Child profile could not be loaded.',
      );
    }

    if (rawProfile['module'] != 'child') {
      throw const HealthReportsApiException(
        'The selected profile is not a Child Care profile.',
      );
    }

    final name = rawProfile['full_name'];

    if (name is String && name.trim().isNotEmpty) {
      return name.trim();
    }

    return null;
  }

  // ==========================================================
  // PAGINATED REPORTS
  // ==========================================================

  Future<Map<String, dynamic>> loadPage(
      int page, {
        int perPage = 20,
      }) {
    return getJson(
      '$reportsPath?page=$page&per_page=$perPage',
    );
  }

  // ==========================================================
  // EXPLICIT REPORT CATEGORY (BACKEND V5)
  // ==========================================================

  Future<String> saveCategory({
    required String reportId,
    required String category,
  }) async {
    if (!_healthReportCategories.contains(category)) {
      throw const HealthReportsApiException(
        'Please select one of the supported report categories.',
      );
    }

    final headers = await _headers();
    headers['Content-Type'] = 'application/json';

    final response = await _client.patch(
      Uri.parse('$baseUrl${reportPath(reportId)}/category'),
      headers: headers,
      body: jsonEncode({'category': category}),
    ).timeout(const Duration(seconds: 40));

    final result = _decodeJson(response);
    if (result['category_reviewed'] != true) {
      throw const HealthReportsApiException(
        'The server did not confirm the category review. '
            'Refresh the report list before trying again.',
      );
    }
    return (result['category'] ?? category).toString();
  }

  // ==========================================================
  // VALIDATE FILE SIGNATURE
  // ==========================================================

  String? detectMime(Uint8List bytes) {
    if (bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D) {
      return 'application/pdf';
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }

    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }

    return null;
  }

  bool extensionMatches(
      String name,
      String mime,
      ) {
    final value = name.toLowerCase();

    switch (mime) {
      case 'application/pdf':
        return value.endsWith('.pdf');

      case 'image/jpeg':
        return value.endsWith('.jpg') ||
            value.endsWith('.jpeg');

      case 'image/png':
        return value.endsWith('.png');

      case 'image/webp':
        return value.endsWith('.webp');
    }

    return false;
  }

  // ==========================================================
  // READ FILE SAFELY
  // ==========================================================

  Future<Uint8List> readFile(
      PlatformFile file,
      ) async {
    final knownLength =
        file.lengthSync() ?? await file.length();

    if (knownLength != null &&
        knownLength > maxReportBytes) {
      throw const HealthReportsApiException(
        'Maximum report size is 10 MB.',
      );
    }

    final builder = BytesBuilder(copy: false);

    int total = 0;

    await for (final chunk in file.readAsByteStream()) {
      total += chunk.length;

      if (total > maxReportBytes) {
        throw const HealthReportsApiException(
          'Maximum report size is 10 MB.',
        );
      }

      builder.add(chunk);
    }

    if (total == 0) {
      throw const HealthReportsApiException(
        'The selected file is empty.',
      );
    }

    return builder.takeBytes();
  }

  // ==========================================================
  // UPLOAD REPORT
  // ==========================================================

  Future<ChildHealthReport> upload(
      PlatformFile file,
      ) async {
    final bytes = await readFile(file);

    final mime = detectMime(bytes);

    if (mime == null ||
        !extensionMatches(file.name, mime)) {
      throw const HealthReportsApiException(
        'Select a valid PDF, JPG, PNG or WebP file.',
      );
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl$reportsPath'),
    );

    request.headers.addAll(await _headers());

    // The backend accepts exactly one multipart field.
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: file.name,
      ),
    );

    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 100));

    final response =
    await http.Response.fromStream(streamedResponse);

    final json = _decodeJson(response);
    final report = json['report'];

    if (report is! Map) {
      throw const HealthReportsApiException(
        'Upload response was incomplete. '
            'Refresh the report list before retrying.',
      );
    }

    return ChildHealthReport.fromJson(
      Map<String, dynamic>.from(report),
    );
  }

  // ==========================================================
  // ORIGINAL DOWNLOAD RESPONSE
  // ==========================================================

  Future<http.Response> downloadResponse(
      String reportId,
      ) async {
    final response = await _client
        .get(
      Uri.parse(
        '$baseUrl${reportPath(reportId)}/download',
      ),
      headers: await _headers(),
    )
        .timeout(const Duration(seconds: 50));

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw HealthReportsApiException(
        _serverError(response),
        statusCode: response.statusCode,
      );
    }

    return response;
  }

  // ==========================================================
  // SIGNED CLOUDINARY URL
  // ==========================================================

  Uri validateSignedUrl(String value) {
    final uri = Uri.tryParse(value);

    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() !=
            'res.cloudinary.com' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      throw const HealthReportsApiException(
        'Invalid secure file access link.',
      );
    }

    return uri;
  }

  Uri? extractSignedUrl(
      http.Response response,
      ) {
    final type =
        response.headers['content-type'] ?? '';

    if (!type.toLowerCase().contains('json')) {
      return null;
    }

    final data = _decodeJson(response);

    final report = data['report'];

    if (report is! Map) {
      throw const HealthReportsApiException(
        'Invalid report download response.',
      );
    }

    final url = report['url'];

    if (url is! String || url.isEmpty) {
      throw const HealthReportsApiException(
        'Secure download link unavailable. '
            'Check storage configuration.',
      );
    }

    return validateSignedUrl(url);
  }

  // ==========================================================
  // DOWNLOAD FILE BYTES
  // ==========================================================

  Future<Uint8List> downloadBytes(
      String reportId,
      ) async {
    final response =
    await downloadResponse(reportId);

    final signedUrl = extractSignedUrl(response);

    if (signedUrl == null) {
      // Legacy database-backed reports are
      // delivered directly by Flask.
      if (response.bodyBytes.isEmpty) {
        throw const HealthReportsApiException(
          'The stored report is empty.',
        );
      }

      return response.bodyBytes;
    }

    final result = await _client
        .get(signedUrl)
        .timeout(const Duration(seconds: 70));

    if (result.statusCode != 200) {
      throw const HealthReportsApiException(
        'Could not retrieve the secure report file.',
      );
    }

    if (result.bodyBytes.isEmpty) {
      throw const HealthReportsApiException(
        'Downloaded report is empty.',
      );
    }

    return result.bodyBytes;
  }

  // ==========================================================
  // ORIGINAL PDF URI
  // ==========================================================

  Future<Uri?> pdfUri(
      String reportId,
      ) async {
    final response =
    await downloadResponse(reportId);

    return extractSignedUrl(response);
  }

  // ==========================================================
  // OCR OPTIONS
  // ==========================================================

  Future<Map<String, dynamic>> ocrOptions() {
    return getJson(
      '/api/v1/patients/report-text/options',
    );
  }

  // ==========================================================
  // GET SAVED OCR
  // ==========================================================

  Future<Map<String, dynamic>> getOcr(
      String reportId,
      ) async {
    final response = await getJson(
      textPath(reportId),
    );

    final analysis = response['analysis'];

    if (analysis is! Map) {
      throw const HealthReportsApiException(
        'Invalid OCR status response.',
      );
    }

    return Map<String, dynamic>.from(analysis);
  }

  // ==========================================================
  // START OCR
  // ==========================================================

  Future<Map<String, dynamic>> requestOcr({
    required String reportId,
    required String sourceLanguage,
    required bool translate,
    required bool consent,
  }) async {
    final response = await postJson(
      textPath(reportId),
      {
        'source_language': sourceLanguage,
        'translate_to_english': translate,
        'external_translation_consent': consent,
      },
    );

    final analysis = response['analysis'];

    if (analysis is! Map) {
      throw const HealthReportsApiException(
        'Invalid OCR request response.',
      );
    }

    return Map<String, dynamic>.from(analysis);
  }
}

// ============================================================
// MAIN HEALTH REPORTS SCREEN
// ============================================================

class HealthReportsScreen extends StatefulWidget {
  final String profileId;
  final String childName;
  final String apiBaseUrl;

  const HealthReportsScreen({
    super.key,
    required this.profileId,
    this.childName = 'Child',
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
  });

  @override
  State<HealthReportsScreen> createState() =>
      _HealthReportsScreenState();
}

class _HealthReportsScreenState
    extends State<HealthReportsScreen> {
  late _HealthReportsApi _api;

  final TextEditingController _searchController =
  TextEditingController();

  final List<ChildHealthReport> _reports = [];

  HealthReportFilter _filter =
      HealthReportFilter.all;
  String? _categoryFilter;

  static const int _perPage = 20;

  String? _loadedChildName;
  String? _loadingError;

  int _currentPage = 0;
  int _totalReports = 0;
  int _generation = 0;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isUploading = false;
  bool _isOpening = false;

  // ==========================================================
  // BASE URL
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

  String get _displayChildName =>
      _loadedChildName ?? widget.childName;

  bool get _busy =>
      _isLoading || _isUploading || _isOpening;

  // ==========================================================
  // LIFECYCLE
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _api = _HealthReportsApi(
      baseUrl: _baseUrl,
      profileId: widget.profileId,
    );

    _searchController.addListener(
      _searchChanged,
    );

    _refreshReports();
  }

  @override
  void didUpdateWidget(
      covariant HealthReportsScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.profileId != widget.profileId ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _generation++;

      _api.dispose();

      _api = _HealthReportsApi(
        baseUrl: _baseUrl,
        profileId: widget.profileId,
      );

      _reports.clear();

      _currentPage = 0;
      _totalReports = 0;

      _loadedChildName = null;
      _loadingError = null;

      _isUploading = false;
      _isOpening = false;
      _isLoadingMore = false;

      _filter = HealthReportFilter.all;
      _categoryFilter = null;

      _searchController.clear();

      _refreshReports();
    }
  }

  @override
  void dispose() {
    _generation++;

    _api.dispose();

    _searchController.removeListener(
      _searchChanged,
    );

    _searchController.dispose();

    super.dispose();
  }

  void _searchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ==========================================================
  // ERROR HANDLING
  // ==========================================================

  String _friendlyError(Object error) {
    if (error is HealthReportsApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'Server response timed out. Please retry.';
    }

    if (error is http.ClientException) {
      return 'Unable to connect to the server.';
    }

    if (error is PlatformException) {
      return 'Device operation failed. Please retry.';
    }

    if (error is FormatException) {
      return 'Invalid data received from the server.';
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
              ? HealthReportsColors.red
              : HealthReportsColors.navy,
          content: Text(value),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ==========================================================
  // PARSE REPORTS
  // ==========================================================

  List<ChildHealthReport> _parseReports(
      Map<String, dynamic> data,
      ) {
    final items = data['items'];

    if (items is! List) {
      throw const HealthReportsApiException(
        'Invalid report list from the server.',
      );
    }

    final parsed = <ChildHealthReport>[];

    for (final item in items) {
      if (item is! Map) continue;

      final report = ChildHealthReport.fromJson(
        Map<String, dynamic>.from(item),
      );

      if (report.id.isNotEmpty &&
          report.profileId == widget.profileId) {
        parsed.add(report);
      }
    }

    return parsed;
  }

  // ==========================================================
  // REFRESH REPORTS
  // ==========================================================

  Future<bool> _refreshReports() async {
    final generation = ++_generation;
    final profileId = widget.profileId;
    final api = _api;

    if (!mounted) return false;

    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _loadingError = null;
    });

    try {
      final name = await api.loadChildName();

      final response = await api.loadPage(
        1,
        perPage: _perPage,
      );

      if (!mounted ||
          generation != _generation ||
          profileId != widget.profileId) {
        return false;
      }

      final parsed = _parseReports(response);

      final rawTotal = response['total'];

      setState(() {
        _loadedChildName = name;

        _reports
          ..clear()
          ..addAll(parsed);

        _currentPage = 1;

        _totalReports = rawTotal is num
            ? rawTotal.toInt()
            : parsed.length;

        _loadingError = null;
        _isLoading = false;
      });

      return true;
    } catch (error) {
      if (!mounted ||
          generation != _generation ||
          profileId != widget.profileId) {
        return false;
      }

      setState(() {
        _reports.clear();

        _currentPage = 0;
        _totalReports = 0;

        _loadingError = _friendlyError(error);
        _isLoading = false;
      });

      return false;
    }
  }

  // ==========================================================
  // LOAD MORE
  // ==========================================================

  Future<void> _loadMoreReports() async {
    if (_isLoading ||
        _isLoadingMore ||
        _reports.length >= _totalReports) {
      return;
    }

    final generation = _generation;
    final profileId = widget.profileId;
    final api = _api;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final page = _currentPage + 1;

      final result = await api.loadPage(
        page,
        perPage: _perPage,
      );

      if (!mounted ||
          generation != _generation ||
          profileId != widget.profileId) {
        return;
      }

      final parsed = _parseReports(result);

      setState(() {
        final existingIds =
        _reports.map((report) => report.id).toSet();

        for (final report in parsed) {
          if (existingIds.add(report.id)) {
            _reports.add(report);
          }
        }

        _currentPage = page;

        final total = result['total'];

        if (total is num) {
          _totalReports = total.toInt();
        }
      });
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          widget.profileId == profileId) {
        _message(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted &&
          generation == _generation &&
          widget.profileId == profileId) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  // ==========================================================
  // FILTERS
  // ==========================================================

  List<ChildHealthReport> get _filteredReports {
    final query =
    _searchController.text.trim().toLowerCase();

    return _reports.where((report) {
      if (_filter == HealthReportFilter.pdf &&
          !report.isPdf) {
        return false;
      }

      if (_filter == HealthReportFilter.images &&
          !report.isImage) {
        return false;
      }
      if (_categoryFilter != null &&
          report.category != _categoryFilter) {
        return false;
      }

      if (query.isEmpty) return true;

      return report.name.toLowerCase().contains(query) ||
          report.category.toLowerCase().contains(query);
    }).toList();
  }

  int get _loadedPdfCount {
    return _reports.where((r) => r.isPdf).length;
  }

  int get _loadedImageCount {
    return _reports.where((r) => r.isImage).length;
  }

  // ==========================================================
  // UPLOAD
  // ==========================================================

  // ==========================================================
  // CHOOSE ONE CANONICAL SERVER CATEGORY
  // ==========================================================

  Future<String?> _chooseCategory({
    required String title,
    String? current,
  }) async {
    String? selected = _healthReportCategories.contains(current)
        ? current
        : null;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select what this document is for. The category '
                      'will be saved to FamilyCare+ and shared with '
                      'Medical History. It is not a medical diagnosis.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: HealthReportsColors.muted,
                  ),
                ),
                const SizedBox(height: 15),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: _healthReportCategories.map((category) {
                    return ChoiceChip(
                      label: Text(category),
                      selected: selected == category,
                      showCheckmark: false,
                      selectedColor: HealthReportsColors.green,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: selected == category
                            ? Colors.white
                            : HealthReportsColors.text,
                      ),
                      onSelected: (_) {
                        setDialogState(() => selected = category);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(dialogContext, selected),
              child: const Text('Confirm Category'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // UPLOAD AND SAVE CATEGORY AS TWO SEPARATE OPERATIONS
  // ==========================================================

  Future<void> _uploadReport() async {
    if (_busy || _loadingError != null) return;

    final profileId = widget.profileId;
    final api = _api;

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf', 'jpg', 'jpeg', 'png', 'webp',
        ],
        dialogTitle: 'Select Medical Report',
      );

      if (file == null || !mounted ||
          profileId != widget.profileId) {
        return;
      }

      // Do not upload until the user classifies the document.
      final category = await _chooseCategory(
        title: 'Report Category',
      );
      if (category == null || !mounted ||
          profileId != widget.profileId) {
        return;
      }

      setState(() => _isUploading = true);

      // A report upload and category PATCH are NOT one transaction.
      // If PATCH fails, the original file is still uploaded: never
      // advise retrying upload, which could duplicate the report.
      final uploaded = await api.upload(file);
      if (!mounted || profileId != widget.profileId) return;

      String? categoryFailure;
      try {
        await api.saveCategory(
          reportId: uploaded.id,
          category: category,
        );
      } catch (error) {
        categoryFailure = _friendlyError(error);
      }

      if (!mounted || profileId != widget.profileId) return;
      final refreshed = await _refreshReports();
      if (!mounted || profileId != widget.profileId) return;

      if (categoryFailure != null) {
        _message(
          'Report uploaded, but category was NOT saved: '
              '$categoryFailure. Use Edit Category to retry; '
              'do not upload the file again.',
          error: true,
        );
      } else if (!refreshed) {
        _message(
          'Report and category were submitted to the server, '
              'but the report list could not refresh. Try Refresh.',
        );
      } else {
        _message('Report uploaded and category saved to FamilyCare+.');
      }
    } catch (error) {
      if (mounted && profileId == widget.profileId) {
        _message(_friendlyError(error), error: true);
      }
    } finally {
      if (mounted && profileId == widget.profileId) {
        setState(() => _isUploading = false);
      }
    }
  }

  // ==========================================================
  // EDIT CATEGORY OF AN EXISTING UPLOADED REPORT
  // ==========================================================

  Future<void> _editCategory(ChildHealthReport report) async {
    if (_busy || _loadingError != null) return;

    final profileId = widget.profileId;
    final api = _api;
    final chosen = await _chooseCategory(
      title: 'Edit Report Category',
      current: report.category,
    );
    if (!mounted || profileId != widget.profileId ||
        chosen == null) return;
    if (chosen == report.category && report.categoryReviewed) return;

    setState(() => _isUploading = true);
    try {
      final updated = await api.saveCategory(
        reportId: report.id,
        category: chosen,
      );
      if (!mounted || profileId != widget.profileId) return;
      final refreshed = await _refreshReports();
      if (!mounted || profileId != widget.profileId) return;
      _message(
        refreshed
            ? 'Report category saved as $updated.'
            : 'Category saved, but report list refresh failed. '
            'Try Refresh.',
      );
    } catch (error) {
      if (mounted && profileId == widget.profileId) {
        _message(_friendlyError(error), error: true);
      }
    } finally {
      if (mounted && profileId == widget.profileId) {
        setState(() => _isUploading = false);
      }
    }
  }

  // ==========================================================
  // OPEN ORIGINAL
  // ==========================================================

  Future<void> _openReport(
      ChildHealthReport report,
      ) async {
    if (_isOpening) return;

    final profileId = widget.profileId;
    final api = _api;

    setState(() {
      _isOpening = true;
    });

    try {
      if (report.isImage) {
        final bytes =
        await api.downloadBytes(report.id);

        if (!mounted ||
            widget.profileId != profileId) {
          return;
        }

        await showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return Dialog(
              insetPadding: const EdgeInsets.all(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 900,
                  maxHeight: 750,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        16, 12, 8, 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              report.name,
                              maxLines: 2,
                              overflow:
                              TextOverflow.ellipsis,
                              style: const TextStyle(
                                color:
                                HealthReportsColors.navy,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close preview',
                            onPressed: () {
                              Navigator.pop(dialogContext);
                            },
                            icon: const Icon(
                              Icons.close_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 5,
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          errorBuilder: (
                              context,
                              error,
                              stackTrace,
                              ) {
                            return const Padding(
                              padding: EdgeInsets.all(25),
                              child: Text(
                                'Unable to display this image.',
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );

        return;
      }

      // Cloudinary PDFs can open via the short-lived signed URL.
      // Legacy protected PDFs have no public URL; users must Save.
      // Never expose bearer tokens in an external PDF viewer URL.
      final uri = await api.pdfUri(report.id);

      if (!mounted ||
          widget.profileId != profileId) {
        return;
      }

      if (uri == null) {
        throw const HealthReportsApiException(
          'This PDF uses protected file delivery. '
              'Use Save to download the original PDF.',
        );
      }

      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        throw const HealthReportsApiException(
          'Unable to open the PDF viewer.',
        );
      }
    } catch (error) {
      if (mounted &&
          widget.profileId == profileId) {
        _message(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted &&
          widget.profileId == profileId) {
        setState(() {
          _isOpening = false;
        });
      }
    }
  }

  // ==========================================================
  // SAVE ORIGINAL FILE
  // ==========================================================

  Future<void> _saveReport(
      ChildHealthReport report,
      ) async {
    if (_isOpening) return;

    final profileId = widget.profileId;
    final api = _api;

    setState(() {
      _isOpening = true;
    });

    try {
      final bytes =
      await api.downloadBytes(report.id);

      if (!mounted ||
          widget.profileId != profileId) {
        return;
      }

      final cleanName = report.name
          .replaceAll(
        RegExp(r'[\\/\x00-\x1f]'),
        '_',
      )
          .trim();

      final fallback = report.isPdf
          ? 'medical_report.pdf'
          : 'medical_report.jpg';

      final result = await FilePicker.saveFile(
        dialogTitle: 'Save Medical Report',
        fileName: cleanName.isEmpty
            ? fallback
            : cleanName,
        bytes: bytes,
        mimeType: report.contentType.isEmpty
            ? 'application/octet-stream'
            : report.contentType,
      );

      if (!mounted ||
          widget.profileId != profileId) {
        return;
      }

      if (result != null) {
        _message(
          'Report saved to the selected destination.',
        );
      }
    } catch (error) {
      if (mounted &&
          widget.profileId == profileId) {
        _message(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted &&
          widget.profileId == profileId) {
        setState(() {
          _isOpening = false;
        });
      }
    }
  }

  // ==========================================================
  // OPEN OCR SHEET
  // ==========================================================

  Future<void> _openOcr(
      ChildHealthReport report,
      ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ReportTextSheet(
          api: _api,
          report: report,
        );
      },
    );
  }

  // ==========================================================
  // SCREEN
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealthReportsColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: HealthReportsColors.navy,
        elevation: 0,
        title: const Text(
          'Health Reports',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh reports',
            onPressed: _busy
                ? null
                : () => _refreshReports(),
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading && _reports.isEmpty
            ? const Center(
          child: CircularProgressIndicator(
            color: HealthReportsColors.green,
          ),
        )
            : RefreshIndicator(
          onRefresh: () async {
            await _refreshReports();
          },
          child: ListView(
            physics:
            const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              16, 20, 16, 45,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1120,
                  ),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      _breadcrumb(),
                      const SizedBox(height: 18),
                      _hero(),
                      const SizedBox(height: 17),
                      _notice(
                        'Health Reports and Medical History '
                            'use the same saved documents. '
                            'Upload once, then access the original '
                            'file and any completed OCR result.',
                        HealthReportsColors.lightBlue,
                        HealthReportsColors.blue,
                      ),
                      const SizedBox(height: 20),
                      if (_loadingError != null)
                        _errorState()
                      else ...[
                        _summary(),
                        const SizedBox(height: 20),
                        _uploadSection(),
                        const SizedBox(height: 20),
                        _reportsSection(),
                        const SizedBox(height: 20),
                        _privacyNotice(),
                      ],
                      const SizedBox(height: 24),
                      const Center(
                        child: Text(
                          'FamilyCare+ • Your family. '
                              'Your care.',
                          style: TextStyle(
                            color:
                            HealthReportsColors.muted,
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
  // BREADCRUMB
  // ==========================================================

  Widget _breadcrumb() {
    return const Row(
      children: [
        Text(
          'Child Care',
          style: TextStyle(
            color: HealthReportsColors.muted,
            fontSize: 12,
          ),
        ),
        SizedBox(width: 6),
        Icon(
          Icons.chevron_right_rounded,
          size: 17,
          color: HealthReportsColors.muted,
        ),
        SizedBox(width: 6),
        Text(
          'Health Reports',
          style: TextStyle(
            color: HealthReportsColors.green,
            fontSize: 12,
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
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const Text(
                  'IMPORTANT RECORDS. ALWAYS TOGETHER.',
                  style: TextStyle(
                    color: HealthReportsColors.green,
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Health Reports',
                  style: TextStyle(
                    color: HealthReportsColors.navy,
                    fontFamily: 'serif',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Keep $_displayChildName\'s medical '
                      'documents organized in one place.',
                  style: const TextStyle(
                    color: HealthReportsColors.muted,
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
            backgroundColor: Color(0xFFE0EDE5),
            child: Icon(
              Icons.folder_copy_outlined,
              color: HealthReportsColors.green,
              size: 35,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SUMMARY
  // ==========================================================

  Widget _summary() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 11.0;

        final columns =
        constraints.maxWidth >= 720 ? 3 : 2;

        final width =
            (constraints.maxWidth -
                gap * (columns - 1)) /
                columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _statCard(
              width,
              'Total Reports',
              _totalReports,
              Icons.folder_copy_outlined,
              HealthReportsColors.green,
            ),
            _statCard(
              width,
              'PDFs Loaded',
              _loadedPdfCount,
              Icons.picture_as_pdf_outlined,
              HealthReportsColors.red,
            ),
            _statCard(
              width,
              'Images Loaded',
              _loadedImageCount,
              Icons.image_outlined,
              HealthReportsColors.blue,
            ),
          ],
        );
      },
    );
  }

  Widget _statCard(
      double width,
      String title,
      int count,
      IconData icon,
      Color color,
      ) {
    return Container(
      width: width,
      constraints:
      const BoxConstraints(minHeight: 125),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: HealthReportsColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            '$count',
            style: const TextStyle(
              color: HealthReportsColors.navy,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              color: HealthReportsColors.muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // UPLOAD PANEL
  // ==========================================================

  Widget _uploadSection() {
    return _card(
      Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                color: HealthReportsColors.green,
                size: 26,
              ),
              SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Upload Medical Report',
                  style: TextStyle(
                    color: HealthReportsColors.navy,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          const Text(
            'Upload laboratory results, prescriptions, '
                'scans or other health documents.',
            style: TextStyle(
              color: HealthReportsColors.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 17),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            decoration: BoxDecoration(
              color: HealthReportsColors.cream,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: HealthReportsColors.border,
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.upload_file_outlined,
                  size: 43,
                  color: HealthReportsColors.green,
                ),
                const SizedBox(height: 13),
                const Text(
                  'Choose a medical report',
                  style: TextStyle(
                    color: HealthReportsColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'PDF • JPG • JPEG • PNG • WebP\n'
                      'Maximum size: 10 MB',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: HealthReportsColors.muted,
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : _uploadReport,
                  icon: _isUploading
                      ? const SizedBox(
                    height: 18,
                    width: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(
                    Icons.add_rounded,
                  ),
                  label: Text(
                    _isUploading
                        ? 'Uploading...'
                        : 'Choose & Upload',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                    HealthReportsColors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 50),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'The original filename is retained by the server. '
                'You will select a saved report category before upload. '
                'Custom titles and report dates cannot be saved until '
                'dedicated metadata APIs are available. OCR reads '
                'the saved file without re-uploading it.',
            style: TextStyle(
              color: HealthReportsColors.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // REPORTS LIST
  // ==========================================================

  Widget _reportsSection() {
    final reports = _filteredReports;

    return _card(
      Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'Saved Health Reports',
            style: TextStyle(
              color: HealthReportsColors.navy,
              fontFamily: 'serif',
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'View originals or read extracted '
                'medical text in English.',
            style: TextStyle(
              color: HealthReportsColors.muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search report by name...',
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: HealthReportsColors.green,
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
              filled: true,
              fillColor: HealthReportsColors.cream,
              border: OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(13),
              ),
            ),
          ),
          const SizedBox(height: 15),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(
                  'All Reports',
                  HealthReportFilter.all,
                ),
                _filterChip(
                  'PDF',
                  HealthReportFilter.pdf,
                ),
                _filterChip(
                  'Images',
                  HealthReportFilter.images,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _reportCategoryChip('All Categories', null),
                for (final category in _healthReportCategories)
                  _reportCategoryChip(category, category),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Text(
            'Showing ${reports.length} matching '
                'loaded reports • $_totalReports total',
            style: const TextStyle(
              color: HealthReportsColors.muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 17),
          if (reports.isEmpty)
            _emptyState()
          else
            for (final report in reports) ...[
              _reportCard(report),
              const SizedBox(height: 11),
            ],
          if (_reports.length < _totalReports) ...[
            const SizedBox(height: 13),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoadingMore
                    ? null
                    : _loadMoreReports,
                icon: _isLoadingMore
                    ? const SizedBox(
                  height: 17,
                  width: 17,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(
                  Icons.expand_more_rounded,
                ),
                label: Text(
                  _isLoadingMore
                      ? 'Loading...'
                      : 'Load More Reports',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Search and filters currently apply '
                  'to loaded reports. Load more to '
                  'include additional documents.',
              style: TextStyle(
                color: HealthReportsColors.muted,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // FILTER CHIP
  // ==========================================================

  Widget _filterChip(
      String title,
      HealthReportFilter filter,
      ) {
    final selected = _filter == filter;

    return Padding(
      padding:
      const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(title),
        selected: selected,
        showCheckmark: false,
        selectedColor: HealthReportsColors.blue,
        labelStyle: TextStyle(
          color: selected
              ? Colors.white
              : HealthReportsColors.text,
          fontSize: 11,
        ),
        onSelected: (_) {
          setState(() {
            _filter = filter;
          });
        },
      ),
    );
  }

  // ==========================================================
  // CATEGORY FILTER
  // ==========================================================

  Widget _reportCategoryChip(String label, String? category) {
    final selected = _categoryFilter == category;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: HealthReportsColors.green,
        labelStyle: TextStyle(
          fontSize: 11,
          color: selected ? Colors.white : HealthReportsColors.text,
        ),
        onSelected: (_) {
          setState(() => _categoryFilter = category);
        },
      ),
    );
  }

  // ==========================================================
  // REPORT CARD
  // ==========================================================

  Widget _reportCard(
      ChildHealthReport report,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HealthReportsColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: HealthReportsColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: report.color.withValues(
                    alpha: 0.09,
                  ),
                  borderRadius:
                  BorderRadius.circular(12),
                ),
                child: Icon(
                  report.icon,
                  color: report.color,
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
                      report.name,
                      maxLines: 3,
                      overflow:
                      TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HealthReportsColors.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      HealthReportFormatter.date(
                        report.createdAt,
                      ),
                      style: const TextStyle(
                        color: HealthReportsColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tag(
                report.isPdf ? 'PDF' : 'Image',
                report.color,
              ),
              _tag(
                HealthReportFormatter.fileSize(
                  report.sizeBytes,
                ),
                HealthReportsColors.green,
              ),
              _tag(
                report.category,
                HealthReportsColors.purple,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            report.categoryReviewed
                ? 'Category reviewed and saved by account holder.'
                : 'Category has not been manually reviewed; '
                'OCR may automatically organize it.',
            style: const TextStyle(
              fontSize: 10,
              color: HealthReportsColors.muted,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Listed date is upload date, not the report event date.',
            style: const TextStyle(
              fontSize: 10,
              color: HealthReportsColors.muted,
            ),
          ),
          const Divider(height: 26),
          Wrap(
            spacing: 8,
            runSpacing: 3,
            children: [
              TextButton.icon(
                onPressed: _isOpening
                    ? null
                    : () => _openReport(report),
                icon: Icon(
                  report.isPdf
                      ? Icons.open_in_new_rounded
                      : Icons.visibility_outlined,
                  size: 17,
                ),
                label: Text(
                  report.isPdf
                      ? 'Open PDF'
                      : 'Preview',
                ),
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _editCategory(report),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 17,
                ),
                label: const Text('Edit Category'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _openOcr(report),
                icon: const Icon(
                  Icons.translate_rounded,
                  size: 17,
                ),
                label: const Text(
                  'Read in English',
                ),
              ),
              TextButton.icon(
                onPressed: _isOpening
                    ? null
                    : () => _saveReport(report),
                icon: const Icon(
                  Icons.download_rounded,
                  size: 17,
                ),
                label: const Text('Save'),
              ),
              const Tooltip(
                message:
                'Report deletion API is not available yet.',
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: HealthReportsColors.muted,
                  size: 19,
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

  Widget _emptyState() {
    final filtered =
        _filter != HealthReportFilter.all ||
            _categoryFilter != null ||
            _searchController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 35,
      ),
      width: double.infinity,
      decoration: BoxDecoration(
        color: HealthReportsColors.cream,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.folder_open_outlined,
            size: 47,
            color: HealthReportsColors.green,
          ),
          const SizedBox(height: 13),
          Text(
            filtered
                ? 'No matching reports'
                : 'No medical reports yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HealthReportsColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            filtered
                ? 'Try a different file type or search.'
                : 'Upload your child\'s first report.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HealthReportsColors.muted,
              fontSize: 12,
            ),
          ),
          if (!filtered) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : _uploadReport,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Upload First Report',
              ),
              style: FilledButton.styleFrom(
                backgroundColor:
                HealthReportsColors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // ERROR STATE
  // ==========================================================

  Widget _errorState() {
    return _card(
      Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: HealthReportsColors.orange,
            size: 45,
          ),
          const SizedBox(height: 12),
          const Text(
            'Unable to Load Reports',
            style: TextStyle(
              color: HealthReportsColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            _loadingError ?? 'Please retry.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HealthReportsColors.red,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 15),
          OutlinedButton.icon(
            onPressed: () => _refreshReports(),
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // PRIVACY NOTICE
  // ==========================================================

  Widget _privacyNotice() {
    return _notice(
      'Medical documents contain sensitive '
          'health information. Downloaded files '
          'are outside FamilyCare+ app protection. '
          'OCR and translation can misread dates, '
          'medicine names, doses and measurements. '
          'Always verify important information '
          'against the original document.',
      HealthReportsColors.lightGreen,
      HealthReportsColors.green,
    );
  }

  // ==========================================================
  // SHARED UI
  // ==========================================================

  Widget _card(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: HealthReportsColors.border,
        ),
      ),
      child: child,
    );
  }

  Widget _tag(
      String title,
      Color color,
      ) {
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
        title,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _notice(
      String message,
      Color background,
      Color color,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: HealthReportsColors.text,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// OCR AND ENGLISH TRANSLATION SHEET
// ============================================================

class _ReportTextSheet extends StatefulWidget {
  final _HealthReportsApi api;
  final ChildHealthReport report;

  const _ReportTextSheet({
    required this.api,
    required this.report,
  });

  @override
  State<_ReportTextSheet> createState() =>
      _ReportTextSheetState();
}

class _ReportTextSheetState
    extends State<_ReportTextSheet> {
  static const fallbackLanguages = <String, String>{
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

  Map<String, String> _languages =
  Map<String, String>.from(fallbackLanguages);

  Map<String, dynamic> _analysis = {};

  Timer? _pollTimer;

  bool _loading = true;
  bool _working = false;
  bool _pollInFlight = false;

  bool _configured = false;
  bool _optionsLoaded = false;

  bool _translate = true;
  bool _consent = false;
  bool _showEnglish = true;

  String _sourceLanguage = 'en';

  String? _error;

  // ==========================================================
  // STATUS AND RESULT
  // ==========================================================

  String get _status {
    return (_analysis['status'] ??
        'NOT_REQUESTED')
        .toString()
        .toUpperCase();
  }

  bool get _isProcessing {
    return _status == 'QUEUED' ||
        _status == 'PROCESSING';
  }

  Map<String, dynamic> get _result {
    final result = _analysis['result'];

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    return {};
  }

  String get _originalText {
    return (_result['original_text'] ?? '').toString();
  }

  String get _englishText {
    return (_result['english_text'] ?? '').toString();
  }

  String get _displayedText {
    if (_showEnglish && _englishText.trim().isNotEmpty) {
      return _englishText;
    }
    return _originalText;
  }

  String get _analysisError {
    final error = _analysis['error'];

    if (error is Map) {
      return (error['message'] ?? '').toString();
    }

    return '';
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
    _stopPolling();

    super.dispose();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ==========================================================
  // ERROR HELPERS
  // ==========================================================

  String _friendlyError(Object error) {
    if (error is HealthReportsApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'OCR request timed out.';
    }

    if (error is http.ClientException) {
      return 'Cannot connect to the server.';
    }

    return 'Unable to process this report.';
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: HealthReportsColors.navy,
        content: Text(message),
      ),
    );
  }

  // ==========================================================
  // LOAD OPTIONS + SAVED RESULT
  // ==========================================================

  Future<void> _initialize() async {
    try {
      final options = await widget.api.ocrOptions();

      final rawLanguages = options['languages'];

      if (rawLanguages is List) {
        final parsed = <String, String>{};

        for (final item in rawLanguages) {
          if (item is! Map) continue;

          final code = item['code'];
          final name = item['name'];

          if (code is String && name is String) {
            parsed[code] = name;
          }
        }

        if (parsed.isNotEmpty) {
          _languages = parsed;
        }
      }

      _configured = options['configured'] == true;
      _optionsLoaded = true;
    } catch (_) {
      _optionsLoaded = false;
      _configured = false;
    }

    try {
      final analysis = await widget.api.getOcr(
        widget.report.id,
      );

      if (!mounted) return;

      _analysis = analysis;

      final previous = analysis['options'];

      if (previous is Map) {
        final code =
        previous['source_language'];

        if (code is String &&
            _languages.containsKey(code)) {
          _sourceLanguage = code;
        }

        _translate =
            previous['translate_to_english'] == true;
      }
    } catch (error) {
      _error = _friendlyError(error);
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    if (_isProcessing) {
      _startPolling();
    }
  }

  // ==========================================================
  // RELOAD ANALYSIS
  // ==========================================================

  Future<void> _reloadAnalysis({
    bool showError = true,
  }) async {
    try {
      final analysis = await widget.api.getOcr(
        widget.report.id,
      );

      if (!mounted) return;

      setState(() {
        _analysis = analysis;

        if (showError) {
          _error = null;
        }
      });

      if (!_isProcessing) {
        _stopPolling();
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = _friendlyError(error);
      });

      _stopPolling();
    }
  }

  // ==========================================================
  // POLL OCR STATUS
  // ==========================================================

  void _startPolling() {
    _stopPolling();

    if (!_isProcessing) return;

    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
          (timer) async {
        if (!mounted || !_isProcessing) {
          timer.cancel();
          return;
        }

        if (_pollInFlight) {
          return;
        }

        _pollInFlight = true;

        try {
          await _reloadAnalysis(
            showError: false,
          );
        } finally {
          _pollInFlight = false;
        }

        if (!mounted || !_isProcessing) {
          timer.cancel();
        }
      },
    );
  }

  // ==========================================================
  // START EXTRACTION
  // ==========================================================

  Future<void> _startOcr() async {
    if (_working ||
        _isProcessing ||
        !_configured) {
      return;
    }

    final wantsTranslation =
        _sourceLanguage != 'en' &&
            _translate;

    if (wantsTranslation && !_consent) {
      _showMessage(
        'Please give consent before sending '
            'extracted text to MyMemory.',
      );
      return;
    }

    _stopPolling();

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final result = await widget.api.requestOcr(
        reportId: widget.report.id,
        sourceLanguage: _sourceLanguage,
        translate: wantsTranslation,
        consent: wantsTranslation && _consent,
      );

      if (!mounted) return;

      setState(() {
        _analysis = result;
        _showEnglish = true;
      });

      if (_isProcessing) {
        _startPolling();
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  // ==========================================================
  // COPY TEXT
  // ==========================================================

  Future<void> _copyText() async {
    final text = _displayedText;

    if (text.trim().isEmpty) {
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: text),
    );

    _showMessage(
      'Text copied. Verify important medical '
          'details against the original report.',
    );
  }

  // ==========================================================
  // STATUS COLOR
  // ==========================================================

  Color get _statusColor {
    switch (_status) {
      case 'COMPLETED':
        return HealthReportsColors.green;

      case 'PARTIAL':
        return HealthReportsColors.orange;

      case 'FAILED':
        return HealthReportsColors.red;

      case 'PROCESSING':
      case 'QUEUED':
        return HealthReportsColors.blue;

      default:
        return HealthReportsColors.muted;
    }
  }

  // ==========================================================
  // SHEET UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom:
        MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight:
          MediaQuery.sizeOf(context).height * 0.92,
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
              20, 23, 20, 30,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 680,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    _header(),
                    const SizedBox(height: 18),
                    _notice(
                      'English is the default reading view. '
                          'The original document is never '
                          'modified or replaced.',
                      HealthReportsColors.lightBlue,
                      HealthReportsColors.blue,
                    ),
                    const SizedBox(height: 20),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(30),
                          child:
                          CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      _settings(),
                      const SizedBox(height: 17),
                      _statusSection(),
                      const SizedBox(height: 18),
                      _textSection(),
                      const SizedBox(height: 18),
                      _warningsSection(),
                    ],
                    const SizedBox(height: 15),
                    const Text(
                      'This tool extracts and translates '
                          'text only. It does not interpret '
                          'medical results or provide a diagnosis.',
                      style: TextStyle(
                        color: HealthReportsColors.muted,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // HEADER
  // ==========================================================

  Widget _header() {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.translate_rounded,
          color: HealthReportsColors.green,
          size: 28,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              const Text(
                'Read Medical Report',
                style: TextStyle(
                  color: HealthReportsColors.navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.report.name,
                style: const TextStyle(
                  color: HealthReportsColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: () =>
              Navigator.of(context).pop(),
          icon: const Icon(
            Icons.close_rounded,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // OCR SETTINGS
  // ==========================================================

  Widget _settings() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        const Text(
          'Document Language',
          style: TextStyle(
            color: HealthReportsColors.text,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 9),
        DropdownButtonFormField<String>(
          key: ValueKey(_sourceLanguage),
          initialValue:
          _languages.containsKey(_sourceLanguage)
              ? _sourceLanguage
              : _languages.keys.first,
          isExpanded: true,
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.language_rounded,
              color: HealthReportsColors.green,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          items: _languages.entries.map((entry) {
            return DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value),
            );
          }).toList(),
          onChanged: _working || _isProcessing
              ? null
              : (value) {
            if (value == null) return;

            setState(() {
              _sourceLanguage = value;
              _consent = false;
              _translate = value != 'en';
            });
          },
        ),
        const SizedBox(height: 11),
        const Text(
          'Choose the main printed language. '
              'Automatic language detection is not '
              'available in the current backend.',
          style: TextStyle(
            color: HealthReportsColors.muted,
            fontSize: 11,
            height: 1.5,
          ),
        ),
        if (_sourceLanguage != 'en') ...[
          const SizedBox(height: 13),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Translate into English',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              'Turn off to extract original text only.',
              style: TextStyle(fontSize: 11),
            ),
            value: _translate,
            activeThumbColor:
            HealthReportsColors.green,
            onChanged: _working || _isProcessing
                ? null
                : (value) {
              setState(() {
                _translate = value;
                _consent = false;
              });
            },
          ),
        ],
        if (_sourceLanguage != 'en' &&
            _translate) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity:
            ListTileControlAffinity.leading,
            value: _consent,
            title: const Text(
              'I consent to external translation',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            subtitle: const Text(
              'The extracted medical text will '
                  'be sent to MyMemory to translate '
                  'into English. Accuracy and privacy '
                  'are subject to that external service.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
              ),
            ),
            onChanged: _working || _isProcessing
                ? null
                : (value) {
              setState(() {
                _consent = value ?? false;
              });
            },
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: !_configured ||
                _working ||
                _isProcessing
                ? null
                : _startOcr,
            style: FilledButton.styleFrom(
              backgroundColor: HealthReportsColors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 52),
            ),
            icon: _working
                ? const SizedBox(
              height: 17,
              width: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(
              Icons.document_scanner_outlined,
            ),
            label: Text(
              _working
                  ? 'Starting Processing...'
                  : _sourceLanguage == 'en'
                  ? 'Extract English Text'
                  : _translate
                  ? 'Extract & Translate'
                  : 'Extract Original Text',
            ),
          ),
        ),
        if (!_configured) ...[
          const SizedBox(height: 10),
          Text(
            _optionsLoaded
                ? 'OCR processor is not configured on '
                'this server. Existing completed '
                'results can still be viewed.'
                : 'Unable to check OCR configuration. '
                'New extraction is currently disabled.',
            style: const TextStyle(
              color: HealthReportsColors.orange,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 9),
        const Text(
          'PDF OCR supports up to 5 pages. '
              'For longer documents, split the PDF.',
          style: TextStyle(
            color: HealthReportsColors.muted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // STATUS
  // ==========================================================

  Widget _statusSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HealthReportsColors.cream,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: HealthReportsColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _status == 'COMPLETED'
                    ? Icons.check_circle_outline
                    : _status == 'FAILED'
                    ? Icons.error_outline
                    : Icons.pending_outlined,
                color: _statusColor,
                size: 21,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'OCR Status: $_status',
                  style: TextStyle(
                    color: _statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh OCR Status',
                onPressed: _working
                    ? null
                    : () => _reloadAnalysis(),
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 20,
                ),
              ),
            ],
          ),
          if (_isProcessing) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
            const SizedBox(height: 9),
            const Text(
              'Document is being processed. '
                  'This panel checks the server '
                  'every few seconds.',
              style: TextStyle(
                color: HealthReportsColors.muted,
                fontSize: 11,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                color: HealthReportsColors.red,
                fontSize: 11,
              ),
            ),
          ],
          if (_analysisError.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _analysisError,
              style: const TextStyle(
                color: HealthReportsColors.red,
                fontSize: 11,
              ),
            ),
          ],
          if (_status == 'PARTIAL') ...[
            const SizedBox(height: 8),
            const Text(
              'Text extraction partially succeeded. '
                  'English translation may have failed. '
                  'Original extracted text is shown below.',
              style: TextStyle(
                color: HealthReportsColors.orange,
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
  // EXTRACTED TEXT
  // ==========================================================

  Widget _textSection() {
    final hasText =
        _originalText.trim().isNotEmpty ||
            _englishText.trim().isNotEmpty;

    if (!hasText) {
      return _notice(
        _isProcessing
            ? 'Extraction in progress. '
            'Text will appear when available.'
            : _status == 'NOT_REQUESTED'
            ? 'No OCR result exists for this report. '
            'Select the document language and '
            'start extraction.'
            : 'No readable text is available. '
            'Try a clearer document or review '
            'any processing warnings.',
        HealthReportsColors.lightBlue,
        HealthReportsColors.blue,
      );
    }

    final translated = _englishText.isNotEmpty;

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        const Text(
          'Extracted Report Text',
          style: TextStyle(
            color: HealthReportsColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 13),
        if (translated)
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: true,
                label: Text('English'),
              ),
              ButtonSegment<bool>(
                value: false,
                label: Text('Original'),
              ),
            ],
            selected: {_showEnglish},
            onSelectionChanged: (selection) {
              setState(() {
                _showEnglish = selection.first;
              });
            },
          )
        else
          const Text(
            'Original extracted text only. '
                'English translation is not available.',
            style: TextStyle(
              color: HealthReportsColors.orange,
              fontSize: 11,
            ),
          ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(
            minHeight: 125,
          ),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: HealthReportsColors.cream,
            borderRadius:
            BorderRadius.circular(13),
            border: Border.all(
              color: HealthReportsColors.border,
            ),
          ),
          child: SelectableText(
            translated
                ? _displayedText.trim().isEmpty
                ? 'No text available in this view.'
                : _displayedText
                : _originalText,
            style: const TextStyle(
              color: HealthReportsColors.text,
              fontSize: 12,
              height: 1.65,
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: (translated
              ? _displayedText
              : _originalText)
              .trim()
              .isEmpty
              ? null
              : () async {
            final text = translated
                ? _displayedText
                : _originalText;

            await Clipboard.setData(
              ClipboardData(text: text),
            );

            _showMessage(
              'Extracted text copied.',
            );
          },
          icon: const Icon(
            Icons.copy_outlined,
          ),
          label: const Text('Copy Text'),
        ),
        if (_result['translation_status'] != null) ...[
          const SizedBox(height: 9),
          Text(
            'Translation status: '
                '${_result['translation_status']}',
            style: const TextStyle(
              color: HealthReportsColors.muted,
              fontSize: 10,
            ),
          ),
        ],
        if (_result['page_count'] != null)
          Text(
            'Pages processed: ${_result['page_count']}',
            style: const TextStyle(
              color: HealthReportsColors.muted,
              fontSize: 10,
            ),
          ),
      ],
    );
  }

  // ==========================================================
  // WARNINGS
  // ==========================================================

  Widget _warningsSection() {
    final warnings = _result['warnings'];

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        if (warnings is List && warnings.isNotEmpty) ...[
          const Text(
            'Processing Warnings',
            style: TextStyle(
              color: HealthReportsColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 9),
          for (final warning in warnings)
            Padding(
              padding:
              const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: HealthReportsColors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warning.toString(),
                      style: const TextStyle(
                        color: HealthReportsColors.text,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        _notice(
          'Machine extraction and translation '
              'may misread medicine names, measurements, '
              'dosages, dates and medical terminology. '
              'Always compare with the original report.',
          HealthReportsColors.lightOrange,
          HealthReportsColors.orange,
        ),
      ],
    );
  }

  // ==========================================================
  // NOTICE
  // ==========================================================

  Widget _notice(
      String text,
      Color background,
      Color color,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: HealthReportsColors.text,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
