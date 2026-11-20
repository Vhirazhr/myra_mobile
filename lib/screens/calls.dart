import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../data/device.dart';
import '../data/myra.dart';
import '../ui/common.dart';

class Calls extends StatelessWidget {
  const Calls(this.api, this.feed, {super.key});
  final Myra api;
  final ChangeFeed feed;
  @override
  Widget build(BuildContext c) => Loaded<List<List<DbRow>>>(
    signal: feed,
    load: () => Future.wait([api.list('calls'), api.list('characters')]),
    builder: (data, reload) {
      final chars = {for (final r in data[1]) r['id']: r};
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: pink,
                foregroundColor: ink,
                child: Icon(Icons.add_call),
              ),
              title: const Text('Panggilan baru'),
              subtitle: const Text('Hubungi karakter dengan suara'),
              onTap: () async {
                final target = await showModalBottomSheet<DbRow>(
                  context: c,
                  builder: (d) => SafeArea(
                    child: data[1].isEmpty
                        ? const Empty(
                            Icons.person_outline,
                            'Belum ada karakter',
                            'Buat karakter dari tab Chat.',
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final r in data[1].where(
                                (r) => r['status'] == 'active',
                              ))
                                ListTile(
                                  leading: Avatar(
                                    api,
                                    str(r, 'name'),
                                    path: str(r, 'portrait'),
                                  ),
                                  title: Text(str(r, 'name')),
                                  onTap: () => Navigator.pop(d, r),
                                ),
                            ],
                          ),
                  ),
                );
                if (c.mounted && target != null) {
                  go(c, LiveCall(api, feed, target));
                }
              },
            ),
            const SectionTitle('Riwayat'),
            if (data[0].isEmpty)
              const Empty(
                Icons.call_outlined,
                'Belum ada panggilan',
                'Riwayat panggilan dari Android dan web akan muncul di sini.',
              ),
            for (final call in data[0])
              ListTile(
                leading: Avatar(
                  api,
                  str(chars[call['character_id']] ?? {}, 'name'),
                  path: str(chars[call['character_id']] ?? {}, 'portrait'),
                ),
                title: Text(
                  str(chars[call['character_id']] ?? {}, 'name', 'Karakter'),
                ),
                subtitle: Text(
                  '${{'connecting': 'Menghubungkan', 'connected': 'Terhubung', 'ended': 'Selesai', 'failed': 'Gagal'}[call['state']]} · ${dayLabel(call['created_at'])} ${clock(call['created_at'])}',
                ),
                trailing: IconButton(
                  tooltip: 'Telepon lagi',
                  onPressed: chars[call['character_id']] == null
                      ? null
                      : () => go(
                          c,
                          LiveCall(api, feed, chars[call['character_id']]!),
                        ),
                  icon: const Icon(Icons.call_outlined),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class LiveCall extends StatefulWidget {
  const LiveCall(this.api, this.feed, this.character, {super.key});
  final Myra api;
  final ChangeFeed feed;
  final DbRow character;
  @override
  State<LiveCall> createState() => _LiveCall();
}

class _LiveCall extends State<LiveCall> with WidgetsBindingObserver {
  late final Myra api;
  late final ChangeFeed feed;
  bool closingRoute = false;
  WebSocket? socket;
  StreamSubscription<dynamic>? audio;
  Timer? deadline, ticker;
  String? record;
  DateTime? connectedAt;
  String status = 'Menghubungkan…';
  bool ended = false, mute = false, loud = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    api = widget.api;
    feed = widget.feed;
    start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) finish();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    closingRoute = true;
    unawaited(finish());
    super.dispose();
  }

  Future<void> start() async {
    try {
      await Device.liveStart();
      if (ended) {
        await Device.liveEnd();
        return;
      }
      final token = await api.action('live-token', widget.character['id']);
      record = token['id'];
      if (ended) {
        await saveEnd(false);
        return;
      }
      final uri = Uri(
        scheme: 'wss',
        host: 'generativelanguage.googleapis.com',
        path:
            '/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained',
        queryParameters: {'access_token': token['token']},
      );
      final connection = await WebSocket.connect(
        uri.toString(),
      ).timeout(const Duration(seconds: 25));
      if (ended) {
        await connection.close();
        return;
      }
      socket = connection;
      deadline = Timer(
        const Duration(seconds: 25),
        () => finish('Gemini belum mengonfirmasi sambungan.'),
      );
      connection.add(
        jsonEncode({
          'setup': {'model': 'models/${token['model']}'},
        }),
      );
      await for (final data in connection) {
        if (ended) break;
        final response = jsonDecode(
          data is String ? data : utf8.decode(List<int>.from(data)),
        );
        if (response['error'] != null) {
          throw StateError(response['error']['message'] ?? 'Panggilan gagal.');
        }
        if (response['setupComplete'] != null && connectedAt == null) {
          deadline?.cancel();
          connectedAt = DateTime.now().toUtc();
          await api.db
              .from('calls')
              .update({
                'state': 'connected',
                'started_at': connectedAt!.toIso8601String(),
              })
              .eq('id', record!)
              .eq('state', 'connecting');
          if (ended) break;
          audio = Device.pcm.receiveBroadcastStream().listen((bytes) {
            if (!mute && !ended && connection.readyState == WebSocket.open) {
              connection.add(
                jsonEncode({
                  'realtimeInput': {
                    'audio': {
                      'mimeType': 'audio/pcm;rate=16000',
                      'data': base64Encode(List<int>.from(bytes)),
                    },
                  },
                }),
              );
            }
          }, onError: (e) => finish(readable(e)));
          if (mounted) setState(() => status = 'Terhubung');
          ticker = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        }
        final content = response['serverContent'];
        if (content?['interrupted'] == true) await Device.interrupt();
        for (final p in content?['modelTurn']?['parts'] ?? []) {
          final encoded = p['inlineData']?['data'];
          if (encoded != null && !ended) {
            await Device.playPcm(base64Decode(encoded));
          }
        }
      }
      if (!ended) {
        await finish(
          connectedAt == null ? 'Sambungan ditutup sebelum terhubung.' : null,
        );
      }
    } catch (e) {
      if (!ended) await finish(readable(e));
    }
  }

  Future<void> saveEnd(bool failed) async {
    if (record != null) {
      await api.db
          .from('calls')
          .update({
            'state': failed ? 'failed' : 'ended',
            'ended_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', record!);
      feed.refresh();
    }
  }

  Future<void> finish([String? reason]) async {
    if (ended) return;
    ended = true;
    deadline?.cancel();
    ticker?.cancel();
    if (mounted && !closingRoute) {
      setState(() => status = reason ?? 'Panggilan selesai');
    }
    try {
      await audio?.cancel();
      await Device.liveEnd();
    } finally {
      unawaited(socket?.close());
      try {
        await saveEnd(reason != null);
      } catch (e) {
        if (mounted) alert(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final seconds = connectedAt == null
        ? 0
        : DateTime.now().toUtc().difference(connectedAt!).inSeconds;
    return Scaffold(
      appBar: AppBar(title: const Text('Panggilan suara')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Avatar(
                  widget.api,
                  str(widget.character, 'name'),
                  path: str(widget.character, 'portrait'),
                  size: 106,
                ),
                const SizedBox(height: 18),
                Text(
                  str(widget.character, 'name'),
                  style: Theme.of(c).textTheme.headlineMedium,
                ),
                const SizedBox(height: 9),
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted),
                ),
                if (connectedAt != null && !ended)
                  Text(
                    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                  ),
                const SizedBox(height: 54),
                Wrap(
                  spacing: 16,
                  children: [
                    if (!ended) ...[
                      IconButton.filledTonal(
                        tooltip: 'Mikrofon',
                        onPressed: () => setState(() => mute = !mute),
                        icon: Icon(mute ? Icons.mic_off : Icons.mic),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Speaker',
                        onPressed: () => runUi(c, () async {
                          await Device.speaker(!loud);
                          if (mounted) setState(() => loud = !loud);
                        }),
                        icon: Icon(loud ? Icons.volume_up : Icons.hearing),
                      ),
                    ],
                    IconButton.filled(
                      tooltip: ended ? 'Tutup' : 'Akhiri panggilan',
                      onPressed: () async {
                        await finish();
                        if (c.mounted) Navigator.pop(c);
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.call_end),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
