
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

class DoctorSettingsScreen extends StatefulWidget {
  const DoctorSettingsScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.onBack,
    this.onOpenProfile,
    this.onGoToLogin,
  });

  final String apiBaseUrl;
  final VoidCallback? onBack;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onGoToLogin;

  @override
  State<DoctorSettingsScreen> createState() =>
      _DoctorSettingsScreenState();
}

class _SettingsColors {
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

class _SettingsApiError implements Exception {
  const _SettingsApiError(
      this.message, [
        this.status,
      ]);

  final String message;
  final int? status;

  @override
  String toString() => message;
}

class _DoctorSettingsScreenState
    extends State<DoctorSettingsScreen> {
  final http.Client _client = http.Client();

  bool _loading = true;
  bool _verified = false;
  bool _sessionsExpanded = false;
  bool _loadingSessions = false;
  bool _sessionsLoaded = false;
  bool _loggingOut = false;
  bool _leaving = false;
  bool _passwordChanging = false;

  String? _error;
  String? _sessionsError;
  String? _revokingId;

  String _referralId = '';

  Map<String, dynamic> _user = {};
  List<Map<String, dynamic>> _sessions = [];

  DateTime? _accessExpiresAt;

  int _revision = 0;
  int _sessionsRevision = 0;

  static String _text(dynamic value) =>
      (value ?? '').toString().trim();

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};

  String get _baseUrl {
    var value = widget.apiBaseUrl.trim();

    if (value.isEmpty) {
      value = !kIsWeb &&
          defaultTargetPlatform ==
              TargetPlatform.android
          ? 'http://10.0.2.2:5001'
          : 'http://127.0.0.1:5001';
    }

    value = value.replaceFirst(
      RegExp(r'/+$'),
      '',
    );

    for (final suffix in [
      '/api/v1/doctors',
      '/api/v1/auth',
      '/api/v1',
    ]) {
      if (value.endsWith(suffix)) {
        return value.substring(
          0,
          value.length - suffix.length,
        );
      }
    }

    return value;
  }

  String get _name =>
      _display(_user['full_name']);

  String get _email =>
      _display(_user['email']);

  String get _publicId =>
      _display(_user['public_id']);

  String get _phone => _display(
    _user['phone_number'] ??
        _user['mobile_number'],
  );

  String get _accountStatus =>
      _display(_user['account_status']);

  String get _approvalStatus =>
      _display(_user['approval_status']);

  String _display(dynamic value) {
    final content = _text(value);

    return content.isEmpty
        ? 'Not provided'
        : content;
  }

  String _date(dynamic value) {
    final parsed = value is DateTime
        ? value
        : DateTime.tryParse(_text(value));

    if (parsed == null) {
      return 'Not available';
    }

    final local = parsed.toLocal();

    String pad(int number) =>
        number.toString().padLeft(2, '0');

    return '${pad(local.day)}/${pad(local.month)}/${local.year} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void didUpdateWidget(
      covariant DoctorSettingsScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _loadSettings();
    }
  }

  @override
  void dispose() {
    _revision++;
    _sessionsRevision++;
    _client.close();

    super.dispose();
  }

  String _friendly(Object error) {
    if (error is _SettingsApiError) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'Request timed out. Please retry.';
    }

    if (error is http.ClientException) {
      return 'Cannot connect to FamilyCare+. Check the backend connection.';
    }

    if (error is FormatException) {
      return 'Invalid server response.';
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
              ? _SettingsColors.danger
              : _SettingsColors.ink,
        ),
      );
  }

  Future<Map<String, String>> _headers({
    bool json = false,
  }) async {
    final role =
    await FamilyCareSession.role();

    final token =
    await FamilyCareSession.accessToken();

    final expires =
    await FamilyCareSession.accessTokenExpiresAt();

    if (_text(role).toUpperCase() != 'DOCTOR' ||
        token == null ||
        token.isEmpty ||
        expires == null ||
        !expires.isAfter(
          DateTime.now().toUtc(),
        )) {
      throw const _SettingsApiError(
        'Doctor session expired. Please sign in again.',
        401,
      );
    }

    return {
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _request(
      String method,
      String path, {
        Map<String, dynamic>? body,
      }) async {
    final request = http.Request(
      method,
      Uri.parse('$_baseUrl$path'),
    );

    request.headers.addAll(
      await _headers(
        json: body != null,
      ),
    );

    if (body != null) {
      request.body = jsonEncode(body);
    }

    final streamed = await _client
        .send(request)
        .timeout(
      const Duration(seconds: 30),
    );

    final response = await http.Response.fromStream(
      streamed,
    ).timeout(
      const Duration(seconds: 30),
    );

    Map<String, dynamic> data = {};

    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(
          utf8.decode(response.bodyBytes),
        );

        if (decoded is Map) {
          data = Map<String, dynamic>.from(
            decoded,
          );
        } else if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          throw const FormatException(
            'Expected JSON object.',
          );
        }
      } catch (_) {
        if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          throw const FormatException(
            'Invalid JSON response.',
          );
        }
      }
    }

    if (response.statusCode >= 200 &&
        response.statusCode < 300) {
      return data;
    }

    final issue = data['error'];

    final message = issue is Map
        ? _text(issue['message'])
        : issue is String
        ? issue.trim()
        : '';

    final fallback = switch (response.statusCode) {
      401 => 'Authentication failed or session expired.',
      403 => 'Access denied. Your account permission may have changed.',
      404 => 'The requested session or endpoint was not found.',
      409 => 'This action conflicts with the current account state.',
      422 => 'Please check the submitted details and try again.',
      429 => 'Too many requests. Please try again later.',
      _ => 'Request failed (HTTP ${response.statusCode}).',
    };

    throw _SettingsApiError(
      message.isEmpty ? fallback : message,
      response.statusCode,
    );
  }

  Future<void> _loadSettings() async {
    if (_leaving || _loggingOut) {
      return;
    }

    final version = ++_revision;
    ++_sessionsRevision;

    setState(() {
      _loading = true;
      _verified = false;
      _error = null;
      _sessions = [];
      _sessionsLoaded = false;
      _loadingSessions = false;
      _sessionsError = null;
      _user = {};
      _referralId = '';
      _accessExpiresAt = null;
    });

    try {
      final response = await _request(
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
        throw const _SettingsApiError(
          'Only approved, active doctors can open Settings.',
          403,
        );
      }

      final expiry =
      await FamilyCareSession.accessTokenExpiresAt();

      if (!mounted ||
          version != _revision) {
        return;
      }

      setState(() {
        _user = user;
        _referralId = _text(
          user['referral_id'],
        );

        _accessExpiresAt = expiry;
        _verified = true;
        _loading = false;
      });

      if (_referralId.isEmpty) {
        try {
          final result = await _request(
            'GET',
            '/api/v1/doctors/referral',
          );

          if (!mounted ||
              version != _revision) {
            return;
          }

          setState(() {
            _referralId = _text(
              _map(
                result['doctor'],
              )['referral_id'],
            );
          });
        } catch (_) {
          // Optional referral lookup failure.
        }
      }

      // Keep Active Sessions open after refreshing Settings.
      if (mounted &&
          version == _revision &&
          _sessionsExpanded) {
        await _loadSessions();
      }
    } catch (error) {
      if (!mounted ||
          version != _revision) {
        return;
      }

      setState(() {
        _loading = false;
        _verified = false;
        _error = _friendly(error);
      });
    }
  }

  Future<void> _loadSessions() async {
    if (!_verified ||
        _loadingSessions ||
        _leaving) {
      return;
    }

    final version = ++_sessionsRevision;

    setState(() {
      _loadingSessions = true;
      _sessionsError = null;
    });

    try {
      final response = await _request(
        'GET',
        '/api/v1/auth/sessions',
      );

      if (response['items'] is! List) {
        throw const FormatException(
          'Invalid sessions list.',
        );
      }

      final sessions =
      (response['items'] as List)
          .whereType<Map>()
          .map(
            (value) =>
        Map<String, dynamic>.from(
          value,
        ),
      )
          .toList();

      if (!mounted ||
          version != _sessionsRevision) {
        return;
      }

      setState(() {
        _sessions = sessions;
        _sessionsLoaded = true;
      });
    } catch (error) {
      if (!mounted ||
          version != _sessionsRevision) {
        return;
      }

      setState(() {
        _sessionsError = _friendly(error);
      });
    } finally {
      if (mounted &&
          version == _sessionsRevision) {
        setState(() {
          _loadingSessions = false;
        });
      }
    }
  }

  void _toggleSessions() {
    if (!_verified ||
        _loggingOut ||
        _leaving) {
      return;
    }

    setState(() {
      _sessionsExpanded = !_sessionsExpanded;
    });

    if (_sessionsExpanded &&
        !_sessionsLoaded) {
      _loadSessions();
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String action = 'Continue',
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
            style: FilledButton.styleFrom(
              backgroundColor: danger
                  ? _SettingsColors.danger
                  : _SettingsColors.green,
            ),
            onPressed: () {
              Navigator.pop(
                dialogContext,
                true,
              );
            },
            child: Text(action),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _copyReferral() async {
    if (_referralId.isEmpty) {
      return;
    }

    await Clipboard.setData(
      ClipboardData(
        text: _referralId,
      ),
    );

    _notice('Referral ID copied.');
  }

  Future<void> _leaveForLogin() async {
    if (_leaving) return;

    setState(() {
      _leaving = true;
      _verified = false;
      _sessions = [];
      _sessionsLoaded = false;
      _sessionsExpanded = false;
    });

    ++_sessionsRevision;

    try {
      await FamilyCareSession.clear();

      if (!mounted) return;

      if (widget.onGoToLogin != null) {
        widget.onGoToLogin!();
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => LoginScreen(
              apiBaseUrl: _baseUrl,
            ),
          ),
              (_) => false,
        );
      }
    } catch (_) {
      _notice(
        'Could not clear this device session. Please retry.',
        error: true,
      );

      if (mounted) {
        setState(() {
          _leaving = false;
        });
      }
    }
  }

  Future<void> _changePassword() async {
    if (!_verified ||
        _leaving ||
        _loggingOut ||
        _passwordChanging) {
      return;
    }

    setState(() {
      _passwordChanging = true;
    });

    try {
      final updated = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PasswordChangeDialog(
          submit: (
              current,
              next,
              confirm,
              ) async {
            await _request(
              'POST',
              '/api/v1/auth/change-password',
              body: {
                'current_password': current,
                'new_password': next,
                'confirm_password': confirm,
              },
            );
          },
        ),
      );

      if (updated == true &&
          mounted) {
        await _leaveForLogin();
      }
    } finally {
      if (mounted) {
        setState(() {
          _passwordChanging = false;
        });
      }
    }
  }

  Future<void> _revokeSession(
      Map<String, dynamic> session,
      ) async {
    if (!_verified ||
        _revokingId != null ||
        _loggingOut ||
        _leaving ||
        _passwordChanging) {
      return;
    }

    final id = _text(
      session['id'],
    );

    if (id.isEmpty) {
      return;
    }

    final current =
        session['current'] == true;

    final approved = await _confirm(
      title: current
          ? 'Revoke current session?'
          : 'Revoke this session?',
      message: current
          ? 'You will be signed out from this device.'
          : 'This session will lose access and will need to sign in again.',
      action: 'Revoke',
      danger: true,
    );

    if (!approved ||
        !mounted) {
      return;
    }

    setState(() {
      _revokingId = id;
    });

    try {
      await _request(
        'DELETE',
        '/api/v1/auth/sessions/${Uri.encodeComponent(id)}',
      );

      if (!mounted) return;

      if (current) {
        await _leaveForLogin();
        return;
      }

      _notice('Session revoked.');

      setState(() {
        _sessionsLoaded = false;
      });

      await _loadSessions();
    } catch (error) {
      _notice(
        _friendly(error),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _revokingId = null;
        });
      }
    }
  }

  Future<void> _logout({
    bool everywhere = false,
  }) async {
    if (_loggingOut ||
        _leaving ||
        _passwordChanging ||
        _revokingId != null) {
      return;
    }

    final approved = await _confirm(
      title: everywhere
          ? 'Sign out everywhere?'
          : 'Sign out?',
      message: everywhere
          ? 'All account sessions will be revoked. Every device must sign in again.'
          : 'You will be signed out from this device.',
      action: 'Sign Out',
      danger: true,
    );

    if (!approved ||
        !mounted) {
      return;
    }

    setState(() {
      _loggingOut = true;
    });

    try {
      await _request(
        'POST',
        everywhere
            ? '/api/v1/auth/logout-all'
            : '/api/v1/auth/logout',
      );

      await _leaveForLogin();
    } catch (error) {
      if (!mounted) return;

      if (error is _SettingsApiError &&
          error.status == 401) {
        await _leaveForLogin();
        return;
      }

      final local = await _confirm(
        title: 'Server sign-out not confirmed',
        message:
        '${_friendly(error)}\n\n'
            'You can still clear the login on this device, '
            'but other server sessions may remain active.',
        action: 'Clear This Device',
        danger: true,
      );

      if (local &&
          mounted) {
        await _leaveForLogin();
      }
    } finally {
      if (mounted) {
        setState(() {
          _loggingOut = false;
        });
      }
    }
  }

  void _back() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _infoDialog(
      String title,
      String message,
      ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(
          message,
          style: const TextStyle(
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _panel(
      List<Widget> children,
      ) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: _SettingsColors.border,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _heading(
      String label,
      IconData icon,
      ) =>
      Row(
        children: [
          Icon(
            icon,
            color: _SettingsColors.green,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _SettingsColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );

  Widget _detail(
      String label,
      String value, {
        VoidCallback? copy,
      }) =>
      Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 11,
        ),
        child: Row(
          crossAxisAlignment:
          CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _SettingsColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _SettingsColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            if (copy != null)
              IconButton(
                tooltip: 'Copy',
                onPressed: copy,
                icon: const Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: _SettingsColors.blue,
                ),
              ),
          ],
        ),
      );

  Widget _action({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Color color = _SettingsColors.green,
    Widget? trailing,
  }) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            icon,
            size: 21,
            color: color,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 11,
            height: 1.4,
            color: _SettingsColors.muted,
          ),
        ),
        trailing: trailing ??
            const Icon(
              Icons.chevron_right_rounded,
              color: _SettingsColors.muted,
            ),
      );

  Widget _hero() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          _SettingsColors.mint,
          _SettingsColors.ice,
        ],
      ),
      border: Border.all(
        color: _SettingsColors.border,
      ),
      borderRadius: BorderRadius.circular(19),
    ),
    child: const Row(
      children: [
        Icon(
          Icons.settings_outlined,
          color: _SettingsColors.green,
          size: 30,
        ),
        SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'Account Settings',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: _SettingsColors.ink,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Manage your account, login security and privacy.',
                style: TextStyle(
                  fontSize: 12,
                  color: _SettingsColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _account() => _panel([
    _heading(
      'Account Information',
      Icons.person_outline,
    ),
    const SizedBox(height: 9),
    const Divider(
      color: _SettingsColors.border,
    ),
    _detail('Doctor name', _name),
    const Divider(
      height: 1,
      color: _SettingsColors.border,
    ),
    _detail('Email', _email),
    const Divider(
      height: 1,
      color: _SettingsColors.border,
    ),
    _detail('Phone', _phone),
    const Divider(
      height: 1,
      color: _SettingsColors.border,
    ),
    _detail('Public ID', _publicId),
    const Divider(
      height: 1,
      color: _SettingsColors.border,
    ),
    _detail(
      'Account status',
      _accountStatus,
    ),
    const Divider(
      height: 1,
      color: _SettingsColors.border,
    ),
    _detail(
      'Doctor approval',
      _approvalStatus,
    ),
    if (widget.onOpenProfile != null) ...[
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _leaving || _loggingOut
              ? null
              : widget.onOpenProfile,
          icon: const Icon(
            Icons.edit_outlined,
            size: 17,
          ),
          label: const Text(
            'Open My Profile',
          ),
        ),
      ),
    ],
  ]);

  Widget _referral() => _panel([
    _heading(
      'Doctor Referral',
      Icons.link_outlined,
    ),
    const SizedBox(height: 10),
    const Text(
      'Patients can use this referral ID to connect with your doctor account.',
      style: TextStyle(
        color: _SettingsColors.muted,
        fontSize: 12,
        height: 1.45,
      ),
    ),
    const SizedBox(height: 9),
    Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: _SettingsColors.ice,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _detail(
        'Referral ID',
        _referralId.isEmpty
            ? 'Not available'
            : _referralId,
        copy: _referralId.isEmpty
            ? null
            : _copyReferral,
      ),
    ),
  ]);

  Widget _sessionTile(
      Map<String, dynamic> session,
      ) {
    final id = _text(session['id']);
    final current = session['current'] == true;
    final deleting = _revokingId == id;

    return Container(
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _SettingsColors.page,
        border: Border.all(
          color: _SettingsColors.border,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            current
                ? Icons.smartphone_outlined
                : Icons.devices_outlined,
            color: current
                ? _SettingsColors.green
                : _SettingsColors.blue,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  current
                      ? 'Current session'
                      : 'Active session',
                  style: const TextStyle(
                    color: _SettingsColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Created: ${_date(session['created_at'])}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _SettingsColors.muted,
                  ),
                ),
                Text(
                  'Expires: ${_date(session['expires_at'])}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _SettingsColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (id.isNotEmpty)
            deleting
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
                : IconButton(
              tooltip: 'Revoke session',
              onPressed: _revokingId != null ||
                  _leaving ||
                  _loggingOut ||
                  _passwordChanging
                  ? null
                  : () => _revokeSession(
                session,
              ),
              icon: const Icon(
                Icons.logout_rounded,
                color: _SettingsColors.danger,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  Widget _security() => _panel([
    _heading(
      'Security & Login',
      Icons.shield_outlined,
    ),
    const SizedBox(height: 8),
    const Divider(
      color: _SettingsColors.border,
    ),
    _action(
      icon: Icons.lock_reset_outlined,
      title: 'Change Password',
      subtitle: 'Changing your password signs out all devices.',
      onTap: _passwordChanging ||
          _leaving ||
          _loggingOut
          ? null
          : _changePassword,
      color: _SettingsColors.blue,
    ),
    const Divider(
      height: 1,
      color: _SettingsColors.border,
    ),
    _action(
      icon: Icons.devices_outlined,
      title: 'Active Sessions',
      subtitle: 'View and revoke signed-in sessions.',
      onTap: _leaving || _loggingOut
          ? null
          : _toggleSessions,
      color: _SettingsColors.blue,
      trailing: Icon(
        _sessionsExpanded
            ? Icons.expand_less
            : Icons.expand_more,
        color: _SettingsColors.blue,
      ),
    ),
    if (_sessionsExpanded) ...[
      if (_loadingSessions)
        const Padding(
          padding: EdgeInsets.all(18),
          child: Center(
            child: CircularProgressIndicator(
              color: _SettingsColors.green,
            ),
          ),
        )
      else if (_sessionsError != null) ...[
        Text(
          _sessionsError!,
          style: const TextStyle(
            color: _SettingsColors.danger,
            fontSize: 12,
          ),
        ),
        TextButton(
          onPressed: _loadSessions,
          child: const Text('Retry'),
        ),
      ] else if (_sessions.isEmpty &&
          _sessionsLoaded)
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            'No active sessions returned.',
            style: TextStyle(
              color: _SettingsColors.muted,
            ),
          ),
        )
      else
        for (final session in _sessions)
          _sessionTile(session),
      if (_sessionsLoaded)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _loadingSessions
                ? null
                : _loadSessions,
            icon: const Icon(
              Icons.refresh,
              size: 16,
            ),
            label: const Text(
              'Refresh sessions',
            ),
          ),
        ),
      const Padding(
        padding: EdgeInsets.only(
          top: 5,
          bottom: 7,
        ),
        child: Text(
          'The backend supplies session dates, not device names or last-activity times.',
          style: TextStyle(
            fontSize: 11,
            color: _SettingsColors.muted,
          ),
        ),
      ),
    ],
    const Divider(
      height: 1,
      color: _SettingsColors.border,
    ),
    _detail(
      'Access token expires',
      _date(_accessExpiresAt),
    ),
  ]);

  Widget _privacy() => _panel([
    _heading(
      'Privacy & Data Access',
      Icons.privacy_tip_outlined,
    ),
    const SizedBox(height: 9),
    const Divider(
      color: _SettingsColors.border,
    ),
    _action(
      icon: Icons.folder_shared_outlined,
      title: 'Patient Data Access',
      subtitle: 'Understand per-profile medical permissions.',
      onTap: () => _infoDialog(
        'Patient Data Access',
        'A patient connection does not automatically grant access '
            'to every family member. Child, Adult and Women records '
            'have different sharing rules. Access must be checked '
            'and enforced by the backend for every record and download.',
      ),
    ),
    const Divider(
      height: 1,
      color: _SettingsColors.border,
    ),
    _action(
      icon: Icons.verified_user_outlined,
      title: 'Account Security',
      subtitle: 'How this screen handles login sessions.',
      onTap: () => _infoDialog(
        'Account Security',
        'Settings actions use your authenticated FamilyCare+ Flask API. '
            'Your passwords are submitted only during a password change. '
            'FamilyCareSession manages saved authentication tokens. '
            'The backend determines session validity and access permissions.',
      ),
      color: _SettingsColors.blue,
    ),
  ]);

  Widget _logoutOptions() => _panel([
    _heading(
      'Sign Out',
      Icons.logout_rounded,
    ),
    const SizedBox(height: 9),
    const Divider(
      color: _SettingsColors.border,
    ),
    _action(
      icon: Icons.logout_rounded,
      title: 'Sign Out',
      subtitle: 'End this device session.',
      onTap: _loggingOut ||
          _leaving ||
          _passwordChanging
          ? null
          : () => _logout(),
      color: _SettingsColors.danger,
    ),
    const Divider(
      height: 1,
      color: _SettingsColors.border,
    ),
    _action(
      icon: Icons.phonelink_erase_outlined,
      title: 'Sign Out From All Devices',
      subtitle: 'Revoke every active account session.',
      onTap: _loggingOut ||
          _leaving ||
          _passwordChanging
          ? null
          : () => _logout(
        everywhere: true,
      ),
      color: _SettingsColors.danger,
    ),
    if (_loggingOut)
      const Padding(
        padding: EdgeInsets.only(top: 9),
        child: LinearProgressIndicator(
          color: _SettingsColors.green,
        ),
      ),
  ]);

  Widget _blocked() => Center(
    child: Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_person_outlined,
            size: 49,
            color: _SettingsColors.blue,
          ),
          const SizedBox(height: 13),
          const Text(
            'Doctor Settings Unavailable',
            style: TextStyle(
              color: _SettingsColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            _error ??
                'Please sign in with an approved, active doctor account.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _SettingsColors.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _SettingsColors.green,
            ),
            onPressed: _loadSettings,
            icon: const Icon(
              Icons.refresh,
            ),
            label: const Text(
              'Retry',
            ),
          ),
          TextButton(
            onPressed: _leaveForLogin,
            child: const Text(
              'Go to Login',
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _SettingsColors.page,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _SettingsColors.ink,
      elevation: 0,
      leading: IconButton(
        onPressed: _back,
        icon: const Icon(
          Icons.arrow_back_rounded,
        ),
      ),
      title: const Text(
        'Settings',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 17,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh settings',
          onPressed: _loading ||
              _loggingOut ||
              _leaving ||
              _passwordChanging ||
              _revokingId != null
              ? null
              : _loadSettings,
          icon: const Icon(
            Icons.refresh_rounded,
          ),
        ),
      ],
    ),
    body: _loading
        ? const Center(
      child: CircularProgressIndicator(
        color: _SettingsColors.green,
      ),
    )
        : !_verified
        ? _blocked()
        : RefreshIndicator(
      color: _SettingsColors.green,
      onRefresh: _loadSettings,
      child: ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding:
        const EdgeInsets.fromLTRB(
          16,
          17,
          16,
          30,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 850,
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.stretch,
                children: [
                  _hero(),
                  const SizedBox(height: 14),
                  _account(),
                  const SizedBox(height: 13),
                  _referral(),
                  const SizedBox(height: 13),
                  _security(),
                  const SizedBox(height: 13),
                  _privacy(),
                  const SizedBox(height: 13),
                  _logoutOptions(),
                  const SizedBox(height: 22),
                  const Center(
                    child: Text(
                      'FamilyCare+ • Doctor Workspace',
                      style: TextStyle(
                        fontSize: 11,
                        color: _SettingsColors.muted,
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
  );
}

class _PasswordChangeDialog extends StatefulWidget {
  const _PasswordChangeDialog({
    required this.submit,
  });

  final Future<void> Function(
      String,
      String,
      String,
      ) submit;

  @override
  State<_PasswordChangeDialog> createState() =>
      _PasswordChangeDialogState();
}

class _PasswordChangeDialogState
    extends State<_PasswordChangeDialog> {
  final _key = GlobalKey<FormState>();

  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _visible = false;
  bool _saving = false;

  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();

    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        !(_key.currentState?.validate() ??
            false)) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.submit(
        _current.text,
        _next.text,
        _confirm.text,
      );

      if (mounted) {
        Navigator.pop(
          context,
          true,
        );
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is _SettingsApiError
            ? error.message
            : error is TimeoutException
            ? 'Request timed out. Check whether the password changed before retrying.'
            : 'Unable to change password. Please retry.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Widget _field(
      String label,
      TextEditingController controller, {
        String? Function(String?)? validator,
      }) =>
      Padding(
        padding: const EdgeInsets.only(
          bottom: 13,
        ),
        child: TextFormField(
          controller: controller,
          enabled: !_saving,
          obscureText: !_visible,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          validator: validator,
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(
      'Change Password',
      style: TextStyle(
        color: _SettingsColors.ink,
        fontWeight: FontWeight.w800,
      ),
    ),
    content: SizedBox(
      width: 390,
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Changing your password revokes every active session.',
                style: TextStyle(
                  color: _SettingsColors.muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 15),
              _field(
                'Current password',
                _current,
                validator: (value) =>
                (value ?? '').isEmpty
                    ? 'Enter your current password'
                    : null,
              ),
              _field(
                'New password',
                _next,
                validator: (value) {
                  final password = value ?? '';

                  if (password.length < 8 ||
                      password.length > 128) {
                    return 'Use 8–128 characters';
                  }

                  if (password ==
                      _current.text) {
                    return 'Choose a different password';
                  }

                  return null;
                },
              ),
              _field(
                'Confirm new password',
                _confirm,
                validator: (value) =>
                value != _next.text
                    ? 'Passwords do not match'
                    : null,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity:
                ListTileControlAffinity.leading,
                title: const Text(
                  'Show passwords',
                  style: TextStyle(
                    fontSize: 12,
                  ),
                ),
                value: _visible,
                onChanged: _saving
                    ? null
                    : (value) {
                  setState(() {
                    _visible =
                        value ?? false;
                  });
                },
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(
                    color: _SettingsColors.danger,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving
            ? null
            : () {
          Navigator.pop(
            context,
            false,
          );
        },
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving
            ? null
            : _save,
        style: FilledButton.styleFrom(
          backgroundColor:
          _SettingsColors.green,
        ),
        child: _saving
            ? const SizedBox(
          width: 18,
          height: 18,
          child:
          CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        )
            : const Text(
          'Update Password',
        ),
      ),
    ],
  );
}
