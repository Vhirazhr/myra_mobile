import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

typedef DbRow = Map<String, dynamic>;

const projectUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://splifnxylqaicneodkaj.supabase.co',
);
const bundledKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const stages = [
  'Best friends',
  'Growing closer',
  'Developing feelings',
  'Romantic partners',
];
const modes = ['hybrid', 'natural', 'learning', 'immersion'];
const memoryModes = {
  'automatic': 'Otomatis',
  'remember': 'Ingat di chat berikutnya',
  'private': 'Hanya chat ini',
  'off': 'Lewati memori',
};
String str(DbRow row, String key, [String fallback = '']) =>
    row[key]?.toString() ?? fallback;
bool publicKey(String key) {
  if (key.startsWith('sb_publishable_')) return key.length > 24;
  try {
    final p = key.split('.');
    return p.length == 3 &&
        jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(p[1]))),
            )['role'] ==
            'anon';
  } catch (_) {
    return false;
  }
}

String readable(Object e) {
  if (e is PlatformException) {
    return e.message ?? 'Perangkat gagal menyelesaikan tindakan.';
  }
  if (e is AuthException) return e.message;
  if (e is PostgrestException) return e.message;
  if (e is StorageException) return e.message;
  if (e is FunctionException) {
    final d = e.details;
    return d is Map && d['error'] is String
        ? d['error']
        : 'Layanan MYRA merespons dengan kode ${e.status}.';
  }
  if (e is SocketException) {
    return 'Koneksi terputus. Periksa internet lalu coba lagi.';
  }
  return e.toString().replaceFirst(RegExp(r'^(Bad state: |Exception: )'), '');
}

List<DbRow> rows(dynamic value) => List<DbRow>.from(value as List);
DbRow? firstRow(List<DbRow> r) => r.isEmpty ? null : r.first;
DbRow? latestMessage(DbRow thread) => firstRow(rows(thread['messages'] ?? []));
DateTime activityAt(DbRow thread) =>
    DateTime.parse(str(latestMessage(thread) ?? thread, 'created_at'));
String clock(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null
      ? ''
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String dayLabel(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final diff = DateTime(now.year, now.month, now.day).difference(day).inDays;
  return diff == 0
      ? 'Hari ini'
      : diff == 1
      ? 'Kemarin'
      : '${d.day}/${d.month}/${d.year}';
}

class LocalMedia {
  const LocalMedia(this.path, this.name, this.mime);
  final String path, name, mime;
}

class MediaAsset {
  const MediaAsset(this.path, this.mime);
  final String path, mime;
}

class Myra {
  Myra(this.db);
  final SupabaseClient db;
  String get uid => db.auth.currentUser!.id;
  Future<bool> allowed() async => await db.rpc('is_myra_admin') == true;
  Future<List<DbRow>> list(String table, {String? by, String? value}) async {
    final result = <DbRow>[];
    for (var at = 0; ; at += 200) {
      var q = db.from(table).select();
      if (by != null && value != null) q = q.eq(by, value);
      final page = await q
          .order('created_at', ascending: false)
          .order('id')
          .range(at, at + 199);
      result.addAll(page);
      if (page.length < 200) return result;
    }
  }

  Object? chatPreference(String id, String option) =>
      db.auth.currentUser?.userMetadata?['myra_${option}_$id'];
  Future<void> setChatPreference(String id, String option, Object value) async {
    await db.auth.updateUser(
      UserAttributes(data: {'myra_${option}_$id': value}),
    );
  }

  Future<List<DbRow>> inbox() async {
    final result = <DbRow>[];
    for (var at = 0; ; at += 100) {
      final page = await db
          .from('conversations')
          .select(
            '*,characters(name,portrait),groups(name),messages(id,body,role,mime,created_at)',
          )
          .order('created_at', ascending: false, referencedTable: 'messages')
          .limit(1, referencedTable: 'messages')
          .order('created_at', ascending: false)
          .order('id')
          .range(at, at + 99);
      result.addAll(page);
      if (page.length < 100) break;
    }
    result.sort((a, b) => activityAt(b).compareTo(activityAt(a)));
    return result;
  }

  Future<DbRow> openChat(
    DbRow target, {
    bool group = false,
    DbRow? world,
    bool crossover = false,
  }) async {
    final key = group ? 'group_id' : 'character_id';
    var query = db.from('conversations').select().eq(key, target['id']);
    query = world == null || crossover
        ? query.isFilter('universe_id', null)
        : query.eq('universe_id', world['id']);
    query = world != null && crossover
        ? query.eq('crossover_id', world['id'])
        : query.isFilter('crossover_id', null);
    final existing = await query.order('created_at', ascending: false).limit(1);
    return firstRow(existing) ??
        await db
            .from('conversations')
            .insert({
              key: target['id'],
              'name': world == null
                  ? target['name']
                  : String.fromCharCodes(
                      '${target['name']} · ${world['name']}'.runes.take(180),
                    ),
              if (world != null)
                (crossover ? 'crossover_id' : 'universe_id'): world['id'],
              'language': target['language'] ?? 'Indonesian',
            })
            .select()
            .single();
  }

  Future<DbRow> saveGroup(
    String name,
    List<String> members,
    String mode, {
    String? id,
    String description = '',
  }) async {
    final saved = await db.rpc(
      'save_roster',
      params: {
        'target': 'groups',
        'record_id': id,
        'fields': {'name': name, 'description': description, 'mode': mode},
        'members': members,
      },
    );
    return await db.from('groups').select().eq('id', saved).single();
  }

  Future<List<DbRow>> participants(DbRow chat) async {
    if (chat['group_id'] == null) {
      return [
        await db
            .from('characters')
            .select()
            .eq('id', chat['character_id'])
            .single(),
      ];
    }
    final roster = await db
        .from('group_members')
        .select('characters(*)')
        .eq('group_id', chat['group_id']);
    return [
      for (final m in roster)
        if (m['characters'] != null) Map<String, dynamic>.from(m['characters']),
    ];
  }

  Future<List<DbRow>> history(
    String id, {
    DbRow? before,
    String query = '',
  }) async {
    var q = db.from('messages').select().eq('conversation_id', id);
    if (query.isNotEmpty) q = q.ilike('body', '%$query%');
    if (before != null) {
      final stamp = DateTime.parse(
        before['created_at'],
      ).toUtc().toIso8601String();
      q = q.or(
        'created_at.lt.$stamp,and(created_at.eq.$stamp,id.lt.${before['id']})',
      );
    }
    return await q
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(50);
  }

  Future<DbRow> send({
    required String id,
    required String thread,
    required String text,
    required String memory,
    String? reply,
    List<String> mentions = const [],
    MediaAsset? media,
  }) async {
    final record = {
      'id': id,
      'conversation_id': thread,
      'body': text,
      'role': 'user',
      'memory_mode': memory,
      'reply_to': reply,
      'mentions': mentions,
      'attachment': media?.path ?? '',
      'mime': media?.mime ?? '',
    };
    try {
      return await db.from('messages').insert(record).select().single();
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      return await db
          .from('messages')
          .select()
          .eq('id', id)
          .eq('conversation_id', thread)
          .single();
    }
  }

  Future<dynamic> action(String action, String id) async {
    final r = await db.functions.invoke(
      'myra',
      body: {'action': action, 'id': id},
    );
    if (r.status >= 400 || r.data is Map && r.data['error'] != null) {
      throw StateError(r.data?['error'] ?? 'MYRA gagal merespons.');
    }
    return r.data;
  }

  Future<MediaAsset> upload(
    String bucket,
    LocalMedia local, {
    String? character,
  }) async {
    final file = File(local.path);
    final bytes = await file.length();
    if (bytes == 0 ||
        bytes > (bucket == 'character-avatars' ? 10 : 50) * 1024 * 1024) {
      throw StateError('Ukuran file melebihi batas atau file kosong.');
    }
    final ext = local.name
        .split('.')
        .last
        .replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    final path =
        '$uid/${const Uuid().v4()}.${ext.isEmpty ? 'bin' : ext.substring(0, ext.length.clamp(0, 10))}';
    await db.storage
        .from(bucket)
        .upload(path, file, fileOptions: FileOptions(contentType: local.mime));
    try {
      await db.from('media_assets').insert({
        'bucket': bucket,
        'path': path,
        'name': local.name,
        'mime': local.mime,
        'bytes': bytes,
        if (character != null) 'character_id': character,
      });
    } catch (_) {
      await db.storage.from(bucket).remove([path]);
      rethrow;
    }
    return MediaAsset(path, local.mime);
  }

  final _links = <String, ({Future<String> url, DateTime until})>{};
  Future<String> signed(String bucket, String path) {
    final key = '$bucket/$path', old = _links[key];
    if (old != null && DateTime.now().isBefore(old.until)) return old.url;
    final value = db.storage.from(bucket).createSignedUrl(path, 3600);
    _links[key] = (
      url: value,
      until: DateTime.now().add(const Duration(minutes: 50)),
    );
    value.catchError((Object e) {
      _links.remove(key);
      return '';
    });
    return value;
  }

  Future<List<DbRow>> feed({String? group, String? universe}) async => rows(
    await db.rpc(
      'story_feed',
      params: {'for_group': group, 'for_universe': universe},
    ),
  );
  Future<void> storyView(String id) async {
    try {
      await db.from('story_activity').insert({'story_id': id, 'kind': 'view'});
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> toggleReaction(String message, String emoji) async {
    final old = await db
        .from('message_reactions')
        .select('id')
        .eq('message_id', message)
        .eq('emoji', emoji)
        .eq('owner_id', uid)
        .maybeSingle();
    if (old != null) {
      await db.from('message_reactions').delete().eq('id', old['id']);
    } else {
      await db.from('message_reactions').insert({
        'message_id': message,
        'emoji': emoji,
      });
    }
  }
}

class ChangeFeed extends ChangeNotifier {
  ChangeFeed(this.api) {
    channel = api.db
        .channel('mobile-${api.uid}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          callback: (_) => refresh(),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) refresh();
        });
  }
  final Myra api;
  late final RealtimeChannel channel;
  Timer? timer;
  bool stopped = false;
  void refresh() {
    if (stopped) return;
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 180), () {
      if (!stopped) notifyListeners();
    });
  }

  @override
  void dispose() {
    stopped = true;
    timer?.cancel();
    unawaited(api.db.removeChannel(channel));
    super.dispose();
  }
}
