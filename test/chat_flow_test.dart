import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myra_mobile/main.dart';
import 'package:myra_mobile/screens/chat.dart';
import 'package:myra_mobile/ui/common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class LocalNetworkBinding extends LiveTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
  @override
  bool get registerTestTextInput => true;
}

void main() {
  final env = Platform.environment;
  final url = env['MYRA_LOCAL_TEST_URL'];
  if (url != null) LocalNetworkBinding();
  testWidgets(
    'log in, open a character, send a message and see the AI reply',
    (tester) async {
      if (!['localhost', '127.0.0.1'].contains(Uri.parse(url!).host)) {
        throw StateError('Run against local Supabase only.');
      }
      final admin = SupabaseClient(url, env['SUPABASE_SERVICE_ROLE_KEY']!);
      final client = SupabaseClient(url, env['VITE_SUPABASE_PUBLISHABLE_KEY']!);
      SharedPreferences.setMockInitialValues({});
      final email = '${const Uuid().v4()}@myra.test',
          password = '${const Uuid().v4()}aA!';
      final account = await admin.auth.admin.createUser(
        AdminUserAttributes(
          email: email,
          password: password,
          emailConfirm: true,
        ),
      );
      final uid = account.user!.id;
      Future<void> until(Finder f) async {
        final watch = Stopwatch()..start();
        while (f.evaluate().isEmpty &&
            watch.elapsed < const Duration(seconds: 75)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(f, findsWidgets);
      }

      final frame = GlobalKey();
      Future<void> capture(String name) async {
        final directory = env['MYRA_PREVIEW_DIR'];
        if (directory == null) return;
        await tester.pump(const Duration(milliseconds: 350));
        final boundary =
            frame.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$directory/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      try {
        await admin.from('admin_access').insert({'user_id': uid});
        await admin.from('characters').insert({
          'owner_id': uid,
          'name': 'Ari',
          'language': 'Indonesian',
          'biography': 'Teman yang suka merawat bunga.',
        });
        await admin.from('providers').insert({
          'owner_id': uid,
          'name': 'Local inference',
          'adapter': 'openai',
          'model': env['MYRA_TEST_MODEL']!,
        });
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        await tester.binding.setSurfaceSize(const Size(393, 852));
        final font = env['MYRA_PREVIEW_FONT'];
        if (font != null) {
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          final loader = FontLoader('Roboto')
            ..addFont(
              File(font).readAsBytes().then((b) => ByteData.sublistView(b)),
            );
          await loader.load();
        }
        await tester.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme(),
              home: AuthGate(client),
            ),
          ),
        );
        await until(find.text('Masuk ke MYRA'));
        await tester.enterText(find.byType(TextField).first, email);
        await tester.enterText(find.byType(TextField).last, password);
        await tester.tap(find.text('Masuk'));
        await tester.pump();
        await until(find.text('Saya berusia 18 tahun atau lebih'));
        await tester.tap(find.text('Saya berusia 18 tahun atau lebih'));
        await tester.pump();
        await until(find.byTooltip('Chat baru'));
        await tester.tap(find.byTooltip('Chat baru'));
        await tester.pump();
        await until(find.text('Ari'));
        await tester.tap(find.text('Ari'));
        await tester.pump();
        await until(find.text('Sapa Ari'));
        await tester.enterText(
          find.byType(TextField),
          'Halo Ari, apa kabarmu hari ini?',
        );
        await until(find.byTooltip('Kirim'));
        await tester.tap(find.byTooltip('Kirim'));
        await tester.pump();
        await until(
          find.byWidgetPredicate(
            (w) =>
                w is MessageBubble &&
                !w.mine &&
                w.body.isNotEmpty &&
                !w.speaker.contains('mengetik'),
          ),
        );
        final assistant = find.byWidgetPredicate(
          (w) => w is MessageBubble && !w.mine,
        );
        final reply = tester.widget<MessageBubble>(assistant.first).body;
        final saved = await client
            .from('messages')
            .select('body')
            .eq('role', 'assistant')
            .eq('is_streaming', false)
            .single();
        expect(reply, saved['body']);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        FocusManager.instance.primaryFocus?.unfocus();
        await capture('chat');
        await tester.pageBack();
        await until(find.byTooltip('Chat baru'));
        await until(find.text('Ari'));
        await tester.pump(const Duration(milliseconds: 500));
        await capture('inbox');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.binding.setSurfaceSize(null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await admin.auth.admin.deleteUser(uid);
        await client.dispose();
        await admin.dispose();
      }
    },
    skip: url == null || env['MYRA_TEST_MODEL'] == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
