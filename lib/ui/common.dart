import 'dart:async';
import 'package:flutter/material.dart';
import '../data/myra.dart';

const ink = Color(0xff0b0b0e),
    panel = Color(0xff18181d),
    soft = Color(0xff25232a),
    line = Color(0xff302d35),
    pink = Color(0xfff3a9c4),
    pale = Color(0xfffacadd),
    muted = Color(0xffaaa4b0);
ThemeData theme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: ink,
  colorScheme: const ColorScheme.dark(
    primary: pink,
    onPrimary: Color(0xff302029),
    surface: panel,
    onSurface: Color(0xfffaf6f8),
    secondary: pale,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: ink,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xff121115),
    indicatorColor: Color(0xff432e39),
    height: 70,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: soft,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
  ),
  dividerColor: line,
  listTileTheme: const ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 2),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: pink,
    foregroundColor: ink,
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: panel,
    showDragHandle: true,
  ),
);
void alert(BuildContext c, Object e) {
  if (!c.mounted) return;
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(readable(e)), behavior: SnackBarBehavior.floating),
    );
}

Future<void> runUi(BuildContext c, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (c.mounted) alert(c, e);
  }
}

Future<String?> askText(
  BuildContext c,
  String title, {
  String initial = '',
  int limit = 3000,
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        autofocus: true,
        controller: controller,
        maxLength: limit,
        minLines: 1,
        maxLines: 5,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(d, controller.text.trim());
            }
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  // Dialog animations can keep the TextField mounted after the route completes.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return value;
}

Future<bool> confirm(BuildContext c, String title, String detail) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    ) ??
    false;
void go(BuildContext c, Widget screen) =>
    Navigator.push(c, MaterialPageRoute<void>(builder: (_) => screen));

class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 56});
  final double size;
  @override
  Widget build(BuildContext c) => Image.asset(
    'assets/myra-logo.png',
    width: size,
    height: size,
    semanticLabel: 'MYRA',
  );
}

class Avatar extends StatelessWidget {
  const Avatar(
    this.api,
    this.name, {
    this.path = '',
    this.group = false,
    this.size = 49,
    super.key,
  });
  final Myra api;
  final String name, path;
  final bool group;
  final double size;
  @override
  Widget build(BuildContext c) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e.characters.first.toUpperCase())
        .join();
    final fallback = Center(
      child: group
          ? Icon(Icons.groups_rounded, color: pink, size: size * .48)
          : Text(
              initials,
              style: TextStyle(
                fontSize: size * .32,
                color: pale,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Color.lerp(
          soft,
          const Color(0xff583342),
          (name.runes.fold(0, (a, b) => a + b) % 9) / 10,
        ),
        child: path.isEmpty
            ? fallback
            : FutureBuilder<String>(
                future: api.signed('character-avatars', path),
                builder: (_, s) => s.hasData
                    ? Image.network(
                        s.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => fallback,
                      )
                    : fallback,
              ),
      ),
    );
  }
}

class Empty extends StatelessWidget {
  const Empty(this.icon, this.title, this.detail, {this.action, super.key});
  final IconData icon;
  final String title, detail;
  final Widget? action;
  @override
  Widget build(BuildContext c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: soft,
            child: Icon(icon, color: pink, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(c).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

class Loaded<T> extends StatefulWidget {
  const Loaded({
    super.key,
    required this.load,
    required this.builder,
    this.signal,
  });
  final Future<T> Function() load;
  final Widget Function(T, Future<void> Function()) builder;
  final Listenable? signal;
  @override
  State<Loaded<T>> createState() => _Loaded<T>();
}

class _Loaded<T> extends State<Loaded<T>> {
  T? data;
  Object? error;
  int version = 0;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    widget.signal?.addListener(refresh);
    refresh();
  }

  @override
  void didUpdateWidget(covariant Loaded<T> old) {
    super.didUpdateWidget(old);
    if (old.signal != widget.signal) {
      old.signal?.removeListener(refresh);
      widget.signal?.addListener(refresh);
    }
  }

  @override
  void dispose() {
    widget.signal?.removeListener(refresh);
    super.dispose();
  }

  Future<void> refresh() async {
    final v = ++version;
    try {
      final value = await widget.load();
      if (mounted && v == version) {
        setState(() {
          data = value;
          error = null;
          ready = true;
        });
      }
    } catch (e) {
      if (mounted && v == version) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext c) {
    if (!ready) {
      if (error != null) {
        return Empty(
          Icons.cloud_off_outlined,
          'Gagal memuat',
          readable(error!),
          action: TextButton(
            onPressed: refresh,
            child: const Text('Coba lagi'),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (error != null)
          Material(
            color: soft,
            child: ListTile(
              dense: true,
              title: Text(readable(error!), maxLines: 2),
              trailing: IconButton(
                tooltip: 'Muat ulang',
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
        Expanded(child: widget.builder(data as T, refresh)),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          color: pink,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class BusyButton extends StatefulWidget {
  const BusyButton(this.label, this.action, {super.key});
  final String label;
  final Future<void> Function() action;
  @override
  State<BusyButton> createState() => _BusyButton();
}

class _BusyButton extends State<BusyButton> {
  bool busy = false;
  @override
  Widget build(BuildContext c) => FilledButton(
    onPressed: busy
        ? null
        : () async {
            setState(() => busy = true);
            await runUi(c, widget.action);
            if (mounted) setState(() => busy = false);
          },
    child: busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(widget.label),
  );
}
