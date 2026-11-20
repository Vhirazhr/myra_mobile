import 'dart:async';
import 'package:flutter/material.dart';
import '../data/myra.dart';
import '../data/device.dart';
import '../ui/common.dart';
import 'chat.dart';

String audienceKey(DbRow r) => r['audience'] == 'private'
    ? 'private'
    : '${r['audience']}:${r['group_id'] ?? r['universe_id']}';
Map<String, String> audiences(List<DbRow> groups, List<DbRow> worlds) => {
  'private': 'Pribadi',
  for (final g in groups) 'group:${g['id']}': 'Grup · ${g['name']}',
  for (final u in worlds) 'universe:${u['id']}': 'Universe · ${u['name']}',
};

class Updates extends StatefulWidget {
  const Updates(this.api, this.feed, {super.key});
  final Myra api;
  final ChangeFeed feed;
  @override
  State<Updates> createState() => _Updates();
}

class _Updates extends State<Updates> {
  String selected = 'private';
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => widget.feed.refresh(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Loaded<List<List<DbRow>>>(
    key: ValueKey(selected),
    signal: widget.feed,
    load: () => Future.wait([
      widget.api.feed(
        group: selected.startsWith('group:') ? selected.split(':').last : null,
        universe: selected.startsWith('universe:')
            ? selected.split(':').last
            : null,
      ),
      widget.api.list('characters'),
      widget.api.list('groups'),
      widget.api.list('universes'),
    ]),
    builder: (data, reload) {
      final choices = audiences(data[2], data[3]);
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: pink,
                foregroundColor: ink,
                child: Icon(Icons.add_a_photo_outlined),
              ),
              title: const Text('Buat status'),
              subtitle: const Text('Bagikan momen selama 24 jam'),
              onTap: () =>
                  go(c, StoryForm(widget.api, widget.feed, data[1], choices)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: choices.containsKey(selected)
                    ? selected
                    : 'private',
                decoration: const InputDecoration(labelText: 'Audiens'),
                items: [
                  for (final e in choices.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => selected = v!),
              ),
            ),
            const SectionTitle('Status terbaru'),
            if (data[0].isEmpty)
              const Empty(
                Icons.donut_large,
                'Belum ada status',
                'Status yang dibagikan ke audiens ini akan muncul di sini.',
              ),
            for (final s in data[0])
              Builder(
                builder: (c) {
                  final ch =
                      firstRow(
                        data[1]
                            .where((ch) => ch['id'] == s['character_id'])
                            .toList(),
                      ) ??
                      {};
                  return ListTile(
                    leading: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: pink, width: 2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Avatar(
                          widget.api,
                          str(ch, 'name'),
                          path: str(ch, 'portrait'),
                          size: 41,
                        ),
                      ),
                    ),
                    title: Text(str(ch, 'name')),
                    subtitle: Text(str(s, 'name')),
                    trailing: Text(
                      clock(str(s, 'publish_at')),
                      style: const TextStyle(color: muted),
                    ),
                    onTap: () => go(c, StoryPage(widget.api, widget.feed, s)),
                  );
                },
              ),
          ],
        ),
      );
    },
  );
}

class StoryForm extends StatefulWidget {
  const StoryForm(this.api, this.feed, this.chars, this.choices, {super.key});
  final Myra api;
  final ChangeFeed feed;
  final List<DbRow> chars;
  final Map<String, String> choices;
  @override
  State<StoryForm> createState() => _StoryForm();
}

class _StoryForm extends State<StoryForm> {
  String? author;
  String audience = 'private';
  LocalMedia? file;
  MediaAsset? uploaded;
  final caption = TextEditingController();
  @override
  void dispose() {
    caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Status baru')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: author,
          decoration: const InputDecoration(labelText: 'Karakter'),
          items: [
            for (final ch in widget.chars)
              DropdownMenuItem(
                value: str(ch, 'id'),
                child: Text(str(ch, 'name')),
              ),
          ],
          onChanged: (v) => setState(() => author = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: audience,
          decoration: const InputDecoration(labelText: 'Audiens'),
          items: [
            for (final e in widget.choices.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => audience = v!),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: caption,
          minLines: 4,
          maxLines: 8,
          maxLength: 2000,
          decoration: const InputDecoration(hintText: 'Apa ceritamu hari ini?'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(file?.name ?? 'Pilih foto atau video'),
          onPressed: () => runUi(c, () async {
            final m = await Device.pick('visual');
            if (mounted && m != null) {
              setState(() {
                file = m;
                uploaded = null;
              });
            }
          }),
        ),
        BusyButton('Bagikan status', () async {
          if (author == null) throw StateError('Pilih karakter terlebih dulu.');
          final text = caption.text.trim();
          if (text.isEmpty && file == null) {
            throw StateError('Tulis status atau tambahkan foto/video.');
          }
          if (file != null) {
            uploaded ??= await widget.api.upload(
              'stories',
              file!,
              character: author,
            );
          }
          final now = DateTime.now().toUtc();
          await widget.api.db.from('stories').insert({
            'name': text.isEmpty
                ? 'Status baru'
                : String.fromCharCodes(text.runes.take(160)),
            'caption': text,
            'media': uploaded?.path ?? '',
            'mime': uploaded?.mime ?? '',
            'status': 'published',
            'character_id': author,
            'audience': audience.split(':').first,
            if (audience.startsWith('group:'))
              'group_id': audience.split(':').last,
            if (audience.startsWith('universe:'))
              'universe_id': audience.split(':').last,
            'publish_at': now.toIso8601String(),
            'expires_at': now.add(const Duration(hours: 24)).toIso8601String(),
          });
          widget.feed.refresh();
          if (c.mounted) Navigator.pop(c);
        }),
      ],
    ),
  );
}

class StoryPage extends StatefulWidget {
  const StoryPage(this.api, this.feed, this.story, {super.key});
  final Myra api;
  final ChangeFeed feed;
  final DbRow story;
  @override
  State<StoryPage> createState() => _StoryPage();
}

class _StoryPage extends State<StoryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      runUi(context, () async {
        await widget.api.storyView(widget.story['id']);
        widget.feed.refresh();
      });
    });
  }

  @override
  Widget build(BuildContext c) {
    final s = widget.story;
    return Scaffold(
      appBar: AppBar(title: const Text('Status')),
      body: Loaded<List<DbRow>>(
        signal: widget.feed,
        load: () =>
            widget.api.list('story_activity', by: 'story_id', value: s['id']),
        builder: (activity, reload) {
          final liked = firstRow(
            activity
                .where(
                  (a) => a['kind'] == 'like' && a['owner_id'] == widget.api.uid,
                )
                .toList(),
          );
          Future<void> act(String kind, String value) async {
            if (kind == 'like' && liked != null) {
              await widget.api.db
                  .from('story_activity')
                  .delete()
                  .eq('id', liked['id']);
            } else {
              await widget.api.db.from('story_activity').insert({
                'story_id': s['id'],
                'kind': kind,
                'body': value,
              });
            }
            widget.feed.refresh();
            await reload();
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (str(s, 'media').isNotEmpty)
                ChatMedia(widget.api, {
                  'attachment_bucket': 'stories',
                  'attachment': s['media'],
                  'mime': s['mime'],
                }),
              const SizedBox(height: 20),
              Text(
                str(s, 'caption').isEmpty ? str(s, 'name') : str(s, 'caption'),
                style: Theme.of(c).textTheme.headlineSmall,
              ),
              Text(
                '${dayLabel(s['publish_at'])} · ${clock(s['publish_at'])}',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                children: [
                  IconButton(
                    tooltip: 'Suka',
                    onPressed: () => runUi(c, () => act('like', '')),
                    icon: Icon(
                      liked == null ? Icons.favorite_outline : Icons.favorite,
                      color: pink,
                    ),
                  ),
                  for (final e in ['✨', '🥰', '😄'])
                    TextButton(
                      onPressed: () => runUi(c, () => act('reaction', e)),
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  IconButton(
                    tooltip: 'Balas status',
                    onPressed: () => runUi(c, () async {
                      final v = await askText(c, 'Balas status');
                      if (v != null) await act('reply', v);
                    }),
                    icon: const Icon(Icons.reply),
                  ),
                ],
              ),
              const Divider(),
              for (final a in activity.where(
                (a) => a['kind'] == 'reply' || a['kind'] == 'reaction',
              ))
                ListTile(
                  leading: Icon(
                    a['kind'] == 'reply' ? Icons.reply : Icons.favorite_outline,
                  ),
                  title: Text(str(a, 'body')),
                  trailing: Text(clock(a['created_at'])),
                ),
            ],
          );
        },
      ),
    );
  }
}
