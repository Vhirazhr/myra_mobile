import 'package:flutter/material.dart';
import '../data/myra.dart';
import '../data/device.dart';
import '../ui/common.dart';
import 'chat.dart';
import 'worlds.dart';

class Directory extends StatefulWidget {
  const Directory(this.api, this.feed, {super.key});
  final Myra api;
  final ChangeFeed feed;
  @override
  State<Directory> createState() => _Directory();
}

class _Directory extends State<Directory> {
  String query = '';
  bool opening = false;
  Future<void> open(DbRow target, bool group) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      final t = await widget.api.openChat(target, group: group);
      widget.feed.refresh();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => Chat(widget.api, widget.feed, t),
          ),
        );
      }
    } catch (e) {
      if (mounted) alert(context, e);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Chat baru')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: TextField(
            onChanged: (v) => setState(() => query = v.toLowerCase()),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Cari karakter atau grup',
            ),
          ),
        ),
        if (opening) const LinearProgressIndicator(),
        Expanded(
          child: Loaded<List<List<DbRow>>>(
            signal: widget.feed,
            load: () => Future.wait([
              widget.api.list('characters'),
              widget.api.list('groups'),
            ]),
            builder: (data, reload) {
              final chars = data[0]
                  .where((r) => r['status'] == 'active')
                  .toList();
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: soft,
                        child: Icon(Icons.group_add_outlined, color: pink),
                      ),
                      title: const Text('Grup baru'),
                      onTap: () =>
                          go(c, GroupForm(widget.api, widget.feed, chars)),
                    ),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: soft,
                        child: Icon(Icons.person_add_alt, color: pink),
                      ),
                      title: const Text('Buat karakter'),
                      onTap: () =>
                          go(c, CharacterForm(widget.api, widget.feed)),
                    ),
                    for (final group in [false, true]) ...[
                      SectionTitle(group ? 'Grup' : 'Karakter'),
                      for (final r in (group ? data[1] : chars).where(
                        (r) => str(r, 'name').toLowerCase().contains(query),
                      ))
                        ListTile(
                          leading: Avatar(
                            widget.api,
                            str(r, 'name'),
                            group: group,
                            path: str(r, 'portrait'),
                          ),
                          title: Text(str(r, 'name')),
                          subtitle: Text(
                            group
                                ? str(r, 'mode')
                                : str(r, 'relationship').isEmpty
                                ? 'Karakter AI'
                                : str(r, 'relationship'),
                          ),
                          onTap: () => open(r, group),
                          trailing: group
                              ? IconButton(
                                  tooltip: 'Edit grup',
                                  icon: const Icon(Icons.group_outlined),
                                  onPressed: () => runUi(c, () async {
                                    final roster = await widget.api.db
                                        .from('group_members')
                                        .select('character_id')
                                        .eq('group_id', r['id']);
                                    if (c.mounted) {
                                      go(
                                        c,
                                        GroupForm(
                                          widget.api,
                                          widget.feed,
                                          data[0],
                                          group: r,
                                          initialMembers: [
                                            for (final m in roster)
                                              str(m, 'character_id'),
                                          ],
                                        ),
                                      );
                                    }
                                  }),
                                )
                              : IconButton(
                                  tooltip: 'Profil',
                                  onPressed: () => go(
                                    c,
                                    Profile(widget.api, widget.feed, r),
                                  ),
                                  icon: const Icon(Icons.info_outline),
                                ),
                        ),
                    ],
                    if (chars.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Karakter aktif dari Character Studio akan muncul di sini.',
                          style: TextStyle(color: muted),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class GroupForm extends StatefulWidget {
  const GroupForm(
    this.api,
    this.feed,
    this.chars, {
    this.group,
    this.initialMembers = const [],
    super.key,
  });
  final Myra api;
  final ChangeFeed feed;
  final List<DbRow> chars;
  final DbRow? group;
  final List<String> initialMembers;
  @override
  State<GroupForm> createState() => _GroupForm();
}

class _GroupForm extends State<GroupForm> {
  late final name = TextEditingController(text: widget.group?['name']);
  late final members = widget.initialMembers.toSet();
  late String mode = widget.group?['mode'] ?? 'Natural Chat';
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(widget.group == null ? 'Grup baru' : 'Edit grup'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(
          controller: name,
          maxLength: 180,
          decoration: const InputDecoration(labelText: 'Nama grup'),
        ),
        DropdownButtonFormField<String>(
          initialValue: mode,
          decoration: const InputDecoration(labelText: 'Mode grup'),
          items: [
            for (final v in ['Natural Chat', 'Cinematic Roleplay', 'Hybrid'])
              DropdownMenuItem(value: v, child: Text(v)),
          ],
          onChanged: (v) => setState(() => mode = v!),
        ),
        const SectionTitle('Anggota'),
        for (final ch in widget.chars)
          CheckboxListTile(
            value: members.contains(ch['id']),
            secondary: Avatar(
              widget.api,
              str(ch, 'name'),
              path: str(ch, 'portrait'),
              size: 38,
            ),
            title: Text(str(ch, 'name')),
            onChanged: (v) => setState(() {
              if (v == true) {
                members.add(ch['id']);
              } else {
                members.remove(ch['id']);
              }
            }),
          ),
        BusyButton(
          widget.group == null ? 'Buat grup' : 'Simpan grup',
          () async {
            if (name.text.trim().isEmpty || members.isEmpty) {
              throw StateError(
                'Isi nama grup dan pilih minimal satu karakter.',
              );
            }
            final r = await widget.api.saveGroup(
              name.text.trim(),
              members.toList(),
              mode,
              id: widget.group?['id'],
              description: widget.group?['description'] ?? '',
            );
            widget.feed.refresh();
            if (!c.mounted) return;
            final messenger = ScaffoldMessenger.of(c);
            Navigator.pop(c);
            messenger.showSnackBar(
              SnackBar(content: Text('Grup ${r['name']} tersimpan.')),
            );
          },
        ),
      ],
    ),
  );
}

class Profile extends StatelessWidget {
  const Profile(this.api, this.feed, this.ch, {super.key});
  final Myra api;
  final ChangeFeed feed;
  final DbRow ch;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Profil karakter'),
      actions: [
        IconButton(
          tooltip: 'Edit karakter',
          onPressed: () async {
            await Navigator.push(
              c,
              MaterialPageRoute<void>(
                builder: (_) => CharacterForm(api, feed, row: ch),
              ),
            );
            if (c.mounted) Navigator.pop(c);
          },
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Hapus karakter',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => runUi(c, () async {
            if (!await confirm(
              c,
              'Hapus karakter ${ch['name']}?',
              'Profil, percakapan pribadi, dan catatan terkait akan dihapus dari workspace web dan Android.',
            )) {
              return;
            }
            await api.db
                .from('characters')
                .delete()
                .eq('id', ch['id'])
                .select('id')
                .single();
            feed.refresh();
            if (c.mounted) Navigator.pop(c);
          }),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Center(
          child: Avatar(
            api,
            str(ch, 'name'),
            path: str(ch, 'portrait'),
            size: 110,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          str(ch, 'name'),
          textAlign: TextAlign.center,
          style: Theme.of(c).textTheme.headlineMedium,
        ),
        Text(
          [
            'Karakter AI',
            str(ch, 'pronouns'),
            str(ch, 'relationship'),
          ].where((s) => s.isNotEmpty).join(' · '),
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        BusyButton('Buka chat', () async {
          final t = await api.openChat(ch);
          feed.refresh();
          if (c.mounted) go(c, Chat(api, feed, t));
        }),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Kehidupan karakter'),
          onTap: () => go(c, CharacterLife(api, feed, ch)),
        ),
        for (final entry in {
          'biography': 'Bio',
          'background': 'Latar belakang',
          'communication': 'Gaya bicara',
          'language': 'Bahasa',
          'scenario': 'Skenario dan batasan roleplay',
          'voice': 'Suara karakter',
        }.entries)
          if (str(ch, entry.key).isNotEmpty) ...[
            SectionTitle(entry.value),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(str(ch, entry.key)),
            ),
          ],
      ],
    ),
  );
}

class CharacterForm extends StatefulWidget {
  const CharacterForm(this.api, this.feed, {this.row, super.key});
  final Myra api;
  final ChangeFeed feed;
  final DbRow? row;
  @override
  State<CharacterForm> createState() => _CharacterForm();
}

class _CharacterForm extends State<CharacterForm> {
  static const fields = {
    'name': 'Nama karakter',
    'age': 'Usia',
    'pronouns': 'Pronomina',
    'biography': 'Bio',
    'relationship': 'Hubungan',
    'language': 'Bahasa',
    'communication': 'Gaya bicara',
    'appearance': 'Penampilan',
    'background': 'Latar belakang',
    'scenario': 'Skenario dan batasan roleplay',
    'voice': 'Suara karakter',
  };
  late final controls = {
    for (final k in fields.keys)
      k: TextEditingController(
        text:
            widget.row?[k]?.toString() ??
            (k == 'age'
                ? '24'
                : k == 'language'
                ? 'Indonesian'
                : k == 'voice'
                ? 'Kore'
                : ''),
      ),
  };
  static const traits = [
    'Romantic',
    'Jealous',
    'Clingy',
    'Funny',
    'Cold',
    'Shy',
    'Protective',
    'Playful',
    'Introverted',
    'Extroverted',
    'Confident',
  ];
  late final personality = Map<String, dynamic>.from(
    widget.row?['personality'] ?? {},
  );
  LocalMedia? portrait;
  @override
  void dispose() {
    for (final v in controls.values) {
      v.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(widget.row == null ? 'Buat karakter' : 'Edit karakter'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        OutlinedButton.icon(
          onPressed: () => runUi(c, () async {
            final m = await Device.pick('image/*');
            if (m != null && mounted) setState(() => portrait = m);
          }),
          icon: const Icon(Icons.photo_outlined),
          label: Text(portrait?.name ?? 'Pilih foto profil'),
        ),
        for (final f in fields.entries)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: controls[f.key],
              keyboardType: f.key == 'age' ? TextInputType.number : null,
              maxLines: ['background', 'biography', 'scenario'].contains(f.key)
                  ? 3
                  : 1,
              decoration: InputDecoration(labelText: f.value),
            ),
          ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Kepribadian'),
          children: [
            for (final key in traits)
              ListTile(
                title: Text(key),
                subtitle: Slider(
                  value: ((personality[key] as num?)?.toDouble() ?? 50).clamp(
                    0,
                    100,
                  ),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${personality[key] ?? 50}',
                  onChanged: (v) =>
                      setState(() => personality[key] = v.round()),
                ),
              ),
          ],
        ),
        BusyButton('Simpan karakter', () async {
          final age = int.tryParse(controls['age']!.text.trim());
          if (controls['name']!.text.trim().isEmpty ||
              age == null ||
              age < 18 ||
              age > 120) {
            throw StateError('Isi nama dan usia karakter dewasa (18–120).');
          }
          final data = <String, dynamic>{
            for (final k in fields.keys) k: controls[k]!.text.trim(),
            'age': age,
            'personality': {for (final k in traits) k: 50, ...personality},
          };
          if (portrait != null) {
            data['portrait'] = (await widget.api.upload(
              'character-avatars',
              portrait!,
            )).path;
          }
          if (widget.row == null) {
            await widget.api.db.from('characters').insert(data);
          } else {
            await widget.api.db
                .from('characters')
                .update(data)
                .eq('id', widget.row!['id']);
          }
          widget.feed.refresh();
          if (c.mounted) Navigator.pop(c);
        }),
      ],
    ),
  );
}
