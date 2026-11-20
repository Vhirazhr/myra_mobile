import 'package:flutter/material.dart';
import '../data/myra.dart';
import '../ui/common.dart';
import 'chat.dart';
import 'directory.dart';
import 'updates.dart';
import 'calls.dart';
import 'settings.dart';
import '../data/push.dart';

class Home extends StatefulWidget {
  const Home(this.api, {super.key});
  final Myra api;
  @override
  State<Home> createState() => _Home();
}

class _Home extends State<Home> with WidgetsBindingObserver {
  late final feed = ChangeFeed(widget.api);
  late final PushBinding push;
  int tab = 0, filter = 0;
  bool searching = false, archive = false;
  String query = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    push = PushBinding(widget.api, (id) async {
      final n = await widget.api.db
          .from('notifications')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (!mounted || n == null) return;
      if (n['conversation_id'] != null) {
        final thread = await widget.api.db
            .from('conversations')
            .select()
            .eq('id', n['conversation_id'])
            .single();
        if (mounted) go(context, Chat(widget.api, feed, thread));
      } else if (n['story_id'] != null) {
        setState(() => tab = 1);
      }
    });
    push.attach();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      feed.refresh();
      push.syncIfEnabled();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    push.dispose();
    feed.dispose();
    super.dispose();
  }

  Future<void> threadActions(DbRow t) async {
    final api = widget.api;
    final id = str(t, 'id');
    final pinned = api.chatPreference(id, 'pin') == true;
    final archived = api.chatPreference(id, 'archive') == true;
    final option = await showModalBottomSheet<String>(
      context: context,
      builder: (d) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(pinned ? 'Lepas sematan' : 'Sematkan chat'),
              onTap: () => Navigator.pop(d, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(archived ? 'Kembalikan ke chat' : 'Arsipkan chat'),
              onTap: () => Navigator.pop(d, 'archive'),
            ),
          ],
        ),
      ),
    );
    if (option == null || !mounted) return;
    await api.setChatPreference(
      id,
      option,
      option == 'pin' ? !pinned : !archived,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) {
    final api = widget.api;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: searching && tab == 0
            ? TextField(
                autofocus: true,
                onChanged: (x) => setState(() => query = x),
                decoration: const InputDecoration(
                  hintText: 'Cari percakapan',
                  isDense: true,
                ),
              )
            : Row(
                children: [
                  if (tab == 0) ...[
                    const Brand(size: 30),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    ['MYRA', 'Pembaruan', 'Panggilan', 'Saya'][tab],
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.7,
                    ),
                  ),
                ],
              ),
        actions: [
          if (tab == 0)
            IconButton(
              tooltip: 'Cari chat',
              onPressed: () => setState(() {
                searching = !searching;
                query = '';
              }),
              icon: Icon(searching ? Icons.close : Icons.search),
            ),
          if (tab == 0)
            IconButton(
              tooltip: archive ? 'Kembali ke chat' : 'Arsip chat',
              icon: Icon(
                archive ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              onPressed: () => setState(() => archive = !archive),
            ),
          if (tab != 3)
            IconButton(
              tooltip: 'Notifikasi',
              onPressed: () => go(c, NotificationsPage(api, feed)),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: switch (tab) {
          0 => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: Text(
                  archive ? 'Arsip' : 'Chat',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.2,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 9),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final e in [
                      'Semua',
                      'Personal',
                      'Grup',
                    ].asMap().entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: filter == e.key,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => filter = e.key),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Loaded<List<DbRow>>(
                  load: api.inbox,
                  signal: feed,
                  builder: (items, reload) {
                    final visible = items
                        .where(
                          (t) =>
                              (api.chatPreference(t['id'], 'archive') ==
                                      true) ==
                                  archive &&
                              (filter == 0 ||
                                  (filter == 2) == (t['group_id'] != null)) &&
                              str(
                                t,
                                'name',
                              ).toLowerCase().contains(query.toLowerCase()),
                        )
                        .toList();
                    final pinned = visible
                        .where(
                          (t) => api.chatPreference(t['id'], 'pin') == true,
                        )
                        .toList();
                    visible.removeWhere(
                      (t) => api.chatPreference(t['id'], 'pin') == true,
                    );
                    visible.insertAll(0, pinned);
                    if (visible.isEmpty) {
                      return Empty(
                        Icons.forum_outlined,
                        items.isEmpty
                            ? 'Mulai chat pertamamu'
                            : 'Chat tidak ditemukan',
                        items.isEmpty
                            ? 'Pilih karakter dari MYRA atau mulai percakapan grup.'
                            : 'Coba kata lain atau ganti filter.',
                        action: items.isEmpty
                            ? TextButton(
                                onPressed: () => go(c, Directory(api, feed)),
                                child: const Text('Pilih karakter'),
                              )
                            : null,
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: reload,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) =>
                            const Divider(indent: 84, height: 1),
                        itemBuilder: (_, i) {
                          final t = visible[i],
                              m = latestMessage(t),
                              at = str(m ?? t, 'created_at');
                          return ListTile(
                            leading: Avatar(
                              api,
                              str(t, 'name'),
                              path: t['characters']?['portrait'] ?? '',
                              group: t['group_id'] != null,
                            ),
                            title: Text(
                              str(t, 'name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              m == null
                                  ? 'Belum ada pesan'
                                  : '${m['role'] == 'user' ? 'Kamu: ' : ''}${str(m, 'body')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: muted),
                            ),
                            trailing: Text(
                              dayLabel(at) == 'Hari ini'
                                  ? clock(at)
                                  : dayLabel(at),
                              style: const TextStyle(
                                fontSize: 11,
                                color: muted,
                              ),
                            ),
                            onLongPress: () => runUi(c, () => threadActions(t)),
                            onTap: () => go(c, Chat(api, feed, t)),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          1 => Updates(api, feed),
          2 => Calls(api, feed),
          _ => Settings(api, feed, push),
        },
      ),
      floatingActionButton: tab == 0
          ? FloatingActionButton(
              tooltip: 'Chat baru',
              onPressed: () => go(c, Directory(api, feed)),
              child: const Icon(Icons.edit_outlined),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.donut_large),
            label: 'Pembaruan',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: 'Panggilan',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Saya',
          ),
        ],
      ),
    );
  }
}
