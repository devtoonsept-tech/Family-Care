
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/login_screen.dart';

class DoctorReportsScreen extends StatefulWidget {
  const DoctorReportsScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.initialProfile,
    this.initialChild,
    this.onBack,
  });

  final String apiBaseUrl;
  final Map<String, dynamic>? initialProfile;
  final Map<String, dynamic>? initialChild;
  final VoidCallback? onBack;

  @override
  State<DoctorReportsScreen> createState() =>
      _DoctorReportsScreenState();
}

class _ReportTheme {
  static const ink = Color(0xFF264A51);
  static const green = Color(0xFF367D69);
  static const blue = Color(0xFF477F99);
  static const mint = Color(0xFFE8F7EF);
  static const ice = Color(0xFFECF5FA);
  static const page = Color(0xFFF6FAF9);
  static const line = Color(0xFFDCEAE7);
  static const muted = Color(0xFF70848A);
  static const danger = Color(0xFFAE555B);
}

class _ReportException implements Exception {
  const _ReportException(this.message, [this.status]);

  final String message;
  final int? status;

  @override
  String toString() => message;
}

class _DoctorReportsScreenState
    extends State<DoctorReportsScreen> {
  static const _limit = 25;
  static const _maxBytes = 15 * 1024 * 1024;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  final _client = http.Client();
  final _profileSearch = TextEditingController();
  final _reportSearch = TextEditingController();

  bool _verifying = true;
  bool _authorized = false;
  bool _loadingProfiles = false;
  bool _loadingMoreProfiles = false;
  bool _openingProfile = false;
  bool _loadingReports = false;
  bool _loadingMoreReports = false;

  String _doctorId = '';
  String _module = 'all';
  String _format = 'all';

  String? _authError;
  String? _profilesError;
  String? _reportsError;
  String? _openingReportId;

  Map<String, dynamic>? _selected;
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _reports = [];

  int _profilePage = 0;
  int _profileTotal = 0;
  int _reportPage = 0;
  int _reportTotal = 0;

  int _authVersion = 0;
  int _profilesVersion = 0;
  int _selectionVersion = 0;
  int _reportsVersion = 0;

  static String _str(dynamic value) =>
      (value ?? '').toString().trim();

  static Map<String, dynamic> _object(dynamic value) =>
      value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(dynamic value) =>
      value is List
          ? value
          .whereType<Map>()
          .map(
            (item) => Map<String, dynamic>.from(item),
      )
          .toList()
          : <Map<String, dynamic>>[];

  static int _integer(dynamic value, int fallback) =>
      value is num
          ? value.toInt()
          : int.tryParse(_str(value)) ?? fallback;

  static String _id(Map<String, dynamic>? object) =>
      _str(object?['id']);

  String get _selectedId => _id(_selected);

  bool get _busy =>
      _loadingProfiles ||
          _loadingMoreProfiles ||
          _openingProfile ||
          _loadingReports ||
          _loadingMoreReports ||
          _openingReportId != null;

  String get _doctorBase {
    var base = widget.apiBaseUrl.trim();

    if (base.isEmpty) {
      base = !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:5001'
          : 'http://127.0.0.1:5001';
    }

    base = base.replaceFirst(RegExp(r'/+$'), '');

    if (base.endsWith('/api/v1/doctors')) {
      return base;
    }

    if (base.endsWith('/api/v1')) {
      return '$base/doctors';
    }

    return '$base/api/v1/doctors';
  }

  @override
  void initState() {
    super.initState();

    _profileSearch.addListener(_onSearch);
    _reportSearch.addListener(_onSearch);

    _verify();
  }

  @override
  void didUpdateWidget(
      covariant DoctorReportsScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _verify();
      return;
    }

    final previous = _id(
      oldWidget.initialProfile ?? oldWidget.initialChild,
    );

    final current = _id(
      widget.initialProfile ?? widget.initialChild,
    );

    if (_authorized && previous != current) {
      if (current.isEmpty) {
        _backToProfiles();
      } else {
        _openProfile(current);
      }
    }
  }

  void _onSearch() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _authVersion++;
    _profilesVersion++;
    _selectionVersion++;
    _reportsVersion++;

    _profileSearch.removeListener(_onSearch);
    _reportSearch.removeListener(_onSearch);

    _profileSearch.dispose();
    _reportSearch.dispose();
    _client.close();

    super.dispose();
  }

  String _friendly(Object error) {
    if (error is _ReportException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'The request timed out. Please retry.';
    }

    if (error is http.ClientException) {
      return 'Cannot reach FamilyCare+. Check your API connection.';
    }

    if (error is FormatException) {
      return 'The server returned an invalid response.';
    }

    return 'Unable to complete this request. Please try again.';
  }

  void _notice(
      String message, {
        bool error = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error
              ? _ReportTheme.danger
              : _ReportTheme.ink,
        ),
      );
  }

  Future<Map<String, String>> _headers() async {
    final role = await FamilyCareSession.role();
    final token = await FamilyCareSession.accessToken();
    final expiry =
    await FamilyCareSession.accessTokenExpiresAt();

    if (_str(role).toUpperCase() != 'DOCTOR' ||
        token == null ||
        token.trim().isEmpty ||
        expiry == null ||
        !expiry.isAfter(DateTime.now().toUtc())) {
      throw const _ReportException(
        'Your doctor session expired. Please sign in again.',
        401,
      );
    }

    return {
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
    };
  }

  _ReportException _httpError(
      int status,
      Uint8List bytes,
      ) {
    Map<String, dynamic> body = {};

    try {
      body = _object(
        jsonDecode(utf8.decode(bytes)),
      );
    } catch (_) {}

    final problem = body['error'];

    final message = problem is Map
        ? _str(problem['message'])
        : _str(problem);

    if (message.isNotEmpty) {
      return _ReportException(message, status);
    }

    return _ReportException(
      switch (status) {
        401 => 'Doctor session expired. Please sign in again.',
        403 => 'Reports access was denied or revoked.',
        404 => 'This report or profile is no longer available.',
        429 => 'Too many requests. Please retry shortly.',
        _ => 'Request failed (HTTP $status).',
      },
      status,
    );
  }

  Future<Map<String, dynamic>> _getJson(
      String path, {
        Map<String, String>? query,
      }) async {
    final uri = Uri.parse(
      '$_doctorBase$path',
    ).replace(queryParameters: query);

    final response = await _client
        .get(
      uri,
      headers: await _headers(),
    )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw _httpError(
        response.statusCode,
        response.bodyBytes,
      );
    }

    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes),
    );

    if (decoded is! Map) {
      throw const FormatException(
        'Expected JSON object.',
      );
    }

    return Map<String, dynamic>.from(decoded);
  }

  bool _canSeeReports(
      Map<String, dynamic> profile,
      ) {
    final module =
    _str(profile['module']).toLowerCase();

    if (module == 'child') return true;

    if (module != 'adult' || _doctorId.isEmpty) {
      return false;
    }

    final grant = _object(
      profile['access_permissions'],
    );

    if (grant['active'] != true ||
        _str(grant['doctor_id']) != _doctorId) {
      return false;
    }

    final scopes = grant['scopes'];

    if (scopes is! List ||
        !scopes.contains('reports')) {
      return false;
    }

    final expiryText = _str(grant['expires_at']);

    if (expiryText.isNotEmpty) {
      final expiry = DateTime.tryParse(expiryText);

      if (expiry == null ||
          !expiry.toUtc().isAfter(
            DateTime.now().toUtc(),
          )) {
        return false;
      }
    }

    return true;
  }

  bool _canSeeReportId(
      Map<String, dynamic> profile,
      String reportId,
      ) {
    if (!_canSeeReports(profile)) {
      return false;
    }

    if (_str(profile['module']).toLowerCase() ==
        'child') {
      return true;
    }

    final reportIds = _object(
      profile['access_permissions'],
    )['report_ids'];

    return reportIds == null ||
        (reportIds is List &&
            reportIds.contains(reportId));
  }

  Future<void> _verify() async {
    final version = ++_authVersion;

    _profilesVersion++;
    _selectionVersion++;
    _reportsVersion++;

    setState(() {
      _verifying = true;
      _authorized = false;
      _doctorId = '';

      _authError = null;
      _profilesError = null;
      _reportsError = null;

      _selected = null;
      _profiles = [];
      _reports = [];

      _profilePage = 0;
      _profileTotal = 0;
      _reportPage = 0;
      _reportTotal = 0;

      _loadingProfiles = false;
      _loadingMoreProfiles = false;
      _openingProfile = false;
      _loadingReports = false;
      _loadingMoreReports = false;
      _openingReportId = null;
    });

    try {
      final data = await _getJson('/me');
      final user = _object(data['user']);

      if (_str(user['role']).toUpperCase() != 'DOCTOR' ||
          _str(user['approval_status']).toUpperCase() !=
              'APPROVED' ||
          _str(user['account_status']).toUpperCase() !=
              'ACTIVE' ||
          _str(user['id']).isEmpty) {
        throw const _ReportException(
          'Only approved, active doctors can access reports.',
          403,
        );
      }

      if (!mounted || version != _authVersion) {
        return;
      }

      setState(() {
        _doctorId = _str(user['id']);
        _authorized = true;
        _verifying = false;
      });

      final initialId = _id(
        widget.initialProfile ?? widget.initialChild,
      );

      if (initialId.isEmpty) {
        await _loadProfiles(reset: true);
      } else {
        await _openProfile(initialId);
      }
    } catch (error) {
      if (!mounted || version != _authVersion) {
        return;
      }

      setState(() {
        _verifying = false;
        _authorized = false;
        _authError = _friendly(error);
      });
    }
  }

  Future<void> _loadProfiles({
    required bool reset,
  }) async {
    if (!_authorized ||
        _loadingProfiles ||
        _loadingMoreProfiles) {
      return;
    }

    final version = ++_profilesVersion;
    final module = _module;
    final page = reset ? 1 : _profilePage + 1;

    setState(() {
      _loadingProfiles = reset;
      _loadingMoreProfiles = !reset;
      _profilesError = null;
    });

    try {
      final data = await _getJson(
        '/care-profiles',
        query: {
          'page': '$page',
          'per_page': '$_limit',
          if (module != 'all') 'module': module,
        },
      );

      if (data['items'] is! List) {
        throw const FormatException(
          'Invalid profiles list.',
        );
      }

      final incoming = _list(
        data['items'],
      ).where(_canSeeReports).toList();

      if (!mounted ||
          version != _profilesVersion ||
          module != _module) {
        return;
      }

      setState(() {
        final seen = <String>{};

        _profiles = [
          if (!reset) ..._profiles,
          ...incoming,
        ]
            .where(
              (item) =>
          _id(item).isNotEmpty &&
              seen.add(_id(item)),
        )
            .toList();

        _profilePage = page;
        _profileTotal = _integer(
          data['total'],
          page * _limit,
        );
      });
    } catch (error) {
      if (mounted && version == _profilesVersion) {
        setState(() {
          _profilesError = _friendly(error);
        });
      }
    } finally {
      if (mounted && version == _profilesVersion) {
        setState(() {
          _loadingProfiles = false;
          _loadingMoreProfiles = false;
        });
      }
    }
  }

  void _changeModule(String module) {
    if (!_authorized || _module == module) {
      return;
    }

    _profilesVersion++;

    setState(() {
      _module = module;
      _profiles = [];
      _profilePage = 0;
      _profileTotal = 0;
      _profilesError = null;
      _loadingProfiles = false;
      _loadingMoreProfiles = false;

      _profileSearch.clear();
    });

    _loadProfiles(reset: true);
  }

  Future<void> _openProfile(String id) async {
    if (!_authorized ||
        id.isEmpty ||
        _openingProfile) {
      return;
    }

    final version = ++_selectionVersion;
    _reportsVersion++;

    setState(() {
      _openingProfile = true;
      _profilesError = null;
      _reportsError = null;

      _selected = null;
      _reports = [];

      _reportPage = 0;
      _reportTotal = 0;
      _loadingReports = false;
      _loadingMoreReports = false;
    });

    try {
      final data = await _getJson(
        '/care-profiles/${Uri.encodeComponent(id)}',
      );

      final profile = _object(data['profile']);

      if (_id(profile) != id ||
          !_canSeeReports(profile)) {
        throw const _ReportException(
          'Report access is missing or expired.',
          403,
        );
      }

      if (!mounted ||
          version != _selectionVersion) {
        return;
      }

      setState(() {
        _selected = profile;
        _openingProfile = false;
        _format = 'all';
        _reportSearch.clear();
      });

      await _loadReports(reset: true);
    } catch (error) {
      if (!mounted ||
          version != _selectionVersion) {
        return;
      }

      setState(() {
        _selected = null;
        _reports = [];
        _profilesError = _friendly(error);
      });

      _notice(_friendly(error), error: true);

      if (_profiles.isEmpty) {
        await _loadProfiles(reset: true);
      }
    } finally {
      if (mounted &&
          version == _selectionVersion) {
        setState(() {
          _openingProfile = false;
        });
      }
    }
  }

  Future<void> _loadReports({
    required bool reset,
  }) async {
    if (!_authorized ||
        _selected == null ||
        _loadingReports ||
        _loadingMoreReports) {
      return;
    }

    final id = _selectedId;

    if (!_canSeeReports(_selected!)) {
      _backToProfiles();

      _notice(
        'Report permission has expired.',
        error: true,
      );
      return;
    }

    final version = ++_reportsVersion;
    final page = reset ? 1 : _reportPage + 1;

    setState(() {
      _loadingReports = reset;
      _loadingMoreReports = !reset;
      _reportsError = null;

      if (reset) {
        _reports = [];
        _reportPage = 0;
      }
    });

    try {
      final data = await _getJson(
        '/care-profiles/${Uri.encodeComponent(id)}/reports',
        query: {
          'page': '$page',
          'per_page': '$_limit',
        },
      );

      if (data['items'] is! List) {
        throw const FormatException(
          'Invalid report list.',
        );
      }

      if (!mounted ||
          version != _reportsVersion ||
          _selectedId != id) {
        return;
      }

      if (!_canSeeReports(_selected!)) {
        _backToProfiles();

        _notice(
          'Report permission has expired.',
          error: true,
        );
        return;
      }

      final incoming = _list(data['items'])
          .where(
            (item) =>
        _id(item).isNotEmpty &&
            _canSeeReportId(
              _selected!,
              _id(item),
            ),
      )
          .toList();

      setState(() {
        final seen = <String>{};

        _reports = [
          if (!reset) ..._reports,
          ...incoming,
        ]
            .where(
              (item) => seen.add(_id(item)),
        )
            .toList();

        _reportPage = page;
        _reportTotal = _integer(
          data['total'],
          page * _limit,
        );
      });
    } catch (error) {
      if (!mounted ||
          version != _reportsVersion) {
        return;
      }

      if (error is _ReportException &&
          const {401, 403, 404}.contains(error.status)) {
        if (error.status == 401) {
          _authVersion++;

          setState(() {
            _authorized = false;
            _authError = _friendly(error);
            _profiles = [];
            _reports = [];
            _selected = null;
          });
        } else {
          _backToProfiles();
          _notice(
            _friendly(error),
            error: true,
          );
        }

        return;
      }

      setState(() {
        _reportsError = _friendly(error);
      });
    } finally {
      if (mounted &&
          version == _reportsVersion) {
        setState(() {
          _loadingReports = false;
          _loadingMoreReports = false;
        });
      }
    }
  }

  // Backend v8: title is the descriptive report name.
  String _name(Map<String, dynamic> report) {
    for (final key in [
      'title',
      'name',
      'original_filename',
      'file_name',
    ]) {
      final value = _str(report[key]);

      if (value.isNotEmpty) {
        return value;
      }
    }

    return 'Medical report';
  }

  String _filename(Map<String, dynamic> report) {
    for (final key in [
      'name',
      'original_filename',
      'file_name',
    ]) {
      final value = _str(report[key]);

      if (value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }

  String _fileType(Map<String, dynamic> report) {
    final mime = _str(
      report['content_type'],
    ).toLowerCase();

    final resource = _str(
      report['resource_type'],
    ).toLowerCase();

    if (mime.startsWith('application/pdf')) {
      return 'pdf';
    }

    if (mime.startsWith('image/') ||
        resource == 'image') {
      return 'image';
    }

    final filename = _filename(
      report,
    ).toLowerCase();

    if (filename.endsWith('.pdf')) {
      return 'pdf';
    }

    if ([
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
    ].any(filename.endsWith)) {
      return 'image';
    }

    return 'other';
  }

  String _sizeLabel(dynamic value) {
    final bytes = _integer(value, 0);

    if (bytes <= 0) return '';

    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _dateLabel(Map<String, dynamic> report) {
    final value = _str(report['created_at']).isNotEmpty
        ? _str(report['created_at'])
        : _str(report['uploaded_at']);

    final date =
    DateTime.tryParse(value)?.toLocal();

    if (date == null) return '';

    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  Uri _cloudinaryUri(
      Map<String, dynamic> data,
      ) {
    final raw = _str(
      _object(data['report'])['url'],
    );

    final uri = Uri.tryParse(raw);

    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.toLowerCase() !=
            'res.cloudinary.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443)) {
      throw const _ReportException(
        'Invalid or unsafe temporary report URL.',
      );
    }

    return uri;
  }

  Future<Uint8List> _readBytes(
      http.StreamedResponse response,
      ) async {
    if (response.contentLength != null &&
        response.contentLength! > _maxBytes) {
      throw const _ReportException(
        'This report exceeds the 15 MB preview limit.',
      );
    }

    final buffer = BytesBuilder(copy: false);
    var length = 0;

    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 35),
    )) {
      length += chunk.length;

      if (length > _maxBytes) {
        throw const _ReportException(
          'This report exceeds the 15 MB preview limit.',
        );
      }

      buffer.add(chunk);
    }

    return buffer.takeBytes();
  }

  bool _isPdf(Uint8List data) =>
      data.length >= 5 &&
          data[0] == 37 &&
          data[1] == 80 &&
          data[2] == 68 &&
          data[3] == 70 &&
          data[4] == 45;

  bool _isImage(Uint8List data) =>
      (data.length >= 8 &&
          data[0] == 137 &&
          data[1] == 80 &&
          data[2] == 78 &&
          data[3] == 71) ||
          (data.length >= 3 &&
              data[0] == 255 &&
              data[1] == 216 &&
              data[2] == 255) ||
          (data.length >= 12 &&
              String.fromCharCodes(
                data.sublist(0, 4),
              ) ==
                  'RIFF' &&
              String.fromCharCodes(
                data.sublist(8, 12),
              ) ==
                  'WEBP');

  Future<void> _downloadAndDisplay(
      Map<String, dynamic> report,
      String profileId,
      ) async {
    final reportId = _id(report);

    final uri = Uri.parse(
      '$_doctorBase/care-profiles/'
          '${Uri.encodeComponent(profileId)}/reports/'
          '${Uri.encodeComponent(reportId)}/download',
    );

    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll(await _headers())
      ..headers['Cache-Control'] = 'no-store';

    final response = await _client
        .send(request)
        .timeout(
      const Duration(seconds: 30),
    );

    final data = await _readBytes(response);

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw _httpError(
        response.statusCode,
        data,
      );
    }

    if (!mounted || _selectedId != profileId) {
      return;
    }

    final mime = _str(
      response.headers['content-type'],
    ).toLowerCase();

    if (mime.contains('application/json')) {
      final decoded = jsonDecode(
        utf8.decode(data),
      );

      if (decoded is! Map) {
        throw const FormatException(
          'Invalid signed-link response.',
        );
      }

      final link = _cloudinaryUri(
        Map<String, dynamic>.from(decoded),
      );

      if (_fileType(report) == 'image') {
        await _showImage(
          _name(report),
          url: link.toString(),
        );
      } else {
        final opened = await launchUrl(
          link,
          mode: kIsWeb
              ? LaunchMode.platformDefault
              : LaunchMode.externalApplication,
        );

        if (!opened) {
          throw const _ReportException(
            'No application could open this report.',
          );
        }
      }
    } else if (_isPdf(data)) {
      await _showPdf(
        _name(report),
        data,
      );
    } else if (_isImage(data)) {
      await _showImage(
        _name(report),
        bytes: data,
      );
    } else {
      throw const _ReportException(
        'Only PDF and image reports can be opened.',
      );
    }
  }

  Future<void> _openReport(
      Map<String, dynamic> report,
      ) async {
    final profileId = _selectedId;
    final reportId = _id(report);

    if (!_authorized ||
        _selected == null ||
        profileId.isEmpty ||
        reportId.isEmpty ||
        _openingReportId != null) {
      return;
    }

    setState(() {
      _openingReportId = reportId;
    });

    try {
      final data = await _getJson(
        '/care-profiles/${Uri.encodeComponent(profileId)}',
      );

      final fresh = _object(data['profile']);

      if (_id(fresh) != profileId ||
          !_canSeeReportId(fresh, reportId)) {
        throw const _ReportException(
          'This report is no longer shared with your account.',
          403,
        );
      }

      if (!mounted || _selectedId != profileId) {
        return;
      }

      await _downloadAndDisplay(
        report,
        profileId,
      );
    } catch (error) {
      if (!mounted) return;

      if (error is _ReportException &&
          const {401, 403, 404}.contains(error.status)) {
        if (error.status == 401) {
          _authVersion++;

          setState(() {
            _authorized = false;
            _authError = _friendly(error);
            _selected = null;
            _profiles = [];
            _reports = [];
          });
        } else {
          _backToProfiles();
        }
      }

      _notice(
        _friendly(error),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingReportId = null;
        });
      }
    }
  }

  Future<void> _showImage(
      String title, {
        Uint8List? bytes,
        String? url,
      }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 820,
            maxHeight: 800,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  15,
                  7,
                  5,
                  5,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                      },
                      icon: const Icon(
                        Icons.close,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SizedBox(
                  width: double.infinity,
                  height: 570,
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: bytes != null
                        ? Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (
                          context,
                          error,
                          stackTrace,
                          ) =>
                      const Center(
                        child: Text(
                          'Unable to display image.',
                        ),
                      ),
                    )
                        : Image.network(
                      url!,
                      fit: BoxFit.contain,
                      errorBuilder: (
                          context,
                          error,
                          stackTrace,
                          ) =>
                      const Center(
                        child: Text(
                          'Unable to load the image link.',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (url != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      final opened = await launchUrl(
                        Uri.parse(url),
                        mode: kIsWeb
                            ? LaunchMode.platformDefault
                            : LaunchMode.externalApplication,
                      );

                      if (!opened) {
                        _notice(
                          'Unable to open the image.',
                          error: true,
                        );
                      }
                    },
                    icon: const Icon(
                      Icons.open_in_new,
                    ),
                    label: const Text(
                      'Open externally',
                    ),
                  ),
                ),
              const SizedBox(height: 7),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPdf(
      String name,
      Uint8List bytes,
      ) async {
    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: _ReportTheme.page,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: _ReportTheme.ink,
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: PdfPreview(
            build: (format) async => bytes,
            allowPrinting: false,
            allowSharing: false,
            canChangeOrientation: false,
            canChangePageFormat: false,
            pdfFileName: name,
          ),
        ),
      ),
    );
  }

  void _backToProfiles() {
    _selectionVersion++;
    _reportsVersion++;

    setState(() {
      _selected = null;
      _reports = [];
      _reportPage = 0;
      _reportTotal = 0;
      _reportsError = null;
      _openingProfile = false;
      _loadingReports = false;
      _loadingMoreReports = false;
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
    if (!_authorized || _busy) return;

    if (_selected == null) {
      await _loadProfiles(reset: true);
    } else {
      await _openProfile(_selectedId);
    }
  }

  List<Map<String, dynamic>> get _visibleProfiles {
    final q = _profileSearch.text.trim().toLowerCase();

    return _profiles.where((item) {
      return q.isEmpty ||
          [
            _str(item['full_name']),
            _str(item['module']),
            _str(item['guardian_name']),
          ].any(
                (value) => value.toLowerCase().contains(q),
          );
    }).toList();
  }

  List<Map<String, dynamic>> get _visibleReports {
    final q = _reportSearch.text.trim().toLowerCase();

    return _reports.where((item) {
      if (_format != 'all' &&
          _fileType(item) != _format) {
        return false;
      }

      return q.isEmpty ||
          [
            _name(item),
            _filename(item),
            _str(item['category']),
            _dateLabel(item),
          ].any(
                (value) => value.toLowerCase().contains(q),
          );
    }).toList();
  }

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(
        color: _ReportTheme.line,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _hero(
      String title,
      String subtitle,
      ) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              _ReportTheme.mint,
              _ReportTheme.ice,
            ],
          ),
          border: Border.all(
            color: _ReportTheme.line,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white70,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.folder_shared_outlined,
                color: _ReportTheme.green,
                size: 27,
              ),
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
                      color: _ReportTheme.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _ReportTheme.muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _searchBox(
      TextEditingController controller,
      String hint,
      ) =>
      TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: _ReportTheme.green,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
            onPressed: controller.clear,
            icon: const Icon(Icons.close),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: _ReportTheme.line,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: _ReportTheme.green,
              width: 1.4,
            ),
          ),
        ),
      );

  Widget _chip(
      String title,
      bool selected,
      VoidCallback onTap,
      ) =>
      ChoiceChip(
        label: Text(title),
        selected: selected,
        selectedColor: _ReportTheme.mint,
        backgroundColor: Colors.white,
        side: const BorderSide(
          color: _ReportTheme.line,
        ),
        labelStyle: TextStyle(
          color: selected
              ? _ReportTheme.green
              : _ReportTheme.muted,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        onSelected: (value) => onTap(),
      );

  Widget _errorCard(
      String message,
      VoidCallback retry,
      ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: _panel(
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: _ReportTheme.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: _ReportTheme.danger,
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

  Widget _empty(
      String title,
      String message,
      ) =>
      _panel(
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 29,
            horizontal: 9,
          ),
          child: Column(
            children: [
              const Icon(
                Icons.folder_open_outlined,
                color: _ReportTheme.blue,
                size: 38,
              ),
              const SizedBox(height: 11),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ReportTheme.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ReportTheme.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _profileTile(Map<String, dynamic> item) {
    final child =
        _str(item['module']).toLowerCase() ==
            'child';

    final name = _str(item['full_name']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _openingProfile
              ? null
              : () => _openProfile(_id(item)),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              border: Border.all(
                color: _ReportTheme.line,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: child
                      ? _ReportTheme.mint
                      : _ReportTheme.ice,
                  child: Icon(
                    child
                        ? Icons.child_care_outlined
                        : Icons.monitor_heart_outlined,
                    color: child
                        ? _ReportTheme.green
                        : _ReportTheme.blue,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty
                            ? 'Care profile'
                            : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ReportTheme.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        child
                            ? 'Child • Shared reports'
                            : 'Adult • Authorized reports',
                        style: const TextStyle(
                          color: _ReportTheme.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _ReportTheme.green,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profilesView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _hero(
        'Medical Reports',
        'Open authorized files with descriptive titles and original filenames.',
      ),
      const SizedBox(height: 13),
      _panel(
        const Text(
          'Child reports are available through connected care. '
              'Adult reports require an active reports grant. '
              'Women’s Health uses a separate secure workspace.',
          style: TextStyle(
            color: _ReportTheme.muted,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ),
      const SizedBox(height: 13),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          _chip(
            'All',
            _module == 'all',
                () => _changeModule('all'),
          ),
          _chip(
            'Child',
            _module == 'child',
                () => _changeModule('child'),
          ),
          _chip(
            'Adult',
            _module == 'adult',
                () => _changeModule('adult'),
          ),
        ],
      ),
      const SizedBox(height: 13),
      _searchBox(
        _profileSearch,
        'Search loaded care profiles',
      ),
      const SizedBox(height: 7),
      const Text(
        'Search filters loaded profiles only.',
        style: TextStyle(
          color: _ReportTheme.muted,
          fontSize: 11,
        ),
      ),
      const SizedBox(height: 13),
      if (_profilesError != null)
        _errorCard(
          _profilesError!,
              () => _loadProfiles(reset: true),
        ),
      if (_loadingProfiles || _openingProfile)
        const Padding(
          padding: EdgeInsets.all(33),
          child: Center(
            child: CircularProgressIndicator(
              color: _ReportTheme.green,
            ),
          ),
        )
      else if (_visibleProfiles.isEmpty)
        _empty(
          'No accessible patients',
          'Authorized profiles will appear here.',
        )
      else
        for (final item in _visibleProfiles)
          _profileTile(item),
      if (!_loadingProfiles &&
          _profilePage * _limit <
              _profileTotal) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _loadingMoreProfiles
              ? null
              : () => _loadProfiles(reset: false),
          icon: _loadingMoreProfiles
              ? const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          )
              : const Icon(
            Icons.expand_more,
          ),
          label: Text(
            _loadingMoreProfiles
                ? 'Loading...'
                : 'Load More Patients',
          ),
        ),
      ],
    ],
  );

  Widget _reportTile(
      Map<String, dynamic> report,
      ) {
    final type = _fileType(report);
    final date = _dateLabel(report);
    final category = _str(report['category']);
    final title = _name(report);
    final filename = _filename(report);
    final size = _sizeLabel(
      report['size_bytes'],
    );

    final hasSeparateFilename =
        filename.isNotEmpty &&
            filename != title;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _openingReportId == null
              ? () => _openReport(report)
              : null,
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              border: Border.all(
                color: _ReportTheme.line,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: type == 'pdf'
                      ? const Color(0xFFFBEDEC)
                      : _ReportTheme.ice,
                  child: Icon(
                    type == 'pdf'
                        ? Icons.picture_as_pdf_outlined
                        : type == 'image'
                        ? Icons.image_outlined
                        : Icons.insert_drive_file_outlined,
                    color: type == 'pdf'
                        ? _ReportTheme.danger
                        : _ReportTheme.blue,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ReportTheme.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (hasSeparateFilename) ...[
                        const SizedBox(height: 4),
                        Text(
                          filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ReportTheme.blue,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        [
                          type == 'pdf'
                              ? 'PDF'
                              : type == 'image'
                              ? 'Image'
                              : 'File',
                          if (category.isNotEmpty) category,
                          if (size.isNotEmpty) size,
                          if (date.isNotEmpty) date,
                        ].join(' • '),
                        style: const TextStyle(
                          color: _ReportTheme.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _openingReportId == _id(report)
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _ReportTheme.green,
                  ),
                )
                    : const Icon(
                  Icons.open_in_new_rounded,
                  color: _ReportTheme.green,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reportsView() {
    final name = _str(
      _selected?['full_name'],
    );

    final child =
        _str(_selected?['module']).toLowerCase() ==
            'child';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hero(
          name.isEmpty ? 'Medical Reports' : name,
          '${child ? 'Child' : 'Adult'} • Shared medical files',
        ),
        const SizedBox(height: 13),
        _panel(
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                color: _ReportTheme.blue,
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reports are read-only. Permissions are checked again '
                      'before opening each file. External PDF viewers may '
                      'temporarily cache or download a copy.',
                  style: TextStyle(
                    color: _ReportTheme.muted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Shared Reports',
                style: TextStyle(
                  color: _ReportTheme.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '$_reportTotal total',
              style: const TextStyle(
                color: _ReportTheme.muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _searchBox(
          _reportSearch,
          'Search loaded reports',
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in const [
                ('all', 'All'),
                ('pdf', 'PDF'),
                ('image', 'Images'),
                ('other', 'Other'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: _chip(
                    entry.$2,
                    _format == entry.$1,
                        () => setState(() {
                      _format = entry.$1;
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Search matches loaded titles, filenames, categories and dates only.',
          style: TextStyle(
            color: _ReportTheme.muted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 13),
        if (_reportsError != null)
          _errorCard(
            _reportsError!,
                () => _loadReports(reset: true),
          ),
        if (_loadingReports)
          const Padding(
            padding: EdgeInsets.all(34),
            child: Center(
              child: CircularProgressIndicator(
                color: _ReportTheme.green,
              ),
            ),
          )
        else if (_visibleReports.isEmpty)
          _empty(
            'No matching reports',
            'No reports match your filters or permissions.',
          )
        else
          for (final report in _visibleReports)
            _reportTile(report),
        if (!_loadingReports &&
            _reportPage * _limit <
                _reportTotal) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loadingMoreReports
                ? null
                : () => _loadReports(reset: false),
            icon: _loadingMoreReports
                ? const SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
                : const Icon(
              Icons.expand_more,
            ),
            label: Text(
              _loadingMoreReports
                  ? 'Loading...'
                  : 'Load More Reports',
            ),
          ),
        ],
      ],
    );
  }

  Widget _blocked() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_person_outlined,
            size: 49,
            color: _ReportTheme.blue,
          ),
          const SizedBox(height: 12),
          const Text(
            'Approved Doctor Required',
            style: TextStyle(
              color: _ReportTheme.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _authError ??
                'Sign in with an approved and active doctor account.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ReportTheme.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 15),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _ReportTheme.green,
            ),
            onPressed: _verify,
            icon: const Icon(
              Icons.refresh,
            ),
            label: const Text(
              'Retry Verification',
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _ReportTheme.page,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _ReportTheme.ink,
      elevation: 0,
      leading: IconButton(
        onPressed: _back,
        icon: const Icon(
          Icons.arrow_back_rounded,
        ),
      ),
      title: Text(
        _selected == null
            ? 'Doctor Reports'
            : 'Medical Reports',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _authorized && !_busy
              ? _refresh
              : null,
          icon: const Icon(
            Icons.refresh_rounded,
          ),
        ),
      ],
    ),
    body: _verifying
        ? const Center(
      child: CircularProgressIndicator(
        color: _ReportTheme.green,
      ),
    )
        : !_authorized
        ? _blocked()
        : RefreshIndicator(
      color: _ReportTheme.green,
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
                  : _reportsView(),
            ),
          ),
        ],
      ),
    ),
  );
}
