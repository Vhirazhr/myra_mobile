import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/myra.dart';
import 'ui/common.dart';
import 'screens/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyraApp());
}

class MyraApp extends StatelessWidget {
  const MyraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MYRA',
    debugShowCheckedModeBanner: false,
    theme: theme(),
    home: const Connect(),
  );
}

class Connect extends StatefulWidget {
  const Connect({super.key});
  @override
  State<Connect> createState() => _Connect();
}

class _Connect extends State<Connect> {
  SupabaseClient? db;
  bool busy = true;
  String? error;
  final keyText = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    keyText.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = bundledKey.isNotEmpty
          ? bundledKey
          : prefs.getString('publishable_key') ?? '';
      if (publicKey(key)) {
        await connect(key, validate: false);
        return;
      }
    } catch (e) {
      error = readable(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> connect(String key, {bool validate = true}) async {
    if (!publicKey(key)) {
      throw StateError('Gunakan publishable key atau anon key proyek MYRA.');
    }
    if (validate) {
      final http = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      try {
        final req = await http.getUrl(
          Uri.parse('$projectUrl/auth/v1/settings'),
        );
        req.headers.set('apikey', key);
        final response = await req.close().timeout(const Duration(seconds: 15));
        await response.drain<void>();
        if (response.statusCode != 200) {
          throw StateError(
            'Proyek menolak key atau sedang tidak tersedia (HTTP ${response.statusCode}).',
          );
        }
      } finally {
        http.close(force: true);
      }
    }
    final sdk = await Supabase.initialize(url: projectUrl, publishableKey: key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('publishable_key', key);
    if (mounted) {
      setState(() {
        db = sdk.client;
        busy = false;
        error = null;
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    if (db != null) return AuthGate(db!);
    if (busy) return const Scaffold(body: Center(child: Brand(size: 76)));
    return Welcome(
      title: 'Hubungkan MYRA',
      description:
          'Masukkan publishable key dari proyek Supabase MYRA yang dipakai web.',
      children: [
        TextField(
          controller: keyText,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Supabase publishable key',
            hintText: 'sb_publishable_…',
          ),
        ),
        if (error != null) Text(error!),
        BusyButton('Hubungkan', () => connect(keyText.text.trim())),
      ],
    );
  }
}

class Welcome extends StatelessWidget {
  const Welcome({
    required this.title,
    required this.description,
    required this.children,
    super.key,
  });
  final String title, description;
  final List<Widget> children;
  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Brand(size: 72),
                ),
                const SizedBox(height: 30),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                for (final w in children) ...[w, const SizedBox(height: 14)],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate(this.db, {super.key});
  final SupabaseClient db;
  @override
  State<AuthGate> createState() => _AuthGate();
}

class _AuthGate extends State<AuthGate> {
  StreamSubscription<AuthState>? sub;
  String? user;
  late Myra api;
  Future<bool>? allowed;
  bool recovery = false;
  @override
  void initState() {
    super.initState();
    user = widget.db.auth.currentUser?.id;
    api = Myra(widget.db);
    if (user != null) allowed = api.allowed();
    sub = widget.db.auth.onAuthStateChange.listen(
      (s) {
        if (!mounted) return;
        final next = s.session?.user.id;
        if (next != user || s.event == AuthChangeEvent.passwordRecovery) {
          setState(() {
            user = next;
            api = Myra(widget.db);
            recovery =
                next != null && s.event == AuthChangeEvent.passwordRecovery;
            allowed = next == null ? null : api.allowed();
          });
        }
      },
      onError: (Object e) {
        if (mounted) alert(context, e);
      },
    );
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    if (user == null || recovery) {
      return Login(
        widget.db,
        recover: recovery,
        done: () => setState(() => recovery = false),
      );
    }
    return FutureBuilder<bool>(
      future: allowed,
      builder: (_, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: Brand()));
        }
        if (s.data != true) {
          return Welcome(
            title: s.hasError ? 'Koneksi terganggu' : 'Akun belum terhubung',
            description: s.hasError
                ? readable(s.error!)
                : 'Gunakan akun yang sudah diberi akses ke workspace MYRA di web.',
            children: [
              if (s.hasError)
                TextButton(
                  onPressed: () => setState(() => allowed = api.allowed()),
                  child: const Text('Coba lagi'),
                ),
              BusyButton(
                'Keluar',
                () => widget.db.auth.signOut(scope: SignOutScope.local),
              ),
            ],
          );
        }
        if (widget.db.auth.currentUser?.userMetadata?['myra_adult_confirmed'] !=
            true) {
          return Welcome(
            title: 'Sebelum mulai',
            description:
                'MYRA adalah ruang percakapan dengan karakter AI fiksi untuk pengguna berusia 18 tahun ke atas.',
            children: [
              BusyButton('Saya berusia 18 tahun atau lebih', () async {
                await widget.db.auth.updateUser(
                  UserAttributes(data: {'myra_adult_confirmed': true}),
                );
                if (mounted) setState(() {});
              }),
              BusyButton(
                'Keluar',
                () => widget.db.auth.signOut(scope: SignOutScope.local),
              ),
            ],
          );
        }
        return Home(api, key: ValueKey(user));
      },
    );
  }
}

class Login extends StatefulWidget {
  const Login(this.db, {required this.recover, required this.done, super.key});
  final SupabaseClient db;
  final bool recover;
  final VoidCallback done;
  @override
  State<Login> createState() => _Login();
}

class _Login extends State<Login> {
  final email = TextEditingController(), pass = TextEditingController();
  bool reset = false, hide = true;
  String? info;
  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Welcome(
    title: widget.recover
        ? 'Kata sandi baru'
        : reset
        ? 'Pulihkan akun'
        : 'Masuk ke MYRA',
    description: widget.recover
        ? 'Simpan kata sandi baru untuk akunmu.'
        : reset
        ? 'Tautan pemulihan akan dikirim ke email akunmu.'
        : 'Lanjutkan percakapan dengan karakter dari workspace kamu.',
    children: [
      if (!widget.recover)
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(labelText: 'Email'),
        ),
      if (!reset || widget.recover)
        TextField(
          controller: pass,
          obscureText: hide,
          autofillHints: [
            widget.recover ? AutofillHints.newPassword : AutofillHints.password,
          ],
          decoration: InputDecoration(
            labelText: 'Kata sandi',
            suffixIcon: IconButton(
              tooltip: hide ? 'Tampilkan' : 'Sembunyikan',
              onPressed: () => setState(() => hide = !hide),
              icon: Icon(
                hide
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
      if (info != null) Text(info!, style: const TextStyle(color: pale)),
      BusyButton(
        widget.recover
            ? 'Simpan kata sandi'
            : reset
            ? 'Kirim tautan'
            : 'Masuk',
        () async {
          if (widget.recover) {
            if (pass.text.length < 8) {
              throw StateError('Gunakan minimal 8 karakter.');
            }
            await widget.db.auth.updateUser(
              UserAttributes(password: pass.text),
            );
            widget.done();
          } else if (reset) {
            await widget.db.auth.resetPasswordForEmail(
              email.text.trim(),
              redirectTo: 'id.myra.mobile://auth/recover',
            );
            if (mounted) setState(() => info = 'Periksa kotak masuk emailmu.');
          } else {
            await widget.db.auth.signInWithPassword(
              email: email.text.trim(),
              password: pass.text,
            );
          }
        },
      ),
      if (!widget.recover)
        TextButton(
          onPressed: () => setState(() {
            reset = !reset;
            info = null;
          }),
          child: Text(reset ? 'Kembali ke login' : 'Lupa kata sandi?'),
        ),
    ],
  );
}
