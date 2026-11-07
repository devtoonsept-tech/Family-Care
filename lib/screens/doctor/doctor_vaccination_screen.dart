
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

class DoctorVaccinationScreen extends StatefulWidget {
  const DoctorVaccinationScreen({
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
  State<DoctorVaccinationScreen> createState() =>
      _DoctorVaccinationScreenState();
}

class _VaxColor {
  static const ink = Color(0xFF264A51);
  static const green = Color(0xFF367D69);
  static const blue = Color(0xFF477F99);
  static const mint = Color(0xFFE8F7EF);
  static const ice = Color(0xFFECF5FA);
  static const page = Color(0xFFF6FAF9);
  static const line = Color(0xFFDCEAE7);
  static const muted = Color(0xFF70848A);
  static const red = Color(0xFFAE555B);
  static const amber = Color(0xFF97752F);
}

class _VaxError implements Exception {
  const _VaxError(this.message, [this.status]);

  final String message;
  final int? status;

  @override
  String toString() => message;
}

String _vt(dynamic value) =>
    (value ?? '').toString().trim();

Map<String, dynamic> _vm(dynamic value) =>
    value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};

List<Map<String, dynamic>> _vl(dynamic value) =>
    value is List
        ? value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList()
        : <Map<String, dynamic>>[];

int _vi(dynamic value, [int fallback = 0]) =>
    value is num
        ? value.toInt()
        : int.tryParse(_vt(value)) ?? fallback;

String _vd(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';

DateTime? _parsedDay(dynamic value) =>
    DateTime.tryParse(_vt(value));

class _DoctorVaccinationScreenState
    extends State<DoctorVaccinationScreen> {
  static const _pageSize = 20;

  static const _filters = [
    'All',
    'Completed',
    'Upcoming',
    'Overdue',
  ];

  final _client = http.Client();
  final _search = TextEditingController();

  bool _verifying = true;
  bool _authorized = false;
  bool _loadingChildren = false;
  bool _loadingRecords = false;
  bool _loadingPlan = false;
  bool _openingChild = false;
  bool _saving = false;

  String? _authError;
  String? _childrenError;
  String? _recordsError;
  String? _planError;

  String _doctorId = '';
  String _tab = 'records';
  String _scheme = 'UIP';
  String _filter = 'All';

  Map<String, dynamic>? _child;
  Map<String, dynamic> _plan = {};

  List<Map<String, dynamic>> _children = [];
  List<Map<String, dynamic>> _records = [];

  int _childPage = 0;
  int _childTotal = 0;
  int _recordPage = 0;
  int _recordTotal = 0;

  int _authStamp = 0;
  int _childrenStamp = 0;
  int _selectionStamp = 0;
  int _recordsStamp = 0;
  int _planStamp = 0;

  String get _childId => _vt(_child?['id']);

  String get _root =>
      '/care-profiles/${Uri.encodeComponent(_childId)}';

  String get _base {
    var value = widget.apiBaseUrl.trim();

    if (value.isEmpty) {
      value = !kIsWeb &&
          defaultTargetPlatform ==
              TargetPlatform.android
          ? 'http://10.0.2.2:5001'
          : 'http://127.0.0.1:5001';
    }

    value = value.replaceFirst(RegExp(r'/+$'), '');

    if (value.endsWith('/api/v1/doctors')) {
      return value;
    }

    if (value.endsWith('/api/v1')) {
      return '$value/doctors';
    }

    return '$value/api/v1/doctors';
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
    _verify();
  }

  @override
  void didUpdateWidget(
      covariant DoctorVaccinationScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _verify();
    } else if (_vt(oldWidget.initialChild?['id']) !=
        _vt(widget.initialChild?['id'])) {
      final id = _vt(widget.initialChild?['id']);

      if (_authorized) {
        if (id.isEmpty) {
          _backToChildren();
        } else {
          _openChild(id);
        }
      }
    }
  }

  void _searchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _authStamp++;
    _childrenStamp++;
    _selectionStamp++;
    _recordsStamp++;
    _planStamp++;

    _search.dispose();
    _client.close();

    super.dispose();
  }

  String _message(Object error) {
    if (error is _VaxError) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'Request timed out. Check the list before retrying.';
    }

    if (error is http.ClientException) {
      return 'Cannot reach FamilyCare+. Check the backend connection.';
    }

    if (error is FormatException) {
      return 'The server returned an invalid response.';
    }

    return 'Unable to complete this request. Please retry.';
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
          behavior: SnackBarBehavior.floating,
          backgroundColor:
          error ? _VaxColor.red : _VaxColor.ink,
          content: Text(message),
        ),
      );
  }

  Future<Map<String, dynamic>> _api(
      String method,
      String path, {
        Map<String, String>? query,
        Map<String, dynamic>? payload,
      }) async {
    final role = await FamilyCareSession.role();
    final token =
    await FamilyCareSession.accessToken();
    final expiry =
    await FamilyCareSession.accessTokenExpiresAt();

    if (_vt(role).toUpperCase() != 'DOCTOR' ||
        token == null ||
        token.isEmpty ||
        expiry == null ||
        !expiry.isAfter(DateTime.now().toUtc())) {
      throw const _VaxError(
        'Doctor session expired. Please sign in again.',
        401,
      );
    }

    final uri = Uri.parse(
      '$_base$path',
    ).replace(queryParameters: query);

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
        body: jsonEncode(payload ?? {}),
      )
          .timeout(const Duration(seconds: 35));
    } else if (method == 'DELETE') {
      response = await _client
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 30));
    } else {
      response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));
    }

    Map<String, dynamic> result = {};

    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(
          utf8.decode(response.bodyBytes),
        );

        if (decoded is Map) {
          result =
          Map<String, dynamic>.from(decoded);
        } else if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          throw const FormatException(
            'Expected JSON object.',
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
      final problem = result['error'];

      final server = problem is Map
          ? _vt(problem['message'])
          : _vt(problem);

      final fallback = switch (
      response.statusCode) {
        401 =>
        'Doctor session expired. Please sign in again.',
        403 =>
        'You do not have permission for this child.',
        404 =>
        'Child profile, scheduled dose or record is unavailable.',
        409 =>
        'This dose is already completed or its schedule changed. Refresh and review the existing record.',
        422 =>
        'Please check the dose, administration date and clinical details.',
        429 =>
        'Too many requests. Please retry shortly.',
        _ =>
        'Request failed (HTTP ${response.statusCode}).',
      };

      throw _VaxError(
        server.isEmpty ? fallback : server,
        response.statusCode,
      );
    }

    return result;
  }

  void _block(String message) {
    _authStamp++;
    _childrenStamp++;
    _selectionStamp++;
    _recordsStamp++;
    _planStamp++;

    if (!mounted) return;

    setState(() {
      _verifying = false;
      _authorized = false;
      _authError = message;
      _child = null;
      _children = [];
      _records = [];
      _plan = {};
      _loadingChildren = false;
      _loadingRecords = false;
      _loadingPlan = false;
    });
  }

  Future<void> _verify() async {
    final stamp = ++_authStamp;

    _childrenStamp++;
    _selectionStamp++;
    _recordsStamp++;
    _planStamp++;

    setState(() {
      _verifying = true;
      _authorized = false;

      _authError = null;
      _childrenError = null;
      _recordsError = null;
      _planError = null;

      _child = null;
      _children = [];
      _records = [];
      _plan = {};

      _childPage = 0;
      _childTotal = 0;
      _recordPage = 0;
      _recordTotal = 0;
    });

    try {
      final response = await _api('GET', '/me');
      final user = _vm(response['user']);

      if (_vt(user['role']).toUpperCase() !=
          'DOCTOR' ||
          _vt(user['approval_status'])
              .toUpperCase() !=
              'APPROVED' ||
          _vt(user['account_status'])
              .toUpperCase() !=
              'ACTIVE' ||
          _vt(user['id']).isEmpty) {
        throw const _VaxError(
          'Only approved, active doctors can manage child vaccinations.',
          403,
        );
      }

      if (!mounted || stamp != _authStamp) {
        return;
      }

      setState(() {
        _doctorId = _vt(user['id']);
        _verifying = false;
        _authorized = true;
      });

      final initialId =
      _vt(widget.initialChild?['id']);

      if (initialId.isEmpty) {
        await _loadChildren(reset: true);
      } else {
        await _openChild(initialId);
      }
    } catch (error) {
      if (mounted && stamp == _authStamp) {
        _block(_message(error));
      }
    }
  }

  Future<void> _loadChildren({
    required bool reset,
  }) async {
    if (!_authorized || _loadingChildren) return;

    final stamp = ++_childrenStamp;
    final page = reset ? 1 : _childPage + 1;

    setState(() {
      _loadingChildren = true;
      _childrenError = null;

      if (reset) {
        _children = [];
        _childPage = 0;
        _childTotal = 0;
      }
    });

    try {
      final response = await _api(
        'GET',
        '/care-profiles',
        query: {
          'module': 'child',
          'page': '$page',
          'per_page': '$_pageSize',
        },
      );

      if (response['items'] is! List) {
        throw const FormatException(
          'Invalid children list.',
        );
      }

      if (!mounted || stamp != _childrenStamp) {
        return;
      }

      setState(() {
        final seen = <String>{};

        _children = [
          if (!reset) ..._children,
          ..._vl(response['items']),
        ]
            .where(
              (c) =>
          _vt(c['id']).isNotEmpty &&
              _vt(c['module']).toLowerCase() ==
                  'child' &&
              seen.add(_vt(c['id'])),
        )
            .toList();

        _childPage = page;
        _childTotal = _vi(
          response['total'],
          _children.length,
        );
      });
    } catch (error) {
      if (!mounted || stamp != _childrenStamp) {
        return;
      }

      if (error is _VaxError &&
          error.status == 401) {
        _block(_message(error));
      } else {
        setState(() {
          _childrenError = _message(error);
        });
      }
    } finally {
      if (mounted && stamp == _childrenStamp) {
        setState(() {
          _loadingChildren = false;
        });
      }
    }
  }

  Future<void> _openChild(String id) async {
    if (!_authorized ||
        _openingChild ||
        _saving ||
        id.isEmpty) {
      return;
    }

    final stamp = ++_selectionStamp;
    _recordsStamp++;
    _planStamp++;

    setState(() {
      _openingChild = true;

      _childrenError = null;
      _recordsError = null;
      _planError = null;

      _child = null;
      _records = [];
      _plan = {};

      _recordPage = 0;
      _recordTotal = 0;

      _tab = 'records';
      _filter = 'All';
      _scheme = 'UIP';
    });

    try {
      final response = await _api(
        'GET',
        '/care-profiles/${Uri.encodeComponent(id)}',
      );

      final profile = _vm(response['profile']);

      if (_vt(profile['id']) != id ||
          _vt(profile['module']).toLowerCase() !=
              'child') {
        throw const _VaxError(
          'Child profile is not connected to this doctor.',
          403,
        );
      }

      if (!mounted || stamp != _selectionStamp) {
        return;
      }

      setState(() {
        _child = profile;
        _openingChild = false;
      });

      await Future.wait([
        _loadRecords(reset: true),
        _loadPlan(),
      ]);
    } catch (error) {
      if (!mounted || stamp != _selectionStamp) {
        return;
      }

      if (error is _VaxError &&
          error.status == 401) {
        _block(_message(error));
      } else {
        setState(() {
          _childrenError = _message(error);
        });

        _notice(
          _message(error),
          error: true,
        );
      }
    } finally {
      if (mounted && stamp == _selectionStamp) {
        setState(() => _openingChild = false);
      }
    }
  }

  Future<void> _loadRecords({
    required bool reset,
  }) async {
    if (!_authorized ||
        _child == null ||
        _loadingRecords) {
      return;
    }

    final stamp = ++_recordsStamp;
    final id = _childId;
    final page = reset ? 1 : _recordPage + 1;

    setState(() {
      _loadingRecords = true;
      _recordsError = null;

      if (reset) {
        _records = [];
        _recordPage = 0;
        _recordTotal = 0;
      }
    });

    try {
      final response = await _api(
        'GET',
        '$_root/child-records/vaccination',
        query: {
          'page': '$page',
          'per_page': '$_pageSize',
        },
      );

      if (response['items'] is! List) {
        throw const FormatException(
          'Invalid records list.',
        );
      }

      if (!mounted ||
          stamp != _recordsStamp ||
          id != _childId) {
        return;
      }

      setState(() {
        final seen = <String>{};

        _records = [
          if (!reset) ..._records,
          ..._vl(response['items']),
        ]
            .where(
              (r) =>
          _vt(r['id']).isNotEmpty &&
              seen.add(_vt(r['id'])),
        )
            .toList();

        _recordPage = page;
        _recordTotal = _vi(
          response['total'],
          _records.length,
        );
      });
    } catch (error) {
      if (!mounted ||
          stamp != _recordsStamp ||
          id != _childId) {
        return;
      }

      if (error is _VaxError &&
          error.status == 401) {
        _block(_message(error));
      } else if (error is _VaxError &&
          const {403, 404}.contains(error.status)) {
        _backToChildren();

        _notice(
          _message(error),
          error: true,
        );
      } else {
        setState(() {
          _recordsError = _message(error);
        });
      }
    } finally {
      if (mounted && stamp == _recordsStamp) {
        setState(() {
          _loadingRecords = false;
        });
      }
    }
  }

  Future<void> _loadPlan() async {
    if (!_authorized ||
        _child == null ||
        _loadingPlan) {
      return;
    }

    final stamp = ++_planStamp;
    final id = _childId;

    setState(() {
      _loadingPlan = true;
      _planError = null;
    });

    try {
      final response = await _api(
        'GET',
        '$_root/vaccination-plan',
      );

      if (!mounted ||
          stamp != _planStamp ||
          id != _childId) {
        return;
      }

      setState(() {
        _plan = response;
      });
    } catch (error) {
      if (!mounted ||
          stamp != _planStamp ||
          id != _childId) {
        return;
      }

      if (error is _VaxError &&
          error.status == 401) {
        _block(_message(error));
      } else if (error is _VaxError &&
          const {403, 404}.contains(error.status)) {
        _backToChildren();

        _notice(
          _message(error),
          error: true,
        );
      } else {
        setState(() {
          _planError = _message(error);
        });
      }
    } finally {
      if (mounted && stamp == _planStamp) {
        setState(() => _loadingPlan = false);
      }
    }
  }

  Future<void> _refresh() async {
    if (!_authorized ||
        _saving ||
        _openingChild) {
      return;
    }

    if (_child == null) {
      await _loadChildren(reset: true);
    } else {
      await Future.wait([
        _loadRecords(reset: true),
        _loadPlan(),
      ]);
    }
  }

  void _backToChildren() {
    _selectionStamp++;
    _recordsStamp++;
    _planStamp++;

    if (!mounted) return;

    setState(() {
      _child = null;
      _records = [];
      _plan = {};

      _recordPage = 0;
      _recordTotal = 0;

      _loadingRecords = false;
      _loadingPlan = false;
      _openingChild = false;
      _filter = 'All';
    });

    if (_children.isEmpty) {
      _loadChildren(reset: true);
    }
  }

  void _back() {
    if (_child != null) {
      _backToChildren();
    } else if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _addRecord({
    Map<String, dynamic>? dose,
  }) async {
    if (!_authorized ||
        _child == null ||
        _saving) {
      return;
    }

    final id = _childId;
    final child =
    Map<String, dynamic>.from(_child!);

    if (dose != null && !_canLink(dose)) {
      _notice(
        'This dose is already completed or requires review. Refresh the plan.',
        error: true,
      );
      return;
    }

    final saved =
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: _VaxColor.page,
      builder: (_) => _VaxRecordEditor(
        child: child,
        dose: dose,
        onSave: (data) async {
          if (_childId != id) {
            throw const _VaxError(
              'Child profile changed. Reopen the form.',
            );
          }

          final response = await _api(
            'POST',
            '/care-profiles/${Uri.encodeComponent(id)}/child-records/vaccination',
            payload: data,
          );

          if (_vm(response['record'])['id'] ==
              null) {
            throw const FormatException(
              'Vaccination save was not confirmed.',
            );
          }
        },
      ),
    );

    if (!mounted ||
        id != _childId ||
        saved != true) {
      return;
    }

    _notice(
      dose == null
          ? 'Vaccination record saved.'
          : 'Scheduled dose recorded with doctor attribution.',
    );

    await _refresh();
  }

  Future<void> _removeRecord(
      Map<String, dynamic> record,
      ) async {
    if (!_authorized ||
        _child == null ||
        _saving) {
      return;
    }

    final owned =
        _vt(record['source_role']).toUpperCase() ==
            'DOCTOR' &&
            _vt(record['author_id']) ==
                _doctorId;

    if (!owned) return;

    final id = _vt(record['id']);
    final childId = _childId;

    if (id.isEmpty) return;

    final confirmed =
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Remove vaccination record?',
        ),
        content: const Text(
          'The entry will be removed from the active child history. An audit revision is retained.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
                  dialogContext,
                  false,
                ),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _VaxColor.red,
            ),
            onPressed: () =>
                Navigator.pop(
                  dialogContext,
                  true,
                ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true ||
        !mounted ||
        childId != _childId) {
      return;
    }

    setState(() => _saving = true);

    try {
      await _api(
        'DELETE',
        '/care-profiles/${Uri.encodeComponent(childId)}/child-records/vaccination/${Uri.encodeComponent(id)}',
      );

      _notice('Vaccination entry removed.');
    } catch (error) {
      if (error is _VaxError &&
          error.status == 401) {
        _block(_message(error));
      } else {
        _notice(
          _message(error),
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }

    if (mounted &&
        _authorized &&
        _childId == childId) {
      await _refresh();
    }
  }

  Future<void> _review(
      Map<String, dynamic> dose,
      ) async {
    if (!_authorized ||
        _child == null ||
        _saving) {
      return;
    }

    final id = _childId;

    final result =
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: _VaxColor.page,
      builder: (_) => _VaxReviewEditor(
        dose: dose,
        onSave: (payload) async {
          if (_childId != id) {
            throw const _VaxError(
              'Child profile changed. Reopen the review.',
            );
          }

          await _api(
            'POST',
            '/care-profiles/${Uri.encodeComponent(id)}/vaccination-plan',
            payload: payload,
          );
        },
      ),
    );

    if (!mounted ||
        result != true ||
        id != _childId) {
      return;
    }

    _notice(
      'Applicability review saved. No administration date was recorded.',
    );

    await _loadPlan();
  }

  bool _canLink(
      Map<String, dynamic> dose,
      ) {
    final status =
    _vt(dose['status']).toUpperCase();

    if (_vt(dose['publication_status'])
        .toUpperCase() !=
        'PUBLISHED' ||
        _vt(dose['id']).isEmpty ||
        !const {
          'UPCOMING',
          'DUE',
          'OVERDUE',
        }.contains(status)) {
      return false;
    }

    final duplicateLoaded = _records.any(
          (record) =>
      _vt(record['status']).toLowerCase() ==
          'completed' &&
          (_vt(record['schedule_id']) ==
              _vt(dose['id']) ||
              (_vt(record['vaccine_id'])
                  .isNotEmpty &&
                  _vt(record['vaccine_id']) ==
                      _vt(dose['vaccine_id']) &&
                  _vt(record['dose_code']) ==
                      _vt(dose['dose_code']) &&
                  _vt(record['schedule_type']) ==
                      _vt(dose['schedule_type']))),
    );

    return !duplicateLoaded;
  }

  bool _matchRecord(
      Map<String, dynamic> item,
      ) {
    if (_filter == 'All') return true;

    final status =
    _vt(item['status']).toLowerCase();

    final date =
    _parsedDay(item['date']);

    final today =
    DateUtils.dateOnly(DateTime.now());

    if (_filter == 'Completed') {
      return status == 'completed';
    }

    if (_filter == 'Upcoming') {
      return status == 'planned' &&
          date != null &&
          !date.isBefore(today);
    }

    return status == 'missed' ||
        (status == 'planned' &&
            date != null &&
            date.isBefore(today));
  }

  bool _matchDose(
      Map<String, dynamic> item,
      ) {
    if (_filter == 'All') return true;

    final status =
    _vt(item['status']).toUpperCase();

    if (_filter == 'Completed') {
      return status == 'COMPLETED';
    }

    if (_filter == 'Upcoming') {
      return status == 'UPCOMING' ||
          status == 'DUE';
    }

    return status == 'OVERDUE';
  }

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(
        color: _VaxColor.line,
      ),
      borderRadius:
      BorderRadius.circular(16),
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
              _VaxColor.mint,
              _VaxColor.ice,
            ],
          ),
          border: Border.all(
            color: _VaxColor.line,
          ),
          borderRadius:
          BorderRadius.circular(17),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.vaccines_outlined,
              color: _VaxColor.green,
              size: 29,
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
                      color: _VaxColor.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _VaxColor.muted,
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

  Widget _errorBox(
      String message,
      VoidCallback retry,
      ) =>
      Padding(
        padding: const EdgeInsets.only(
          bottom: 10,
        ),
        child: _panel(
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: _VaxColor.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: _VaxColor.red,
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

  Widget _empty(String label) => _panel(
    Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 27,
        horizontal: 9,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.folder_open_outlined,
            color: _VaxColor.blue,
            size: 35,
          ),
          const SizedBox(height: 9),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _VaxColor.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _chip(
      String label,
      bool active,
      VoidCallback onTap,
      ) =>
      ChoiceChip(
        label: Text(label),
        selected: active,
        selectedColor: _VaxColor.mint,
        backgroundColor: Colors.white,
        side: const BorderSide(
          color: _VaxColor.line,
        ),
        labelStyle: TextStyle(
          color: active
              ? _VaxColor.green
              : _VaxColor.muted,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        onSelected: (_) => onTap(),
      );

  Widget _filtersRow() =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final label in _filters)
              Padding(
                padding: const EdgeInsets.only(
                  right: 7,
                ),
                child: _chip(
                  label,
                  _filter == label,
                      () => setState(
                        () => _filter = label,
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _tabs(
      String first,
      String second,
      bool firstSelected,
      void Function(bool) change,
      ) =>
      Row(
        children: [
          for (final label in [
            first,
            second,
          ]) ...[
            if (label != first)
              const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: (label == first) ==
                    firstSelected
                    ? _VaxColor.green
                    : Colors.white,
                borderRadius:
                BorderRadius.circular(12),
                child: InkWell(
                  borderRadius:
                  BorderRadius.circular(12),
                  onTap: () =>
                      change(label == first),
                  child: Container(
                    height: 47,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius:
                      BorderRadius.circular(12),
                      border: Border.all(
                        color: _VaxColor.line,
                      ),
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: (label == first) ==
                            firstSelected
                            ? Colors.white
                            : _VaxColor.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );

  Widget _childList() {
    final query =
    _search.text.trim().toLowerCase();

    final visible = _children.where(
          (c) =>
      query.isEmpty ||
          [
            _vt(c['full_name']),
            _vt(c['guardian_name']),
          ].any(
                (part) => part
                .toLowerCase()
                .contains(query),
          ),
    ).toList();

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,
      children: [
        _hero(
          'Doctor Vaccination',
          'Select a connected child to review records and UIP / IAP schedules.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'Search loaded children',
            prefixIcon: const Icon(
              Icons.search,
              color: _VaxColor.green,
            ),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
              onPressed: _search.clear,
              icon: const Icon(Icons.close),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius:
              BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Search filters loaded profiles only.',
          style: TextStyle(
            color: _VaxColor.muted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 13),
        if (_childrenError != null)
          _errorBox(
            _childrenError!,
                () => _loadChildren(reset: true),
          ),
        if (_loadingChildren || _openingChild)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(
              child: CircularProgressIndicator(
                color: _VaxColor.green,
              ),
            ),
          )
        else if (visible.isEmpty)
          _empty(
            'No connected child profiles match your search.',
          )
        else
          for (final child in visible)
            Padding(
              padding: const EdgeInsets.only(
                bottom: 9,
              ),
              child: Material(
                color: Colors.white,
                borderRadius:
                BorderRadius.circular(14),
                child: InkWell(
                  borderRadius:
                  BorderRadius.circular(14),
                  onTap: _saving
                      ? null
                      : () => _openChild(
                    _vt(child['id']),
                  ),
                  child: Container(
                    padding:
                    const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _VaxColor.line,
                      ),
                      borderRadius:
                      BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor:
                          _VaxColor.mint,
                          child: Icon(
                            Icons.child_care_outlined,
                            color: _VaxColor.green,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                _vt(child['full_name'])
                                    .isEmpty
                                    ? 'Child profile'
                                    : _vt(
                                  child['full_name'],
                                ),
                                maxLines: 1,
                                overflow:
                                TextOverflow.ellipsis,
                                style:
                                const TextStyle(
                                  color: _VaxColor.ink,
                                  fontWeight:
                                  FontWeight.w800,
                                ),
                              ),
                              const SizedBox(
                                height: 4,
                              ),
                              Text(
                                'DOB: ${_vt(child['date_of_birth'])} • '
                                    'Guardian: ${_vt(child['guardian_name'])}',
                                maxLines: 2,
                                overflow:
                                TextOverflow.ellipsis,
                                style:
                                const TextStyle(
                                  color: _VaxColor.muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: _VaxColor.green,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        if (!_loadingChildren &&
            _childPage * _pageSize <
                _childTotal)
          OutlinedButton.icon(
            onPressed: _saving
                ? null
                : () => _loadChildren(
              reset: false,
            ),
            icon: const Icon(
              Icons.expand_more,
            ),
            label: const Text(
              'Load More Children',
            ),
          ),
      ],
    );
  }

  Widget _detailView() => Column(
    crossAxisAlignment:
    CrossAxisAlignment.stretch,
    children: [
      _hero(
        _vt(_child?['full_name']).isEmpty
            ? 'Child Vaccination'
            : _vt(_child?['full_name']),
        'DOB: ${_vt(_child?['date_of_birth'])} • '
            'Guardian: ${_vt(_child?['guardian_name'])}',
      ),
      const SizedBox(height: 12),
      _panel(
        const Text(
          'Routine recommended dates are not administration dates. '
              'Record the date a dose was actually given. '
              'A clinical review does not mark a dose completed.',
          style: TextStyle(
            color: _VaxColor.muted,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ),
      const SizedBox(height: 12),
      _tabs(
        'Recorded Doses',
        'UIP / IAP Plan',
        _tab == 'records',
            (first) => setState(() {
          _tab =
          first ? 'records' : 'plan';
          _filter = 'All';
        }),
      ),
      const SizedBox(height: 13),
      _tab == 'records'
          ? _recordView()
          : _planView(),
    ],
  );

  Widget _recordView() {
    final visible = _records
        .where(_matchRecord)
        .toList();

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _VaxColor.green,
          ),
          onPressed: _saving
              ? null
              : () => _addRecord(),
          icon: const Icon(Icons.add),
          label: const Text(
            'Add Unlisted Vaccination Record',
          ),
        ),
        const SizedBox(height: 12),
        _filtersRow(),
        const SizedBox(height: 12),
        if (_recordsError != null)
          _errorBox(
            _recordsError!,
                () => _loadRecords(reset: true),
          ),
        if (_loadingRecords)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(
              child: CircularProgressIndicator(
                color: _VaxColor.green,
              ),
            ),
          )
        else if (visible.isEmpty)
          _empty(
            'No records match this filter. More records may be available on additional pages.',
          )
        else
          for (final record in visible)
            _recordTile(record),
        if (!_loadingRecords &&
            _recordPage * _pageSize <
                _recordTotal)
          OutlinedButton.icon(
            onPressed: _saving
                ? null
                : () => _loadRecords(
              reset: false,
            ),
            icon: const Icon(
              Icons.expand_more,
            ),
            label: const Text(
              'Load More Records',
            ),
          ),
        const SizedBox(height: 9),
        const Text(
          'Upcoming and Overdue here apply only to saved Planned/Missed records. '
              'Schedule recommendations are in UIP / IAP Plan.',
          style: TextStyle(
            color: _VaxColor.muted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _recordTile(
      Map<String, dynamic> record,
      ) {
    final owned =
        _vt(record['source_role']).toUpperCase() ==
            'DOCTOR' &&
            _vt(record['author_id']) ==
                _doctorId;

    final completed =
        _vt(record['status']).toLowerCase() ==
            'completed';

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 9,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: _VaxColor.line,
          ),
          borderRadius:
          BorderRadius.circular(14),
        ),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(
            completed
                ? Icons.check_circle
                : Icons.vaccines_outlined,
            color: completed
                ? _VaxColor.blue
                : _VaxColor.amber,
          ),
          title: Text(
            _vt(record['title']).isEmpty
                ? 'Vaccination record'
                : _vt(record['title']),
            style: const TextStyle(
              color: _VaxColor.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            'Recorded date: ${_vt(record['date'])} • '
                '${_vt(record['status'])}',
            style: const TextStyle(
              color: _VaxColor.muted,
              fontSize: 11,
            ),
          ),
          childrenPadding:
          const EdgeInsets.fromLTRB(
            15,
            0,
            15,
            12,
          ),
          children: [
            const Divider(
              color: _VaxColor.line,
            ),
            _detail(
              'Author',
              _vt(record['author_name']),
            ),
            _detail(
              'Verification',
              _vt(record['verification_status']),
            ),
            _detail(
              'Provider',
              _vt(record['provider']),
            ),
            _detail(
              'Vaccinator',
              _vt(record['vaccinator']),
            ),
            _detail(
              'Batch',
              _vt(record['batch_number']),
            ),
            _detail(
              'Schedule type',
              _vt(record['schedule_type']),
            ),
            _detail(
              'Dose code',
              _vt(record['dose_code']),
            ),
            _detail(
              'Next date',
              _vt(record['nextDate']),
            ),
            _detail(
              'Notes',
              _vt(record['notes']),
            ),
            if (owned)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _removeRecord(
                    record,
                  ),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: _VaxColor.red,
                  ),
                  label: const Text(
                    'Remove',
                    style: TextStyle(
                      color: _VaxColor.red,
                    ),
                  ),
                ),
              )
            else
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Other author’s record • Read-only',
                  style: TextStyle(
                    color: _VaxColor.muted,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detail(
      String label,
      String value,
      ) =>
      value.isEmpty
          ? const SizedBox.shrink()
          : Padding(
        padding: const EdgeInsets.only(
          top: 7,
        ),
        child: Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                label,
                style: const TextStyle(
                  color: _VaxColor.muted,
                  fontSize: 11,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(
                  color: _VaxColor.ink,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _planView() {
    final schemeData =
    _vm(_plan[_scheme]);

    final visible =
    _vl(schemeData['items'])
        .where(_matchDose)
        .toList();

    final all =
    _vl(schemeData['items']);

    final complete = all
        .where(
          (e) =>
      _vt(e['status']) ==
          'COMPLETED',
    )
        .length;

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,
      children: [
        _tabs(
          'UIP',
          'IAP',
          _scheme == 'UIP',
              (first) => setState(() {
            _scheme = first
                ? 'UIP'
                : 'IAP';
            _filter = 'All';
          }),
        ),
        const SizedBox(height: 12),
        _filtersRow(),
        const SizedBox(height: 12),
        if (_planError != null)
          _errorBox(
            _planError!,
            _loadPlan,
          ),
        if (_loadingPlan)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(
              child: CircularProgressIndicator(
                color: _VaxColor.green,
              ),
            ),
          )
        else if (_planError == null) ...[
          _panel(
            Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  '$_scheme Plan • '
                      '$complete completed of ${all.length}',
                  style: const TextStyle(
                    color: _VaxColor.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _vt(schemeData['message'])
                      .isEmpty
                      ? 'Recommendations come from the active backend schedule.'
                      : _vt(
                    schemeData['message'],
                  ),
                  style: const TextStyle(
                    color: _VaxColor.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          if (visible.isEmpty)
            _empty(
              'No $_scheme doses match this filter. '
                  'Review-required doses are visible under All.',
            )
          else
            for (final dose in visible)
              _doseTile(dose),
        ],
      ],
    );
  }

  Widget _doseTile(
      Map<String, dynamic> dose,
      ) {
    final vaccine =
    _vm(dose['vaccine']);

    final title =
    _vt(vaccine['name_en']);

    final status =
    _vt(dose['status']).toUpperCase();

    final completed =
        status == 'COMPLETED';

    final reasons = dose['reasons'] is List
        ? (dose['reasons'] as List)
        .map(_vt)
        .where(
          (r) => r.isNotEmpty,
    )
        .toList()
        : <String>[];

    final eligible = _canLink(dose);

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 9,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: _VaxColor.line,
          ),
          borderRadius:
          BorderRadius.circular(14),
        ),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(
            completed
                ? Icons.check_circle
                : Icons.vaccines_outlined,
            color: completed
                ? _VaxColor.blue
                : _VaxColor.green,
          ),
          title: Text(
            title.isEmpty
                ? 'Vaccination'
                : title,
            style: const TextStyle(
              color: _VaxColor.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            '${_vt(dose['dose_name'])} • '
                'Recommended: ${_vt(dose['recommended_date'])}\n'
                'Window ends: ${_vt(dose['window_end'])}',
            style: const TextStyle(
              color: _VaxColor.muted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          childrenPadding:
          const EdgeInsets.fromLTRB(
            15,
            0,
            15,
            13,
          ),
          children: [
            const Divider(
              color: _VaxColor.line,
            ),
            _detail(
              'Status',
              _vt(dose['display_status'])
                  .isEmpty
                  ? status
                  : _vt(
                dose['display_status'],
              ),
            ),
            _detail(
              'Actual given date',
              _vt(dose['completed_date']),
            ),
            _detail(
              'Age group',
              _vt(dose['age_label']),
            ),
            _detail(
              'Publication',
              _vt(dose['publication_status']),
            ),
            _detail(
              'Route',
              _vt(dose['route']),
            ),
            _detail(
              'Injection site',
              _vt(dose['injection_site']),
            ),
            _detail(
              'Reference',
              _vt(dose['source_reference']),
            ),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final reason in reasons)
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 4,
                  ),
                  child: Text(
                    '• $reason',
                    style: const TextStyle(
                      color: _VaxColor.amber,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _review(dose),
                  icon: const Icon(
                    Icons.fact_check_outlined,
                    size: 17,
                  ),
                  label: const Text(
                    'Review applicability',
                  ),
                ),
                if (eligible)
                  FilledButton.icon(
                    style:
                    FilledButton.styleFrom(
                      backgroundColor:
                      _VaxColor.green,
                    ),
                    onPressed: _saving
                        ? null
                        : () => _addRecord(
                      dose: dose,
                    ),
                    icon: const Icon(
                      Icons.event_available_outlined,
                      size: 17,
                    ),
                    label: const Text(
                      'Enter given date',
                    ),
                  ),
              ],
            ),
            if (completed)
              const Padding(
                padding: EdgeInsets.only(
                  top: 8,
                ),
                child: Text(
                  'Already completed • An additional Completed entry is blocked.',
                  style: TextStyle(
                    color: _VaxColor.blue,
                    fontSize: 11,
                  ),
                ),
              )
            else if (!eligible)
              const Padding(
                padding: EdgeInsets.only(
                  top: 8,
                ),
                child: Text(
                  'Recording is unavailable for this dose. '
                      'Check the review or prior-dose requirements.',
                  style: TextStyle(
                    color: _VaxColor.muted,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
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
            size: 47,
            color: _VaxColor.blue,
          ),
          const SizedBox(height: 12),
          const Text(
            'Approved Doctor Required',
            style: TextStyle(
              color: _VaxColor.ink,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _authError ??
                'Sign in using an active approved doctor account.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _VaxColor.muted,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor:
              _VaxColor.green,
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
    backgroundColor: _VaxColor.page,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _VaxColor.ink,
      title: Text(
        _child == null
            ? 'Doctor Vaccination'
            : 'Child Vaccination',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 17,
        ),
      ),
      leading: IconButton(
        onPressed: _back,
        icon: const Icon(
          Icons.arrow_back_rounded,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed:
          _authorized && !_saving
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
      child:
      CircularProgressIndicator(
        color: _VaxColor.green,
      ),
    )
        : !_authorized
        ? _blocked()
        : RefreshIndicator(
      onRefresh: _refresh,
      color: _VaxColor.green,
      child: ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding:
        const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          29,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 950,
              ),
              child: _child == null
                  ? _childList()
                  : _detailView(),
            ),
          ),
        ],
      ),
    ),
  );
}

class _VaxRecordEditor extends StatefulWidget {
  const _VaxRecordEditor({
    required this.child,
    required this.onSave,
    this.dose,
  });

  final Map<String, dynamic> child;
  final Map<String, dynamic>? dose;
  final Future<void> Function(
      Map<String, dynamic>,
      ) onSave;

  @override
  State<_VaxRecordEditor> createState() =>
      _VaxRecordEditorState();
}

class _VaxRecordEditorState
    extends State<_VaxRecordEditor> {
  final _form = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _provider = TextEditingController();
  final _vaccinator = TextEditingController();
  final _batch = TextEditingController();
  final _notes = TextEditingController();

  DateTime? _givenDate;
  DateTime? _nextDate;

  String _status = 'Completed';

  bool _saving = false;
  String? _error;

  bool get _linked => widget.dose != null;

  @override
  void initState() {
    super.initState();

    if (widget.dose != null) {
      final vaccine =
      _vm(widget.dose?['vaccine']);

      _name.text = [
        _vt(vaccine['name_en']),
        _vt(widget.dose?['dose_name']),
      ].where(
            (p) => p.isNotEmpty,
      ).join(' • ');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _provider.dispose();
    _vaccinator.dispose();
    _batch.dispose();
    _notes.dispose();

    super.dispose();
  }

  Future<void> _chooseDate({
    bool next = false,
  }) async {
    final today =
    DateUtils.dateOnly(DateTime.now());

    final dob = _parsedDay(
      widget.child['date_of_birth'],
    );

    final first = dob != null &&
        !dob.isAfter(today)
        ? DateUtils.dateOnly(dob)
        : DateTime(1900);

    final last = next ||
        (_status != 'Completed' &&
            !_linked)
        ? DateTime(
      today.year + 15,
      12,
      31,
    )
        : today;

    final old =
    next ? _nextDate : _givenDate;

    final initial = old != null &&
        !old.isBefore(first) &&
        !old.isAfter(last)
        ? old
        : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: next
          ? 'Optional next documented date'
          : 'Actual vaccination / record date',
    );

    if (!mounted || picked == null) return;

    setState(() {
      if (next) {
        _nextDate = picked;
      } else {
        _givenDate = picked;
      }

      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving ||
        !(_form.currentState?.validate() ??
            false)) {
      return;
    }

    if (_givenDate == null) {
      setState(() {
        _error =
        'Choose an actual administration or record date.';
      });
      return;
    }

    final today =
    DateUtils.dateOnly(DateTime.now());

    if ((_linked ||
        _status == 'Completed') &&
        _givenDate!.isAfter(today)) {
      setState(() {
        _error =
        'A completed dose cannot have a future date.';
      });
      return;
    }

    final dob = _parsedDay(
      widget.child['date_of_birth'],
    );

    if (dob != null &&
        _givenDate!.isBefore(
          DateUtils.dateOnly(dob),
        )) {
      setState(() {
        _error =
        'Record date cannot be before birth.';
      });
      return;
    }

    if (_nextDate != null &&
        _nextDate!.isBefore(_givenDate!)) {
      setState(() {
        _error =
        'Next date must be on or after the record date.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.onSave({
        'title': _name.text.trim(),
        'date': _vd(_givenDate!),
        'status': _linked
            ? 'Completed'
            : _status,
        'provider': _provider.text.trim(),
        'vaccinator':
        _vaccinator.text.trim(),
        'batch_number':
        _batch.text.trim(),
        'notes': _notes.text.trim(),
        if (_nextDate != null)
          'nextDate': _vd(_nextDate!),
        if (_linked)
          'schedule_id':
          widget.dose!['id'],
      });

      if (mounted) {
        Navigator.pop(
          context,
          true,
        );
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is _VaxError
            ? error.status == 409
            ? '${error.message}\n'
            'Refresh the plan and check the existing Completed record.'
            : error.message
            : error is TimeoutException
            ? 'Save timed out. Check the existing records before retrying to avoid duplicates.'
            : 'Could not save the record. Please retry.';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _field(
      String label,
      TextEditingController controller, {
        bool isRequired = false,
        int max = 160,
        int lines = 1,
      }) =>
      Padding(
        padding: const EdgeInsets.only(
          bottom: 11,
        ),
        child: TextFormField(
          enabled: !_saving,
          controller: controller,
          maxLength: max,
          maxLines: lines,
          decoration: InputDecoration(
            labelText: label,
            counterText: '',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius:
              BorderRadius.circular(12),
            ),
          ),
          validator: (value) =>
          isRequired &&
              (value ?? '')
                  .trim()
                  .isEmpty
              ? '$label is required'
              : null,
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      17,
      8,
      17,
      MediaQuery.viewInsetsOf(context)
          .bottom +
          19,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
          CrossAxisAlignment.stretch,
          children: [
            Text(
              _linked
                  ? 'Record Scheduled Dose'
                  : 'Unlisted Vaccination Record',
              style: const TextStyle(
                color: _VaxColor.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Child: ${_vt(widget.child['full_name'])}',
              style: const TextStyle(
                color: _VaxColor.muted,
                fontSize: 12,
              ),
            ),
            if (_linked) ...[
              const SizedBox(
                height: 10,
              ),
              Text(
                'Recommended: ${_vt(widget.dose?['recommended_date'])} • '
                    'Window ends: ${_vt(widget.dose?['window_end'])}',
                style: const TextStyle(
                  color: _VaxColor.blue,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter when this dose was actually administered. '
                    'Recommended dates are never saved as actual dates automatically.',
                style: TextStyle(
                  color: _VaxColor.muted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _field(
              'Vaccine / dose name',
              _name,
              isRequired: true,
            ),
            if (!_linked) ...[
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration:
                const InputDecoration(
                  labelText:
                  'Record status',
                  border:
                  OutlineInputBorder(),
                ),
                items: const [
                  'Completed',
                  'Planned',
                  'Missed',
                  'Review pending',
                ]
                    .map(
                      (s) =>
                      DropdownMenuItem(
                        value: s,
                        child: Text(s),
                      ),
                )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) =>
                    setState(() {
                      _status = value ??
                          'Completed';

                      if (_status ==
                          'Completed' &&
                          _givenDate !=
                              null &&
                          _givenDate!
                              .isAfter(
                            DateUtils
                                .dateOnly(
                              DateTime
                                  .now(),
                            ),
                          )) {
                        _givenDate =
                        null;
                      }
                    }),
              ),
              const SizedBox(height: 11),
            ],
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () => _chooseDate(),
              icon: const Icon(
                Icons.calendar_month_outlined,
              ),
              label: Text(
                _givenDate == null
                    ? 'Select actual / record date'
                    : 'Actual / record date: ${_vd(_givenDate!)}',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () => _chooseDate(
                next: true,
              ),
              icon: const Icon(
                Icons.event_outlined,
              ),
              label: Text(
                _nextDate == null
                    ? 'Add next documented date (optional)'
                    : 'Next documented date: ${_vd(_nextDate!)}',
              ),
            ),
            if (_nextDate != null)
              Align(
                alignment:
                Alignment.centerRight,
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(
                        () =>
                    _nextDate =
                    null,
                  ),
                  child: const Text(
                    'Clear next date',
                  ),
                ),
              ),
            const SizedBox(height: 10),
            _field(
              'Provider (optional)',
              _provider,
            ),
            _field(
              'Vaccinator (optional)',
              _vaccinator,
            ),
            _field(
              'Batch number (optional)',
              _batch,
              max: 100,
            ),
            _field(
              'Notes (optional)',
              _notes,
              max: 2000,
              lines: 3,
            ),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(
                  color: _VaxColor.red,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              style:
              FilledButton.styleFrom(
                backgroundColor:
                _VaxColor.green,
                minimumSize:
                const Size.fromHeight(
                  48,
                ),
              ),
              onPressed:
              _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                width: 16,
                height: 16,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(
                Icons.save_outlined,
              ),
              label: Text(
                _saving
                    ? 'Saving...'
                    : 'Save Vaccination Record',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Only document a completed dose when administration is confirmed from clinical evidence. '
                  'Duplicate linked Completed doses are rejected by the backend.',
              style: TextStyle(
                color: _VaxColor.muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _VaxReviewEditor
    extends StatefulWidget {
  const _VaxReviewEditor({
    required this.dose,
    required this.onSave,
  });

  final Map<String, dynamic> dose;

  final Future<void> Function(
      Map<String, dynamic>,
      ) onSave;

  @override
  State<_VaxReviewEditor> createState() =>
      _VaxReviewEditorState();
}

class _VaxReviewEditorState
    extends State<_VaxReviewEditor> {
  final _reason = TextEditingController();

  String _decision = 'CONFIRM';

  bool _attested = false;
  bool _saving = false;

  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    if (_reason.text.trim().length < 20) {
      setState(() {
        _error =
        'Enter at least 20 characters of clinical reasoning.';
      });
      return;
    }

    if (!_attested) {
      setState(() {
        _error =
        'Professional attestation is required.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.onSave({
        'schedule_id':
        widget.dose['id'],
        'decision': _decision,
        'notes': _reason.text.trim(),
        'attestation': true,
      });

      if (mounted) {
        Navigator.pop(
          context,
          true,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is _VaxError
              ? error.message
              : 'Could not save the review. Please retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    final vaccine =
    _vm(widget.dose['vaccine']);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        17,
        8,
        17,
        MediaQuery.viewInsetsOf(context)
            .bottom +
            20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
          CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Clinical Applicability Review',
              style: TextStyle(
                color: _VaxColor.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${_vt(vaccine['name_en'])} • '
                  '${_vt(widget.dose['dose_name'])}',
              style: const TextStyle(
                color: _VaxColor.green,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This review changes child-specific applicability only. '
                  'It does not create a vaccination record or alter a routine date.',
              style: TextStyle(
                color: _VaxColor.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 13),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'CONFIRM',
                  label: Text('Applicable'),
                  icon: Icon(
                    Icons.check_circle_outline,
                  ),
                ),
                ButtonSegment(
                  value: 'NOT_APPLICABLE',
                  label: Text(
                    'Not applicable',
                  ),
                  icon: Icon(
                    Icons.block_outlined,
                  ),
                ),
              ],
              selected: {
                _decision,
              },
              onSelectionChanged: _saving
                  ? null
                  : (values) => setState(
                    () => _decision =
                    values.first,
              ),
            ),
            const SizedBox(height: 13),
            TextField(
              controller: _reason,
              enabled: !_saving,
              maxLength: 2000,
              maxLines: 4,
              decoration: InputDecoration(
                labelText:
                'Clinical reasoning (min. 20 characters)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                ),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity:
              ListTileControlAffinity.leading,
              value: _attested,
              onChanged: _saving
                  ? null
                  : (value) => setState(
                    () => _attested =
                    value ?? false,
              ),
              title: const Text(
                'I attest that I have reviewed the relevant clinical context.',
                style: TextStyle(
                  color: _VaxColor.ink,
                  fontSize: 12,
                ),
              ),
            ),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(
                  color: _VaxColor.red,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor:
                _VaxColor.green,
                minimumSize:
                const Size.fromHeight(48),
              ),
              onPressed:
              _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                height: 16,
                width: 16,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(
                Icons.fact_check_outlined,
              ),
              label: Text(
                _saving
                    ? 'Saving...'
                    : 'Save Clinical Review',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
