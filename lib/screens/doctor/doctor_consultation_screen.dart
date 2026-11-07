import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

/// Family Care+ • Doctor Consultations • Backend v 10
///
/// Actionable consultation visits and shared care-record requests are
/// different resources. The latter are strictly read-only. Capacity-based
/// bookings are managed in Doctor Appointments Screen, not in this screen.
class DoctorConsultationScreen extends StatefulWidget {
  const DoctorConsultationScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.initialChild,
    this.onBack,
  });

  final String apiBaseUrl;
  final Map<String, dynamic>? initialChild;
  final VoidCallback? onBack;

  @override
  State<DoctorConsultationScreen> createState() =>
      _DoctorConsultationScreenState();
}

class _C {
  static const page = Color(0xFFF4FAF8);
  static const ink = Color(0xFF204A50);
  static const green = Color(0xFF257B6B);
  static const blue = Color(0xFF4683AE);
  static const mint = Color(0xFFE7F5EE);
  static const ice = Color(0xFFEAF4FB);
  static const border = Color(0xFFDCEBE7);
  static const muted = Color(0xFF71888B);
  static const red = Color(0xFFB65359);
  static const amber = Color(0xFFAA792D);
  static const purple = Color(0xFF7774B4);
}

class _ConsultApiError implements Exception {
  const _ConsultApiError(this.message, [this.status = 0]);
  final String message;
  final int status;

  @override
  String toString() => message;
}

class _ConsultChoice {
  const _ConsultChoice({required this.time, required this.duration});
  final DateTime time;
  final int duration;
}

String _s(dynamic value) => (value ?? '').toString().trim();
Map<String, dynamic> _m(dynamic value) => value is Map
    ? Map<String, dynamic>.from(value)
    : <String, dynamic>{};
List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value
    .whereType<Map>()
    .map((row) => Map<String, dynamic>.from(row))
    .toList()
    : <Map<String, dynamic>>[];
int? _asInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(_s(value));
DateTime? _when(dynamic value) =>
    DateTime.tryParse(_s(value))?.toLocal();

String _formatTime(DateTime? value) {
  if (value == null) return 'Not scheduled';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minutes = value.minute.toString().padLeft(2, '0');
  return '${value.day} ${months[value.month - 1]} ${value.year}, '
      '$hour:$minutes ${value.hour >= 12 ? 'PM' : 'AM'}';
}

class _DoctorConsultationScreenState extends State<DoctorConsultationScreen> {
  static const int _pageSize = 20;
  final http.Client _client = http.Client();
  final TextEditingController _search = TextEditingController();

  bool _checking = true;
  bool _authorized = false;
  bool _visitsLoading = false;
  bool _sharedLoading = false;
  bool _moreLoading = false;
  bool _slotsLoading = false;
  String? _authError;
  String? _visitsError;
  String? _sharedError;
  String? _slotsError;
  String? _workingId;

  String _tab = 'visits';
  String _statusFilter = 'ALL';
  String _quickFilter = 'all';
  int _authEpoch = 0;
  int _visitEpoch = 0;
  int _sharedEpoch = 0;
  int _slotEpoch = 0;
  int _sharedPage = 0;
  int _sharedTotal = 0;
  bool _visitsLoaded = false;
  bool _sharedLoaded = false;

  List<Map<String, dynamic>> _visits = [];
  List<Map<String, dynamic>> _shared = [];
  List<Map<String, dynamic>> _slots = [];

  bool get _working => _workingId != null;
  String get _profileId => _s(widget.initialChild?['id']);
  bool get _visitsTab => _tab == 'visits';

  String get _doctorApi {
    var base = widget.apiBaseUrl.trim();
    if (base.isEmpty) {
      base = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:5001'
          : 'http://127.0.0.1:5001';
    }
    base = base.replaceFirst(RegExp(r'/+$'), '');
    if (base.endsWith('/api/v1/doctors')) return base;
    if (base.endsWith('/api/v1')) return '$base/doctors';
    return '$base/api/v1/doctors';
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    unawaited(_verify());
  }

  @override
  void didUpdateWidget(covariant DoctorConsultationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      unawaited(_verify());
    } else if (_s(oldWidget.initialChild?['id']) != _profileId) {
      _search.clear();
      setState(() {
        _statusFilter = 'ALL';
        _quickFilter = 'all';
      });
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authEpoch++;
    _visitEpoch++;
    _sharedEpoch++;
    _slotEpoch++;
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _client.close();
    super.dispose();
  }

  String _friendly(Object error) {
    if (error is _ConsultApiError) return error.message;
    if (error is TimeoutException) return 'Request timed out. Please retry.';
    if (error is http.ClientException) {
      return 'Cannot connect to FamilyCare+. Check the backend URL and network.';
    }
    if (error is FormatException) return 'Unexpected server response. Please retry.';
    return 'Unable to complete the request. Please try again.';
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? _C.red : _C.ink,
      ));
  }

  Future<Map<String, dynamic>> _api(
      String method,
      String endpoint, {
        Map<String, String>? query,
        Map<String, dynamic>? payload,
      }) async {
    final role = await FamilyCareSession.role();
    final token = await FamilyCareSession.accessToken();
    final expiry = await FamilyCareSession.accessTokenExpiresAt();
    if (_s(role).toUpperCase() != 'DOCTOR' ||
        token == null || token.trim().isEmpty ||
        expiry == null || !expiry.isAfter(DateTime.now().toUtc())) {
      throw const _ConsultApiError('Doctor session expired. Sign in again.', 401);
    }

    final uri = Uri.parse('$_doctorApi$endpoint').replace(queryParameters: query);
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
      if (payload != null) 'Content-Type': 'application/json',
    };
    final http.Response response;
    if (method == 'PATCH') {
      response = await _client
          .patch(uri, headers: headers, body: jsonEncode(payload ?? {}))
          .timeout(const Duration(seconds: 30));
    } else {
      response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));
    }

    Map<String, dynamic> data = {};
    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        } else if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const FormatException('Expected a JSON object.');
        }
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final issue = data['error'];
      final serverMessage = issue is Map ? _s(issue['message']) : _s(issue);
      final fallback = switch (response.statusCode) {
        401 => 'Doctor session expired. Please sign in again.',
        403 => 'Doctor access denied or revoked.',
        404 => 'Consultation was not found.',
        409 => 'Consultation changed or conflicts with an appointment. Refresh and retry.',
        422 => 'Check the time, duration, version and status.',
        429 => 'Too many requests. Please retry later.',
        _ => 'Request failed (HTTP ${response.statusCode}).',
      };
      throw _ConsultApiError(
        serverMessage.isNotEmpty ? serverMessage : fallback,
        response.statusCode,
      );
    }
    if (data.isEmpty) {
      throw const FormatException('Server returned an empty response.');
    }
    return data;
  }

  void _block(String reason) {
    _authEpoch++;
    _visitEpoch++;
    _sharedEpoch++;
    _slotEpoch++;
    if (!mounted) return;
    setState(() {
      _checking = false;
      _authorized = false;
      _authError = reason;
      _visits = [];
      _shared = [];
      _slots = [];
      _visitsLoaded = false;
      _sharedLoaded = false;
      _visitsLoading = false;
      _sharedLoading = false;
      _moreLoading = false;
      _slotsLoading = false;
      _workingId = null;
      _sharedPage = 0;
      _sharedTotal = 0;
    });
  }

  Future<void> _verify() async {
    final epoch = ++_authEpoch;
    _visitEpoch++;
    _sharedEpoch++;
    _slotEpoch++;
    setState(() {
      _checking = true;
      _authorized = false;
      _authError = null;
      _visitsError = null;
      _sharedError = null;
      _slotsError = null;
      _visits = [];
      _shared = [];
      _slots = [];
      _visitsLoaded = false;
      _sharedLoaded = false;
      _visitsLoading = false;
      _sharedLoading = false;
      _moreLoading = false;
      _slotsLoading = false;
      _sharedPage = 0;
      _sharedTotal = 0;
    });
    try {
      final result = await _api('GET', '/me');
      final user = _m(result['user']);
      if (_s(user['role']).toUpperCase() != 'DOCTOR' ||
          _s(user['approval_status']).toUpperCase() != 'APPROVED' ||
          _s(user['account_status']).toUpperCase() != 'ACTIVE') {
        throw const _ConsultApiError(
          'An active, approved doctor account is required.', 403,
        );
      }
      if (!mounted || epoch != _authEpoch) return;
      setState(() {
        _checking = false;
        _authorized = true;
      });
      await Future.wait([
        _loadVisits(),
        _loadShared(reset: true),
        _loadSlots(),
      ]);
    } catch (error) {
      if (mounted && epoch == _authEpoch) _block(_friendly(error));
    }
  }

  Future<void> _loadVisits() async {
    if (!_authorized) return;
    final epoch = ++_visitEpoch;
    setState(() {
      _visitsLoading = true;
      _visitsError = null;
    });
    try {
      final result = await _api('GET', '/consultation-visits');
      if (result['items'] is! List) {
        throw const FormatException('Invalid consultation visits response.');
      }
      if (!mounted || epoch != _visitEpoch || !_authorized) return;
      setState(() {
        _visits = _rows(result['items']);
        _visitsLoaded = true;
      });
    } catch (error) {
      if (!mounted || epoch != _visitEpoch) return;
      if (error is _ConsultApiError && error.status == 401) {
        _block(_friendly(error));
        return;
      }
      setState(() {
        _visits = [];
        _visitsLoaded = false;
        _visitsError = _friendly(error);
      });
    } finally {
      if (mounted && epoch == _visitEpoch) {
        setState(() => _visitsLoading = false);
      }
    }
  }

  Future<void> _loadShared({required bool reset}) async {
    if (!_authorized || _sharedLoading || _moreLoading) return;
    final epoch = ++_sharedEpoch;
    final page = reset ? 1 : _sharedPage + 1;
    setState(() {
      _sharedLoading = reset;
      _moreLoading = !reset;
      _sharedError = null;
      if (reset) {
        _sharedPage = 0;
        _sharedTotal = 0;
      }
    });
    try {
      final result = await _api(
        'GET', '/consultation-requests',
        query: {'page': '$page', 'per_page': '$_pageSize'},
      );
      if (result['items'] is! List || _asInt(result['total']) == null) {
        throw const FormatException('Invalid shared consultation requests response.');
      }
      if (!mounted || epoch != _sharedEpoch || !_authorized) return;
      final incoming = _rows(result['items']);
      final ids = <String>{};
      setState(() {
        _shared = <Map<String, dynamic>>[
          if (!reset) ..._shared,
          ...incoming,
        ].where((r) {
          final id = _s(r['id']);
          return id.isNotEmpty && ids.add(id);
        }).toList();
        _sharedPage = page;
        _sharedTotal = _asInt(result['total'])!;
        _sharedLoaded = true;
      });
    } catch (error) {
      if (!mounted || epoch != _sharedEpoch) return;
      if (error is _ConsultApiError && error.status == 401) {
        _block(_friendly(error));
        return;
      }
      setState(() {
        _sharedError = _friendly(error);
        if (reset) {
          _shared = [];
          _sharedLoaded = false;
        }
      });
    } finally {
      if (mounted && epoch == _sharedEpoch) {
        setState(() {
          _sharedLoading = false;
          _moreLoading = false;
        });
      }
    }
  }

  Future<void> _loadSlots() async {
    if (!_authorized) return;
    final epoch = ++_slotEpoch;
    setState(() {
      _slotsLoading = true;
      _slotsError = null;
    });
    try {
      final result = await _api('GET', '/appointment-slots');
      if (result['items'] is! List) {
        throw const FormatException('Invalid availability response.');
      }
      if (!mounted || epoch != _slotEpoch || !_authorized) return;
      setState(() => _slots = _rows(result['items']));
    } catch (error) {
      if (!mounted || epoch != _slotEpoch) return;
      if (error is _ConsultApiError && error.status == 401) {
        _block(_friendly(error));
        return;
      }
      setState(() {
        _slots = [];
        _slotsError = _friendly(error);
      });
    } finally {
      if (mounted && epoch == _slotEpoch) {
        setState(() => _slotsLoading = false);
      }
    }
  }

  Future<void> _refresh() async {
    if (!_authorized || _working) return;
    if (_visitsTab) {
      await Future.wait([_loadVisits(), _loadSlots()]);
    } else {
      await _loadShared(reset: true);
    }
  }

  String _status(Map<String, dynamic> visit) =>
      _s(visit['status']).toUpperCase();
  DateTime? _requested(Map<String, dynamic> visit) =>
      _when(visit['requested_at']);
  DateTime? _confirmed(Map<String, dynamic> visit) =>
      _when(visit['confirmed_at']);
  DateTime? _displayDate(Map<String, dynamic> visit) =>
      _status(visit) == 'CONFIRMED' || _status(visit) == 'COMPLETED'
          ? _confirmed(visit) ?? _requested(visit)
          : _requested(visit);

  List<String> _transitions(String status) => switch (status) {
    'REQUESTED' => const ['CONFIRMED', 'DECLINED', 'CANCELLED'],
    'CONFIRMED' => const ['CONFIRMED', 'COMPLETED', 'DECLINED', 'CANCELLED'],
    _ => const [],
  };

  Future<void> _confirmVisit(Map<String, dynamic> visit) async {
    if (!_authorized || _working) return;
    await _loadSlots();
    if (!mounted || !_authorized) return;
    final reschedule = _status(visit) == 'CONFIRMED';
    final initial = reschedule ? _confirmed(visit) : _requested(visit);
    final result = await showModalBottomSheet<_ConsultChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: _C.page,
      builder: (_) => _ConsultTimePicker(
        title: reschedule ? 'Reschedule Consultation' : 'Confirm Consultation',
        initialTime: initial,
        duration: _asInt(visit['duration_minutes']) ?? 30,
        slots: _slots,
        slotsError: _slotsError,
      ),
    );
    if (!mounted || result == null || !_authorized) return;
    await _changeStatus(
      visit,
      'CONFIRMED',
      time: result.time,
      duration: result.duration,
    );
  }

  Future<void> _askAction(Map<String, dynamic> visit, String next) async {
    if (!_authorized || _working) return;
    final title = switch (next) {
      'COMPLETED' => 'Complete consultation?',
      'DECLINED' => 'Decline consultation?',
      _ => 'Cancel consultation?',
    };
    final message = switch (next) {
      'COMPLETED' => 'Mark as completed only after the consultation has actually happened.',
      'DECLINED' => 'Decline this consultation? It cannot be undone from this screen.',
      _ => 'Cancel this consultation? It cannot be undone from this screen.',
    };
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Go Back'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: next == 'COMPLETED' ? _C.green : _C.red,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(next == 'COMPLETED'
                ? 'Complete' : next == 'DECLINED' ? 'Decline' : 'Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    await _changeStatus(visit, next);
  }

  Future<void> _changeStatus(
      Map<String, dynamic> visit,
      String next, {
        DateTime? time,
        int? duration,
      }) async {
    if (!_authorized || _working) return;
    final id = _s(visit['id']);
    final version = _asInt(visit['version']);
    if (id.isEmpty || !_transitions(_status(visit)).contains(next)) return;
    if (version == null || version < 1) {
      _toast('Consultation version unavailable. Refresh before updating.', error: true);
      await _loadVisits();
      return;
    }
    if (next == 'CONFIRMED' &&
        (time == null || !time.isAfter(DateTime.now()) ||
            duration == null || duration < 5 || duration > 240)) {
      _toast('Choose a future consultation time and valid duration.', error: true);
      return;
    }
    // Prevent an unscheduled or future consultation being marked completed.
    if (next == 'COMPLETED') {
      final start = _confirmed(visit);
      if (start == null || start.isAfter(DateTime.now())) {
        _toast('Consultation must have reached its scheduled time.', error: true);
        return;
      }
    }
    setState(() => _workingId = id);
    try {
      final result = await _api(
        'PATCH',
        '/consultation-visits/${Uri.encodeComponent(id)}/status',
        payload: {
          'status': next,
          'version': version,
          if (next == 'CONFIRMED') ...{
            'confirmed_at': time!.toUtc().toIso8601String(),
            'duration_minutes': duration!,
          },
        },
      );
      final saved = _m(result['consultation']);
      if (_s(saved['id']) != id || _status(saved) != next) {
        throw const FormatException('Server did not confirm the status update.');
      }
      if (!mounted) return;
      setState(() {
        _visits = [
          for (final row in _visits)
            if (_s(row['id']) == id) saved else row,
        ];
      });
      _toast(next == 'CONFIRMED'
          ? 'Consultation time confirmed.'
          : 'Consultation updated to ${next.toLowerCase()}.');
    } catch (error) {
      if (error is _ConsultApiError && error.status == 401) {
        _block(_friendly(error));
      } else {
        _toast(_friendly(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _workingId = null);
      if (mounted && _authorized) {
        await Future.wait([_loadVisits(), _loadSlots()]);
      }
    }
  }

  Color _statusColor(String status) => switch (status) {
    'REQUESTED' => _C.amber,
    'CONFIRMED' => _C.blue,
    'COMPLETED' => _C.green,
    'CANCELLED' || 'DECLINED' => _C.red,
    _ => _C.muted,
  };

  String _statusName(String status) => switch (status) {
    'REQUESTED' => 'Requested',
    'CONFIRMED' => 'Confirmed',
    'COMPLETED' => 'Completed',
    'CANCELLED' => 'Cancelled',
    'DECLINED' => 'Declined',
    _ => status.isEmpty ? 'Not specified' : status,
  };

  List<Map<String, dynamic>> get _visible {
    final term = _search.text.trim().toLowerCase();
    final now = DateTime.now();
    final source = _visitsTab ? _visits : _shared;
    final rows = source.where((item) {
      if (_profileId.isNotEmpty && _s(item['profile_id']) != _profileId) {
        return false;
      }
      final status = _status(item);
      if (_statusFilter != 'ALL' && status != _statusFilter) return false;
      if (_visitsTab) {
        final date = _displayDate(item);
        if (_quickFilter == 'requests' && status != 'REQUESTED') return false;
        if (_quickFilter == 'upcoming' &&
            (status != 'CONFIRMED' || date == null || !date.isAfter(now))) {
          return false;
        }
        if (_quickFilter == 'completed' && status != 'COMPLETED') return false;
      }
      if (term.isEmpty) return true;
      return [
        item['patient_name'], item['title'], item['concern'], item['notes'],
        item['date'], item['status'],
      ].any((v) => _s(v).toLowerCase().contains(term));
    }).toList();
    if (_visitsTab) {
      rows.sort((a, b) {
        final first = _displayDate(a);
        final second = _displayDate(b);
        if (first == null) return second == null ? 0 : 1;
        if (second == null) return -1;
        return _quickFilter == 'upcoming'
            ? first.compareTo(second)
            : second.compareTo(first);
      });
    }
    return rows;
  }

  // ============================================================
  // COMMON RESPONSIVE UI
  // ============================================================

  Widget _panel(Widget child, {EdgeInsetsGeometry? padding}) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _C.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _infoPanel(String text, {bool warning = false}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFF7E9) : _C.mint,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _C.border),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline, size: 18, color: warning ? _C.amber : _C.green),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 11, color: _C.ink, height: 1.45))),
    ]),
  );

  Widget _errorPanel(String message, VoidCallback retry) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _panel(Row(children: [
      const Icon(Icons.error_outline, color: _C.red, size: 21),
      const SizedBox(width: 8),
      Expanded(child: Text(message,
          style: const TextStyle(color: _C.red, fontSize: 12))),
      IconButton(tooltip: 'Retry', onPressed: retry,
          icon: const Icon(Icons.refresh_rounded)),
    ])),
  );

  Widget _loading() => const Padding(
    padding: EdgeInsets.all(30),
    child: Center(child: CircularProgressIndicator(color: _C.green)),
  );

  Widget _empty(String headline, String detail) => _panel(Padding(
    padding: const EdgeInsets.symmetric(vertical: 27, horizontal: 8),
    child: Column(children: [
      const Icon(Icons.event_note_outlined, size: 38, color: _C.blue),
      const SizedBox(height: 9),
      Text(headline, textAlign: TextAlign.center,
          style: const TextStyle(color: _C.ink, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(detail, textAlign: TextAlign.center,
          style: const TextStyle(color: _C.muted, fontSize: 12, height: 1.4)),
    ]),
  ));

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_statusName(status),
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w800)),
    );
  }

  Widget _infoRow(String label, String text, {Color? color}) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$label: ',
            style: const TextStyle(color: _C.muted)),
        TextSpan(text: text,
            style: TextStyle(color: color ?? _C.ink,
                fontWeight: FontWeight.w700)),
      ]), style: const TextStyle(fontSize: 12, height: 1.45)),
    );
  }

  Widget _hero() => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF156A6C), Color(0xFF289483), Color(0xFF63B2A3)],
      ),
    ),
    child: Row(children: [
      Container(
        width: 53, height: 53,
        decoration: BoxDecoration(
          color: const Color(0x44FFFFFF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.medical_services_outlined,
            size: 28, color: Colors.white),
      ),
      const SizedBox(width: 13),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Consultations', style: TextStyle(
            color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900,
          )),
          const SizedBox(height: 5),
          Text(_profileId.isEmpty
              ? 'Patient visits and shared care requests'
              : 'Consultations for the selected care profile',
              style: const TextStyle(fontSize: 11,
                  color: Colors.white, height: 1.4)),
        ],
      )),
    ]),
  );

  Widget _tabButton(String label, String value, IconData icon) {
    final active = _tab == value;
    return Expanded(child: Material(
      color: active ? _C.green : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          _search.clear();
          setState(() {
            _tab = value;
            _statusFilter = 'ALL';
            _quickFilter = 'all';
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 51,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? _C.green : _C.border),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: active ? Colors.white : _C.green),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: active ? Colors.white : _C.ink))),
          ]),
        ),
      ),
    ));
  }

  Widget _miniStat(String label, int? count, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _C.border),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Text('${count?.toString() ?? '—'} $label',
              style: const TextStyle(color: _C.ink, fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _stats() {
    if (!_visitsTab) {
      return Wrap(spacing: 8, runSpacing: 8, children: [
        _miniStat('Shared total', _sharedLoaded ? _sharedTotal : null,
            Icons.folder_shared_outlined, _C.blue),
        _miniStat('Loaded', _sharedLoaded ? _shared.length : null,
            Icons.article_outlined, _C.green),
      ]);
    }
    final ok = _visitsLoaded;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _miniStat('Requested', ok ? _visits.where((v) => _status(v) == 'REQUESTED').length : null,
          Icons.pending_actions_outlined, _C.amber),
      _miniStat('Confirmed', ok ? _visits.where((v) => _status(v) == 'CONFIRMED').length : null,
          Icons.event_available_outlined, _C.blue),
      _miniStat('Completed', ok ? _visits.where((v) => _status(v) == 'COMPLETED').length : null,
          Icons.task_alt_outlined, _C.green),
    ]);
  }

  Widget _filters() {
    final statusItems = _visitsTab
        ? const ['ALL', 'REQUESTED', 'CONFIRMED', 'COMPLETED', 'DECLINED', 'CANCELLED']
        : const ['ALL', 'REQUESTED'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_visitsTab) ...[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final entry in const [
              ('all', 'All Visits'),
              ('requests', 'New Requests'),
              ('upcoming', 'Upcoming'),
              ('completed', 'Completed'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  label: Text(entry.$2),
                  selected: _quickFilter == entry.$1,
                  onSelected: (_) => setState(() {
                    _quickFilter = entry.$1;
                    _statusFilter = 'ALL';
                  }),
                  selectedColor: _C.mint,
                  side: const BorderSide(color: _C.border),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      TextField(
        controller: _search,
        decoration: InputDecoration(
          hintText: _visitsTab ? 'Search patient, concern or notes'
              : 'Search shared requests',
          prefixIcon: const Icon(Icons.search, color: _C.green),
          suffixIcon: _search.text.isEmpty ? null : IconButton(
            tooltip: 'Clear search', onPressed: _search.clear,
            icon: const Icon(Icons.close),
          ),
          filled: true, fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _C.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _C.green),
          ),
        ),
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final status in statusItems)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: ChoiceChip(
                label: Text(status == 'ALL' ? 'All statuses' : _statusName(status)),
                selected: _statusFilter == status,
                selectedColor: _C.mint,
                side: const BorderSide(color: _C.border),
                onSelected: (_) => setState(() => _statusFilter = status),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _visitCard(Map<String, dynamic> visit) {
    final status = _status(visit);
    final requested = _requested(visit);
    final confirmed = _confirmed(visit);
    final id = _s(visit['id']);
    final canComplete = status == 'CONFIRMED' &&
        confirmed != null && !confirmed.isAfter(DateTime.now());
    final name = _s(visit['patient_name']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(radius: 20, backgroundColor: _C.mint,
              child: Icon(Icons.person_outline, color: _C.green)),
          const SizedBox(width: 10),
          Expanded(child: Text(name.isEmpty ? 'Patient name unavailable' : name,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _C.ink, fontSize: 14,
                  fontWeight: FontWeight.w800))),
          _statusBadge(status),
        ]),
        const SizedBox(height: 10),
        Text(_s(visit['concern']).isEmpty ? 'Concern not specified' : _s(visit['concern']),
            style: const TextStyle(fontSize: 12, color: _C.ink, height: 1.45)),
        _infoRow('Requested for', _formatTime(requested)),
        if (confirmed != null) ...[
          _infoRow('Confirmed for', _formatTime(confirmed), color: _C.green),
          _infoRow('Duration', '${_asInt(visit['duration_minutes']) ?? 30} minutes',
              color: _C.blue),
        ],
        if (_s(visit['notes']).isNotEmpty)
          _infoRow('Notes', _s(visit['notes'])),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 7, children: [
          OutlinedButton.icon(
            onPressed: () => _details(visit, visit: true),
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text('Details'),
          ),
          if (status == 'REQUESTED') ...[
            FilledButton(
              onPressed: _working ? null : () => _confirmVisit(visit),
              style: FilledButton.styleFrom(backgroundColor: _C.green),
              child: Text(_workingId == id ? 'Updating...' : 'Confirm Time'),
            ),
            OutlinedButton(
              onPressed: _working ? null : () => _askAction(visit, 'DECLINED'),
              child: const Text('Decline'),
            ),
            TextButton(
              onPressed: _working ? null : () => _askAction(visit, 'CANCELLED'),
              child: const Text('Cancel', style: TextStyle(color: _C.red)),
            ),
          ],
          if (status == 'CONFIRMED') ...[
            FilledButton(
              onPressed: _working ? null : () => _confirmVisit(visit),
              style: FilledButton.styleFrom(backgroundColor: _C.green),
              child: const Text('Reschedule'),
            ),
            if (canComplete)
              OutlinedButton(
                onPressed: _working ? null : () => _askAction(visit, 'COMPLETED'),
                child: const Text('Complete'),
              ),
            TextButton(
              onPressed: _working ? null : () => _askAction(visit, 'CANCELLED'),
              child: const Text('Cancel', style: TextStyle(color: _C.red)),
            ),
            TextButton(
              onPressed: _working ? null : () => _askAction(visit, 'DECLINED'),
              child: const Text('Decline', style: TextStyle(color: _C.red)),
            ),
          ],
        ]),
      ])),
    );
  }

  Widget _sharedCard(Map<String, dynamic> request) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.folder_shared_outlined, size: 23, color: _C.blue),
        const SizedBox(width: 9),
        Expanded(child: Text(
          _s(request['title']).isEmpty ? 'Shared care request'
              : _s(request['title']),
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _C.ink, fontSize: 14,
              fontWeight: FontWeight.w800),
        )),
        _statusBadge(_status(request)),
      ]),
      if (_s(request['date']).isNotEmpty)
        _infoRow('Requested date', _s(request['date'])),
      if (_s(request['notes']).isNotEmpty)
        _infoRow('Notes', _s(request['notes'])),
      if (_s(request['verification_status']).isNotEmpty)
        _infoRow('Source', _s(request['verification_status'])),
      const SizedBox(height: 9),
      Row(children: [
        const Expanded(child: Text('Shared record • Read-only',
            style: TextStyle(color: _C.muted, fontSize: 11))),
        TextButton.icon(
          onPressed: () => _details(request, visit: false),
          icon: const Icon(Icons.visibility_outlined, size: 16),
          label: const Text('Details'),
        ),
      ]),
    ])),
  );

  void _details(Map<String, dynamic> record, {required bool visit}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _C.page,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .82),
        child: ListView(shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 7, 18, 28),
          children: [
            Text(visit ? 'Consultation Details' : 'Shared Care Request',
                style: const TextStyle(color: _C.ink, fontSize: 19,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            _detail('Status', _statusName(_status(record))),
            _detail('Care profile', record['profile_id']),
            if (visit) ...[
              _detail('Patient', record['patient_name']),
              _detail('Concern', record['concern']),
              _detail('Requested time', _formatTime(_requested(record))),
              if (_confirmed(record) != null) ...[
                _detail('Confirmed time', _formatTime(_confirmed(record))),
                _detail('Duration', '${_asInt(record['duration_minutes']) ?? 30} minutes'),
              ],
              _detail('Version', record['version']),
              if (record['review_rating'] != null)
                _detail('Patient review', record['review_rating']),
            ] else ...[
              _detail('Request title', record['title']),
              _detail('Requested date', record['date']),
              _detail('Source verification', record['verification_status']),
            ],
            _detail('Notes', record['notes']),
            const SizedBox(height: 8),
            const Divider(color: _C.border),
            Text(
              visit
                  ? 'This is a consultation visit. Confirming it does not create a v10 capacity booking or a video-call link.'
                  : 'This is a shared care record. It is not a booked visit and cannot be accepted or declined here.',
              style: const TextStyle(color: _C.muted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _C.muted, fontSize: 11)),
      const SizedBox(height: 4),
      Text(_s(value).isEmpty ? 'Not provided' : _s(value),
          style: const TextStyle(color: _C.ink, fontSize: 12,
              fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _main() {
    final visible = _visible;
    final loading = _visitsTab ? _visitsLoading : _sharedLoading;
    final failure = _visitsTab ? _visitsError : _sharedError;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _hero(),
      const SizedBox(height: 14),
      Row(children: [
        _tabButton('Consultation Visits', 'visits', Icons.event_note_outlined),
        const SizedBox(width: 9),
        _tabButton('Shared Requests', 'shared', Icons.folder_shared_outlined),
      ]),
      const SizedBox(height: 14),
      _infoPanel(_visitsTab
          ? 'Patient consultations are confirmed or rescheduled here. The new v10 capacity-based bookings are managed separately under Appointments.'
          : 'Only records explicitly shared with your doctor account appear here. These requests are read-only, not booked appointments.'),
      const SizedBox(height: 13),
      _stats(),
      const SizedBox(height: 14),
      _filters(),
      const SizedBox(height: 10),
      Text(
        _visitsTab
            ? 'Showing ${visible.length} of ${_visits.length} latest visits (maximum 100 returned by server). Times use the device timezone.'
            : 'Showing ${visible.length} of ${_shared.length} loaded shared requests. More pages may be available.',
        style: const TextStyle(fontSize: 11, color: _C.muted, height: 1.4),
      ),
      const SizedBox(height: 12),
      if (failure != null)
        _errorPanel(failure, _visitsTab ? _loadVisits : () => _loadShared(reset: true)),
      if (loading)
        _loading()
      else if (failure == null && visible.isEmpty)
        _empty(
          _visitsTab ? 'No matching consultations' : 'No shared requests found',
          _visitsTab ? 'Try All Visits or another status filter.'
              : 'Check the sharing permission or try another search.',
        )
      else if (failure == null)
          for (final row in visible)
            _visitsTab ? _visitCard(row) : _sharedCard(row),
      if (!_visitsTab && _sharedLoaded && !_sharedLoading &&
          _sharedPage * _pageSize < _sharedTotal) ...[
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _moreLoading ? null : () => _loadShared(reset: false),
          icon: _moreLoading
              ? const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.expand_more),
          label: Text(_moreLoading ? 'Loading...' : 'Load More Requests'),
        ),
      ],
      if (_slotsLoading && _visitsTab)
        const Padding(padding: EdgeInsets.only(top: 12),
            child: Text('Refreshing available consultation slots...',
                style: TextStyle(fontSize: 11, color: _C.muted))),
      const SizedBox(height: 22),
      const Text('FamilyCare+ • Doctor-only clinical access',
          textAlign: TextAlign.center,
          style: TextStyle(color: _C.muted, fontSize: 11)),
    ]);
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
      const Icon(Icons.lock_person_outlined, color: _C.blue, size: 48),
      const SizedBox(height: 12),
      const Text('Approved Doctor Required', style: TextStyle(
          color: _C.ink, fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(_authError ?? 'Sign in with an approved, active doctor account.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _C.muted, height: 1.45)),
      const SizedBox(height: 15),
      FilledButton.icon(
        onPressed: _verify,
        style: FilledButton.styleFrom(backgroundColor: _C.green),
        icon: const Icon(Icons.refresh),
        label: const Text('Retry Verification'),
      ),
    ]),
  ));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _C.page,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _C.ink,
      leading: IconButton(
        onPressed: _back,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Doctor Consultations', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w800)),
      actions: [
        IconButton(
          tooltip: 'Refresh consultations',
          onPressed: !_authorized || _working || _checking ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _checking
        ? const Center(child: CircularProgressIndicator(color: _C.green))
        : !_authorized
        ? _blocked()
        : RefreshIndicator(
      color: _C.green,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 30),
        children: [
          Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: _main(),
          )),
        ],
      ),
    ),
  );
}

// This editor is only opened when confirming/rescheduling a legacy visit.
// It never creates a new capacity booking or a new availability slot.
class _ConsultTimePicker extends StatefulWidget {
  const _ConsultTimePicker({
    required this.title,
    required this.initialTime,
    required this.duration,
    required this.slots,
    required this.slotsError,
  });

  final String title;
  final DateTime? initialTime;
  final int duration;
  final List<Map<String, dynamic>> slots;
  final String? slotsError;

  @override
  State<_ConsultTimePicker> createState() => _ConsultTimePickerState();
}

class _ConsultTimePickerState extends State<_ConsultTimePicker> {
  late DateTime _time;
  late TextEditingController _durationController;
  String _slotId = 'custom';
  bool _chosen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final earliest = DateTime.now().add(const Duration(minutes: 10));
    final initial = widget.initialTime?.toLocal();
    if (initial != null && initial.isAfter(earliest)) {
      _time = initial;
      // The patient explicitly requested this time; doctor can retain it.
      _chosen = true;
    } else {
      _time = earliest;
      // A generated time is NOT automatically accepted.
      _chosen = false;
    }
    final minutes = widget.duration >= 5 && widget.duration <= 240
        ? widget.duration : 30;
    _durationController = TextEditingController(text: '$minutes');
  }

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _chooseTime() async {
    final today = DateTime.now();
    final maximum = DateTime(today.year + 2, 12, 31);
    final initial = _time.isAfter(maximum) ? today : _time;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: maximum,
      helpText: 'Choose confirmed consultation date',
    );
    if (!mounted || date == null) return;
    final clock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
      helpText: 'Choose confirmed consultation time',
    );
    if (!mounted || clock == null) return;
    setState(() {
      _slotId = 'custom';
      _time = DateTime(date.year, date.month, date.day, clock.hour, clock.minute);
      _chosen = true;
      _error = null;
    });
  }

  void _submit() {
    final duration = int.tryParse(_durationController.text.trim());
    if (!_chosen) {
      setState(() => _error = 'Select a real date and time before confirming.');
    } else if (!_time.isAfter(DateTime.now())) {
      setState(() => _error = 'Choose a future consultation date and time.');
    } else if (duration == null || duration < 5 || duration > 240) {
      setState(() => _error = 'Duration must be between 5 and 240 minutes.');
    } else {
      Navigator.pop(context, _ConsultChoice(time: _time, duration: duration));
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.slots.where((slot) {
      final time = _when(slot['starts_at']);
      return time != null && time.isAfter(DateTime.now()) &&
          _s(slot['id']).isNotEmpty;
    }).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 8, 18,
          MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: const TextStyle(color: _C.ink,
              fontWeight: FontWeight.w900, fontSize: 19)),
          const SizedBox(height: 8),
          const Text('Select a future time in your device timezone. The backend receives UTC.',
              style: TextStyle(color: _C.muted, fontSize: 12, height: 1.4)),
          if (widget.slotsError != null) ...[
            const SizedBox(height: 10),
            const Text('Available slots could not be loaded. You can still choose a custom time.',
                style: TextStyle(color: _C.amber, fontSize: 12)),
          ],
          if (available.isNotEmpty) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey(_slotId),
              initialValue: _slotId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Available time (optional)',
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: 'custom', child: Text('Custom date and time'),
                ),
                for (final slot in available)
                  DropdownMenuItem<String>(
                    value: _s(slot['id']),
                    child: Text(
                      '${_formatTime(_when(slot['starts_at']))} • '
                          '${_asInt(slot['duration_minutes']) ?? 30} min',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _slotId = value;
                  if (value != 'custom') {
                    final selected = available.firstWhere(
                          (slot) => _s(slot['id']) == value,
                    );
                    _time = _when(selected['starts_at'])!;
                    _durationController.text =
                    '${_asInt(selected['duration_minutes']) ?? 30}';
                    _chosen = true;
                  }
                  _error = null;
                });
              },
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _chooseTime,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(_chosen ? _formatTime(_time) : 'Choose date & time'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _C.green,
              side: const BorderSide(color: _C.border),
            ),
          ),
          if (!_chosen) ...[
            const SizedBox(height: 5),
            const Text('No appointment time selected yet.',
                style: TextStyle(fontSize: 11, color: _C.amber)),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _durationController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 3,
            decoration: const InputDecoration(
              labelText: 'Duration (5–240 minutes)',
              counterText: '', filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: _C.red, fontSize: 12)),
            const SizedBox(height: 7),
          ],
          const SizedBox(height: 9),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check_rounded),
            label: Text(widget.title),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: _C.green,
            ),
          ),
          const SizedBox(height: 10),
          const Text('The backend checks conflicts with other confirmed consultations. '
              'Selecting an available slot does not create a v10 capacity booking.',
              style: TextStyle(color: _C.muted, fontSize: 11, height: 1.4)),
        ],
      )),
    );
  }
}