import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/myra.dart';
import '../data/device.dart';
import '../ui/common.dart';
import 'calls.dart';

class Chat extends StatefulWidget {
  const Chat(this.api, this.feed, this.thread, {super.key});
  final Myra api;
  final ChangeFeed feed;
  final DbRow thread;
  @override
  State<Chat> createState() => _Chat();
}

class _Chat extends State<Chat> with WidgetsBindingObserver {
  late final Myra api;
  late final ChangeFeed feed;
  final draft = TextEditingController();
  List<DbRow> messages = [], members = [], reactions = [];
  late DbRow thread = Map.of(widget.thread);
  final mentions = <String>{};
  DbRow? reply;
  LocalMedia? file;
  MediaAsset? uploaded;
  String query = '', memory = 'automatic';
  String? pendingId, failedGeneration;
  bool busy = false,
      recording = false,
      loaded = false,
      more = false,
      loadingOlder = false,
      searching = false;
  Object? error;
  int version = 0;
  Timer? debounce;
  String get id => thread['id'];
  @override
  void initState() {
    super.initState();
    api = widget.api;
    feed = widget.feed;
    WidgetsBinding.instance.addObserver(this);
    feed.addListener(refresh);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    feed.removeListener(refresh);
    debounce?.cancel();
    draft.dispose();
    if (recording) unawaited(Device.stopNote().catchError((_) => null));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused && recording) record();
  }

  Future<List<DbRow>> getReactions(List<DbRow> list) async {
    if (list.isEmpty) return [];
    final result = <DbRow>[];
    for (var i = 0; i < list.length; i += 50) {
      result.addAll(
        await api.db
            .from('message_reactions')
            .select()
            .inFilter(
              'message_id',
              list.skip(i).take(50).map((r) => r['id']).toList(),
            ),
      );
    }
    return result;
  }

  Future<void> refresh() async {
    final v = ++version;
    try {
      final page = await api.history(id, query: query);
      final roster = await api.participants(thread);
      final previous = messages
          .where(
            (m) =>
                page.isNotEmpty &&
                DateTime.parse(
                  m['created_at'],
                ).isBefore(DateTime.parse(page.last['created_at'])),
          )
          .toList();
      final combined = [...page, if (page.length == 50) ...previous];
      final r = await getReactions(combined);
      if (mounted && v == version) {
        setState(() {
          if (previous.isEmpty || page.length < 50) more = page.length == 50;
          messages = combined;
          members = roster;
          reactions = r;
          loaded = true;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && v == version) setState(() => error = e);
    }
  }

  Future<void> older() async {
    if (loadingOlder || messages.isEmpty) return;
    setState(() => loadingOlder = true);
    final q = query;
    try {
      final page = await api.history(id, before: messages.last, query: q);
      final r = await getReactions(page);
      if (mounted && q == query) {
        setState(() {
          final seen = messages.map((m) => m['id']).toSet();
          messages.addAll(page.where((m) => seen.add(m['id'])));
          reactions.addAll(r);
          more = page.length == 50;
        });
      }
    } catch (e) {
      if (mounted) alert(context, e);
    } finally {
      if (mounted) setState(() => loadingOlder = false);
    }
  }

  void filter(String v) {
    debounce?.cancel();
    setState(() {
      query = v;
      messages = [];
      loaded = false;
      ++version;
    });
    debounce = Timer(const Duration(milliseconds: 200), refresh);
  }

  Future<void> generate(String message) async {
    try {
      final source = await api.db
          .from('messages')
          .select('mime,transcript')
          .eq('id', message)
          .single();
      if (str(source, 'mime').startsWith('audio/') &&
          str(source, 'transcript').isEmpty) {
        await api.action('transcribe', message);
      }
      await api.action('generate', message);
      if (mounted) setState(() => failedGeneration = null);
    } catch (e) {
      if (mounted) setState(() => failedGeneration = message);
      rethrow;
    } finally {
      feed.refresh();
    }
  }

  Future<void> send() async {
    if (busy || recording || (draft.text.trim().isEmpty && file == null)) {
      return;
    }
    setState(() => busy = true);
    try {
      pendingId ??= const Uuid().v4();
      if (file != null) {
        uploaded ??= await api.upload('conversation-media', file!);
      }
      final item = await api.send(
        id: pendingId!,
        thread: id,
        text: draft.text.trim().isEmpty
            ? (file?.mime.startsWith('audio/') == true
                  ? 'Pesan suara'
                  : 'Lampiran media')
            : draft.text.trim(),
        memory: memory,
        reply: reply?['id'],
        mentions: mentions.toList(),
        media: uploaded,
      );
      if (mounted) {
        setState(() {
          draft.clear();
          file = null;
          uploaded = null;
          pendingId = null;
          reply = null;
          mentions.clear();
        });
        await refresh();
      }
      feed.refresh();
      await generate(item['id']);
    } catch (e) {
      if (mounted) alert(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> record() async {
    if (busy) return;
    try {
      if (recording) {
        final m = await Device.stopNote();
        if (mounted) {
          setState(() {
            recording = false;
            if (m != null) {
              file = m;
              uploaded = null;
            }
          });
        }
      } else {
        await Device.startNote();
        if (mounted) setState(() => recording = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => recording = false);
        alert(context, e);
      }
    }
  }

  String speaker(DbRow m) => m['role'] == 'user'
      ? 'Kamu'
      : str(
          firstRow(
                members.where((r) => r['id'] == m['character_id']).toList(),
              ) ??
              thread,
          'name',
        );
  Future<void> actions(DbRow m) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                children: [
                  for (final e in ['💗', '👍', '😂', '✨', '🥹'])
                    TextButton(
                      onPressed: () => Navigator.pop(c, e),
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                ],
              ),
              for (final pair in {
                'reply': 'Balas pesan',
                if (m['role'] == 'user') 'edit': 'Edit pesan',
                'delete': 'Hapus pesan',
                if (m['role'] == 'user') 'generate': 'Minta balasan AI',
                if (m['role'] == 'assistant' && str(m, 'attachment').isEmpty)
                  'voice-note': 'Buat pesan suara',
                if (str(m, 'mime').startsWith('audio/'))
                  'transcribe': 'Transkripsikan suara',
              }.entries)
                ListTile(
                  title: Text(pair.value),
                  onTap: () => Navigator.pop(c, pair.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null || busy) return;
    if (selected == 'reply') {
      setState(() => reply = m);
      return;
    }
    setState(() => busy = true);
    try {
      if (selected == 'edit') {
        final text = await askText(
          context,
          'Edit pesan',
          initial: str(m, 'body'),
          limit: 24000,
        );
        if (text == null) return;
        await api.db
            .from('messages')
            .update({'body': text})
            .eq('id', m['id'])
            .eq('role', 'user')
            .select('id')
            .single();
      } else if (selected == 'delete') {
        if (!await confirm(
          context,
          'Hapus pesan ini?',
          'Balasan dan memori yang terkait juga dapat terhapus.',
        )) {
          return;
        }
        await api.db
            .from('messages')
            .delete()
            .eq('id', m['id'])
            .select('id')
            .single();
        if (failedGeneration == m['id']) failedGeneration = null;
        messages.removeWhere((item) => item['id'] == m['id']);
      } else if (selected == 'generate') {
        await generate(m['id']);
      } else if (['voice-note', 'transcribe'].contains(selected)) {
        await api.action(selected, m['id']);
      } else {
        await api.toggleReaction(m['id'], selected);
      }
      feed.refresh();
      await refresh();
    } catch (e) {
      if (mounted) alert(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> options() async {
    final t = await api.db.from('conversations').select().eq('id', id).single();
    if (!mounted) return;
    String mode = t['mode'], stage = t['relationship_stage'] ?? stages.first;
    bool proactive = t['proactive'];
    final lang = TextEditingController(text: t['language']);
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Pengaturan chat'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: lang,
                  decoration: const InputDecoration(labelText: 'Bahasa'),
                ),
                DropdownButtonFormField(
                  initialValue: mode,
                  decoration: const InputDecoration(
                    labelText: 'Mode percakapan',
                  ),
                  items: [
                    for (final v in modes)
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) => update(() => mode = v!),
                ),
                DropdownButtonFormField(
                  isExpanded: true,
                  initialValue: stage,
                  decoration: const InputDecoration(
                    labelText: 'Tahap hubungan',
                  ),
                  items: [
                    for (final v in stages)
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) => update(() => stage = v!),
                ),
                if (t['character_id'] != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: proactive,
                    title: const Text('Boleh memulai chat'),
                    onChanged: (v) => update(() => proactive = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    final language = lang.text.trim();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    lang.dispose();
    if (save != true) return;
    if (language.isEmpty) throw StateError('Isi bahasa percakapan.');
    thread = await api.db
        .from('conversations')
        .update({
          'mode': mode,
          'language': language,
          'relationship_stage': stage,
          'proactive': proactive,
        })
        .eq('id', id)
        .select()
        .single();
    feed.refresh();
  }

  @override
  Widget build(BuildContext c) {
    final isGroup = thread['group_id'] != null;
    return Scaffold(
      backgroundColor: switch (api.chatPreference(id, 'wallpaper')) {
        'rose' => const Color(0xff281d24),
        'plum' => const Color(0xff221c2c),
        _ => ink,
      },
      appBar: AppBar(
        titleSpacing: 0,
        title: searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Cari pesan'),
                onChanged: filter,
              )
            : Row(
                children: [
                  Avatar(
                    api,
                    str(thread, 'name'),
                    group: isGroup,
                    path: isGroup || members.isEmpty
                        ? ''
                        : str(members.first, 'portrait'),
                    size: 36,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          str(thread, 'name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          isGroup
                              ? '${members.length} karakter'
                              : 'Karakter AI',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (!isGroup && !searching && members.isNotEmpty)
            IconButton(
              tooltip: 'Panggilan suara',
              onPressed: () => go(c, LiveCall(api, feed, members.first)),
              icon: const Icon(Icons.call_outlined),
            ),
          PopupMenuButton<String>(
            onSelected: (s) {
              if (s == 'search') {
                setState(() => searching = !searching);
                filter('');
              } else if (s == 'wallpaper') {
                runUi(c, () async {
                  final color = await showModalBottomSheet<String>(
                    context: c,
                    builder: (d) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final e in {
                            'black': 'Hitam MYRA',
                            'rose': 'Rose',
                            'plum': 'Plum',
                          }.entries)
                            ListTile(
                              title: Text(e.value),
                              onTap: () => Navigator.pop(d, e.key),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (color != null) {
                    await api.setChatPreference(id, 'wallpaper', color);
                    if (mounted) setState(() {});
                  }
                });
              } else {
                runUi(c, options);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'search',
                child: Text(searching ? 'Tutup pencarian' : 'Cari pesan'),
              ),
              const PopupMenuItem(
                value: 'wallpaper',
                child: Text('Latar chat'),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Pengaturan chat'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (error != null)
              ListTile(
                title: Text(readable(error!), maxLines: 2),
                trailing: IconButton(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            Expanded(
              child: !loaded && error == null
                  ? const Center(child: CircularProgressIndicator())
                  : messages.isEmpty
                  ? Empty(
                      Icons.chat_bubble_outline,
                      query.isEmpty
                          ? 'Sapa ${thread['name']}'
                          : 'Tidak ada hasil',
                      query.isEmpty
                          ? 'Kirim pesan untuk memulai percakapan.'
                          : 'Coba kata lain.',
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                      itemCount: messages.length + (more ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == messages.length) {
                          return TextButton(
                            onPressed: loadingOlder ? null : older,
                            child: const Text('Pesan sebelumnya'),
                          );
                        }
                        final m = messages[i],
                            mine = m['role'] == 'user',
                            quoted = firstRow(
                              messages
                                  .where((x) => x['id'] == m['reply_to'])
                                  .toList(),
                            );
                        return Column(
                          children: [
                            if (i == messages.length - 1 ||
                                dayLabel(str(messages[i + 1], 'created_at')) !=
                                    dayLabel(str(m, 'created_at')))
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  dayLabel(str(m, 'created_at')),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                              ),
                            MessageBubble(
                              mine: mine,
                              speaker: m['is_streaming'] == true
                                  ? '${speaker(m)} sedang mengetik…'
                                  : speaker(m),
                              body: str(m, 'body'),
                              time: mine
                                  ? '${clock(str(m, 'created_at'))} · ${messages.any((r) => r['source_id'] == m['id']) ? 'Dibalas' : 'Tersimpan'}'
                                  : clock(str(m, 'created_at')),
                              quote: m['reply_to'] == null
                                  ? null
                                  : str(
                                      quoted ?? {},
                                      'body',
                                      'Pesan sebelumnya',
                                    ),
                              transcript: str(m, 'transcript'),
                              reactions: reactions
                                  .where((r) => r['message_id'] == m['id'])
                                  .map((r) => r['emoji'])
                                  .join(' '),
                              media: str(m, 'attachment').isEmpty
                                  ? null
                                  : ChatMedia(api, m),
                              onHold: () => actions(m),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (busy) const LinearProgressIndicator(minHeight: 2),
            if (failedGeneration != null)
              ListTile(
                dense: true,
                title: const Text('Pesan tersimpan. Balasan AI tertunda.'),
                trailing: TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          await runUi(c, () => generate(failedGeneration!));
                          if (mounted) setState(() => busy = false);
                        },
                  child: const Text('Coba lagi'),
                ),
              ),
            if (reply != null || file != null || mentions.isNotEmpty)
              ListTile(
                dense: true,
                leading: Icon(reply != null ? Icons.reply : Icons.attach_file),
                title: Text(
                  [
                    if (reply != null) str(reply!, 'body'),
                    if (file != null) file!.name,
                    for (final m in members.where(
                      (m) => mentions.contains(m['id']),
                    ))
                      '@${m['name']}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          file = null;
                          uploaded = null;
                          reply = null;
                          mentions.clear();
                        }),
                  icon: const Icon(Icons.close),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 9, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PopupMenuButton<String>(
                    tooltip: 'Opsi pesan',
                    enabled: !busy && !recording,
                    icon: const Icon(Icons.add_circle_outline),
                    onSelected: (v) => runUi(c, () async {
                      if (v == 'media') {
                        final m = await Device.pick('media');
                        if (mounted && m != null) {
                          setState(() {
                            file = m;
                            uploaded = null;
                          });
                        }
                      } else if (v.startsWith('@')) {
                        setState(() {
                          final k = v.substring(1);
                          if (!mentions.add(k)) mentions.remove(k);
                        });
                      } else {
                        setState(() => memory = v);
                      }
                    }),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'media',
                        child: Text('Lampirkan media'),
                      ),
                      for (final m in memoryModes.entries)
                        CheckedPopupMenuItem(
                          value: m.key,
                          checked: memory == m.key,
                          child: Text(m.value),
                        ),
                      if (isGroup)
                        for (final m in members)
                          CheckedPopupMenuItem(
                            value: '@${m['id']}',
                            checked: mentions.contains(m['id']),
                            child: Text('@${m['name']}'),
                          ),
                    ],
                  ),
                  Expanded(
                    child: TextField(
                      controller: draft,
                      enabled: !busy && !recording,
                      onChanged: (_) => setState(() {}),
                      maxLines: 5,
                      minLines: 1,
                      maxLength: 24000,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: recording ? 'Sedang merekam…' : 'Pesan',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: recording
                        ? 'Selesai merekam'
                        : draft.text.trim().isEmpty && file == null
                        ? 'Rekam suara'
                        : 'Kirim',
                    onPressed: busy
                        ? null
                        : recording || draft.text.trim().isEmpty && file == null
                        ? record
                        : send,
                    icon: Icon(
                      recording
                          ? Icons.stop
                          : draft.text.trim().isEmpty && file == null
                          ? Icons.mic
                          : Icons.send_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.mine,
    required this.body,
    required this.speaker,
    required this.time,
    this.quote,
    this.transcript = '',
    this.reactions = '',
    this.media,
    this.onHold,
  });
  final bool mine;
  final String body, speaker, time, transcript, reactions;
  final String? quote;
  final Widget? media;
  final VoidCallback? onHold;
  @override
  Widget build(BuildContext c) {
    final fg = mine ? ink : Colors.white;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onHold,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(c).width * .8,
          ),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? pale : panel,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 3),
              bottomRight: Radius.circular(mine ? 3 : 16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Text(
                  speaker,
                  style: const TextStyle(
                    color: pink,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              if (quote != null)
                Container(
                  padding: const EdgeInsets.only(left: 8),
                  margin: const EdgeInsets.only(bottom: 5),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: mine ? Colors.black45 : pink,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    quote!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg.withValues(alpha: .7)),
                  ),
                ),
              if (media != null) media!,
              Text(body, style: TextStyle(color: fg, height: 1.35)),
              if (transcript.isNotEmpty)
                Text(
                  transcript,
                  style: TextStyle(color: fg, fontStyle: FontStyle.italic),
                ),
              Text(
                time,
                style: TextStyle(
                  fontSize: 10,
                  color: fg.withValues(alpha: .65),
                ),
              ),
              if (reactions.isNotEmpty) Text(reactions),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatMedia extends StatelessWidget {
  const ChatMedia(this.api, this.m, {super.key});
  final Myra api;
  final DbRow m;
  @override
  Widget build(BuildContext c) {
    final mime = str(m, 'mime');
    return FutureBuilder<String>(
      future: api.signed(
        str(
          m,
          'attachment_bucket',
          m['role'] == 'assistant' && mime.startsWith('audio/')
              ? 'voice-media'
              : 'conversation-media',
        ),
        m['attachment'],
      ),
      builder: (_, s) {
        if (s.hasError) return Text(readable(s.error!));
        if (!s.hasData) return const LinearProgressIndicator();
        if (mime.startsWith('image/')) {
          return GestureDetector(
            onTap: () => go(
              c,
              Scaffold(
                appBar: AppBar(),
                body: Center(
                  child: InteractiveViewer(child: Image.network(s.data!)),
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                s.data!,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Text('Gambar gagal dimuat'),
              ),
            ),
          );
        }
        return TextButton.icon(
          style: TextButton.styleFrom(
            backgroundColor: soft,
            foregroundColor: pale,
          ),
          onPressed: () => runUi(c, () => Device.open(s.data!, mime)),
          icon: const Icon(Icons.play_arrow),
          label: Text(
            mime.startsWith('audio/') ? 'Putar audio' : 'Putar video',
          ),
        );
      },
    );
  }
}
