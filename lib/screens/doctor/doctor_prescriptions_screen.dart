
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

class DoctorPrescriptionsScreen extends StatefulWidget {
  const DoctorPrescriptionsScreen({
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
  State<DoctorPrescriptionsScreen> createState() =>
      _DoctorPrescriptionsScreenState();
}

class _RxTheme {
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

class _RxError implements Exception {
  const _RxError(this.message, [this.status]);
  final String message;
  final int? status;

  @override
  String toString() => message;
}

String _rxText(dynamic v) => (v ?? '').toString().trim();

Map<String, dynamic> _rxMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _rxRows(dynamic v) => v is List
    ? v.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
    : <Map<String, dynamic>>[];

int _rxInt(dynamic v, [int fallback = 0]) =>
    v is num ? v.toInt() : int.tryParse(_rxText(v)) ?? fallback;

String _rxDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

String _rxDateTime(dynamic value) {
  final date = DateTime.tryParse(_rxText(value))?.toLocal();
  if (date == null) return 'Date unavailable';
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _DoctorPrescriptionsScreenState
    extends State<DoctorPrescriptionsScreen> {
  static const _pageSize = 20;

  final _client = http.Client();
  final _search = TextEditingController();

  bool _checking = true;
  bool _verified = false;
  bool _loadingProfiles = false;
  bool _loadingItems = false;
  bool _working = false;

  String? _authError;
  String? _profilesError;
  String? _rxError;
  String? _legacyError;

  String _moduleFilter = 'all';
  String _statusFilter = 'ALL';
  String _section = 'structured';

  int _childPage = 0;
  int _childTotal = 0;
  int _revision = 0;
  int _listRevision = 0;
  int _selectionRevision = 0;

  List<Map<String, dynamic>> _children = [];
  List<Map<String, dynamic>> _adults = [];
  List<Map<String, dynamic>> _women = [];
  List<Map<String, dynamic>> _prescriptions = [];
  List<Map<String, dynamic>> _legacy = [];

  Map<String, dynamic>? _selected;

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

  String get _id => _rxText(_selected?['id']);
  String get _module => _rxText(_selected?['module']).toLowerCase();

  bool get _canEdit {
    if (_selected == null) return false;

    if (_module == 'child') return true;

    final permissions = _rxMap(_selected?['permissions']);

    if (_module == 'adult') {
      return permissions['reports'] == 'edit';
    }

    if (_module == 'women') {
      return permissions['records'] == 'edit';
    }

    return false;
  }

  bool get _canRead {
    if (_selected == null) return false;

    if (_module == 'child') return true;

    final permissions = _rxMap(_selected?['permissions']);

    if (_module == 'adult') {
      return const {'view', 'edit'}.contains(permissions['reports']);
    }

    if (_module == 'women') {
      return const {'view', 'edit'}.contains(permissions['records']);
    }

    return false;
  }

  bool get _legacyAvailable =>
      _module == 'child' ||
          (_module == 'adult' &&
              const {'view', 'edit'}.contains(
                _rxMap(_selected?['permissions'])['medicine'],
              ));

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
    _verify();
  }

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant DoctorPrescriptionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _verify();
      return;
    }

    final oldId = _rxText(
      (oldWidget.initialProfile ?? oldWidget.initialChild)?['id'],
    );

    final newId = _rxText(
      (widget.initialProfile ?? widget.initialChild)?['id'],
    );

    if (oldId != newId && _verified) {
      if (newId.isEmpty) {
        _goProfiles();
      } else {
        _selectProfile(widget.initialProfile ?? widget.initialChild!);
      }
    }
  }

  @override
  void dispose() {
    _revision++;
    _listRevision++;
    _selectionRevision++;
    _search.dispose();
    _client.close();
    super.dispose();
  }

  String _friendly(Object error) {
    if (error is _RxError) return error.message;

    if (error is TimeoutException) {
      return 'Request timed out. Check your connection.';
    }

    if (error is http.ClientException) {
      return 'Cannot connect to FamilyCare+.';
    }

    if (error is FormatException) {
      return 'Invalid server response.';
    }

    if (error is StateError) {
      return error.message.toString();
    }

    return 'Unable to complete the request. Please retry.';
  }

  void _notice(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? _RxTheme.danger : _RxTheme.ink,
          content: Text(message),
        ),
      );
  }

  Future<Map<String, dynamic>> _api(
      String method,
      String path, {
        Map<String, String>? query,
        Map<String, dynamic>? body,
      }) async {
    final role = await FamilyCareSession.role();
    final token = await FamilyCareSession.accessToken();
    final expiry = await FamilyCareSession.accessTokenExpiresAt();

    if (_rxText(role).toUpperCase() != 'DOCTOR' ||
        token == null ||
        token.isEmpty ||
        expiry == null ||
        !expiry.isAfter(DateTime.now().toUtc())) {
      throw const _RxError(
        'Doctor session expired. Please sign in again.',
        401,
      );
    }

    final url = Uri.parse('$_base$path').replace(
      queryParameters: query,
    );

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };

    final http.Response response;

    if (method == 'POST') {
      response = await _client
          .post(
        url,
        headers: headers,
        body: jsonEncode(body ?? {}),
      )
          .timeout(const Duration(seconds: 30));
    } else if (method == 'PUT') {
      response = await _client
          .put(
        url,
        headers: headers,
        body: jsonEncode(body ?? {}),
      )
          .timeout(const Duration(seconds: 30));
    } else {
      response = await _client
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));
    }

    Map<String, dynamic> decoded = {};

    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = _rxMap(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
      } catch (_) {
        if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          throw const FormatException('Invalid response JSON.');
        }
      }
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final issue = decoded['error'];
      final server = issue is Map
          ? _rxText(issue['message'])
          : _rxText(issue);

      final message = switch (response.statusCode) {
        401 => 'Session expired. Please sign in again.',
        403 => 'Permission is missing, expired or read-only.',
        404 => 'Profile or prescription is no longer available.',
        409 => 'Prescription changed or cannot be modified. Refresh first.',
        422 => 'Check all required medicine fields and dates.',
        _ => 'Request failed (HTTP ${response.statusCode}).',
      };

      throw _RxError(
        server.isNotEmpty ? server : message,
        response.statusCode,
      );
    }

    return decoded;
  }

  void _accessLost(String message) {
    _revision++;
    _listRevision++;
    _selectionRevision++;

    if (!mounted) return;

    setState(() {
      _checking = false;
      _verified = false;
      _authError = message;
      _children = [];
      _adults = [];
      _women = [];
      _selected = null;
      _prescriptions = [];
      _legacy = [];
    });
  }

  Future<void> _verify() async {
    final version = ++_revision;

    _listRevision++;
    _selectionRevision++;

    setState(() {
      _checking = true;
      _verified = false;
      _authError = null;
      _selected = null;
      _prescriptions = [];
      _legacy = [];
      _children = [];
      _adults = [];
      _women = [];
      _childPage = 0;
      _childTotal = 0;
      _loadingProfiles = false;
      _loadingItems = false;
    });

    try {
      final result = await _api(
        'GET',
        '/api/v1/doctors/me',
      );

      final user = _rxMap(result['user']);

      if (_rxText(user['role']).toUpperCase() != 'DOCTOR' ||
          _rxText(user['approval_status']).toUpperCase() != 'APPROVED' ||
          _rxText(user['account_status']).toUpperCase() != 'ACTIVE') {
        throw const _RxError(
          'Only approved active doctors can use prescriptions.',
          403,
        );
      }

      if (!mounted || version != _revision) return;

      setState(() {
        _checking = false;
        _verified = true;
      });

      final initial = widget.initialProfile ?? widget.initialChild;

      if (_rxText(initial?['id']).isNotEmpty) {
        await _selectProfile(initial!);
      } else {
        await _loadProfiles(reset: true);
      }
    } catch (error) {
      if (!mounted || version != _revision) return;
      _accessLost(_friendly(error));
    }
  }

  Future<void> _loadProfiles({required bool reset}) async {
    if (!_verified || _loadingProfiles) return;

    final version = ++_listRevision;
    final page = reset ? 1 : _childPage + 1;

    setState(() {
      _loadingProfiles = true;
      _profilesError = null;

      if (reset) {
        _children = [];
        _adults = [];
        _women = [];
        _childPage = 0;
        _childTotal = 0;
      }
    });

    try {
      final childrenResponse = await _api(
        'GET',
        '/api/v1/doctors/care-profiles',
        query: {
          'module': 'child',
          'page': '$page',
          'per_page': '$_pageSize',
        },
      );

      if (childrenResponse['items'] is! List) {
        throw const FormatException('Invalid child profile list.');
      }

      final incoming = _rxRows(childrenResponse['items']);

      List<Map<String, dynamic>> adults = _adults;
      List<Map<String, dynamic>> women = _women;
      final issues = <String>[];

      if (reset) {
        try {
          final response = await _api(
            'GET',
            '/api/v1/adult-access/shared',
          );

          adults = _rxRows(response['items'])
              .map(
                (e) => {
              ...e,
              'module': 'adult',
              'full_name': _rxText(e['name']),
            },
          )
              .toList();
        } catch (error) {
          issues.add('Adult: ${_friendly(error)}');
        }

        try {
          final response = await _api(
            'GET',
            '/api/v1/women/shared',
          );

          women = _rxRows(response['items'])
              .map(
                (e) => {
              ...e,
              'module': 'women',
              'full_name': _rxText(e['name']),
            },
          )
              .toList();
        } catch (error) {
          issues.add('Women: ${_friendly(error)}');
        }
      }

      if (!mounted || version != _listRevision) return;

      setState(() {
        final seen = <String>{};

        _children = [
          if (!reset) ..._children,
          ...incoming,
        ]
            .where(
              (e) =>
          _rxText(e['id']).isNotEmpty &&
              seen.add(_rxText(e['id'])),
        )
            .toList();

        _adults = adults;
        _women = women;
        _childPage = page;
        _childTotal = _rxInt(
          childrenResponse['total'],
          _children.length,
        );

        if (issues.isNotEmpty) {
          _profilesError = issues.join(' • ');
        }
      });
    } catch (error) {
      if (mounted && version == _listRevision) {
        if (error is _RxError && error.status == 401) {
          _accessLost(_friendly(error));
        } else {
          setState(() => _profilesError = _friendly(error));
        }
      }
    } finally {
      if (mounted && version == _listRevision) {
        setState(() => _loadingProfiles = false);
      }
    }
  }

  List<Map<String, dynamic>> get _visibleProfiles {
    final query = _search.text.toLowerCase().trim();

    final candidates = <Map<String, dynamic>>[
      ..._children,
      ..._adults.where((p) {
        final permissions = _rxMap(p['permissions']);

        return const {'view', 'edit'}.contains(permissions['reports']) ||
            const {'view', 'edit'}.contains(permissions['medicine']);
      }),
      ..._women.where(
            (p) => const {'view', 'edit'}.contains(
          _rxMap(p['permissions'])['records'],
        ),
      ),
    ];

    return candidates.where((profile) {
      if (_moduleFilter != 'all' &&
          _rxText(profile['module']) != _moduleFilter) {
        return false;
      }

      return query.isEmpty ||
          [
            _rxText(profile['full_name']),
            _rxText(profile['module']),
            _rxText(profile['guardian_name']),
          ].any(
                (value) => value.toLowerCase().contains(query),
          );
    }).toList();
  }

  Future<Map<String, dynamic>> _freshProfile(
      Map<String, dynamic> profile,
      ) async {
    final id = _rxText(profile['id']);
    final module = _rxText(profile['module']).toLowerCase();

    if (id.isEmpty) {
      throw const _RxError('Invalid care profile.');
    }

    if (module == 'child') {
      final result = await _api(
        'GET',
        '/api/v1/doctors/care-profiles/${Uri.encodeComponent(id)}',
      );

      return _rxMap(result['profile']);
    }

    if (module == 'adult' || module == 'women') {
      final path = module == 'adult'
          ? '/api/v1/adult-access'
          : '/api/v1/women';

      final result = await _api(
        'GET',
        '$path/profiles/${Uri.encodeComponent(id)}/workspace',
      );

      final meta = _rxMap(result['profile']);

      return {
        ...profile,
        'full_name': _rxText(meta['name']).isNotEmpty
            ? meta['name']
            : profile['full_name'],
        'date_of_birth': meta['dob'],
        'permissions': _rxMap(result['permissions']),
        'access_expires_at': result['access_expires_at'],
      };
    }

    throw const _RxError('Unsupported care module.');
  }

  Future<void> _selectProfile(
      Map<String, dynamic> profile,
      ) async {
    if (!_verified || _working) return;

    final version = ++_selectionRevision;
    final id = _rxText(profile['id']);

    setState(() {
      _loadingItems = true;
      _selected = null;
      _prescriptions = [];
      _legacy = [];
      _rxError = null;
      _legacyError = null;
      _section = 'structured';
      _statusFilter = 'ALL';
      _search.clear();
    });

    try {
      final fresh = await _freshProfile(profile);

      if (!mounted || version != _selectionRevision) return;

      setState(() {
        _selected = fresh;
        if (!_canRead && _legacyAvailable) {
          _section = 'legacy';
        }
      });

      await _loadSelected(version);
    } catch (error) {
      if (!mounted || version != _selectionRevision) return;

      setState(() {
        _selected = null;
        _prescriptions = [];
        _legacy = [];
        _profilesError = _friendly(error);
      });

      _notice(_friendly(error), error: true);
    } finally {
      if (mounted && version == _selectionRevision) {
        setState(() => _loadingItems = false);
      }
    }
  }

  Future<void> _loadSelected(int version) async {
    final id = _id;
    if (id.isEmpty) return;

    setState(() {
      _loadingItems = true;
      _rxError = null;
      _legacyError = null;
      _prescriptions = [];
      _legacy = [];
    });

    try {
      if (_canRead) {
        try {
          final result = await _api(
            'GET',
            '/api/v1/doctors/care-profiles/${Uri.encodeComponent(id)}/prescriptions',
          );

          if (result['items'] is! List) {
            throw const FormatException('Invalid prescription list.');
          }

          if (mounted &&
              version == _selectionRevision &&
              id == _id) {
            setState(() {
              _prescriptions = _rxRows(result['items']);
            });
          }
        } catch (error) {
          if (mounted && version == _selectionRevision) {
            setState(() => _rxError = _friendly(error));
          }
        }
      }

      if (_legacyAvailable) {
        try {
          if (_module == 'child') {
            final response = await _api(
              'GET',
              '/api/v1/doctors/care-profiles/${Uri.encodeComponent(id)}/child-records/prescription',
              query: {
                'page': '1',
                'per_page': '100',
              },
            );

            if (response['items'] is! List) {
              throw const FormatException('Invalid care notes.');
            }

            if (mounted &&
                version == _selectionRevision &&
                id == _id) {
              setState(() {
                _legacy = _rxRows(response['items']);
              });
            }
          } else {
            final result = await _api(
              'GET',
              '/api/v1/adult-access/profiles/${Uri.encodeComponent(id)}/workspace',
            );

            if (mounted &&
                version == _selectionRevision &&
                id == _id) {
              setState(() {
                _legacy = _rxRows(result['records'])
                    .where(
                      (record) =>
                  _rxText(record['kind']) == 'medicine',
                )
                    .toList();
              });
            }
          }
        } catch (error) {
          if (mounted && version == _selectionRevision) {
            setState(() => _legacyError = _friendly(error));
          }
        }
      }
    } finally {
      if (mounted && version == _selectionRevision) {
        setState(() => _loadingItems = false);
      }
    }
  }

  Future<void> _refreshSelected() async {
    if (!_verified ||
        _working ||
        _selected == null) {
      return;
    }

    final version = ++_selectionRevision;
    final old = Map<String, dynamic>.from(_selected!);

    setState(() {
      _loadingItems = true;
      _prescriptions = [];
      _legacy = [];
    });

    try {
      final fresh = await _freshProfile(old);

      if (!mounted || version != _selectionRevision) return;

      setState(() {
        _selected = fresh;
        if (!_canRead && _legacyAvailable) {
          _section = 'legacy';
        }
      });

      await _loadSelected(version);
    } catch (error) {
      if (!mounted || version != _selectionRevision) return;

      if (error is _RxError && error.status == 401) {
        _accessLost(_friendly(error));
      } else {
        _goProfiles();
        _notice(_friendly(error), error: true);
      }
    } finally {
      if (mounted && version == _selectionRevision) {
        setState(() => _loadingItems = false);
      }
    }
  }

  void _goProfiles() {
    _selectionRevision++;

    setState(() {
      _selected = null;
      _prescriptions = [];
      _legacy = [];
      _search.clear();
      _statusFilter = 'ALL';
      _loadingItems = false;
    });

    if (_children.isEmpty &&
        _adults.isEmpty &&
        _women.isEmpty) {
      _loadProfiles(reset: true);
    }
  }

  void _back() {
    if (_selected != null) {
      _goProfiles();
    } else if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _refresh() async {
    if (_selected != null) {
      await _refreshSelected();
    } else if (_verified) {
      await _loadProfiles(reset: true);
    } else {
      await _verify();
    }
  }

  String _rxPath(String profileId) =>
      '/api/v1/doctors/care-profiles/${Uri.encodeComponent(profileId)}/prescriptions';

  Future<void> _editDraft([
    Map<String, dynamic>? existing,
  ]) async {
    if (!_verified ||
        !_canEdit ||
        _working ||
        _selected == null) {
      return;
    }

    final profile = Map<String, dynamic>.from(_selected!);
    final id = _id;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => _StructuredRxEditor(
          patientName: _rxText(profile['full_name']),
          existing: existing,
          onSave: (data) async {
            final fresh = await _freshProfile(profile);
            final rights = _rxMap(fresh['permissions']);
            final module = _rxText(fresh['module']);

            final allowed = module == 'child' ||
                (module == 'adult' &&
                    rights['reports'] == 'edit') ||
                (module == 'women' &&
                    rights['records'] == 'edit');

            if (!allowed) {
              throw const _RxError(
                'Prescription edit permission is no longer active.',
                403,
              );
            }

            final oldId = _rxText(existing?['id']);

            final result = await _api(
              oldId.isEmpty ? 'POST' : 'PUT',
              oldId.isEmpty
                  ? _rxPath(id)
                  : '${_rxPath(id)}/${Uri.encodeComponent(oldId)}',
              body: data,
            );

            if (_rxText(
              _rxMap(result['prescription'])['id'],
            ).isEmpty) {
              throw const FormatException(
                'Draft save was not confirmed.',
              );
            }
          },
        ),
      ),
    );

    if (saved == true &&
        mounted &&
        id == _id) {
      _notice(
        existing == null ? 'Draft created.' : 'Draft updated.',
      );
      await _refreshSelected();
    }
  }

  Future<void> _decision(
      Map<String, dynamic> rx,
      String action,
      ) async {
    if (_working || !_canEdit || !_verified) return;

    final rxId = _rxText(rx['id']);
    final profileId = _id;
    final version = _rxInt(rx['version']);

    if (rxId.isEmpty || version < 1) {
      _notice(
        'Invalid prescription version. Refresh first.',
        error: true,
      );
      return;
    }

    var reason = '';
    var attested = false;

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            action == 'ISSUE'
                ? 'Issue prescription?'
                : 'Void issued prescription?',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  action == 'ISSUE'
                      ? 'Review medicines and patient details before issuing. '
                      'An issued prescription cannot be edited. '
                      'Your medical registration number must be on file.'
                      : 'Voiding preserves the issued document and records your reason. '
                      'It does not delete the prescription.',
                ),
                if (action == 'VOID') ...[
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    maxLength: 1000,
                    maxLines: 3,
                    onChanged: (value) {
                      setDialogState(() => reason = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Reason for voiding',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: attested,
                  controlAffinity:
                  ListTileControlAffinity.leading,
                  title: const Text(
                    'I have reviewed and clinically authorized this action.',
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      attested = value ?? false;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Back'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: action == 'VOID'
                    ? _RxTheme.danger
                    : _RxTheme.green,
              ),
              onPressed: !attested ||
                  (action == 'VOID' &&
                      reason.trim().isEmpty)
                  ? null
                  : () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(
                action == 'ISSUE' ? 'Issue' : 'Void',
              ),
            ),
          ],
        ),
      ),
    );

    if (approved != true ||
        !mounted ||
        profileId != _id) {
      return;
    }

    setState(() => _working = true);

    try {
      final fresh = await _freshProfile(_selected!);
      final permissions = _rxMap(fresh['permissions']);
      final module = _rxText(fresh['module']);

      if (!(module == 'child' ||
          (module == 'adult' &&
              permissions['reports'] == 'edit') ||
          (module == 'women' &&
              permissions['records'] == 'edit'))) {
        throw const _RxError(
          'Edit permission expired or revoked.',
          403,
        );
      }

      final result = await _api(
        'POST',
        '${_rxPath(profileId)}/${Uri.encodeComponent(rxId)}/decision',
        body: {
          'action': action,
          'version': version,
          'attestation': true,
          if (action == 'VOID') 'reason': reason.trim(),
        },
      );

      final saved = _rxMap(result['prescription']);

      if (_rxText(saved['id']) != rxId ||
          _rxText(saved['status']).toUpperCase() !=
              (action == 'ISSUE' ? 'ISSUED' : 'VOID')) {
        throw const FormatException(
          'Server did not confirm this decision.',
        );
      }

      _notice(
        action == 'ISSUE'
            ? 'Prescription issued.'
            : 'Prescription voided.',
      );
    } catch (error) {
      _notice(_friendly(error), error: true);

      if (error is _RxError &&
          error.status == 401) {
        _accessLost(_friendly(error));
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }

      if (mounted &&
          _verified &&
          _selected != null) {
        await _refreshSelected();
      }
    }
  }

  Future<void> _addLegacy() async {
    if (!_verified ||
        _module != 'child' ||
        _selected == null ||
        _working) {
      return;
    }

    final profile = Map<String, dynamic>.from(_selected!);
    final id = _id;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => _LegacyRxEditor(
          child: profile,
          onSave: (payload) async {
            await _freshProfile(profile);

            final result = await _api(
              'POST',
              '/api/v1/doctors/care-profiles/${Uri.encodeComponent(id)}/child-records/prescription',
              body: payload,
            );

            if (_rxMap(result['record']).isEmpty) {
              throw const FormatException(
                'Save not confirmed.',
              );
            }
          },
        ),
      ),
    );

    if (saved == true &&
        mounted &&
        id == _id) {
      _notice('Child care instructions saved.');
      await _refreshSelected();
    }
  }

  List<Map<String, dynamic>> get _visibleRx {
    final query = _search.text.trim().toLowerCase();

    return _prescriptions.where((rx) {
      if (_statusFilter != 'ALL' &&
          _rxText(rx['status']).toUpperCase() !=
              _statusFilter) {
        return false;
      }

      final data = _rxMap(rx['data']);
      final medicines = _rxRows(data['medicines']);

      return query.isEmpty ||
          [
            _rxText(rx['doctor_name']),
            _rxText(rx['status']),
            _rxText(data['instructions']),
            ...medicines.map(
                  (medicine) => _rxText(medicine['name']),
            ),
          ].any(
                (value) => value.toLowerCase().contains(query),
          );
    }).toList();
  }

  Widget _panel(
      Widget child, {
        EdgeInsetsGeometry? padding,
      }) =>
      Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: _RxTheme.border,
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: child,
      );

  Widget _banner(
      String title,
      String subtitle,
      ) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              _RxTheme.mint,
              _RxTheme.ice,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _RxTheme.border,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.medication_outlined,
              size: 30,
              color: _RxTheme.green,
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
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: _RxTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: _RxTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _errorCard(
      String value,
      VoidCallback retry,
      ) =>
      _panel(
        Row(
          children: [
            const Icon(
              Icons.error_outline,
              color: _RxTheme.danger,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: _RxTheme.danger,
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
      );

  Widget _empty(
      String title,
      String message,
      ) =>
      _panel(
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 25,
            horizontal: 12,
          ),
          child: Column(
            children: [
              const Icon(
                Icons.folder_open_outlined,
                color: _RxTheme.blue,
                size: 35,
              ),
              const SizedBox(height: 9),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _RxTheme.ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: _RxTheme.muted,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _chip(
      String label,
      bool selected,
      VoidCallback action,
      ) =>
      ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => action(),
        backgroundColor: Colors.white,
        selectedColor: _RxTheme.mint,
        side: const BorderSide(
          color: _RxTheme.border,
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected
              ? _RxTheme.green
              : _RxTheme.muted,
        ),
      );

  Widget _searchField(String hint) => TextField(
    controller: _search,
    decoration: InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: const Icon(
        Icons.search,
        color: _RxTheme.green,
      ),
      suffixIcon: _search.text.isEmpty
          ? null
          : IconButton(
        onPressed: _search.clear,
        icon: const Icon(Icons.close),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: _RxTheme.border,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: _RxTheme.green,
        ),
      ),
    ),
  );

  Widget _profileTile(Map<String, dynamic> profile) {
    final module = _rxText(profile['module']);

    final icon = module == 'child'
        ? Icons.child_care_outlined
        : module == 'women'
        ? Icons.female_outlined
        : Icons.monitor_heart_outlined;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _loadingItems
              ? null
              : () => _selectProfile(profile),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _RxTheme.border,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _RxTheme.ice,
                  child: Icon(
                    icon,
                    color: _RxTheme.blue,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        _rxText(profile['full_name']).isEmpty
                            ? 'Care profile'
                            : _rxText(profile['full_name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _RxTheme.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        module == 'child'
                            ? 'Child'
                            : module == 'women'
                            ? 'Women’s Health'
                            : 'Adult Health',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _RxTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _RxTheme.green,
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
      _banner(
        'Prescriptions',
        'Doctor-authored prescriptions and shared medicine history',
      ),
      const SizedBox(height: 13),
      _panel(
        const Text(
          'Structured prescriptions require clinical edit access. '
              'Child prescription instructions remain a separate legacy care record.',
          style: TextStyle(
            color: _RxTheme.muted,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in const [
              ('all', 'All'),
              ('child', 'Child'),
              ('adult', 'Adult'),
              ('women', 'Women'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: _chip(
                  entry.$2,
                  _moduleFilter == entry.$1,
                      () {
                    setState(() {
                      _moduleFilter = entry.$1;
                    });
                  },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _searchField('Search loaded profiles'),
      const SizedBox(height: 10),
      if (_profilesError != null) ...[
        _errorCard(
          _profilesError!,
              () => _loadProfiles(reset: true),
        ),
        const SizedBox(height: 10),
      ],
      if (_loadingProfiles || _loadingItems)
        const Padding(
          padding: EdgeInsets.all(25),
          child: Center(
            child: CircularProgressIndicator(
              color: _RxTheme.green,
            ),
          ),
        )
      else if (_visibleProfiles.isEmpty)
        _empty(
          'No accessible profiles',
          'Only connected, permission-controlled profiles appear here.',
        )
      else
        for (final profile in _visibleProfiles)
          _profileTile(profile),
      if (!_loadingProfiles &&
          _childPage * _pageSize < _childTotal) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _loadProfiles(reset: false),
          icon: const Icon(Icons.expand_more),
          label: const Text('Load More Children'),
        ),
      ],
      const SizedBox(height: 8),
      const Text(
        'Search filters loaded profiles. Child profiles are paginated.',
        style: TextStyle(
          fontSize: 11,
          color: _RxTheme.muted,
        ),
      ),
    ],
  );

  Widget _statusBadge(String status) {
    final color = status == 'ISSUED'
        ? _RxTheme.green
        : status == 'DRAFT'
        ? _RxTheme.blue
        : _RxTheme.danger;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 10,
          color: color,
        ),
      ),
    );
  }

  Widget _rxCard(Map<String, dynamic> rx) {
    final data = _rxMap(rx['data']);
    final medicines = _rxRows(data['medicines']);
    final status = _rxText(rx['status']).toUpperCase();
    final edit = _canEdit && !_working;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _panel(
        Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: _RxTheme.ice,
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: _RxTheme.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${medicines.length} medicine${medicines.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _RxTheme.ink,
                    ),
                  ),
                ),
                _statusBadge(status),
              ],
            ),
            const SizedBox(height: 9),
            for (final medicine in medicines.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '• ${_rxText(medicine['name'])}  ${_rxText(medicine['strength'])}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _RxTheme.ink,
                  ),
                ),
              ),
            if (medicines.length > 3)
              Text(
                '+${medicines.length - 3} more medicines',
                style: const TextStyle(
                  fontSize: 11,
                  color: _RxTheme.muted,
                ),
              ),
            const SizedBox(height: 7),
            Text(
              'Created ${_rxDateTime(rx['created_at'])} • Version ${_rxInt(rx['version'])}',
              style: const TextStyle(
                color: _RxTheme.muted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 5,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showRx(rx),
                  icon: const Icon(
                    Icons.visibility_outlined,
                    size: 16,
                  ),
                  label: const Text('Details'),
                ),
                if (status == 'DRAFT' && edit) ...[
                  FilledButton(
                    onPressed: () => _editDraft(rx),
                    style: FilledButton.styleFrom(
                      backgroundColor: _RxTheme.green,
                    ),
                    child: const Text('Edit Draft'),
                  ),
                  OutlinedButton(
                    onPressed: () => _decision(rx, 'ISSUE'),
                    child: const Text('Issue'),
                  ),
                ],
                if (status == 'ISSUED' && edit)
                  TextButton(
                    onPressed: () => _decision(rx, 'VOID'),
                    child: const Text(
                      'Void',
                      style: TextStyle(
                        color: _RxTheme.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRx(Map<String, dynamic> rx) {
    final data = _rxMap(rx['data']);
    final medicines = _rxRows(data['medicines']);
    final issuer = _rxMap(data['issuer']);
    final patient = _rxMap(data['patient']);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * 0.82,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 3, 20, 28),
          children: [
            const Text(
              'Prescription Details',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _RxTheme.ink,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 11),
            _statusBadge(
              _rxText(rx['status']).toUpperCase(),
            ),
            const SizedBox(height: 11),
            _detail('Doctor', rx['doctor_name']),
            _detail('Patient', patient['name']),
            _detail('DOB', patient['dob']),
            _detail('Issued at', rx['issued_at']),
            _detail('Registration', issuer['registration']),
            for (var i = 0; i < medicines.length; i++) ...[
              const Divider(
                color: _RxTheme.border,
              ),
              Text(
                'Medicine ${i + 1}',
                style: const TextStyle(
                  color: _RxTheme.green,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              for (final field in const [
                'name',
                'strength',
                'dose',
                'frequency',
                'duration',
                'instructions',
              ])
                _detail(
                  field[0].toUpperCase() + field.substring(1),
                  medicines[i][field],
                ),
            ],
            const Divider(
              color: _RxTheme.border,
            ),
            _detail(
              'General instructions',
              data['instructions'],
            ),
            _detail('Follow-up', data['follow_up']),
            _detail('Void reason', rx['void_reason']),
            const SizedBox(height: 10),
            const Text(
              'Only the issuing doctor can manage this document. '
                  'Voided documents remain in the medical history.',
              style: TextStyle(
                color: _RxTheme.muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(
      String label,
      dynamic value,
      ) {
    final content = _rxText(value);

    if (content.isEmpty || content == 'null') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: _RxTheme.muted,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            content,
            style: const TextStyle(
              fontSize: 12,
              color: _RxTheme.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legacyCard(
      Map<String, dynamic> entry,
      ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: _panel(
          Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                _rxText(entry['title']).isEmpty
                    ? 'Medicine record'
                    : _rxText(entry['title']),
                style: const TextStyle(
                  color: _RxTheme.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _rxText(entry['date']),
                style: const TextStyle(
                  color: _RxTheme.muted,
                  fontSize: 11,
                ),
              ),
              if (_rxText(entry['notes']).isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _rxText(entry['notes']),
                  style: const TextStyle(
                    color: _RxTheme.ink,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_rxText(entry['author_name']).isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Added by ${_rxText(entry['author_name'])}',
                  style: const TextStyle(
                    color: _RxTheme.green,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _selectedView() {
    final name = _rxText(_selected?['full_name']);
    final canRead = _canRead;
    final legacy = _legacyAvailable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _banner(
          name.isEmpty ? 'Prescriptions' : name,
          '${_module == 'child' ? 'Child' : _module == 'adult' ? 'Adult' : 'Women'} • Medical records',
        ),
        const SizedBox(height: 12),
        _panel(
          Text(
            _canEdit
                ? 'You have edit access. Drafts remain private until you issue them.'
                : 'View-only access. Prescription changes require an active edit grant.',
            style: const TextStyle(
              fontSize: 12,
              color: _RxTheme.muted,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (canRead)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: _chip(
                    'Structured Rx',
                    _section == 'structured',
                        () {
                      setState(() {
                        _section = 'structured';
                        _search.clear();
                      });
                    },
                  ),
                ),
              if (legacy)
                _chip(
                  _module == 'child'
                      ? 'Child Instructions'
                      : 'Medicine History',
                  _section == 'legacy',
                      () {
                    setState(() {
                      _section = 'legacy';
                      _search.clear();
                    });
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        if (_section == 'structured' && canRead) ...[
          if (_canEdit) ...[
            FilledButton.icon(
              onPressed: _working ? null : () => _editDraft(),
              style: FilledButton.styleFrom(
                backgroundColor: _RxTheme.green,
                minimumSize: const Size.fromHeight(47),
              ),
              icon: const Icon(Icons.add),
              label: const Text(
                'Create Prescription Draft',
              ),
            ),
            const SizedBox(height: 12),
          ],
          _searchField('Search loaded prescriptions'),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final status in const [
                  'ALL',
                  'DRAFT',
                  'ISSUED',
                  'VOID',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: _chip(
                      status == 'ALL'
                          ? 'All'
                          : status == 'VOID'
                          ? 'Voided'
                          : status,
                      _statusFilter == status,
                          () {
                        setState(() {
                          _statusFilter = status;
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_rxError != null) ...[
            _errorCard(
              _rxError!,
              _refreshSelected,
            ),
            const SizedBox(height: 10),
          ],
          if (_loadingItems)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(25),
                child: CircularProgressIndicator(
                  color: _RxTheme.green,
                ),
              ),
            )
          else if (_visibleRx.isEmpty)
            _empty(
              'No prescriptions',
              'No doctor-authored structured prescriptions match your filters.',
            )
          else
            for (final rx in _visibleRx)
              _rxCard(rx),
          const SizedBox(height: 12),
          const Text(
            'Issued prescriptions are visible to the patient. Drafts are private. '
                'There is no PDF or signature export endpoint in this API.',
            style: TextStyle(
              fontSize: 11,
              color: _RxTheme.muted,
              height: 1.4,
            ),
          ),
        ] else if (_section == 'legacy' && legacy) ...[
          if (_module == 'child') ...[
            FilledButton.icon(
              onPressed: _working ? null : _addLegacy,
              style: FilledButton.styleFrom(
                backgroundColor: _RxTheme.green,
              ),
              icon: const Icon(
                Icons.note_add_outlined,
              ),
              label: const Text(
                'Add Child Care Instructions',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_legacyError != null) ...[
            _errorCard(
              _legacyError!,
              _refreshSelected,
            ),
            const SizedBox(height: 10),
          ],
          if (_loadingItems)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(25),
                child: CircularProgressIndicator(
                  color: _RxTheme.green,
                ),
              ),
            )
          else if (_legacy.isEmpty)
            _empty(
              'No legacy records',
              'No shared child instructions or medicine records were found.',
            )
          else
            for (final entry in _legacy)
              _legacyCard(entry),
          const SizedBox(height: 11),
          const Text(
            'Legacy care entries are not structured prescriptions. '
                'Child instructions show up to the latest 100 entries.',
            style: TextStyle(
              color: _RxTheme.muted,
              fontSize: 11,
            ),
          ),
        ] else ...[
          _empty(
            'Access unavailable',
            'The required prescription or medicine permission has not been granted.',
          ),
        ],
      ],
    );
  }

  Widget _blocked() => Center(
    child: Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_person_outlined,
            size: 48,
            color: _RxTheme.blue,
          ),
          const SizedBox(height: 11),
          const Text(
            'Approved Doctor Required',
            style: TextStyle(
              color: _RxTheme.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _authError ??
                'Sign in with an approved doctor account.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _RxTheme.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _verify,
            style: FilledButton.styleFrom(
              backgroundColor: _RxTheme.green,
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _RxTheme.page,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _RxTheme.ink,
      leading: IconButton(
        onPressed: _back,
        icon: const Icon(
          Icons.arrow_back_rounded,
        ),
      ),
      title: const Text(
        'Prescriptions',
        style: TextStyle(
          fontWeight: FontWeight.w800,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _working ? null : _refresh,
          icon: const Icon(
            Icons.refresh_rounded,
          ),
        ),
      ],
    ),
    body: _checking
        ? const Center(
      child: CircularProgressIndicator(
        color: _RxTheme.green,
      ),
    )
        : !_verified
        ? _blocked()
        : RefreshIndicator(
      color: _RxTheme.green,
      onRefresh: _refresh,
      child: ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          15,
          16,
          15,
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
                  : _selectedView(),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MedicineControllers {
  _MedicineControllers([Map<String, dynamic>? data])
      : name = TextEditingController(
    text: _rxText(data?['name']),
  ),
        strength = TextEditingController(
          text: _rxText(data?['strength']),
        ),
        dose = TextEditingController(
          text: _rxText(data?['dose']),
        ),
        frequency = TextEditingController(
          text: _rxText(data?['frequency']),
        ),
        duration = TextEditingController(
          text: _rxText(data?['duration']),
        ),
        instructions = TextEditingController(
          text: _rxText(data?['instructions']),
        );

  final TextEditingController name;
  final TextEditingController strength;
  final TextEditingController dose;
  final TextEditingController frequency;
  final TextEditingController duration;
  final TextEditingController instructions;

  Map<String, dynamic> toJson() => {
    'name': name.text.trim(),
    'strength': strength.text.trim(),
    'dose': dose.text.trim(),
    'frequency': frequency.text.trim(),
    'duration': duration.text.trim(),
    'instructions': instructions.text.trim(),
  };

  void dispose() {
    name.dispose();
    strength.dispose();
    dose.dispose();
    frequency.dispose();
    duration.dispose();
    instructions.dispose();
  }
}

class _StructuredRxEditor extends StatefulWidget {
  const _StructuredRxEditor({
    required this.patientName,
    required this.onSave,
    this.existing,
  });

  final String patientName;
  final Map<String, dynamic>? existing;
  final Future<void> Function(
      Map<String, dynamic>,
      ) onSave;

  @override
  State<_StructuredRxEditor> createState() =>
      _StructuredRxEditorState();
}

class _StructuredRxEditorState extends State<_StructuredRxEditor> {
  final _formKey = GlobalKey<FormState>();
  final _instructions = TextEditingController();
  final _medicines = <_MedicineControllers>[];

  DateTime? _followUp;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    final data = _rxMap(widget.existing?['data']);

    _instructions.text = _rxText(data['instructions']);
    _followUp = DateTime.tryParse(
      _rxText(data['follow_up']),
    );

    for (final medicine in _rxRows(data['medicines'])) {
      _medicines.add(
        _MedicineControllers(medicine),
      );
    }

    if (_medicines.isEmpty) {
      _medicines.add(_MedicineControllers());
    }
  }

  @override
  void dispose() {
    for (final medicine in _medicines) {
      medicine.dispose();
    }

    _instructions.dispose();
    super.dispose();
  }

  void _addMedicine() {
    if (_medicines.length >= 30 || _saving) return;

    setState(() {
      _medicines.add(_MedicineControllers());
    });
  }

  void _removeMedicine(int index) {
    if (_medicines.length <= 1 || _saving) return;

    final old = _medicines.removeAt(index);

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback(
          (_) => old.dispose(),
    );
  }

  Future<void> _chooseFollowUp() async {
    final now = DateUtils.dateOnly(DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: _followUp != null &&
          !_followUp!.isBefore(now)
          ? _followUp!
          : now,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      helpText: 'Optional follow-up date',
    );

    if (mounted && picked != null) {
      setState(() => _followUp = picked);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.onSave({
        'medicines': _medicines
            .map((medicine) => medicine.toJson())
            .toList(),
        'instructions': _instructions.text.trim(),
        'follow_up': _followUp == null
            ? null
            : _rxDate(_followUp!),
        'version': widget.existing == null
            ? 0
            : _rxInt(widget.existing?['version']),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is _RxError
            ? error.message
            : error is TimeoutException
            ? 'Save timed out. Check the list before retrying to avoid duplicate drafts.'
            : 'Unable to save. Check the connection and fields.';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _field(
      String label,
      TextEditingController controller,
      int max, {
        bool requiredField = true,
        int lines = 1,
      }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: controller,
          enabled: !_saving,
          maxLength: max,
          maxLines: lines,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          validator: (value) =>
          requiredField &&
              (value ?? '').trim().isEmpty
              ? '$label is required'
              : null,
        ),
      );

  Widget _medicineCard(
      _MedicineControllers medicine,
      int index,
      ) =>
      Container(
        margin: const EdgeInsets.only(bottom: 13),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _RxTheme.border,
          ),
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Medicine ${index + 1}',
                    style: const TextStyle(
                      color: _RxTheme.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (_medicines.length > 1)
                  IconButton(
                    tooltip: 'Remove medicine',
                    onPressed: _saving
                        ? null
                        : () => _removeMedicine(index),
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: _RxTheme.danger,
                    ),
                  ),
              ],
            ),
            _field(
              'Medicine name',
              medicine.name,
              160,
            ),
            _field(
              'Strength',
              medicine.strength,
              80,
            ),
            _field(
              'Dose',
              medicine.dose,
              80,
            ),
            _field(
              'Frequency',
              medicine.frequency,
              120,
            ),
            _field(
              'Duration',
              medicine.duration,
              120,
            ),
            _field(
              'Medicine instructions (optional)',
              medicine.instructions,
              500,
              requiredField: false,
              lines: 2,
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _RxTheme.page,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _RxTheme.ink,
      title: Text(
        widget.existing == null
            ? 'New Prescription Draft'
            : 'Edit Prescription Draft',
      ),
    ),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 700,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Patient: ${widget.patientName}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _RxTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter only medicines and instructions supported by your own clinical assessment. '
                          'Saving creates or updates a private draft; it does not issue the prescription.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: _RxTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < _medicines.length; i++)
                      _medicineCard(
                        _medicines[i],
                        i,
                      ),
                    OutlinedButton.icon(
                      onPressed: _medicines.length >= 30 ||
                          _saving
                          ? null
                          : _addMedicine,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Add Another Medicine',
                      ),
                    ),
                    const SizedBox(height: 15),
                    _field(
                      'General instructions (optional)',
                      _instructions,
                      3000,
                      requiredField: false,
                      lines: 4,
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : _chooseFollowUp,
                      icon: const Icon(
                        Icons.event_outlined,
                      ),
                      label: Text(
                        _followUp == null
                            ? 'Add Follow-up Date (Optional)'
                            : 'Follow-up: ${_rxDate(_followUp!)}',
                      ),
                    ),
                    if (_followUp != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _saving
                              ? null
                              : () {
                            setState(() {
                              _followUp = null;
                            });
                          },
                          child: const Text('Clear Date'),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _RxTheme.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: 17),
                    FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                        _RxTheme.green,
                        minimumSize:
                        const Size.fromHeight(50),
                      ),
                      icon: _saving
                          ? const SizedBox(
                        width: 17,
                        height: 17,
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
                            : 'Save Draft',
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

class _LegacyRxEditor extends StatefulWidget {
  const _LegacyRxEditor({
    required this.child,
    required this.onSave,
  });

  final Map<String, dynamic> child;

  final Future<void> Function(
      Map<String, dynamic>,
      ) onSave;

  @override
  State<_LegacyRxEditor> createState() =>
      _LegacyRxEditorState();
}

class _LegacyRxEditorState extends State<_LegacyRxEditor> {
  final _key = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _provider = TextEditingController();

  DateTime _date = DateUtils.dateOnly(
    DateTime.now(),
  );

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _provider.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final today = DateUtils.dateOnly(DateTime.now());

    final born = DateTime.tryParse(
      _rxText(widget.child['date_of_birth']),
    );

    final first = born != null && !born.isAfter(today)
        ? born
        : DateTime(1900);

    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: first,
      lastDate: today,
    );

    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        !(_key.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.onSave({
        'title': _title.text.trim(),
        'notes': _notes.text.trim(),
        'provider': _provider.text.trim(),
        'date': _rxDate(_date),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is _RxError
              ? error.message
              : 'Could not save the instructions. Check the list before retrying.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _RxTheme.page,
    appBar: AppBar(
      title: const Text(
        'Add Child Instructions',
      ),
      backgroundColor: Colors.white,
      foregroundColor: _RxTheme.ink,
    ),
    body: Form(
      key: _key,
      child: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          Text(
            'Child: ${_rxText(widget.child['full_name'])}',
            style: const TextStyle(
              color: _RxTheme.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'This is a care note, not a structured or signed prescription.',
            style: TextStyle(
              color: _RxTheme.muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _title,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
            (value ?? '').trim().isEmpty
                ? 'Title is required'
                : null,
          ),
          const SizedBox(height: 9),
          OutlinedButton.icon(
            onPressed: _chooseDate,
            icon: const Icon(
              Icons.calendar_month_outlined,
            ),
            label: Text(
              'Date: ${_rxDate(_date)}',
            ),
          ),
          const SizedBox(height: 13),
          TextFormField(
            controller: _notes,
            maxLength: 2000,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Clinical instructions',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
            (value ?? '').trim().isEmpty
                ? 'Instructions are required'
                : null,
          ),
          const SizedBox(height: 9),
          TextFormField(
            controller: _provider,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Provider / clinic (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(
                color: _RxTheme.danger,
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving
                ? null
                : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _RxTheme.green,
            ),
            child: Text(
              _saving
                  ? 'Saving...'
                  : 'Save Instructions',
            ),
          ),
        ],
      ),
    ),
  );
}
