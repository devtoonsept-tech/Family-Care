
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';
import 'doctor_patients_screen.dart';
import 'doctor_child_care_screen.dart';
import 'doctor_vaccination_screen.dart';
import 'doctor_consultation_screen.dart';
import 'doctor_appointments_screen.dart';
import 'doctor_clinical_records_screen.dart';
import 'doctor_prescriptions_screen.dart';
import 'doctor_reports_screen.dart';
import 'doctor_settings_screen.dart';
import 'doctor_notification_preferences.dart';

class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({
    super.key,
    this.doctorName = '',
    this.email = '',
    this.approvalStatus = 'UNKNOWN',
    this.doctorDetails,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.onOpenProfile,
    this.onOpenSection,
    this.onGoToLogin,
  });

  final String doctorName;
  final String email;
  final String approvalStatus;
  final Map<String, dynamic>? doctorDetails;
  final String apiBaseUrl;
  final VoidCallback? onOpenProfile;
  final ValueChanged<String>? onOpenSection;
  final VoidCallback? onGoToLogin;

  @override
  State<DoctorDashboardScreen> createState() =>
      _DoctorDashboardScreenState();
}

class _DashColors {
  static const navy = Color(0xFF153F45);
  static const ink = Color(0xFF214D52);
  static const green = Color(0xFF267C6D);
  static const teal = Color(0xFF128B89);
  static const blue = Color(0xFF4B86B3);
  static const purple = Color(0xFF7972B9);
  static const coral = Color(0xFFE9947F);
  static const amber = Color(0xFFE5AB59);
  static const page = Color(0xFFF4FAF9);
  static const mint = Color(0xFFE9F7F1);
  static const sky = Color(0xFFECF5FB);
  static const border = Color(0xFFDDECE8);
  static const muted = Color(0xFF70888B);
  static const danger = Color(0xFFB85159);
}

class _DashApiException implements Exception {
  const _DashApiException(
      this.message, [
        this.status = 0,
      ]);

  final String message;
  final int status;

  @override
  String toString() => message;
}

class _DoctorModule {
  const _DoctorModule(
      this.id,
      this.title,
      this.subtitle,
      this.icon,
      this.color,
      );

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _DecorativePainter extends CustomPainter {
  const _DecorativePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..isAntiAlias = true
      ..color = color.withAlpha(18);

    canvas.drawCircle(
      Offset(size.width - 6, -4),
      47,
      paint,
    );

    paint.color = color.withAlpha(12);

    canvas.drawCircle(
      Offset(size.width - 38, 33),
      36,
      paint,
    );

    paint.color = color.withAlpha(37);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.5;

    canvas.drawArc(
      Rect.fromLTWH(
        size.width - 70,
        -17,
        64,
        64,
      ),
      0.2,
      math.pi * 0.9,
      false,
      paint,
    );

    paint.style = PaintingStyle.fill;
    paint.color = color.withAlpha(48);

    canvas.drawCircle(
      Offset(size.width - 17, 68),
      3,
      paint,
    );

    canvas.drawCircle(
      Offset(size.width - 77, 15),
      2,
      paint,
    );
  }

  @override
  bool shouldRepaint(
      covariant _DecorativePainter oldDelegate,
      ) =>
      oldDelegate.color != color;
}

class _DoctorDashboardScreenState
    extends State<DoctorDashboardScreen> {
  static const List<_DoctorModule> _modules = [
    _DoctorModule(
      'patients',
      'Patients',
      'Your care network',
      Icons.people_alt_outlined,
      _DashColors.green,
    ),
    _DoctorModule(
      'child-care',
      'Child Care',
      'Child health management',
      Icons.child_care_outlined,
      _DashColors.blue,
    ),
    _DoctorModule(
      'vaccination',
      'Vaccination',
      'Immunization records',
      Icons.vaccines_outlined,
      _DashColors.purple,
    ),
    _DoctorModule(
      'consultations',
      'Consultations',
      'Requests and visits',
      Icons.medical_services_outlined,
      _DashColors.teal,
    ),
    _DoctorModule(
      'appointments',
      'Appointments',
      'Manage your schedule',
      Icons.event_available_outlined,
      _DashColors.coral,
    ),
    _DoctorModule(
      'clinical-records',
      'Clinical Records',
      'Health records',
      Icons.assignment_outlined,
      _DashColors.blue,
    ),
    _DoctorModule(
      'prescriptions',
      'Prescriptions',
      'Medicines and instructions',
      Icons.medication_outlined,
      _DashColors.purple,
    ),
    _DoctorModule(
      'reports',
      'Reports',
      'Medical documents',
      Icons.folder_shared_outlined,
      _DashColors.green,
    ),
    _DoctorModule(
      'referrals',
      'Referrals',
      'Care coordination',
      Icons.hub_outlined,
      _DashColors.teal,
    ),
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey =
  GlobalKey<ScaffoldState>();

  final http.Client _client = http.Client();

  Timer? _notificationTimer;

  late String _approval;
  late String _name;
  late String _email;
  late Map<String, dynamic> _doctor;

  String _referralId = '';
  String _photoUrl = '';
  String _notificationToken = '';

  String? _rejectionReason;
  String? _error;
  String? _notificationError;

  bool _verifying = false;
  bool _verified = false;
  bool _needsLogin = false;
  bool _checkingApproval = false;
  bool _loadingOverview = false;
  bool _loadingUnread = false;
  bool _openingSection = false;
  bool _loggingOut = false;

  int? _patientCount;
  int? _childCount;
  int? _pendingCount;
  int? _upcomingCount;
  int? _slotCount;
  int? _todayCount;
  int? _unreadCount;

  bool _visitsAvailable = false;

  Map<String, dynamic>? _nextVisit;

  int _authRevision = 0;
  int _overviewRevision = 0;

  // ============================================================
  // HELPERS
  // ============================================================

  static String _text(dynamic value) =>
      (value ?? '').toString().trim();

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(
      dynamic value,
      ) =>
      value is List
          ? value
          .whereType<Map>()
          .map(
            (item) =>
        Map<String, dynamic>.from(item),
      )
          .toList()
          : <Map<String, dynamic>>[];

  static int? _number(dynamic value) =>
      value is num
          ? value.toInt()
          : int.tryParse(_text(value));

  String get _rootUrl {
    var url = widget.apiBaseUrl.trim();

    if (url.isEmpty) {
      url = !kIsWeb &&
          defaultTargetPlatform ==
              TargetPlatform.android
          ? 'http://10.0.2.2:5001'
          : 'http://127.0.0.1:5001';
    }

    url = url.replaceFirst(
      RegExp(r'/+$'),
      '',
    );

    for (final suffix in [
      '/api/v1/doctors',
      '/api/v1',
    ]) {
      if (url.endsWith(suffix)) {
        return url.substring(
          0,
          url.length - suffix.length,
        );
      }
    }

    return url;
  }

  bool get _approved =>
      _approval == 'APPROVED';

  bool get _ready =>
      _approved &&
          _verified &&
          !_needsLogin;

  bool get _busy =>
      _verifying ||
          _checkingApproval ||
          _openingSection ||
          _loggingOut;

  String get _displayName =>
      _name.isEmpty ? 'Doctor' : _name;

  String get _greeting {
    final clean = _displayName.replaceFirst(
      RegExp(
        r'^dr\.?\s+',
        caseSensitive: false,
      ),
      '',
    );

    return clean == 'Doctor'
        ? 'Hello, Doctor'
        : 'Hello, Dr. $clean';
  }

  String _extractPhoto(
      Map<String, dynamic> doctor,
      ) {
    final images = _map(
      doctor['images'],
    );

    final photo = _map(
      images['profile_photo'],
    );

    final direct = _map(
      doctor['photo'],
    );

    for (final value in [
      photo['url'],
      direct['url'],
      doctor['profile_photo_url'],
    ]) {
      if (_text(value).isNotEmpty) {
        return _text(value);
      }
    }

    return '';
  }

  bool _validPhotoUrl(String url) {
    final uri = Uri.tryParse(url);

    if (uri == null ||
        uri.scheme != 'https') {
      return false;
    }

    return const {
      'res.cloudinary.com',
      'api.cloudinary.com',
    }.contains(uri.host.toLowerCase());
  }

  // ============================================================
  // INITIALIZATION
  // ============================================================

  void _initialize() {
    _approval =
        widget.approvalStatus.trim().toUpperCase();

    _name = widget.doctorName.trim();
    _email = widget.email.trim();

    _doctor = Map<String, dynamic>.from(
      widget.doctorDetails ?? {},
    );

    _referralId = _text(
      _doctor['referral_id'],
    );

    _photoUrl = _extractPhoto(_doctor);
    _notificationToken = '';

    _rejectionReason = null;
    _error = null;
    _notificationError = null;

    _verified = false;
    _needsLogin = false;

    _patientCount = null;
    _childCount = null;
    _pendingCount = null;
    _upcomingCount = null;
    _slotCount = null;
    _todayCount = null;
    _unreadCount = null;

    _visitsAvailable = false;
    _nextVisit = null;
  }

  @override
  void initState() {
    super.initState();

    _initialize();

    DoctorNotificationPreferences.enabled.addListener(
      _onNotificationPreferenceChanged,
    );

    unawaited(
      DoctorNotificationPreferences.load(),
    );

    _notificationTimer = Timer.periodic(
      const Duration(seconds: 60),
          (timer) {
        if (!mounted ||
            !_ready ||
            _loadingOverview) {
          return;
        }

        if (!(ModalRoute.of(context)?.isCurrent ??
            true)) {
          return;
        }

        unawaited(_refreshUnreadCount());
      },
    );

    if (_approved) {
      _verifyDoctor();
    }
  }

  @override
  void didUpdateWidget(
      covariant DoctorDashboardScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.doctorName != widget.doctorName ||
        oldWidget.email != widget.email ||
        oldWidget.approvalStatus !=
            widget.approvalStatus ||
        oldWidget.doctorDetails !=
            widget.doctorDetails ||
        oldWidget.apiBaseUrl !=
            widget.apiBaseUrl) {
      _authRevision++;
      _overviewRevision++;

      _verifying = false;
      _loadingOverview = false;

      _initialize();

      unawaited(
        DoctorNotificationPreferences.load(),
      );

      if (_approved) {
        _verifyDoctor();
      }
    }
  }

  @override
  void dispose() {
    _authRevision++;
    _overviewRevision++;

    _notificationTimer?.cancel();

    DoctorNotificationPreferences.enabled.removeListener(
      _onNotificationPreferenceChanged,
    );

    _client.close();

    super.dispose();
  }

  void _onNotificationPreferenceChanged() {
    if (!mounted) return;

    if (!DoctorNotificationPreferences.isEnabled) {
      setState(() {
        _unreadCount = null;
        _notificationError = null;
      });
    } else {
      setState(() {});

      if (_ready) {
        unawaited(
          _refreshUnreadCount(),
        );
      }
    }
  }

  // ============================================================
  // ERROR HANDLING
  // ============================================================

  String _friendlyError(Object error) {
    if (error is _DashApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'Request timed out. Try again.';
    }

    if (error is http.ClientException) {
      return 'Cannot connect to FamilyCare+. Check the backend connection.';
    }

    if (error is FormatException) {
      return 'Invalid response from the server.';
    }

    return 'Unable to complete the request.';
  }

  void _showMessage(
      String message, {
        bool error = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error
              ? _DashColors.danger
              : _DashColors.navy,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // API
  // ============================================================

  Future<Map<String, dynamic>> _api(
      String method,
      String path, {
        Map<String, String>? query,
        String? notificationToken,
        Map<String, dynamic>? payload,
      }) async {
    final role =
    await FamilyCareSession.role();

    final accessToken =
    await FamilyCareSession.accessToken();

    final expiresAt =
    await FamilyCareSession.accessTokenExpiresAt();

    if (_text(role).toUpperCase() != 'DOCTOR' ||
        accessToken == null ||
        accessToken.trim().isEmpty ||
        expiresAt == null ||
        !expiresAt.isAfter(
          DateTime.now().toUtc(),
        )) {
      throw const _DashApiException(
        'Doctor session expired. Sign in again.',
        401,
      );
    }

    final token =
        notificationToken ?? accessToken;

    final uri = Uri.parse(
      '$_rootUrl$path',
    ).replace(
      queryParameters: query,
    );

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
      if (payload != null)
        'Content-Type': 'application/json',
    };

    late final http.Response response;

    if (method == 'POST') {
      response = await _client
          .post(
        uri,
        headers: headers,
        body: jsonEncode(
          payload ?? {},
        ),
      )
          .timeout(
        const Duration(seconds: 30),
      );
    } else {
      response = await _client
          .get(
        uri,
        headers: headers,
      )
          .timeout(
        const Duration(seconds: 30),
      );
    }

    Map<String, dynamic> result = {};

    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(
          utf8.decode(response.bodyBytes),
        );

        if (decoded is Map) {
          result = Map<String, dynamic>.from(
            decoded,
          );
        } else if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          throw const FormatException(
            'Expected a JSON object.',
          );
        }
      } on FormatException {
        if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          rethrow;
        }
      }
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final issue = result['error'];

      final message = issue is Map
          ? _text(issue['message'])
          : _text(issue);

      final fallback = switch (response.statusCode) {
        401 => 'Session expired. Sign in again.',
        403 => 'Doctor access or permission denied.',
        404 => 'The requested resource was not found.',
        409 => 'The record changed. Refresh and try again.',
        429 => 'Too many requests. Try again later.',
        _ => 'Request failed (HTTP ${response.statusCode}).',
      };

      throw _DashApiException(
        message.isNotEmpty
            ? message
            : fallback,
        response.statusCode,
      );
    }

    return result;
  }

  // ============================================================
  // DOCTOR AUTHORIZATION
  // ============================================================

  Future<bool> _verifyDoctor({
    bool loadOverview = true,
  }) async {
    if (!_approved ||
        _loggingOut ||
        _needsLogin) {
      return false;
    }

    if (_verifying) {
      return _ready;
    }

    final revision = ++_authRevision;

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final response = await _api(
        'GET',
        '/api/v1/doctors/me',
      );

      final user = _map(
        response['user'],
      );

      if (_text(user['role']).toUpperCase() !=
          'DOCTOR' ||
          _text(user['approval_status'])
              .toUpperCase() !=
              'APPROVED' ||
          _text(user['account_status'])
              .toUpperCase() !=
              'ACTIVE') {
        throw const _DashApiException(
          'An approved, active doctor account is required.',
          403,
        );
      }

      if (!mounted ||
          revision != _authRevision) {
        return false;
      }

      final doctor = _map(
        user['doctor'],
      );

      setState(() {
        if (_text(user['full_name']).isNotEmpty) {
          _name = _text(
            user['full_name'],
          );
        }

        if (_text(user['email']).isNotEmpty) {
          _email = _text(
            user['email'],
          );
        }

        _doctor = doctor;

        _photoUrl = _extractPhoto(
          doctor,
        );

        _notificationToken = _text(
          response['notification_token'],
        );

        if (_text(doctor['referral_id']).isNotEmpty) {
          _referralId = _text(
            doctor['referral_id'],
          );
        }

        _approval = 'APPROVED';
        _verified = true;
        _needsLogin = false;
      });

      unawaited(
        _refreshProfilePhoto(revision),
      );

      if (loadOverview) {
        await _loadOverview();
      }

      return mounted &&
          revision == _authRevision &&
          _ready;
    } catch (error) {
      if (mounted &&
          revision == _authRevision) {
        _overviewRevision++;

        setState(() {
          _verified = false;
          _error = _friendlyError(error);

          if (error is _DashApiException &&
              error.status == 401) {
            _needsLogin = true;
          }

          _unreadCount = null;
          _notificationError =
              _friendlyError(error);
        });
      }

      return false;
    } finally {
      if (mounted &&
          revision == _authRevision) {
        setState(() {
          _verifying = false;
        });
      }
    }
  }

  // ============================================================
  // REAL DOCTOR PROFILE PHOTO
  // ============================================================

  Future<void> _refreshProfilePhoto(
      int revision,
      ) async {
    try {
      final response = await _api(
        'GET',
        '/api/v1/doctors/profile-photo',
      );

      if (!mounted ||
          revision != _authRevision ||
          !_ready) {
        return;
      }

      final photo = _map(
        response['photo'],
      );

      final url = _text(
        photo['url'],
      );

      if (url.isNotEmpty &&
          !_validPhotoUrl(url)) {
        return;
      }

      if (_photoUrl != url) {
        setState(() {
          _photoUrl = url;
        });
      }
    } catch (_) {
      // Keep the genuine URL from /doctors/me.
    }
  }

  Widget _photoPlaceholder({
    bool unavailable = false,
  }) =>
      Center(
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person_outline_rounded,
              size: 47,
              color: Color(0xFF296F69),
            ),
            const SizedBox(height: 8),
            Text(
              unavailable
                  ? 'Photo unavailable'
                  : 'No profile photo',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF296F69),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );

  Widget _doctorPhoto() {
    if (!_validPhotoUrl(_photoUrl)) {
      return _photoPlaceholder();
    }

    return Image.network(
      _photoUrl,
      key: ValueKey(_photoUrl),
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      loadingBuilder: (
          context,
          child,
          progress,
          ) {
        if (progress == null) {
          return child;
        }

        return const Center(
          child: SizedBox(
            width: 25,
            height: 25,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _DashColors.green,
            ),
          ),
        );
      },
      errorBuilder: (
          context,
          error,
          stackTrace,
          ) =>
          _photoPlaceholder(
            unavailable: true,
          ),
    );
  }

  // ============================================================
  // NOTIFICATION AUTHENTICATION
  // ============================================================

  Future<String> _notificationAuth({
    bool renew = false,
  }) async {
    if (!renew &&
        _notificationToken.isNotEmpty) {
      return _notificationToken;
    }

    final response = await _api(
      'GET',
      '/api/v1/doctors/me',
    );

    final user = _map(
      response['user'],
    );

    if (_text(user['role']).toUpperCase() !=
        'DOCTOR' ||
        _text(user['approval_status'])
            .toUpperCase() !=
            'APPROVED' ||
        _text(user['account_status'])
            .toUpperCase() !=
            'ACTIVE') {
      throw const _DashApiException(
        'Doctor account is no longer active.',
        403,
      );
    }

    final token = _text(
      response['notification_token'],
    );

    if (token.isEmpty) {
      throw const _DashApiException(
        'Notification token was not returned by the server.',
      );
    }

    _notificationToken = token;

    return token;
  }

  Future<Map<String, dynamic>> _inbox({
    int page = 1,
  }) async {
    var token = await _notificationAuth();

    try {
      return await _api(
        'GET',
        '/api/v1/doctors/notifications',
        notificationToken: token,
        query: {
          'page': '$page',
          'per_page': '25',
        },
      );
    } on _DashApiException catch (error) {
      if (error.status != 401) {
        rethrow;
      }

      token = await _notificationAuth(
        renew: true,
      );

      return _api(
        'GET',
        '/api/v1/doctors/notifications',
        notificationToken: token,
        query: {
          'page': '$page',
          'per_page': '25',
        },
      );
    }
  }

  Future<void> _markNotificationRead(
      String id,
      ) async {
    if (id.isEmpty) return;

    var token = await _notificationAuth();

    final path =
        '/api/v1/doctors/notifications/'
        '${Uri.encodeComponent(id)}/read';

    try {
      await _api(
        'POST',
        path,
        notificationToken: token,
        payload: const {},
      );
    } on _DashApiException catch (error) {
      if (error.status != 401) {
        rethrow;
      }

      token = await _notificationAuth(
        renew: true,
      );

      await _api(
        'POST',
        path,
        notificationToken: token,
        payload: const {},
      );
    }
  }

  Future<void> _refreshUnreadCount() async {
    if (!_ready ||
        !DoctorNotificationPreferences.isEnabled ||
        _loadingUnread ||
        _loggingOut) {
      return;
    }

    _loadingUnread = true;

    try {
      final response = await _inbox();

      final unread = _number(
        response['unread'],
      );

      if (unread == null) {
        throw const FormatException(
          'The doctor inbox did not return an unread count.',
        );
      }

      if (!mounted ||
          !_ready ||
          !DoctorNotificationPreferences.isEnabled) {
        return;
      }

      setState(() {
        _unreadCount = unread;
        _notificationError = null;
      });
    } catch (error) {
      if (mounted &&
          DoctorNotificationPreferences.isEnabled) {
        setState(() {
          _unreadCount = null;
          _notificationError =
              _friendlyError(error);
        });
      }
    } finally {
      _loadingUnread = false;
    }
  }

  // ============================================================
  // DASHBOARD COUNTS
  // ============================================================

  Future<void> _loadOverview() async {
    if (!_ready ||
        _loggingOut) {
      return;
    }

    final revision = ++_overviewRevision;

    setState(() {
      _loadingOverview = true;
    });

    Future<Map<String, dynamic>?> safeGet(
        String path, {
          Map<String, String>? query,
        }) async {
      try {
        return await _api(
          'GET',
          path,
          query: query,
        );
      } catch (_) {
        return null;
      }
    }

    String? notificationFailure;

    try {
      final results =
      await Future.wait<Map<String, dynamic>?>([
        safeGet(
          '/api/v1/doctors/referral',
        ),
        safeGet(
          '/api/v1/doctors/patients',
          query: {
            'page': '1',
            'per_page': '1',
          },
        ),
        safeGet(
          '/api/v1/doctors/care-profiles',
          query: {
            'module': 'child',
            'page': '1',
            'per_page': '1',
          },
        ),
        safeGet(
          '/api/v1/doctors/consultation-visits',
        ),
        safeGet(
          '/api/v1/doctors/appointment-slots',
        ),
        (() async {
          if (!DoctorNotificationPreferences.isEnabled) {
            return null;
          }

          try {
            return await _inbox();
          } catch (error) {
            notificationFailure =
                _friendlyError(error);
            return null;
          }
        })(),
      ]);

      if (!mounted ||
          revision != _overviewRevision ||
          !_ready) {
        return;
      }

      final referral = _map(
        results[0]?['doctor'],
      );

      final visitData =
      results[3]?['items'];

      final slotData =
      results[4]?['items'];

      final now = DateTime.now();

      var requested = 0;
      var upcoming = 0;
      var today = 0;

      Map<String, dynamic>? nextVisit;
      DateTime? nextDate;

      if (visitData is List) {
        for (final visit in _list(visitData)) {
          final status = _text(
            visit['status'],
          ).toUpperCase();

          if (status == 'REQUESTED') {
            requested++;
          }

          if (status != 'CONFIRMED') {
            continue;
          }

          final date = DateTime.tryParse(
            _text(
              visit['confirmed_at'],
            ),
          )?.toLocal();

          if (date == null ||
              !date.isAfter(now)) {
            continue;
          }

          upcoming++;

          if (date.year == now.year &&
              date.month == now.month &&
              date.day == now.day) {
            today++;
          }

          if (nextDate == null ||
              date.isBefore(nextDate)) {
            nextDate = date;
            nextVisit = visit;
          }
        }
      }

      setState(() {
        if (_text(referral['referral_id']).isNotEmpty) {
          _referralId = _text(
            referral['referral_id'],
          );
        }

        _patientCount = _number(
          results[1]?['total'],
        );

        _childCount = _number(
          results[2]?['total'],
        );

        _pendingCount = visitData is List
            ? requested
            : null;

        _upcomingCount = visitData is List
            ? upcoming
            : null;

        _todayCount = visitData is List
            ? today
            : null;

        _nextVisit = nextVisit;

        _visitsAvailable =
        visitData is List;

        _slotCount = slotData is List
            ? slotData.length
            : null;

        _unreadCount =
        DoctorNotificationPreferences.isEnabled
            ? _number(
          results[5]?['unread'],
        )
            : null;

        _notificationError =
            notificationFailure;
      });
    } finally {
      if (mounted &&
          revision == _overviewRevision) {
        setState(() {
          _loadingOverview = false;
        });
      }
    }
  }

  // ============================================================
  // APPROVAL CHECK
  // ============================================================

  Future<void> _checkApproval() async {
    if (_checkingApproval ||
        _loggingOut ||
        _email.isEmpty) {
      return;
    }

    String password = '';

    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Check doctor approval',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _email,
              style: const TextStyle(
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: (value) {
                password = value;
              },
              onSubmitted: (_) {
                Navigator.pop(
                  dialogContext,
                  password,
                );
              },
              decoration: const InputDecoration(
                labelText: 'Doctor password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
                password,
              );
            },
            child: const Text('Check'),
          ),
        ],
      ),
    );

    if (!mounted ||
        entered == null ||
        entered.isEmpty) {
      return;
    }

    final revision = _authRevision;

    setState(() {
      _checkingApproval = true;
    });

    try {
      final response = await _client
          .post(
        Uri.parse(
          '$_rootUrl/api/v1/doctors/approval-status',
        ),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': _email,
          'password': entered,
        }),
      )
          .timeout(
        const Duration(seconds: 25),
      );

      Map<String, dynamic> data = {};

      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(
          response.body,
        );

        if (decoded is Map) {
          data = Map<String, dynamic>.from(
            decoded,
          );
        }
      }

      if (response.statusCode != 200) {
        final error = _map(
          data['error'],
        );

        throw _DashApiException(
          _text(error['message']).isNotEmpty
              ? _text(error['message'])
              : 'Could not check approval status.',
        );
      }

      if (!mounted ||
          revision != _authRevision) {
        return;
      }

      final status = _text(
        data['approval_status'],
      ).toUpperCase();

      if (status.isEmpty) {
        throw const FormatException(
          'Missing approval status.',
        );
      }

      setState(() {
        _approval = status;
        _rejectionReason = _text(
          data['rejection_reason'],
        );

        _verified = false;
        _needsLogin =
            status == 'APPROVED';
      });

      _showMessage(
        status == 'APPROVED'
            ? 'Approved! Sign in again to open the clinical dashboard.'
            : 'Approval: ${_approvalLabel(status)}',
      );
    } catch (error) {
      _showMessage(
        _friendlyError(error),
        error: true,
      );
    } finally {
      if (mounted &&
          revision == _authRevision) {
        setState(() {
          _checkingApproval = false;
        });
      }
    }
  }

  String _approvalLabel(
      String status,
      ) =>
      switch (status) {
        'PROFILE_REQUIRED' => 'Profile required',
        'PENDING_APPROVAL' => 'Pending admin review',
        'REJECTED' => 'Changes requested',
        'APPROVED' => _ready
            ? 'Verified doctor'
            : 'Approved doctor',
        'SUSPENDED' => 'Restricted account',
        _ => 'Status unavailable',
      };

  // ============================================================
  // NAVIGATION
  // ============================================================

  void _openProfile() {
    if (widget.onOpenProfile != null) {
      widget.onOpenProfile!();
    } else {
      _showMessage(
        'Profile navigation is not connected.',
        error: true,
      );
    }
  }

  Future<void> _openSection(
      String section,
      ) async {
    if (_openingSection ||
        _loggingOut ||
        _verifying) {
      return;
    }

    setState(() {
      _openingSection = true;
    });

    try {
      final verified = await _verifyDoctor(
        loadOverview: false,
      );

      if (!verified ||
          !mounted) {
        _showMessage(
          _error ??
              'Approved doctor session required.',
          error: true,
        );

        return;
      }

      if (widget.onOpenSection != null &&
          !const {
            'patients',
            'child-care',
            'vaccination',
            'notifications',
          }.contains(section)) {
        widget.onOpenSection!(section);
        return;
      }

      Widget? screen;

      switch (section) {
        case 'patients':
          screen = DoctorPatientsScreen(
            apiBaseUrl: _rootUrl,
          );
          break;

        case 'child-care':
          screen = DoctorChildCareScreen(
            apiBaseUrl: _rootUrl,
          );
          break;

        case 'vaccination':
          screen = DoctorVaccinationScreen(
            apiBaseUrl: _rootUrl,
          );
          break;

        case 'consultations':
          screen = DoctorConsultationScreen(
            apiBaseUrl: _rootUrl,
          );
          break;

        case 'appointments':
          screen = DoctorAppointmentsScreen(
            apiBaseUrl: _rootUrl,
          );
          break;

        case 'clinical-records':
          screen = DoctorClinicalRecordsScreen(
            apiBaseUrl: _rootUrl,
          );
          break;

        case 'prescriptions':
          screen = DoctorPrescriptionsScreen(
            apiBaseUrl: _rootUrl,
          );
          break;

        case 'reports':
          screen = DoctorReportsScreen(
            apiBaseUrl: _rootUrl,
          );
          break;

        case 'settings':
          screen = DoctorSettingsScreen(
            apiBaseUrl: _rootUrl,
            onOpenProfile: _openProfile,
            onGoToLogin: widget.onGoToLogin,
          );
          break;

        case 'referrals':
          await _showReferrals();
          break;

        case 'notifications':
          await _showNotifications();
          break;

        default:
          throw const _DashApiException(
            'This section is not connected.',
          );
      }

      if (screen != null && mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => screen!,
          ),
        );
      }
    } catch (error) {
      _showMessage(
        _friendlyError(error),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingSection = false;
        });

        if (_ready) {
          unawaited(
            _loadOverview(),
          );
        }
      }
    }
  }

  // ============================================================
  // NOTIFICATION INBOX
  // ============================================================

  Future<void> _showNotifications() async {
    List<Map<String, dynamic>> notifications = [];

    int? unread;
    int page = 1;
    int total = 0;

    bool busy = false;
    bool started = false;

    String? error;
    String? marking;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _DashColors.page,
      builder: (sheetContext) {
        Future<void> reload(
            StateSetter update, {
              bool loadMore = false,
            }) async {
          if (busy) return;

          update(() {
            busy = true;
            error = null;
          });

          try {
            final result = await _inbox(
              page: loadMore ? page + 1 : 1,
            );

            if (!sheetContext.mounted) {
              return;
            }

            if (result['items'] is! List) {
              throw const FormatException(
                'Invalid notification list.',
              );
            }

            final count = _number(
              result['unread'],
            );

            if (count == null) {
              throw const FormatException(
                'Unread count missing from API response.',
              );
            }

            final loaded = _list(
              result['items'],
            );

            update(() {
              if (loadMore) {
                final ids = <String>{};

                notifications = [
                  ...notifications,
                  ...loaded,
                ].where((item) {
                  return ids.add(
                    _text(item['id']),
                  );
                }).toList();

                page++;
              } else {
                notifications = loaded;
                page = 1;
              }

              unread = count;

              total = _number(
                result['total'],
              ) ??
                  notifications.length;
            });

            if (mounted) {
              setState(() {
                if (DoctorNotificationPreferences
                    .isEnabled) {
                  _unreadCount = count;
                }

                _notificationError = null;
              });
            }
          } catch (exception) {
            if (sheetContext.mounted) {
              update(() {
                error =
                    _friendlyError(exception);
              });
            }

            if (mounted) {
              setState(() {
                _notificationError =
                    _friendlyError(exception);
              });
            }
          } finally {
            if (sheetContext.mounted) {
              update(() {
                busy = false;
              });
            }
          }
        }

        Future<void> markAsRead(
            StateSetter update,
            String id,
            ) async {
          if (id.isEmpty ||
              marking != null ||
              busy) {
            return;
          }

          update(() {
            marking = id;
          });

          try {
            await _markNotificationRead(id);

            if (!sheetContext.mounted) {
              return;
            }

            await reload(update);
          } catch (exception) {
            if (sheetContext.mounted) {
              update(() {
                error =
                    _friendlyError(exception);
              });
            }
          } finally {
            if (sheetContext.mounted) {
              update(() {
                marking = null;
              });
            }
          }
        }

        return StatefulBuilder(
          builder: (context, update) {
            if (!started) {
              started = true;

              WidgetsBinding.instance
                  .addPostFrameCallback((_) {
                if (sheetContext.mounted) {
                  reload(update);
                }
              });
            }

            return SizedBox(
              height: math.min(
                MediaQuery.sizeOf(sheetContext)
                    .height *
                    0.80,
                680.0,
              ),
              child: Column(
                children: [
                  Padding(
                    padding:
                    const EdgeInsets.fromLTRB(
                      18,
                      6,
                      12,
                      10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          color: _DashColors.teal,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Doctor Inbox',
                            style: TextStyle(
                              color: _DashColors.ink,
                              fontSize: 18,
                              fontWeight:
                              FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          unread == null
                              ? '— unread'
                              : '$unread unread',
                          style: const TextStyle(
                            color: _DashColors.green,
                            fontSize: 12,
                            fontWeight:
                            FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh notifications',
                          onPressed: busy
                              ? null
                              : () => reload(update),
                          icon: const Icon(
                            Icons.refresh,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 17,
                      ),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: _DashColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const Divider(
                    height: 1,
                    color: _DashColors.border,
                  ),
                  Expanded(
                    child: busy &&
                        notifications.isEmpty
                        ? const Center(
                      child:
                      CircularProgressIndicator(
                        color:
                        _DashColors.green,
                      ),
                    )
                        : notifications.isEmpty
                        ? const Center(
                      child: Text(
                        'No notifications to show.',
                        style: TextStyle(
                          color:
                          _DashColors.muted,
                        ),
                      ),
                    )
                        : ListView.builder(
                      padding:
                      const EdgeInsets.all(
                        14,
                      ),
                      itemCount:
                      notifications.length +
                          (notifications
                              .length <
                              total
                              ? 1
                              : 0),
                      itemBuilder:
                          (context, index) {
                        if (index ==
                            notifications.length) {
                          return OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => reload(
                              update,
                              loadMore:
                              true,
                            ),
                            icon: const Icon(
                              Icons.expand_more,
                            ),
                            label: const Text(
                              'Load Older',
                            ),
                          );
                        }

                        final item =
                        notifications[index];

                        final id = _text(
                          item['id'],
                        );

                        final isUnread =
                            item['read_at'] ==
                                null;

                        return Padding(
                          padding:
                          const EdgeInsets.only(
                            bottom: 9,
                          ),
                          child: Container(
                            padding:
                            const EdgeInsets.all(
                              13,
                            ),
                            decoration:
                            BoxDecoration(
                              color: isUnread
                                  ? _DashColors
                                  .mint
                                  : Colors.white,
                              border: Border.all(
                                color:
                                _DashColors
                                    .border,
                              ),
                              borderRadius:
                              BorderRadius.circular(
                                14,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isUnread
                                          ? Icons.mark_email_unread_outlined
                                          : Icons.mark_email_read_outlined,
                                      color: isUnread
                                          ? _DashColors.teal
                                          : _DashColors.muted,
                                    ),
                                    const SizedBox(
                                      width: 8,
                                    ),
                                    Expanded(
                                      child: Text(
                                        _text(item['title'])
                                            .isEmpty
                                            ? 'Doctor notification'
                                            : _text(item['title']),
                                        style:
                                        const TextStyle(
                                          color:
                                          _DashColors.ink,
                                          fontSize: 13,
                                          fontWeight:
                                          FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: 6,
                                ),
                                Text(
                                  _text(
                                    item['body'],
                                  ),
                                  style:
                                  const TextStyle(
                                    color:
                                    _DashColors.muted,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(
                                  height: 7,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _formatDate(
                                          item['created_at'],
                                        ),
                                        style:
                                        const TextStyle(
                                          color:
                                          _DashColors.muted,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    if (isUnread)
                                      TextButton(
                                        onPressed: marking != null ||
                                            busy ||
                                            id.isEmpty
                                            ? null
                                            : () => markAsRead(
                                          update,
                                          id,
                                        ),
                                        child: Text(
                                          marking == id
                                              ? 'Saving...'
                                              : 'Mark as Read',
                                          style:
                                          const TextStyle(
                                            fontSize: 11,
                                          ),
                                        ),
                                      )
                                    else
                                      const Text(
                                        'Read',
                                        style:
                                        TextStyle(
                                          color:
                                          _DashColors.green,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
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
      },
    );

    if (mounted && _ready) {
      await _loadOverview();
    }
  }

  // ============================================================
  // REFERRALS
  // ============================================================

  Future<void> _showReferrals() async {
    final response = await _api(
      'GET',
      '/api/v1/doctors/handoffs',
    );

    final referrals = _list(
      response['items'],
    );

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: _DashColors.page,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
          MediaQuery.sizeOf(sheetContext)
              .height *
              0.76,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            18,
            10,
            18,
            28,
          ),
          children: [
            const Text(
              'Doctor Referrals',
              style: TextStyle(
                color: _DashColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Recent referrals returned by the server.',
              style: TextStyle(
                color: _DashColors.muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            if (referrals.isEmpty)
              _surface(
                const Text(
                  'No referrals found.',
                ),
              ),
            for (final item in referrals.take(100))
              Padding(
                padding: const EdgeInsets.only(
                  bottom: 9,
                ),
                child: _surface(
                  Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(item['recipient_name'])
                            .isNotEmpty
                            ? _text(
                          item['recipient_name'],
                        )
                            : 'Referral',
                        style: const TextStyle(
                          color: _DashColors.ink,
                          fontSize: 13,
                          fontWeight:
                          FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Status: ${_text(item['status'])} • '
                            '${_text(item['direction'])}',
                        style: const TextStyle(
                          color: _DashColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> _logout() async {
    if (_loggingOut) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to access your doctor workspace.',
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
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true ||
        !mounted) {
      return;
    }

    setState(() {
      _loggingOut = true;
    });

    try {
      final token =
      await FamilyCareSession.accessToken();

      if (token != null &&
          token.isNotEmpty) {
        try {
          await _client
              .post(
            Uri.parse(
              '$_rootUrl/api/v1/auth/logout',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'X-Auth-Transport': 'bearer',
              'Accept': 'application/json',
            },
          )
              .timeout(
            const Duration(seconds: 12),
          );
        } catch (_) {
          // Local logout proceeds if the API is unavailable.
        }
      }

      await FamilyCareSession.clear();

      if (!mounted) return;

      _authRevision++;
      _overviewRevision++;

      if (widget.onGoToLogin != null) {
        widget.onGoToLogin!();
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => LoginScreen(
              apiBaseUrl: _rootUrl,
            ),
          ),
              (_) => false,
        );
      }
    } catch (_) {
      _showMessage(
        'Unable to clear the local session.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loggingOut = false;
        });
      }
    }
  }

  // ============================================================
  // COMMON UI
  // ============================================================

  Widget _surface(
      Widget child, {
        EdgeInsetsGeometry? padding,
      }) =>
      Container(
        width: double.infinity,
        padding: padding ??
            const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: _DashColors.border,
          ),
          borderRadius:
          BorderRadius.circular(16),
        ),
        child: child,
      );

  Widget _avatar({
    double radius = 24,
  }) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _DashColors.mint,
      child: ClipOval(
        child: _validPhotoUrl(_photoUrl)
            ? Image.network(
          _photoUrl,
          key: ValueKey(_photoUrl),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (
              context,
              error,
              stackTrace,
              ) =>
              Icon(
                Icons.person_outline,
                color: _DashColors.green,
                size: radius,
              ),
        )
            : Icon(
          Icons.person_outline,
          color: _DashColors.green,
          size: radius,
        ),
      ),
    );
  }

  void _drawerAction(
      VoidCallback callback,
      ) {
    Navigator.of(context).pop();

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (mounted) {
        callback();
      }
    });
  }

  Widget _drawerItem(
      IconData icon,
      String label,
      VoidCallback callback, {
        bool enabled = true,
      }) =>
      ListTile(
        enabled: enabled,
        contentPadding:
        const EdgeInsets.symmetric(
          horizontal: 16,
        ),
        leading: Icon(
          icon,
          size: 21,
          color: enabled
              ? _DashColors.green
              : _DashColors.muted,
        ),
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          size: 17,
        ),
        onTap: enabled
            ? () => _drawerAction(
          callback,
        )
            : null,
      );

  Widget _drawer() => Drawer(
    backgroundColor: _DashColors.page,
    child: SafeArea(
      child: Column(
        children: [
          Container(
            color: _DashColors.mint,
            padding: const EdgeInsets.all(19),
            child: Row(
              children: [
                _avatar(),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName,
                        maxLines: 1,
                        overflow:
                        TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _DashColors.ink,
                          fontSize: 15,
                          fontWeight:
                          FontWeight.w800,
                        ),
                      ),
                      Text(
                        _email,
                        maxLines: 1,
                        overflow:
                        TextOverflow.ellipsis,
                        style: const TextStyle(
                          color:
                          _DashColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                _drawerItem(
                  Icons.dashboard_outlined,
                  'Dashboard',
                      () {},
                ),
                _drawerItem(
                  Icons.person_outline,
                  'My Profile',
                  _openProfile,
                ),
                _drawerItem(
                  Icons.settings_outlined,
                  'Settings',
                      () => _openSection(
                    'settings',
                  ),
                  enabled: _ready,
                ),
                _drawerItem(
                  Icons.notifications_none,
                  'Notifications',
                      () => _openSection(
                    'notifications',
                  ),
                  enabled: _ready,
                ),
                const Divider(
                  color: _DashColors.border,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    17,
                    9,
                    10,
                    7,
                  ),
                  child: Text(
                    'CLINICAL WORKSPACE',
                    style: TextStyle(
                      color: _DashColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                for (final module in _modules)
                  _drawerItem(
                    module.icon,
                    module.title,
                        () => _openSection(
                      module.id,
                    ),
                    enabled: _ready,
                  ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            color: _DashColors.border,
          ),
          _drawerItem(
            Icons.logout_outlined,
            'Sign Out',
            _logout,
          ),
        ],
      ),
    ),
  );

  // ============================================================
  // NOTIFICATION BELL
  // ============================================================

  Widget _notificationBell() =>
      ValueListenableBuilder<bool>(
        valueListenable:
        DoctorNotificationPreferences.enabled,
        builder: (context, enabled, child) {
          final unread = enabled
              ? _unreadCount
              : null;

          return Semantics(
            label: enabled
                ? 'Doctor notifications'
                : 'Doctor notifications, indicators disabled',
            button: true,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Material(
                  color: const Color(0xF4FFFFFF),
                  borderRadius:
                  BorderRadius.circular(17),
                  elevation: 3,
                  child: InkWell(
                    borderRadius:
                    BorderRadius.circular(17),
                    onTap: _ready &&
                        !_openingSection
                        ? () => _openSection(
                      'notifications',
                    )
                        : null,
                    child: SizedBox(
                      width: 45,
                      height: 45,
                      child: Icon(
                        enabled
                            ? Icons.notifications_none_rounded
                            : Icons.notifications_off_outlined,
                        size: 25,
                        color: enabled
                            ? _DashColors.green
                            : _DashColors.muted,
                      ),
                    ),
                  ),
                ),
                if (enabled &&
                    unread != null &&
                    unread > 0)
                  Positioned(
                    right: -5,
                    top: -6,
                    child: Container(
                      constraints:
                      const BoxConstraints(
                        minWidth: 19,
                        minHeight: 19,
                      ),
                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                        _DashColors.danger,
                        borderRadius:
                        BorderRadius.circular(
                          11,
                        ),
                        border: Border.all(
                          color: Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        unread > 99
                            ? '99+'
                            : '$unread',
                        textAlign:
                        TextAlign.center,
                        style:
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight:
                          FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                if (enabled &&
                    _notificationError != null)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding:
                      const EdgeInsets.all(3),
                      decoration:
                      const BoxDecoration(
                        color:
                        _DashColors.amber,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.priority_high,
                        color: Colors.white,
                        size: 11,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );

  // ============================================================
  // WELCOME BANNER WITH REAL DOCTOR PHOTO
  // ============================================================

  Widget _hero() => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth < 420;

      final height =
      compact ? 187.0 : 205.0;

      final photoWidth =
      compact ? 122.0 : 200.0;

      final photoInset =
      compact ? 8.0 : 19.0;

      return ClipRRect(
        borderRadius:
        BorderRadius.circular(22),
        child: Container(
          height: height,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF156C6D),
                Color(0xFF2D9580),
                Color(0xFF66B5A4),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: -42,
                top: -57,
                child: Container(
                  width: 152,
                  height: 152,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                      const Color(0x24FFFFFF),
                      width: 20,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: photoInset,
                top: compact ? 12 : 13,
                bottom: 0,
                width: photoWidth,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius:
                    const BorderRadius.vertical(
                      top: Radius.circular(23),
                    ),
                    color: const Color(
                      0xFFE5F3EE,
                    ),
                    border: Border.all(
                      color:
                      const Color(0x66FFFFFF),
                      width: 1.3,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius:
                    const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    child: _doctorPhoto(),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 15 : 24,
                    18,
                    photoWidth +
                        photoInset +
                        (compact ? 7 : 24),
                    17,
                  ),
                  child: Column(
                    mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding:
                        const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration:
                        BoxDecoration(
                          color:
                          const Color(0x33FFFFFF),
                          borderRadius:
                          BorderRadius.circular(
                            30,
                          ),
                        ),
                        child: const Text(
                          'FAMILYCARE+ • DOCTOR',
                          maxLines: 1,
                          overflow:
                          TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight:
                            FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        _greeting,
                        maxLines: 3,
                        overflow:
                        TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize:
                          compact ? 18 : 26,
                          fontWeight:
                          FontWeight.w900,
                          height: 1.12,
                        ),
                      ),
                      Container(
                        padding:
                        const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        decoration:
                        BoxDecoration(
                          color:
                          const Color(0x33FFFFFF),
                          borderRadius:
                          BorderRadius.circular(
                            10,
                          ),
                        ),
                        child: Row(
                          mainAxisSize:
                          MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.link,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(
                              width: 5,
                            ),
                            Flexible(
                              child: Text(
                                _referralId.isEmpty
                                    ? 'Referral unavailable'
                                    : _referralId,
                                maxLines: 1,
                                overflow:
                                TextOverflow.ellipsis,
                                style:
                                const TextStyle(
                                  color:
                                  Colors.white,
                                  fontSize: 10,
                                  fontWeight:
                                  FontWeight.w700,
                                ),
                              ),
                            ),
                            if (_referralId.isNotEmpty)
                              InkWell(
                                onTap: () async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text:
                                      _referralId,
                                    ),
                                  );

                                  _showMessage(
                                    'Referral ID copied.',
                                  );
                                },
                                child: const Padding(
                                  padding:
                                  EdgeInsets.all(
                                    5,
                                  ),
                                  child: Icon(
                                    Icons.copy,
                                    color:
                                    Colors.white,
                                    size: 15,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: photoInset + 8,
                top: compact ? 17 : 19,
                child: _notificationBell(),
              ),
            ],
          ),
        ),
      );
    },
  );

  // ============================================================
  // APPROVAL STATUS CARD
  // ============================================================

  Widget _statusCard() {
    final active = _ready;

    final color = active
        ? _DashColors.green
        : _approval == 'REJECTED'
        ? _DashColors.danger
        : _DashColors.amber;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: active
            ? _DashColors.mint
            : const Color(0xFFFFF7E9),
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color: color.withAlpha(45),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active
                    ? Icons.verified_rounded
                    : Icons.info_outline,
                color: color,
                size: 19,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _approvalLabel(_approval),
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
              ),
              if (_verifying ||
                  _checkingApproval)
                const SizedBox(
                  width: 17,
                  height: 17,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    color:
                    _DashColors.green,
                  ),
                ),
            ],
          ),
          if (!active) ...[
            const SizedBox(height: 7),
            Text(
              _error ??
                  (_needsLogin
                      ? 'A fresh doctor login is required.'
                      : _approval ==
                      'PENDING_APPROVAL'
                      ? 'Your profile is under admin review.'
                      : 'Clinical access requires an approved doctor account.'),
              style: const TextStyle(
                color: _DashColors.muted,
                fontSize: 12,
              ),
            ),
            if (_rejectionReason != null &&
                _rejectionReason!.isNotEmpty)
              Padding(
                padding:
                const EdgeInsets.only(
                  top: 6,
                ),
                child: Text(
                  'Admin feedback: $_rejectionReason',
                  style: const TextStyle(
                    color:
                    _DashColors.danger,
                    fontSize: 11,
                  ),
                ),
              ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!_approved)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : _checkApproval,
                    icon: const Icon(
                      Icons.refresh,
                      size: 16,
                    ),
                    label: const Text(
                      'Check Status',
                    ),
                  ),
                if (!_approved)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : _openProfile,
                    icon: const Icon(
                      Icons.person_outline,
                      size: 16,
                    ),
                    label: const Text(
                      'My Profile',
                    ),
                  ),
                if (_approved && !active)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : _needsLogin
                        ? _logout
                        : () => _verifyDoctor(),
                    icon: const Icon(
                      Icons.verified_user_outlined,
                      size: 16,
                    ),
                    label: Text(
                      _needsLogin
                          ? 'Sign In Again'
                          : 'Verify Session',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // OVERVIEW UI
  // ============================================================

  Widget _sectionHeader(
      String title, {
        String? subtitle,
      }) =>
      Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _DashColors.ink,
              fontSize: 17,
              fontWeight:
              FontWeight.w900,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color:
                _DashColors.muted,
                fontSize: 11,
              ),
            ),
          ],
        ],
      );

  Widget _statCard(
      String label,
      int? value,
      String subtitle,
      IconData icon,
      Color color,
      ) =>
      ClipRRect(
        borderRadius:
        BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 142,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color:
              _DashColors.border,
            ),
            borderRadius:
            BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter:
                  _DecorativePainter(
                    color,
                  ),
                ),
              ),
              Padding(
                padding:
                const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize:
                  MainAxisSize.min,
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 31,
                      height: 31,
                      decoration: BoxDecoration(
                        color:
                        color.withAlpha(25),
                        borderRadius:
                        BorderRadius.circular(
                          10,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 17,
                        color: color,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    Text(
                      value?.toString() ??
                          '—',
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style: const TextStyle(
                        color:
                        _DashColors.ink,
                        fontSize: 23,
                        fontWeight:
                        FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style: const TextStyle(
                        color:
                        _DashColors.ink,
                        fontSize: 11,
                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style: const TextStyle(
                        color:
                        _DashColors.muted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _overview() => Column(
    crossAxisAlignment:
    CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: _sectionHeader(
              'Care Overview',
              subtitle:
              'Live data from your doctor account',
            ),
          ),
          if (_loadingOverview)
            const SizedBox(
              width: 17,
              height: 17,
              child:
              CircularProgressIndicator(
                strokeWidth: 2,
                color:
                _DashColors.green,
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns =
          constraints.maxWidth >= 760
              ? 4
              : 2;

          final width =
              (constraints.maxWidth -
                  (columns - 1) * 9) /
                  columns;

          return Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              SizedBox(
                width: width,
                child: _statCard(
                  'Patients',
                  _patientCount,
                  'Linked accounts',
                  Icons.people_alt_outlined,
                  _DashColors.green,
                ),
              ),
              SizedBox(
                width: width,
                child: _statCard(
                  'Children',
                  _childCount,
                  'Shared child profiles',
                  Icons.child_care_outlined,
                  _DashColors.blue,
                ),
              ),
              SizedBox(
                width: width,
                child: _statCard(
                  'Requests',
                  _pendingCount,
                  'Recent pending visits',
                  Icons.pending_actions_outlined,
                  _DashColors.purple,
                ),
              ),
              SizedBox(
                width: width,
                child: _statCard(
                  'Booked',
                  _upcomingCount,
                  'Recent future visits',
                  Icons.calendar_month_outlined,
                  _DashColors.coral,
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 7),
      const Text(
        'Request and booked figures use the latest loaded visits. '
            'Unavailable values are shown as —.',
        style: TextStyle(
          color: _DashColors.muted,
          fontSize: 10,
          height: 1.4,
        ),
      ),
    ],
  );

  // ============================================================
  // APPOINTMENT UI
  // ============================================================

  static String _formatDate(
      dynamic raw,
      ) {
    final date = DateTime.tryParse(
      _text(raw),
    )?.toLocal();

    if (date == null) {
      return 'Date unavailable';
    }

    final hour = date.hour % 12 == 0
        ? 12
        : date.hour % 12;

    final minute =
    date.minute.toString().padLeft(
      2,
      '0',
    );

    return '${date.day}/${date.month}/${date.year} • '
        '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
  }

  Widget _smallMetric(
      IconData icon,
      String label,
      int? value,
      Color color,
      ) =>
      Container(
        padding:
        const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: color.withAlpha(17),
          borderRadius:
          BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 16,
            ),
            const SizedBox(width: 5),
            Text(
              '$label ${value?.toString() ?? '—'}',
              style: const TextStyle(
                color: _DashColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );

  Widget _appointmentCard() {
    final visit = _nextVisit;

    final date = DateTime.tryParse(
      visit == null
          ? ''
          : _text(
        visit['confirmed_at'],
      ),
    )?.toLocal();

    return ClipRRect(
      borderRadius:
      BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color:
            _DashColors.border,
          ),
          borderRadius:
          BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
              const EdgeInsets.fromLTRB(
                15,
                14,
                12,
                5,
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color:
                      _DashColors.sky,
                      borderRadius:
                      BorderRadius.circular(
                        11,
                      ),
                    ),
                    child: const Icon(
                      Icons.calendar_month_outlined,
                      color:
                      _DashColors.blue,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'Next Appointment',
                      style: TextStyle(
                        color:
                        _DashColors.ink,
                        fontSize: 15,
                        fontWeight:
                        FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _openingSection
                        ? null
                        : () => _openSection(
                      'appointments',
                    ),
                    child: const Text(
                      'View All',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
              const EdgeInsets.fromLTRB(
                15,
                8,
                15,
                15,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        if (visit != null &&
                            date != null) ...[
                          Text(
                            _text(visit['patient_name'])
                                .isEmpty
                                ? 'Patient consultation'
                                : _text(
                              visit['patient_name'],
                            ),
                            maxLines: 1,
                            overflow:
                            TextOverflow.ellipsis,
                            style:
                            const TextStyle(
                              color:
                              _DashColors.ink,
                              fontSize: 14,
                              fontWeight:
                              FontWeight.w800,
                            ),
                          ),
                          const SizedBox(
                            height: 6,
                          ),
                          Text(
                            _formatDate(
                              visit['confirmed_at'],
                            ),
                            style:
                            const TextStyle(
                              color:
                              _DashColors.green,
                              fontSize: 12,
                              fontWeight:
                              FontWeight.w700,
                            ),
                          ),
                          if (_text(visit['concern'])
                              .isNotEmpty) ...[
                            const SizedBox(
                              height: 6,
                            ),
                            Text(
                              _text(
                                visit['concern'],
                              ),
                              maxLines: 2,
                              overflow:
                              TextOverflow.ellipsis,
                              style:
                              const TextStyle(
                                color:
                                _DashColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ] else ...[
                          Text(
                            _visitsAvailable
                                ? 'No upcoming confirmed visits'
                                : 'Appointments could not be loaded',
                            style:
                            const TextStyle(
                              color:
                              _DashColors.ink,
                              fontSize: 13,
                              fontWeight:
                              FontWeight.w800,
                            ),
                          ),
                          const SizedBox(
                            height: 5,
                          ),
                          Text(
                            _visitsAvailable
                                ? 'No future confirmed visit in the latest loaded records.'
                                : 'Pull down to refresh and try again.',
                            style:
                            const TextStyle(
                              color:
                              _DashColors.muted,
                              fontSize: 11,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  SizedBox(
                    width: 75,
                    height: 75,
                    child: CustomPaint(
                      painter:
                      const _DecorativePainter(
                        _DashColors.blue,
                      ),
                      child: const Icon(
                        Icons.favorite_border,
                        color:
                        _DashColors.teal,
                        size: 39,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              color:
              _DashColors.border,
            ),
            Padding(
              padding:
              const EdgeInsets.all(12),
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _smallMetric(
                    Icons.today_outlined,
                    'Today',
                    _todayCount,
                    _DashColors.blue,
                  ),
                  _smallMetric(
                    Icons.add_circle_outline,
                    'Slots',
                    _slotCount,
                    _DashColors.green,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CLINICAL WORKSPACE
  // ============================================================

  Widget _moduleCard(
      _DoctorModule module,
      double width,
      ) =>
      SizedBox(
        width: width,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openingSection
                ? null
                : () => _openSection(
              module.id,
            ),
            borderRadius:
            BorderRadius.circular(16),
            child: ClipRRect(
              borderRadius:
              BorderRadius.circular(16),
              child: Container(
                height: 121,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color:
                    _DashColors.border,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    16,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter:
                        _DecorativePainter(
                          module.color,
                        ),
                      ),
                    ),
                    Padding(
                      padding:
                      const EdgeInsets.all(
                        12,
                      ),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration:
                                BoxDecoration(
                                  color: module.color
                                      .withAlpha(
                                    23,
                                  ),
                                  borderRadius:
                                  BorderRadius.circular(
                                    12,
                                  ),
                                ),
                                child: Icon(
                                  module.icon,
                                  color:
                                  module.color,
                                  size: 20,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.north_east,
                                color: module.color
                                    .withAlpha(
                                  170,
                                ),
                                size: 15,
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            module.title,
                            maxLines: 1,
                            overflow:
                            TextOverflow.ellipsis,
                            style:
                            const TextStyle(
                              color:
                              _DashColors.ink,
                              fontSize: 12,
                              fontWeight:
                              FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            module.subtitle,
                            maxLines: 1,
                            overflow:
                            TextOverflow.ellipsis,
                            style:
                            const TextStyle(
                              color:
                              _DashColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _workspace() => Column(
    crossAxisAlignment:
    CrossAxisAlignment.start,
    children: [
      _sectionHeader(
        'Clinical Workspace',
        subtitle:
        'Everything you need in one place',
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns =
          constraints.maxWidth >= 830
              ? 4
              : constraints.maxWidth >= 520
              ? 3
              : 2;

          final width =
              (constraints.maxWidth -
                  (columns - 1) * 9) /
                  columns;

          return Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final module in _modules)
                _moduleCard(
                  module,
                  width,
                ),
            ],
          );
        },
      ),
    ],
  );

  // ============================================================
  // MAIN SCREEN
  // ============================================================

  @override
  Widget build(BuildContext context) =>
      Scaffold(
        key: _scaffoldKey,
        backgroundColor:
        _DashColors.page,
        drawer: _drawer(),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor:
          _DashColors.ink,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Open menu',
            icon: const Icon(
              Icons.menu,
            ),
            onPressed: () {
              _scaffoldKey.currentState
                  ?.openDrawer();
            },
          ),
          title: const Text(
            'Doctor Dashboard',
            style: TextStyle(
              fontSize: 16,
              fontWeight:
              FontWeight.w900,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: _busy
                  ? null
                  : _approved &&
                  !_needsLogin
                  ? () => _verifyDoctor()
                  : _checkApproval,
              icon: const Icon(
                Icons.refresh,
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          color:
          _DashColors.green,
          onRefresh: () async {
            if (_approved &&
                !_busy &&
                !_needsLogin) {
              await _verifyDoctor();
            }
          },
          child: ListView(
            physics:
            const AlwaysScrollableScrollPhysics(),
            padding:
            const EdgeInsets.fromLTRB(
              14,
              15,
              14,
              27,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints:
                  const BoxConstraints(
                    maxWidth: 1000,
                  ),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                    children: [
                      _hero(),
                      const SizedBox(height: 11),
                      _statusCard(),
                      if (_ready) ...[
                        const SizedBox(
                          height: 22,
                        ),
                        _overview(),
                        const SizedBox(
                          height: 20,
                        ),
                        _appointmentCard(),
                        const SizedBox(
                          height: 23,
                        ),
                        _workspace(),
                      ] else ...[
                        const SizedBox(
                          height: 13,
                        ),
                        _surface(
                          const Row(
                            children: [
                              Icon(
                                Icons.lock_outline,
                                color:
                                _DashColors.blue,
                              ),
                              SizedBox(
                                width: 9,
                              ),
                              Expanded(
                                child: Text(
                                  'Clinical modules unlock after admin approval '
                                      'and a valid doctor login.',
                                  style:
                                  TextStyle(
                                    color:
                                    _DashColors.muted,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      const Text(
                        'FamilyCare+ • Connected care',
                        textAlign:
                        TextAlign.center,
                        style: TextStyle(
                          color:
                          _DashColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
