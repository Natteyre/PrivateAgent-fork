import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:volume_controller/volume_controller.dart';

/// Lightweight contact projection for search results.
class ContactHit {
  final String id;
  final String name;
  final String? phone;
  const ContactHit({required this.id, required this.name, this.phone});
}

/// Device-level controls: volume, brightness, alarms, contacts, dialer,
/// local notifications, and optional Shizuku shell commands.
class SystemControlService {
  SystemControlService._();
  static final SystemControlService instance = SystemControlService._();

  static const _channel = MethodChannel('com.orailnoor.privateagent/system');

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  final _volumeController = VolumeController();
  final _brightnessController = ScreenBrightness();

  // ------------------------------------------------------------------
  // Volume
  // ------------------------------------------------------------------

  Future<double> getVolume() async {
    try {
      return _volumeController.getVolume();
    } catch (_) {
      return 0;
    }
  }

  Future<void> setVolume(double value) async {
    try {
      _volumeController.setVolume(value.clamp(0.0, 1.0));
    } catch (_) {}
  }

  Future<void> volumeUp() async => setVolume(await getVolume() + 0.15);
  Future<void> volumeDown() async => setVolume(await getVolume() - 0.15);

  Future<void> setMuted(bool muted) async {
    try {
      if (muted) {
        _volumeController.muteVolume();
      } else {
        _volumeController.setVolume(0.5);
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Brightness
  // ------------------------------------------------------------------

  Future<bool> setBrightness(double value) async {
    final v = value.clamp(0.0, 1.0);
    try {
      await _brightnessController.setScreenBrightness(v);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<double?> getBrightness() async {
    try {
      return await _brightnessController.current;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Alarms (native MethodChannel — no android_intent_plus needed)
  // ------------------------------------------------------------------

  Future<bool> setAlarm({
    required int hour,
    required int minute,
    String label = 'PrivateAgent alarm',
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeMethod('setAlarm', {
        'hour': hour,
        'minute': minute,
        'label': label,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // Contacts & dialer
  // ------------------------------------------------------------------

  Future<bool> requestContactsPermission() async {
    try {
      return await FlutterContacts.requestPermission();
    } catch (_) {
      return false;
    }
  }

  Future<List<ContactHit>> searchContacts(String query,
      {int limit = 10}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    if (!await requestContactsPermission()) return const [];
    try {
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
      );
      final hits = <ContactHit>[];
      for (final c in contacts) {
        final name = c.displayName;
        if (name.toLowerCase().contains(q)) {
          hits.add(ContactHit(
            id: c.id,
            name: name,
            phone: c.phones.isEmpty ? null : c.phones.first.number,
          ));
          if (hits.length >= limit) break;
        }
      }
      return hits;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> dial(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // Local notifications
  // ------------------------------------------------------------------

  Future<void> _ensureNotifications() async {
    if (_notificationsReady) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(settings);
    _notificationsReady = true;
  }

  Future<void> notify(String title, String body) async {
    try {
      await _ensureNotifications();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'agent_status',
          'Agent Status',
          channelDescription: 'Task progress and completion notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
        title,
        body,
        details,
      );
    } catch (_) {}
  }
}

