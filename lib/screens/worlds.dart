import 'package:flutter/material.dart';
import '../data/myra.dart';
import '../ui/common.dart';
import 'chat.dart';

class Worlds extends StatelessWidget {
  const Worlds(this.api, this.feed, {super.key});
  final Myra api;
  final ChangeFeed feed;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Universe')),
    body: Loaded<List<List<DbRow>>>(
      signal: feed,
      load: () => Future.wait([api.list('universes'), api.list('crossovers')]),
      builder: (data, reload) => data.every((l) => l.isEmpty)
          ? const Empty(
              Icons.public,
              'Belum ada universe',
              'Universe dan crossover dari studio web akan muncul di sini.',
            )
          : RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  for (final i in [0, 1]) ...[
                    if (data[i].isNotEmpty)
                      SectionTitle(i == 0 ? 'Universe' : 'Crossover'),
                    for (final row in data[i])
                      ListTile(
                        leading: Icon(
                          i == 0 ? Icons.public : Icons.hub_outlined,
                          color: pink,
                        ),
                        title: Text(str(row, 'name')),
                        subtitle: Text(
                          str(row, 'description'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () =>
                            go(c, World(api, feed, row, crossover: i == 1)),
                      ),
                  ],
                ],
              ),
            ),
    ),
  );
}

class World extends StatelessWidget {
  const World(
    this.api,
    this.feed,
    this.row, {
    required this.crossover,
    super.key,
  });
  final Myra api;
  final ChangeFeed feed;
  final DbRow row;
  final bool crossover;
  @override
  Widget build(BuildContext c) {
    final ids = crossover
        ? [str(row, 'universe_id'), str(row, 'other_universe_id')]
        : [str(row, 'id')];
    return Scaffold(
      appBar: AppBar(title: Text(str(row, 'name'))),
      body: Loaded<List<List<DbRow>>>(
        signal: feed,
        load: () async => [
          await api.db
              .from('world_entries')
              .select()
              .inFilter('universe_id', ids)
              .order('event_date')
              .order('created_at'),
          await api.db
              .from('universe_characters')
              .select('characters(*)')
              .inFilter('universe_id', ids),
        ],
        builder: (d, reload) {
          final roster = <dynamic, DbRow>{
            for (final m in d[1])
              if (m['characters'] != null)
                m['characters']['id']: m['characters'],
          };
          return ListView(
            children: [
              if (str(row, 'description').isNotEmpty)
                ListTile(title: Text(str(row, 'description'))),
              if (str(row, 'rules').isNotEmpty)
                ListTile(
                  title: const Text('Aturan dunia'),
                  subtitle: Text(str(row, 'rules')),
                ),
              const SectionTitle('Chat dalam dunia ini'),
              if (roster.isEmpty)
                const ListTile(title: Text('Belum ada karakter')),
              for (final ch in roster.values)
                ListTile(
                  leading: Avatar(
                    api,
                    str(ch, 'name'),
                    path: str(ch, 'portrait'),
                  ),
                  title: Text(str(ch, 'name')),
                  onTap: () => runUi(c, () async {
                    final t = await api.openChat(
                      ch,
                      world: row,
                      crossover: crossover,
                    );
                    feed.refresh();
                    if (c.mounted) go(c, Chat(api, feed, t));
                  }),
                ),
              for (final k in {
                'lore': 'Lore',
                'location': 'Lokasi',
                'event': 'Linimasa',
              }.entries)
                if (d[0].any((r) => r['kind'] == k.key)) ...[
                  SectionTitle(k.value),
                  for (final r in d[0].where((r) => r['kind'] == k.key))
                    ListTile(
                      title: Text(str(r, 'name')),
                      subtitle: Text(
                        [
                          str(r, 'event_date'),
                          str(r, 'body'),
                        ].where((v) => v.isNotEmpty).join(' · '),
                      ),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }
}

class CharacterLife extends StatelessWidget {
  const CharacterLife(this.api, this.feed, this.ch, {super.key});
  final Myra api;
  final ChangeFeed feed;
  final DbRow ch;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text('Kehidupan ${ch['name']}')),
    body: Loaded<List<List<DbRow>>>(
      signal: feed,
      load: () => Future.wait([
        api.list('diaries', by: 'character_id', value: ch['id']),
        api.list('events', by: 'character_id', value: ch['id']),
        api.list('relationships'),
        api.list('characters'),
        api.list('interactions'),
      ]),
      builder: (data, reload) {
        final relations = data[2].where(
          (r) =>
              r['character_id'] == ch['id'] ||
              r['other_character_id'] == ch['id'],
        );
        final names = {for (final r in data[3]) r['id']: r['name']};
        if (relations.isEmpty && data[0].isEmpty && data[1].isEmpty) {
          return const Empty(
            Icons.menu_book_outlined,
            'Belum ada aktivitas',
            'Diari, peristiwa, dan riwayat hubungan dari simulasi akan muncul di sini.',
          );
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (relations.isNotEmpty) const SectionTitle('Hubungan'),
              for (final r in relations)
                ExpansionTile(
                  title: Text(
                    names[r['character_id'] == ch['id']
                            ? r['other_character_id']
                            : r['character_id']] ??
                        'Karakter',
                  ),
                  subtitle: Text('${r['kind']} · Kepercayaan ${r['trust']}%'),
                  children: [
                    if (str(r, 'history').isNotEmpty)
                      ListTile(title: Text(str(r, 'history'))),
                    for (final event in data[4].where(
                      (e) => e['relationship_id'] == r['id'],
                    ))
                      ListTile(
                        title: Text(str(event, 'name')),
                        subtitle: Text(str(event, 'body')),
                      ),
                  ],
                ),
              for (final i in [0, 1])
                if (data[i].isNotEmpty) ...[
                  SectionTitle(i == 0 ? 'Diari' : 'Peristiwa'),
                  for (final r in data[i])
                    ListTile(
                      title: Text(str(r, 'name')),
                      subtitle: Text(
                        [
                          str(r, 'mood'),
                          str(r, 'body'),
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      trailing: Text(
                        dayLabel(str(r, i == 0 ? 'created_at' : 'due_at')),
                      ),
                    ),
                ],
            ],
          ),
        );
      },
    ),
  );
}
