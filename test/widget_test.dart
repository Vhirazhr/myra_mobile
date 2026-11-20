import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myra_mobile/data/myra.dart';
import 'package:myra_mobile/main.dart';
import 'package:myra_mobile/screens/chat.dart';
import 'package:myra_mobile/screens/updates.dart';
import 'package:myra_mobile/ui/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('accepts client credentials and rejects privileged keys', () {
    String jwt(String role) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role}))).replaceAll('=', '')}.signature';
    expect(publicKey(jwt('service_role')), isFalse);
    expect(publicKey('sb_secret_abcdefghijklmnopqrstuvwxyz'), isFalse);
    expect(publicKey(jwt('anon')), isTrue);
    expect(publicKey('sb_publishable_abcdefghijklmnopqrstuvwxyz'), isTrue);
  });
  test('inbox uses message timestamp when available', () {
    final row = {
      'created_at': '2026-01-01T01:00:00Z',
      'messages': [
        {'body': 'Halo', 'created_at': '2026-02-01T01:00:00Z'},
      ],
    };
    expect(latestMessage(row)?['body'], 'Halo');
    expect(activityAt(row).month, 2);
    expect(
      activityAt({'created_at': row['created_at'], 'messages': []}).month,
      1,
    );
  });
  test('story audiences distinguish the group and universe', () {
    expect(
      audiences(
        [
          {'id': 'a', 'name': 'AA'},
        ],
        [
          {'id': 'a', 'name': 'AA'},
        ],
      ).keys,
      orderedEquals(['private', 'group:a', 'universe:a']),
    );
  });
  testWidgets('first launch presents project setup and rejects a secret key', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyraApp());
    await tester.pumpAndSettle();
    expect(find.text('Hubungkan MYRA'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sb_secret_example');
    await tester.tap(find.text('Hubungkan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Gunakan publishable key'), findsOneWidget);
  });
  testWidgets('bubble exposes sender, reply, reaction and long press', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme(),
        home: Scaffold(
          body: MessageBubble(
            mine: false,
            body: 'Halo!',
            speaker: 'Ari',
            time: '14:20',
            quote: 'Pagi',
            reactions: '💗',
            onHold: () => pressed = true,
          ),
        ),
      ),
    );
    expect(find.text('Ari'), findsOneWidget);
    expect(find.text('Pagi'), findsOneWidget);
    expect(find.text('💗'), findsOneWidget);
    await tester.longPress(find.text('Halo!'));
    expect(pressed, isTrue);
  });
}
