
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

class DoctorChildCareScreen extends StatefulWidget {
  const DoctorChildCareScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.initialChild,
    this.onBack,
    this.onOpenSection,
  });

  final String apiBaseUrl;
  final Map<String, dynamic>? initialChild;
  final VoidCallback? onBack;
  final void Function(
      Map<String, dynamic> child,
      String section,
      )? onOpenSection;

  @override
  State<DoctorChildCareScreen> createState() =>
      _DoctorChildCareScreenState();
}

class _ChildPalette {
  static const ink = Color(0xFF214F44);
  static const green = Color(0xFF367D69);
  static const mint = Color(0xFFC6F0DD);
  static const pale = Color(0xFFEDF9F3);
  static const page = Color(0xFFF5FAF7);
  static const line = Color(0xFFD9EAE1);
  static const muted = Color(0xFF71877D);
  static const danger = Color(0xFFB44F51);
}

class _ChildApiException implements Exception {
  const _ChildApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DoctorChildCareScreenState
    extends State<DoctorChildCareScreen> {
  static const _pageSize = 20;

  static const _areas = <String, String>{
    'all': 'All shared',
    'vaccination': 'Vaccination',
    'growth': 'Growth',
    'nutrition': 'Nutrition',
    'care': 'Care notes',
    'prescription': 'Prescriptions',
  };

  final _client = http.Client();
  final _search = TextEditingController();

  bool _verifying = true;
  bool _verified = false;
  bool _loadingChildren = false;
  bool _loadingMoreChildren = false;
  bool _openingChild = false;
  bool _loadingRecords = false;
  bool _loadingMoreRecords = false;
  bool _navigating = false;

  String? _error;
  String? _recordsError;
  String _area = 'all';

  int _verifyVersion = 0;
  int _childrenVersion = 0;
  int _childVersion = 0;
  int _recordsVersion = 0;

  List<Map<String, dynamic>> _children = [];
  Map<String, dynamic>? _child;
  List<Map<String, dynamic>> _records = [];

  int _childrenPage = 0;
  int _childrenTotal = 0;
  int _recordsPage = 0;
  int _recordsTotal = 0;

  String get _baseUrl {
    final configured = widget.apiBaseUrl.trim();

    if (configured.isNotEmpty) {
      return configured.replaceFirst(RegExp(r'/+$'), '');
    }

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5001';
    }

    return 'http://127.0.0.1:5001';
  }

  static String _text(dynamic value) =>
      (value ?? '').toString().trim();

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};

  static int _count(dynamic value, int fallback) =>
      value is num
          ? value.toInt()
          : int.tryParse(_text(value)) ?? fallback;

  static String _id(Map<String, dynamic>? value) =>
      _text(value?['id']);

  String _message(Object error) {
    if (error is _ChildApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'The request timed out. Please try again.';
    }

    if (error is http.ClientException) {
      return 'Could not connect to FamilyCare+. '
          'Check the API connection.';
    }

    if (error is FormatException) {
      return 'Invalid response from the server.';
    }

    return 'Something went wrong. Please try again.';
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    _verify();
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _verifyVersion++;
    _childrenVersion++;
    _childVersion++;
    _recordsVersion++;

    _search.removeListener(_onSearch);
    _search.dispose();
    _client.close();

    super.dispose();
  }

  void _snack(
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
              ? _ChildPalette.danger
              : _ChildPalette.ink,
        ),
      );
  }

  Future<Map<String, dynamic>> _request(
      String method,
      String path, {
        Map<String, String>? query,
        Map<String, dynamic>? payload,
      }) async {
    final role = await FamilyCareSession.role();
    final token = await FamilyCareSession.accessToken();
    final expiry =
    await FamilyCareSession.accessTokenExpiresAt();

    if (_text(role).toUpperCase() != 'DOCTOR' ||
        token == null ||
        token.trim().isEmpty ||
        expiry == null ||
        !expiry.isAfter(DateTime.now().toUtc())) {
      throw const _ChildApiException(
        'Your doctor session has expired. '
            'Please sign in again.',
      );
    }

    final url = Uri.parse(
      '$_baseUrl$path',
    ).replace(queryParameters: query);

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
    };

    if (payload != null) {
      headers['Content-Type'] = 'application/json';
    }

    final http.Response response;

    if (method == 'POST') {
      response = await _client
          .post(
        url,
        headers: headers,
        body: jsonEncode(payload ?? {}),
      )
          .timeout(const Duration(seconds: 35));
    } else {
      response = await _client
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));
    }

    Map<String, dynamic> data = {};

    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        throw const FormatException(
          'Invalid JSON response.',
        );
      }
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final server = _map(data['error']);
      final message = _text(server['message']);

      if (response.statusCode == 401) {
        throw const _ChildApiException(
          'Session expired. Please sign in again.',
        );
      }

      if (response.statusCode == 403) {
        throw _ChildApiException(
          message.isNotEmpty
              ? message
              : 'Permission denied. '
              'Access may have been revoked.',
        );
      }

      if (response.statusCode == 404) {
        throw const _ChildApiException(
          'This child profile or record is no '
              'longer available.',
        );
      }

      throw _ChildApiException(
        message.isNotEmpty
            ? message
            : 'Request failed '
            '(HTTP ${response.statusCode}).',
      );
    }

    if (data.isEmpty) {
      throw const FormatException(
        'Empty JSON response.',
      );
    }

    return data;
  }

  Future<void> _verify() async {
    final requestId = ++_verifyVersion;

    ++_childrenVersion;
    ++_childVersion;
    ++_recordsVersion;

    setState(() {
      _verifying = true;
      _verified = false;
      _error = null;
      _recordsError = null;
      _child = null;
      _children = [];
      _records = [];
      _loadingChildren = false;
      _loadingMoreChildren = false;
      _loadingRecords = false;
      _loadingMoreRecords = false;
      _openingChild = false;
      _childrenPage = 0;
      _childrenTotal = 0;
      _recordsPage = 0;
      _recordsTotal = 0;
    });

    try {
      final response = await _request(
        'GET',
        '/api/v1/doctors/me',
      );

      final user = _map(response['user']);

      if (_text(user['role']).toUpperCase() !=
          'DOCTOR' ||
          _text(user['approval_status'])
              .toUpperCase() !=
              'APPROVED' ||
          _text(user['account_status'])
              .toUpperCase() !=
              'ACTIVE') {
        throw const _ChildApiException(
          'Only approved, active doctors '
              'can open Child Care.',
        );
      }

      if (!mounted || requestId != _verifyVersion) {
        return;
      }

      setState(() {
        _verified = true;
        _verifying = false;
      });

      final preferred = _id(widget.initialChild);

      if (preferred.isNotEmpty) {
        await _openChild(preferred);
      } else {
        await _loadChildren(reset: true);
      }
    } catch (error) {
      if (!mounted || requestId != _verifyVersion) {
        return;
      }

      setState(() {
        _verified = false;
        _verifying = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _loadChildren({
    required bool reset,
  }) async {
    if (!_verified ||
        _loadingChildren ||
        _loadingMoreChildren) {
      return;
    }

    final requestId = ++_childrenVersion;
    final page = reset ? 1 : _childrenPage + 1;

    setState(() {
      _loadingChildren = reset;
      _loadingMoreChildren = !reset;
      _error = null;
    });

    try {
      final response = await _request(
        'GET',
        '/api/v1/doctors/care-profiles',
        query: {
          'module': 'child',
          'page': '$page',
          'per_page': '$_pageSize',
        },
      );

      if (response['items'] is! List) {
        throw const FormatException(
          'Invalid child profile list.',
        );
      }

      final incoming = (response['items'] as List)
          .whereType<Map>()
          .map(
            (value) =>
        Map<String, dynamic>.from(value),
      )
          .where(
            (value) =>
        _id(value).isNotEmpty &&
            _text(value['module']).toLowerCase() ==
                'child',
      )
          .toList();

      if (!mounted ||
          requestId != _childrenVersion) {
        return;
      }

      setState(() {
        final seen = <String>{};

        _children = [
          if (!reset) ..._children,
          ...incoming,
        ].where((value) => seen.add(_id(value))).toList();

        _childrenPage = page;
        _childrenTotal = _count(
          response['total'],
          _children.length,
        );
      });
    } catch (error) {
      if (mounted && requestId == _childrenVersion) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && requestId == _childrenVersion) {
        setState(() {
          _loadingChildren = false;
          _loadingMoreChildren = false;
        });
      }
    }
  }

  Future<void> _openChild(
      String id, {
        bool preserveArea = false,
      }) async {
    if (!_verified || _openingChild || id.isEmpty) {
      return;
    }

    final requestId = ++_childVersion;

    setState(() {
      _openingChild = true;
      _error = null;
    });

    try {
      final response = await _request(
        'GET',
        '/api/v1/doctors/care-profiles/'
            '${Uri.encodeComponent(id)}',
      );

      final profile = _map(response['profile']);

      if (_id(profile) != id ||
          _text(profile['module']).toLowerCase() !=
              'child') {
        throw const _ChildApiException(
          'This is not an authorized child profile.',
        );
      }

      if (!mounted || requestId != _childVersion) {
        return;
      }

      ++_recordsVersion;

      setState(() {
        _child = profile;

        if (!preserveArea) {
          _area = 'all';
        }

        _records = [];
        _recordsPage = 0;
        _recordsTotal = 0;
        _loadingRecords = false;
        _loadingMoreRecords = false;
        _recordsError = null;
        _openingChild = false;
      });

      await _loadRecords(reset: true);
    } catch (error) {
      if (!mounted || requestId != _childVersion) {
        return;
      }

      setState(() {
        _openingChild = false;
        _error = _message(error);
      });

      _snack(_message(error), error: true);
    }
  }

  Future<void> _loadRecords({
    required bool reset,
  }) async {
    if (!_verified ||
        _child == null ||
        _loadingRecords ||
        _loadingMoreRecords) {
      return;
    }

    final requestId = ++_recordsVersion;
    final childId = _id(_child);
    final area = _area;
    final page = reset ? 1 : _recordsPage + 1;

    setState(() {
      _loadingRecords = reset;
      _loadingMoreRecords = !reset;
      _recordsError = null;
    });

    try {
      final root =
          '/api/v1/doctors/care-profiles/'
          '${Uri.encodeComponent(childId)}';

      final path = area == 'all'
          ? '$root/records'
          : '$root/child-records/$area';

      final response = await _request(
        'GET',
        path,
        query: {
          'page': '$page',
          'per_page': '$_pageSize',
        },
      );

      if (response['items'] is! List) {
        throw const FormatException(
          'Invalid record list.',
        );
      }

      final incoming = (response['items'] as List)
          .whereType<Map>()
          .map(
            (value) =>
        Map<String, dynamic>.from(value),
      )
          .where(
            (value) => _id(value).isNotEmpty,
      )
          .toList();

      if (!mounted ||
          requestId != _recordsVersion ||
          childId != _id(_child) ||
          area != _area) {
        return;
      }

      setState(() {
        final seen = <String>{};

        _records = [
          if (!reset) ..._records,
          ...incoming,
        ].where((value) => seen.add(_id(value))).toList();

        _recordsPage = page;
        _recordsTotal = _count(
          response['total'],
          _records.length,
        );
      });
    } catch (error) {
      if (mounted && requestId == _recordsVersion) {
        setState(() {
          _recordsError = _message(error);
        });
      }
    } finally {
      if (mounted && requestId == _recordsVersion) {
        setState(() {
          _loadingRecords = false;
          _loadingMoreRecords = false;
        });
      }
    }
  }

  void _selectArea(String area) {
    if (area == _area || _child == null) return;

    ++_recordsVersion;

    setState(() {
      _area = area;
      _records = [];
      _recordsPage = 0;
      _recordsTotal = 0;
      _recordsError = null;
      _loadingRecords = false;
      _loadingMoreRecords = false;
    });

    _loadRecords(reset: true);
  }

  void _backToChildren() {
    ++_childVersion;
    ++_recordsVersion;

    setState(() {
      _child = null;
      _area = 'all';
      _records = [];
      _recordsPage = 0;
      _recordsTotal = 0;
      _recordsError = null;
      _loadingRecords = false;
      _loadingMoreRecords = false;
      _openingChild = false;
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

  Future<void> _refresh() async {
    if (_child != null) {
      await _openChild(
        _id(_child),
        preserveArea: true,
      );
    } else {
      await _loadChildren(reset: true);
    }
  }

  Future<void> _openSection(String section) async {
    final child = _child;

    if (child == null || _navigating) return;

    if (widget.onOpenSection == null) {
      _snack(
        'This section will be connected '
            'in its dedicated Doctor screen.',
      );
      return;
    }

    final id = _id(child);

    setState(() => _navigating = true);

    try {
      final data = await _request(
        'GET',
        '/api/v1/doctors/care-profiles/'
            '${Uri.encodeComponent(id)}',
      );

      final profile = _map(data['profile']);

      if (_id(profile) != id ||
          _text(profile['module']).toLowerCase() !=
              'child') {
        throw const _ChildApiException(
          'Child access could not be verified.',
        );
      }

      final permissions = _map(
        profile['access_permissions'],
      );

      final scope = section == 'reports'
          ? 'reports'
          : 'records';

      if (permissions.isNotEmpty &&
          (permissions['active'] != true ||
              permissions['scopes'] is! List ||
              !(permissions['scopes'] as List)
                  .contains(scope))) {
        throw const _ChildApiException(
          'Access is not granted for this section.',
        );
      }

      if (!mounted || _id(_child) != id) {
        return;
      }

      widget.onOpenSection!(profile, section);
    } catch (error) {
      _snack(_message(error), error: true);
    } finally {
      if (mounted) {
        setState(() => _navigating = false);
      }
    }
  }

  Future<void> _addEntry(String area) async {
    final child = _child;

    if (child == null || !_verified) return;

    if (!const {
      'growth',
      'nutrition',
      'care',
      'prescription',
    }.contains(area)) {
      return;
    }

    final childId = _id(child);

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => _DoctorChildEntryEditor(
          area: area,
          child: child,
          onSave: (payload) async {
            final response = await _request(
              'POST',
              '/api/v1/doctors/care-profiles/'
                  '${Uri.encodeComponent(childId)}'
                  '/child-records/$area',
              payload: payload,
            );

            if (_map(response['record']).isEmpty) {
              throw const _ChildApiException(
                'The server did not confirm '
                    'the saved record.',
              );
            }
          },
        ),
      ),
    );

    if (!mounted || saved != true) return;

    _snack('Entry saved and shared with the family.');

    await _loadRecords(reset: true);
  }

  String _age(dynamic raw) {
    final dob = DateTime.tryParse(_text(raw));

    if (dob == null) return 'Age unavailable';

    final now = DateTime.now();

    if (dob.isAfter(now)) return 'Age unavailable';

    int years = now.year - dob.year;

    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }

    if (years == 0) {
      int months =
          (now.year - dob.year) * 12 +
              now.month -
              dob.month;

      if (now.day < dob.day) months--;

      return '${months < 0 ? 0 : months} months';
    }

    return '$years ${years == 1 ? 'year' : 'years'}';
  }

  List<Map<String, dynamic>> get _visibleChildren {
    final query = _search.text.trim().toLowerCase();

    if (query.isEmpty) return _children;

    return _children.where((item) {
      return [
        _text(item['full_name']),
        _text(item['guardian_name']),
        _text(item['guardian_contact']),
      ].any(
            (value) => value.toLowerCase().contains(query),
      );
    }).toList();
  }

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(
        color: _ChildPalette.line,
      ),
    ),
    child: child,
  );

  Widget _heading(IconData icon, String text) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: _ChildPalette.pale,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(
          icon,
          color: _ChildPalette.green,
          size: 20,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: _ChildPalette.ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );

  Widget _hero(String title, String subtitle) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          Color(0xFFE5F8EE),
          _ChildPalette.mint,
        ],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: const Color(0xFFBCE4D0),
      ),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white70,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.child_care_outlined,
            color: _ChildPalette.green,
            size: 30,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ChildPalette.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _ChildPalette.green,
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

  Widget _errorCard(
      String message,
      VoidCallback retry,
      ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _panel(
      Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: _ChildPalette.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: _ChildPalette.danger,
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
      String subtitle,
      ) => _panel(
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          const Icon(
            Icons.folder_open_outlined,
            color: _ChildPalette.green,
            size: 41,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ChildPalette.ink,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ChildPalette.muted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _childList() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _hero(
        'Child Care',
        'View children shared with your doctor account.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _search,
        decoration: InputDecoration(
          hintText: 'Search loaded children',
          prefixIcon: const Icon(
            Icons.search,
            color: _ChildPalette.green,
          ),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
            icon: const Icon(Icons.close),
            onPressed: _search.clear,
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: _ChildPalette.line,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Search filters loaded results. '
            'Use Load More for older pages.',
        style: TextStyle(
          color: _ChildPalette.muted,
          fontSize: 11,
        ),
      ),
      const SizedBox(height: 15),
      if (_error != null)
        _errorCard(
          _error!,
              () => _loadChildren(reset: true),
        ),
      if (_loadingChildren || _openingChild)
        const Padding(
          padding: EdgeInsets.all(38),
          child: Center(
            child: CircularProgressIndicator(
              color: _ChildPalette.green,
            ),
          ),
        )
      else if (_visibleChildren.isEmpty)
        _empty(
          _search.text.trim().isEmpty
              ? 'No connected children'
              : 'No matching children',
          'Authorized child profiles will appear here '
              'after they are connected to your account.',
        )
      else
        for (final child in _visibleChildren)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              child: InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: _openingChild
                    ? null
                    : () => _openChild(_id(child)),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _ChildPalette.line,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: _ChildPalette.pale,
                        child: Icon(
                          Icons.child_care_outlined,
                          color: _ChildPalette.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              _text(child['full_name']).isEmpty
                                  ? 'Child profile'
                                  : _text(child['full_name']),
                              style: const TextStyle(
                                color: _ChildPalette.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_age(child['date_of_birth'])} • '
                                  'Guardian: '
                                  '${_text(child['guardian_name']).isEmpty ? 'Not provided' : _text(child['guardian_name'])}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ChildPalette.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: _ChildPalette.green,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      if (!_loadingChildren &&
          _children.length < _childrenTotal) ...[
        const SizedBox(height: 9),
        OutlinedButton.icon(
          onPressed: _loadingMoreChildren
              ? null
              : () => _loadChildren(reset: false),
          icon: _loadingMoreChildren
              ? const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          )
              : const Icon(Icons.expand_more),
          label: Text(
            _loadingMoreChildren
                ? 'Loading...'
                : 'Load More',
          ),
        ),
      ],
    ],
  );

  Widget _detailRow(
      String label,
      String value,
      ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 125,
          child: Text(
            label,
            style: const TextStyle(
              color: _ChildPalette.muted,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? 'Not provided' : value,
            style: const TextStyle(
              color: _ChildPalette.ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _shortcut(
      String title,
      IconData icon,
      VoidCallback onTap,
      ) => Material(
    color: _ChildPalette.pale,
    borderRadius: BorderRadius.circular(13),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 15,
          horizontal: 9,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: _ChildPalette.green,
              size: 23,
            ),
            const SizedBox(height: 7),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ChildPalette.ink,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _childDetails() {
    final child = _child!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hero(
          _text(child['full_name']).isEmpty
              ? 'Child Care'
              : _text(child['full_name']),
          '${_age(child['date_of_birth'])} • '
              'Doctor-authorized care',
        ),
        const SizedBox(height: 15),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                Icons.person_outline,
                'Child Profile',
              ),
              const SizedBox(height: 11),
              _detailRow(
                'Date of birth',
                _text(child['date_of_birth']),
              ),
              _detailRow(
                'Gender',
                _text(child['gender']),
              ),
              _detailRow(
                'Guardian',
                _text(child['guardian_name']),
              ),
              _detailRow(
                'Contact',
                _text(child['guardian_contact']),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                Icons.grid_view_outlined,
                'Care Sections',
              ),
              const SizedBox(height: 13),
              LayoutBuilder(
                builder: (context, dimensions) {
                  final columns =
                  dimensions.maxWidth >= 640 ? 4 : 2;

                  final width =
                      (dimensions.maxWidth -
                          (columns - 1) * 10) /
                          columns;

                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: width,
                        child: _shortcut(
                          'Vaccination',
                          Icons.vaccines_outlined,
                              () => _openSection('vaccination'),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _shortcut(
                          'Consultations',
                          Icons.medical_services_outlined,
                              () => _openSection('consultation'),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _shortcut(
                          'Reports',
                          Icons.folder_shared_outlined,
                              () => _openSection('reports'),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _shortcut(
                          'Shared Records',
                          Icons.assignment_outlined,
                              () => _selectArea('all'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _recordsPanel(),
        const SizedBox(height: 16),
        const Text(
          'Private medical-history entries and private '
              'consultation journals are not included. '
              'Doctor entries are attributed and shared '
              'with the family.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ChildPalette.muted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _recordsPanel() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          Icons.fact_check_outlined,
          'Shared Child Records',
        ),
        const SizedBox(height: 13),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final entry in _areas.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _area == entry.key,
                selectedColor: _ChildPalette.mint,
                backgroundColor: Colors.white,
                side: const BorderSide(
                  color: _ChildPalette.line,
                ),
                labelStyle: TextStyle(
                  color: _area == entry.key
                      ? _ChildPalette.ink
                      : _ChildPalette.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
                onSelected: (_) => _selectArea(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 13),
        if (const {
          'growth',
          'nutrition',
          'care',
          'prescription',
        }.contains(_area)) ...[
          FilledButton.icon(
            onPressed: _loadingRecords
                ? null
                : () => _addEntry(_area),
            style: FilledButton.styleFrom(
              backgroundColor: _ChildPalette.green,
            ),
            icon: const Icon(Icons.add),
            label: Text(
              _area == 'prescription'
                  ? 'Add prescription instructions'
                  : 'Add ${_areas[_area]?.toLowerCase()} entry',
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_recordsError != null)
          _errorCard(
            _recordsError!,
                () => _loadRecords(reset: true),
          ),
        if (_loadingRecords)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(
                color: _ChildPalette.green,
              ),
            ),
          )
        else if (_records.isEmpty)
          _empty(
            'No records here',
            'Only records shared through backend '
                'permissions are shown.',
          )
        else
          for (final record in _records)
            _recordCard(record),
        if (!_loadingRecords &&
            _records.length < _recordsTotal) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loadingMoreRecords
                ? null
                : () => _loadRecords(reset: false),
            icon: _loadingMoreRecords
                ? const SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.expand_more),
            label: Text(
              _loadingMoreRecords
                  ? 'Loading...'
                  : 'Load More Records',
            ),
          ),
        ],
      ],
    ),
  );

  Widget _recordCard(Map<String, dynamic> record) {
    final title = _text(record['title']);

    final kind = _text(record['kind']).isNotEmpty
        ? _text(record['kind'])
        : _area;

    final category = _text(record['category']);

    final doctor =
        _text(record['source_role']).toUpperCase() ==
            'DOCTOR';

    final details = <String>[
      if (_text(record['weight']).isNotEmpty)
        'Weight: ${_text(record['weight'])} kg',
      if (_text(record['height']).isNotEmpty)
        'Height: ${_text(record['height'])} cm',
      if (_text(record['meal']).isNotEmpty)
        'Meal: ${_text(record['meal'])}',
      if (_text(record['status']).isNotEmpty)
        'Status: ${_text(record['status'])}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _ChildPalette.page,
        border: Border.all(
          color: _ChildPalette.line,
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                color: _ChildPalette.green,
                size: 19,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title.isEmpty ? 'Untitled record' : title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: _ChildPalette.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${category.isNotEmpty ? category : kind} • '
                '${_text(record['date'])} • '
                '${doctor ? 'Doctor entry' : 'Shared record'}',
            style: const TextStyle(
              color: _ChildPalette.muted,
              fontSize: 11,
            ),
          ),
          if (doctor &&
              _text(record['author_name']).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Added by ${_text(record['author_name'])}',
              style: const TextStyle(
                color: _ChildPalette.green,
                fontSize: 11,
              ),
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              details.join(' • '),
              style: const TextStyle(
                color: _ChildPalette.ink,
                fontSize: 11,
              ),
            ),
          ],
          if (_text(record['notes']).isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              _text(record['notes']),
              style: const TextStyle(
                color: _ChildPalette.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
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
            color: _ChildPalette.green,
            size: 52,
          ),
          const SizedBox(height: 12),
          const Text(
            'Doctor access required',
            style: TextStyle(
              color: _ChildPalette.ink,
              fontWeight: FontWeight.w800,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ??
                'Please sign in with an '
                    'approved doctor account.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ChildPalette.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _verify,
            style: FilledButton.styleFrom(
              backgroundColor: _ChildPalette.green,
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry Verification'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ChildPalette.page,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ChildPalette.ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _back,
        ),
        title: Text(
          _child == null
              ? 'Doctor Child Care'
              : 'Child Care Details',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: !_verified ||
                _loadingChildren ||
                _loadingRecords ||
                _openingChild
                ? null
                : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _verifying
          ? const Center(
        child: CircularProgressIndicator(
          color: _ChildPalette.green,
        ),
      )
          : !_verified
          ? _blocked()
          : RefreshIndicator(
        color: _ChildPalette.green,
        onRefresh: _refresh,
        child: ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            16,
            18,
            16,
            30,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 980,
                ),
                child: _child == null
                    ? _childList()
                    : _childDetails(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorChildEntryEditor extends StatefulWidget {
  const _DoctorChildEntryEditor({
    required this.area,
    required this.child,
    required this.onSave,
  });

  final String area;
  final Map<String, dynamic> child;
  final Future<void> Function(
      Map<String, dynamic>,
      ) onSave;

  @override
  State<_DoctorChildEntryEditor> createState() =>
      _DoctorChildEntryEditorState();
}

class _DoctorChildEntryEditorState
    extends State<_DoctorChildEntryEditor> {
  final _form = GlobalKey<FormState>();

  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _meal = TextEditingController();

  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  static String _format(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _weight.dispose();
    _height.dispose();
    _meal.dispose();

    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(
      DateTime.now(),
    );

    final dob = DateTime.tryParse(
      (widget.child['date_of_birth'] ?? '').toString(),
    );

    final first = dob != null && !dob.isAfter(today)
        ? DateUtils.dateOnly(dob)
        : DateTime(1900);

    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: first,
      lastDate: today,
    );

    if (date != null && mounted) {
      setState(() => _date = date);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final payload = <String, dynamic>{
        'title': _title.text.trim(),
        'date': _format(_date),
        'notes': _notes.text.trim(),
        if (widget.area == 'growth') ...{
          'weight': _weight.text.trim(),
          'height': _height.text.trim(),
        },
        if (widget.area == 'nutrition')
          'meal': _meal.text.trim(),
        if (widget.area == 'prescription')
          'category': 'Prescription',
      };

      await widget.onSave(payload);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is _ChildApiException
            ? error.message
            : error is TimeoutException
            ? 'Saving timed out. Please retry.'
            : 'Could not save the record. '
            'Please try again.';
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
        bool requiredField = false,
        int max = 160,
        int lines = 1,
        TextInputType? keyboard,
        String? Function(String?)? extra,
      }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      enabled: !_saving,
      maxLength: max,
      maxLines: lines,
      keyboardType: keyboard,
      style: const TextStyle(
        color: _ChildPalette.ink,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: _ChildPalette.muted,
        ),
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      validator: (value) {
        if (requiredField &&
            (value ?? '').trim().isEmpty) {
          return '$label is required';
        }

        return extra?.call(value);
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final type = switch (widget.area) {
      'growth' => 'Growth Measurement',
      'nutrition' => 'Nutrition Entry',
      'prescription' => 'Prescription Instructions',
      _ => 'Care Note',
    };

    return Scaffold(
      backgroundColor: _ChildPalette.page,
      appBar: AppBar(
        title: Text('Add $type'),
        foregroundColor: _ChildPalette.ink,
        backgroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(17),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 660,
              ),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Doctor-authored entry',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: _ChildPalette.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Child: ${widget.child['full_name'] ?? 'Child'}',
                      style: const TextStyle(
                        color: _ChildPalette.muted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _field(
                      'Title',
                      _title,
                      requiredField: true,
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : _pickDate,
                      icon: const Icon(
                        Icons.calendar_month_outlined,
                      ),
                      label: Text(
                        'Record date: ${_format(_date)}',
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (widget.area == 'growth') ...[
                      _field(
                        'Weight (kg)',
                        _weight,
                        requiredField: true,
                        max: 12,
                        keyboard:
                        const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        extra: (raw) {
                          final v = double.tryParse(
                            (raw ?? '').trim(),
                          );

                          return v != null &&
                              v > 0 &&
                              v <= 300
                              ? null
                              : 'Enter weight between '
                              '0 and 300 kg';
                        },
                      ),
                      _field(
                        'Height (cm)',
                        _height,
                        requiredField: true,
                        max: 12,
                        keyboard:
                        const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        extra: (raw) {
                          final v = double.tryParse(
                            (raw ?? '').trim(),
                          );

                          return v != null &&
                              v > 0 &&
                              v <= 250
                              ? null
                              : 'Enter height between '
                              '0 and 250 cm';
                        },
                      ),
                    ],
                    if (widget.area == 'nutrition')
                      _field(
                        'Meal (optional)',
                        _meal,
                      ),
                    _field(
                      widget.area == 'prescription'
                          ? 'Prescription instructions'
                          : 'Notes (optional)',
                      _notes,
                      requiredField:
                      widget.area == 'prescription',
                      max: 2000,
                      lines: 4,
                    ),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: _ChildPalette.danger,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                        _ChildPalette.green,
                        minimumSize:
                        const Size.fromHeight(52),
                      ),
                      icon: _saving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                        CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : const Icon(
                        Icons.save_outlined,
                      ),
                      label: Text(
                        _saving
                            ? 'Saving...'
                            : 'Save doctor entry',
                      ),
                    ),
                    const SizedBox(height: 13),
                    const Text(
                      'Saved entries are attributed to '
                          'the doctor and shared with the family.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _ChildPalette.muted,
                        fontSize: 11,
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
}