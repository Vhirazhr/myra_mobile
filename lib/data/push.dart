import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'myra.dart';

class PushBinding {
  PushBinding(this.api, this.open);
  final Myra api;
  final Future<void> Function(String id) open;
  static const channel = MethodChannel('id.myra.mobile/push');
  String get pref => 'push_${api.uid}';
  bool disposed = false;
  Future<void>? syncing;
  void attach() {
    channel.setMethodCallHandler((m) async {
      if (disposed) return;
      if (m.method == 'token') await syncIfEnabled();
      if (m.method == 'notice' && m.arguments is String) {
        await open(m.arguments);
      }
    });
    unawaited(_initial());
  }

  Future<void> _initial() async {
    try {
      final n = await channel.invokeMethod<String>('initial');
      if (!disposed && n != null) await open(n);
      await syncIfEnabled();
    } catch (_) {
      /* A notification can refer to a deleted record. */
    }
  }

  Future<bool> enabled() async =>
      (await SharedPreferences.getInstance()).getBool(pref) ?? false;
  Future<void> syncIfEnabled() async {
    if (disposed || !await enabled()) return;
    try {
      await register();
    } catch (_) {
      /* Retry on next resume after transient failures. */
    }
  }

  Future<void> register() =>
      syncing ??= _register().whenComplete(() => syncing = null);
  Future<void> _register() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await channel.invokeMethod<String>('enable');
    if (token == null || token.isEmpty) {
      throw StateError('Token FCM belum tersedia.');
    }
    final key = 'device_${api.uid}';
    final id = prefs.getString(key) ?? const Uuid().v4();
    await prefs.setString(key, id);
    await api.db.from('devices').upsert({
      'id': id,
      'token': token,
      'name': 'MYRA Android',
    }, onConflict: 'id');
    await prefs.setBool(pref, true);
  }

  Future<void> disable() async {
    await syncing;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('device_${api.uid}');
    if (id != null) await api.db.from('devices').delete().eq('id', id);
    await prefs.setBool(pref, false);
    if (id != null) await channel.invokeMethod('disable');
  }

  void dispose() {
    disposed = true;
    channel.setMethodCallHandler(null);
  }
}
