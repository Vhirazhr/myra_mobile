import 'package:flutter/services.dart';
import 'myra.dart';

class Device {
  static const bridge = MethodChannel('id.myra.mobile/device');
  static const pcm = EventChannel('id.myra.mobile/pcm');
  static Future<LocalMedia?> pick(String type) async {
    final v = await bridge.invokeMapMethod<String, dynamic>('pick', {
      'type': type,
    });
    return media(v);
  }

  static LocalMedia? media(Map<String, dynamic>? v) =>
      v == null ? null : LocalMedia(v['path'], v['name'], v['mime']);
  static Future<void> startNote() => bridge.invokeMethod('startNote');
  static Future<LocalMedia?> stopNote() async =>
      media(await bridge.invokeMapMethod<String, dynamic>('stopNote'));
  static Future<void> open(String url, String mime) =>
      bridge.invokeMethod('openMedia', {'url': url, 'mime': mime});
  static Future<void> liveStart() => bridge.invokeMethod('liveStart');
  static Future<void> liveEnd() => bridge.invokeMethod('liveEnd');
  static Future<void> playPcm(Uint8List b) => bridge.invokeMethod('playPcm', b);
  static Future<void> interrupt() => bridge.invokeMethod('interrupt');
  static Future<void> speaker(bool on) => bridge.invokeMethod('speaker', on);
}
