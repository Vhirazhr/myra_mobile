import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:myra_mobile/data/myra.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

// Run only against disposable local Supabase. Credentials stay in the test process.
void main() {
  final env = Platform.environment;
  final url = env['MYRA_LOCAL_TEST_URL'];
  test(
    'mobile and a fresh client share private workspace data',
    () async {
      if (!['localhost', '127.0.0.1'].contains(Uri.parse(url!).host)) {
        throw StateError(
          'This fixture only provisions users on local Supabase.',
        );
      }
      final admin = SupabaseClient(url, env['SUPABASE_SERVICE_ROLE_KEY']!);
      final anon = env['VITE_SUPABASE_PUBLISHABLE_KEY']!;
      final app = SupabaseClient(url, anon);
      final second = SupabaseClient(url, anon);
      final guest = SupabaseClient(url, anon);
      final users = <String>[];
      final password = '${const Uuid().v4()}!Aa9';
      final objects = <String>[];
      String? owner;
      try {
        Future<String> provision(bool allowed) async {
          final email = '${const Uuid().v4()}@myra.test';
          final res = await admin.auth.admin.createUser(
            AdminUserAttributes(
              email: email,
              password: password,
              emailConfirm: true,
            ),
          );
          final id = res.user!.id;
          users.add(id);
          if (allowed) await admin.from('admin_access').insert({'user_id': id});
          return email;
        }

        final email = await provision(true);
        final outsider = await provision(false);
        await app.auth.signInWithPassword(email: email, password: password);
        final api = Myra(app);
        owner = api.uid;
        expect(await api.allowed(), isTrue);
        final ch = await app
            .from('characters')
            .insert({'name': 'Ari'})
            .select()
            .single();
        await app
            .from('characters')
            .update({'biography': 'Suka kucing'})
            .eq('id', ch['id']);
        final group = await api.saveGroup('Sahabat', [ch['id']], 'Hybrid');
        final groupChat = await api.openChat(group, group: true);
        expect((await api.participants(groupChat)).single['name'], 'Ari');
        final chat = await api.openChat(ch);
        expect(chat['mode'], 'hybrid');
        final worldId = await app.rpc(
          'save_roster',
          params: {
            'target': 'universes',
            'record_id': null,
            'fields': {'name': 'Aster'},
            'members': [ch['id']],
          },
        );
        final world = await app
            .from('universes')
            .select()
            .eq('id', worldId)
            .single();
        final worldChat = await api.openChat(ch, world: world);
        expect(worldChat['universe_id'], worldId);
        expect(worldChat['id'], isNot(chat['id']));
        await api.setChatPreference(chat['id'], 'pin', true);
        await api.setChatPreference(chat['id'], 'wallpaper', 'rose');
        await api.setChatPreference(worldChat['id'], 'archive', true);

        final sent = await api.send(
          id: const Uuid().v4(),
          thread: chat['id'],
          text: 'My favorite flower is jasmine.',
          memory: 'remember',
        );
        final reply = await api.send(
          id: const Uuid().v4(),
          thread: chat['id'],
          text: 'Halo!',
          memory: 'off',
          reply: sent['id'],
        );
        await api.send(
          id: reply['id'],
          thread: chat['id'],
          text: 'Halo!',
          memory: 'off',
          reply: sent['id'],
        );
        await api.toggleReaction(sent['id'], '💗');
        expect(
          (await app
                  .from('message_reactions')
                  .select()
                  .eq('message_id', sent['id']))
              .length,
          1,
        );
        expect(
          (await api.history(chat['id'], query: 'flower')).single['id'],
          sent['id'],
        );
        expect(
          (await api.history(chat['id'], before: reply)).single['id'],
          sent['id'],
        );
        final temp = await Directory.systemTemp.createTemp(
          'myra_story_fixture',
        );
        late final MediaAsset asset;
        try {
          final file = File('${temp.path}/pixel.png');
          await file.writeAsBytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO6pB1sAAAAASUVORK5CYII=',
            ),
          );
          asset = await api.upload(
            'stories',
            LocalMedia(file.path, 'pixel.png', 'image/png'),
            character: ch['id'],
          );
          objects.add(asset.path);
        } finally {
          await temp.delete(recursive: true);
        }
        final story = await app
            .from('stories')
            .insert({
              'name': 'Jasmine',
              'status': 'published',
              'audience': 'group',
              'group_id': group['id'],
              'media': asset.path,
              'mime': asset.mime,
              'character_id': ch['id'],
            })
            .select()
            .single();
        expect(await api.feed(), isEmpty);
        expect((await api.feed(group: group['id'])).single['id'], story['id']);
        await api.storyView(story['id']);
        await api.storyView(story['id']);
        expect(
          (await app.from('story_activity').select().eq('kind', 'view')).length,
          1,
        );
        await app.from('story_activity').insert({
          'kind': 'reply',
          'body': 'Cantik',
          'story_id': story['id'],
        });
        expect(
          await app.storage.from('stories').download(asset.path),
          isNotEmpty,
        );
        await guest.auth.signInWithPassword(
          email: outsider,
          password: password,
        );
        expect(await Myra(guest).allowed(), isFalse);
        expect(await Myra(guest).inbox(), isEmpty);
        await expectLater(
          guest.from('characters').insert({'name': 'Guest'}),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          guest.storage.from('stories').download(asset.path),
          throwsA(isA<StorageException>()),
        );
        if (env['MYRA_TEST_MODEL'] != null) {
          await app.from('providers').insert({
            'name': 'Local inference',
            'adapter': 'openai',
            'model': env['MYRA_TEST_MODEL'],
            'enabled': true,
          });
          await api.action('generate', sent['id']);
          final generated = (await api.history(
            chat['id'],
          )).singleWhere((m) => m['source_id'] == sent['id']);
          expect(generated['role'], 'assistant');
          expect(generated['body'], isNotEmpty);
          expect(generated['is_streaming'], false);
          List<DbRow> recall = [];
          for (var attempt = 0; attempt < 40; attempt++) {
            recall = rows(
              await app.rpc(
                'recall_memories',
                params: {
                  'thread': chat['id'],
                  'speaker': ch['id'],
                  'query_text': 'jasmine',
                },
              ),
            );
            if (recall.any(
              (m) =>
                  m['source_id'] == generated['id'] &&
                  m['body'] == sent['body'],
            )) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
          expect(
            recall.any(
              (m) =>
                  m['source_id'] == generated['id'] &&
                  m['body'] == sent['body'],
            ),
            isTrue,
          );
        }
        await second.auth.signInWithPassword(email: email, password: password);
        final fresh = Myra(second);
        expect(fresh.chatPreference(chat['id'], 'pin'), true);
        expect(fresh.chatPreference(chat['id'], 'wallpaper'), 'rose');
        expect(fresh.chatPreference(worldChat['id'], 'archive'), true);
        expect(
          (await fresh.list('characters')).single['biography'],
          'Suka kucing',
        );
        expect(
          (await fresh.inbox()).map((c) => c['name']),
          containsAll(['Ari', 'Sahabat']),
        );
        expect(
          (await fresh.history(
            chat['id'],
          )).where((m) => m['id'] == reply['id']).single['reply_to'],
          sent['id'],
        );
        final refreshed = await second.auth.refreshSession();
        expect(refreshed.user?.id, owner);
      } finally {
        if (objects.isNotEmpty) {
          await admin.storage.from('stories').remove(objects);
        }
        for (final id in users) {
          await admin.auth.admin.deleteUser(id);
        }
        await Future.wait([
          admin.dispose(),
          app.dispose(),
          second.dispose(),
          guest.dispose(),
        ]);
      }
    },
    skip: url == null
        ? 'Set MYRA_LOCAL_TEST_URL to enable the local integration fixture.'
        : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
