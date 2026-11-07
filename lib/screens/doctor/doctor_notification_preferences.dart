
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/login_screen.dart';

/// FamilyCare+
/// Doctor Notification Preferences
///
/// Stores notification preferences separately for each doctor
/// on the current device.
///
/// This setting controls in-app notification indicators and
/// automatic unread-count checks.
///
/// It does NOT disable backend notification creation or
/// Android/iOS push notifications.
class DoctorNotificationPreferences {
  DoctorNotificationPreferences._();

  // Secure storage already used by FamilyCareSession.
  static const FlutterSecureStorage _storage =
  FlutterSecureStorage();

  // Reactive notification setting.
  //
  // Dashboard and Settings listen to this notifier.
  // Default is enabled.
  static final ValueNotifier<bool> enabled =
  ValueNotifier<bool>(true);

  // Prevent outdated asynchronous loads from overwriting
  // more recent preference changes.
  static int _loadRevision = 0;

  // Unique preference key for each doctor.
  static String _key(String userId) {
    return 'fc_doctor_in_app_notifications_v1_$userId';
  }

  // Current notification preference.
  static bool get isEnabled => enabled.value;

  /// Loads the logged-in doctor's saved setting.
  ///
  /// Called when Doctor Dashboard or Doctor Settings opens.
  static Future<bool> load() async {
    final revision = ++_loadRevision;

    final userId =
    (await FamilyCareSession.userId())?.trim();

    if (revision != _loadRevision) {
      return enabled.value;
    }

    // No doctor session: use default.
    if (userId == null || userId.isEmpty) {
      enabled.value = true;
      return true;
    }

    try {
      final stored = await _storage.read(
        key: _key(userId),
      );

      if (revision != _loadRevision) {
        return enabled.value;
      }

      // First-time users have notifications enabled.
      enabled.value = stored != 'false';

      return enabled.value;
    } catch (_) {
      // If local secure storage cannot be read,
      // keep notification indicators enabled by default.
      if (revision == _loadRevision) {
        enabled.value = true;
      }

      return enabled.value;
    }
  }

  /// Saves the logged-in doctor's in-app notification setting.
  ///
  /// true  = enable badge and foreground checks
  /// false = hide badge and disable automatic unread checks
  ///
  /// The doctor can still open the inbox manually.
  static Future<void> setEnabled(bool value) async {
    final revision = ++_loadRevision;

    final userId =
    (await FamilyCareSession.userId())?.trim();

    if (userId == null || userId.isEmpty) {
      throw StateError(
        'Sign in before changing notification preferences.',
      );
    }

    // Persist first so a storage failure does not falsely
    // display the setting as successfully saved.
    await _storage.write(
      key: _key(userId),
      value: value ? 'true' : 'false',
    );

    if (revision == _loadRevision) {
      enabled.value = value;
    }
  }
}
