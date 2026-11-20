import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/myra.dart';
import '../data/push.dart';
import '../ui/common.dart';
import 'chat.dart';
import 'updates.dart';
import 'worlds.dart';

class Settings extends StatelessWidget {
  const Settings(this.api, this.feed, this.push, {super.key});
  final Myra api;
  final ChangeFeed feed;
  final PushBinding push;
  @override
  Widget build(BuildContext c) => Loaded<DbRow>(
    signal: feed,
    load: () async => {
      ...?await api.db
          .from('settings')
          .select()
          .eq('owner_id', api.uid)
          .maybeSingle(),
      'push': await push.enabled(),
    },
    builder: (s, reload) {
      Future<void> save(String k, dynamic v) async {
        await api.db.from('settings').upsert({
          'owner_id': api.uid,
          k: v,
        }, onConflict: 'owner_id');
        await reload();
        feed.refresh();
      }

      Future<void> selectTime(String key, String initial) async {
        final parts = initial.split(':');
        final t = await showTimePicker(
          context: c,
          initialTime: TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          ),
        );
        if (t != null) {
          await save(
            key,
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
          );
        }
      }

      return ListView(
        children: [
          ListTile(
            leading: const Brand(size: 52),
            title: Text(api.db.auth.currentUser?.email ?? 'Akun MYRA'),
            subtitle: const Text('Workspace MYRA'),
          ),
          const Divider(),
          const SectionTitle('Preferensi'),
          SwitchListTile(
            value: s['notifications'] ?? true,
            title: const Text('Notifikasi akun'),
            onChanged: (v) => runUi(c, () => save('notifications', v)),
          ),
          SwitchListTile(
            value: s['push'] == true,
            title: const Text('Push di perangkat ini'),
            subtitle: const Text('Melalui Firebase Cloud Messaging'),
            onChanged: (v) => runUi(c, () async {
              if (v) {
                await push.register();
              } else {
                await push.disable();
              }
              await reload();
            }),
          ),
          SwitchListTile(
            value: s['proactive'] ?? false,
            title: const Text('Karakter boleh menyapa duluan'),
            subtitle: const Text('Aktifkan juga pada chat yang kamu pilih.'),
            onChanged: (v) => runUi(c, () => save('proactive', v)),
          ),
          for (final k in ['quiet_start', 'quiet_end'])
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: Text(
                k == 'quiet_start' ? 'Mulai jam tenang' : 'Akhir jam tenang',
              ),
              subtitle: Text(
                '${str(s, k, k == 'quiet_start' ? '22:00' : '07:00').substring(0, 5)} · ${str(s, 'timezone', 'Asia/Jakarta')}',
              ),
              onTap: () => runUi(
                c,
                () => selectTime(
                  k,
                  str(s, k, k == 'quiet_start' ? '22:00' : '07:00'),
                ),
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Universe dan crossover'),
            onTap: () => go(c, Worlds(api, feed)),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Memori'),
            onTap: () => go(c, Memories(api, feed)),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Kotak notifikasi'),
            onTap: () => go(c, NotificationsPage(api, feed)),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Keluar'),
            onTap: () => runUi(c, () async {
              if (await confirm(
                c,
                'Keluar dari MYRA?',
                'Sesi pada perangkat ini akan ditutup.',
              )) {
                await push.disable();
                await api.db.auth.signOut(scope: SignOutScope.local);
              }
            }),
          ),
        ],
      );
    },
  );
}

class Memories extends StatelessWidget {
  const Memories(this.api, this.feed, {super.key});
  final Myra api;
  final ChangeFeed feed;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Memori')),
    floatingActionButton: FloatingActionButton(
      tooltip: 'Tambah memori pribadi',
      onPressed: () => runUi(c, () async {
        final body = await askText(c, 'Tambah memori pribadi', limit: 6000);
        if (body != null) {
          await api.db.from('memories').insert({'scope': 'user', 'body': body});
          feed.refresh();
        }
      }),
      child: const Icon(Icons.add),
    ),
    body: Loaded<List<DbRow>>(
      signal: feed,
      load: () => api.list('memories'),
      builder: (items, reload) => items.isEmpty
          ? const Empty(
              Icons.auto_awesome_outlined,
              'Belum ada memori',
              'Memori yang disimpan dari percakapan akan muncul di sini.',
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 85),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final m = items[i];
                return ListTile(
                  title: Text(str(m, 'body')),
                  subtitle: Text(
                    '${m['scope']} · ${dayLabel(m['created_at'])}',
                  ),
                  trailing: PopupMenuButton<String>(
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Hapus')),
                    ],
                    onSelected: (v) => runUi(c, () async {
                      if (v == 'edit') {
                        final txt = await askText(
                          c,
                          'Edit memori',
                          initial: m['body'],
                          limit: 6000,
                        );
                        if (txt == null) return;
                        await api.db
                            .from('memories')
                            .update({'body': txt})
                            .eq('id', m['id']);
                      } else {
                        if (!await confirm(
                          c,
                          'Hapus memori ini?',
                          'Karakter tidak lagi menggunakan catatan ini sebagai konteks.',
                        )) {
                          return;
                        }
                        await api.db
                            .from('memories')
                            .delete()
                            .eq('id', m['id']);
                      }
                      await reload();
                      feed.refresh();
                    }),
                  ),
                );
              },
            ),
    ),
  );
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage(this.api, this.feed, {super.key});
  final Myra api;
  final ChangeFeed feed;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Notifikasi')),
    body: Loaded<List<DbRow>>(
      signal: feed,
      load: () async => (await api.list('notifications'))
          .where((n) => !DateTime.parse(n['due_at']).isAfter(DateTime.now()))
          .toList(),
      builder: (items, reload) => items.isEmpty
          ? const Empty(
              Icons.notifications_none,
              'Belum ada notifikasi',
              'Kabar dari karakter dan grup akan muncul di sini.',
            )
          : ListView(
              children: [
                for (final n in items)
                  ListTile(
                    leading: Icon(
                      Icons.notifications,
                      color: n['read_at'] == null ? pink : muted,
                    ),
                    title: Text(str(n, 'name')),
                    subtitle: Text(str(n, 'body')),
                    onTap: () => runUi(c, () async {
                      if (n['read_at'] == null) {
                        await api.db
                            .from('notifications')
                            .update({
                              'read_at': DateTime.now()
                                  .toUtc()
                                  .toIso8601String(),
                            })
                            .eq('id', n['id']);
                      }
                      feed.refresh();
                      if (n['conversation_id'] != null) {
                        final r = await api.db
                            .from('conversations')
                            .select()
                            .eq('id', n['conversation_id'])
                            .single();
                        if (c.mounted) go(c, Chat(api, feed, r));
                      } else if (n['story_id'] != null) {
                        final s = await api.db
                            .from('stories')
                            .select()
                            .eq('id', n['story_id'])
                            .single();
                        if (s['status'] != 'published' ||
                            DateTime.parse(
                              s['expires_at'],
                            ).isBefore(DateTime.now()) ||
                            DateTime.parse(
                              s['publish_at'],
                            ).isAfter(DateTime.now())) {
                          throw StateError('Status ini sudah tidak tersedia.');
                        }
                        if (c.mounted) go(c, StoryPage(api, feed, s));
                      }
                    }),
                  ),
              ],
            ),
    ),
  );
}
