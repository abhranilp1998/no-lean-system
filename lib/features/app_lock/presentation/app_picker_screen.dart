import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/app_lock_providers.dart';
import '../domain/locked_app.dart';
import '../domain/never_lockable.dart';
import '../services/app_lock_gateway.dart';

/// Lists launchable apps; never-lockable ones are shown but can't be
/// picked. Returns the new locked-app list, or null when cancelled.
class AppPickerScreen extends ConsumerStatefulWidget {
  const AppPickerScreen({required this.selected, super.key});

  final List<LockedApp> selected;

  static Future<List<LockedApp>?> open(
    BuildContext context, {
    required List<LockedApp> selected,
  }) => Navigator.of(context).push<List<LockedApp>>(
    MaterialPageRoute(builder: (_) => AppPickerScreen(selected: selected)),
  );

  @override
  ConsumerState<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends ConsumerState<AppPickerScreen> {
  late final Future<List<InstalledAppInfo>> _apps = ref
      .read(appLockGatewayProvider)
      .installedApps();
  late final Map<String, LockedApp> _picked = {
    for (final app in widget.selected) app.packageName: app,
  };
  String _query = '';

  void _toggle(InstalledAppInfo info, bool on) => setState(() {
    if (on) {
      _picked[info.packageName] =
          _picked[info.packageName] ??
          LockedApp(
            packageName: info.packageName,
            label: info.label,
            paymentApp: isSuggestedPaymentApp(info.packageName),
          );
    } else {
      _picked.remove(info.packageName);
    }
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('app-picker'),
      appBar: AppBar(
        title: Text(
          'CHOOSE APPS',
          style: displayFont(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            key: const ValueKey('app-picker-done'),
            onPressed: () => Navigator.pop(context, _picked.values.toList()),
            child: const Text('DONE'),
          ),
        ],
      ),
      body: FutureBuilder<List<InstalledAppInfo>>(
        future: _apps,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final query = _query.toLowerCase();
          final apps = snapshot.data!
              .where(
                (app) =>
                    query.isEmpty ||
                    app.label.toLowerCase().contains(query) ||
                    app.packageName.contains(query),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 30),
            children: [
              TextField(
                key: const ValueKey('app-picker-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search apps',
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
              if (snapshot.data!.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No apps found. App lock needs Android.',
                    style: TextStyle(color: muted),
                  ),
                ),
              for (final app in apps)
                Builder(
                  builder: (context) {
                    final protected =
                        app.neverLockable || isNeverLockable(app.packageName);
                    return CheckboxListTile(
                      key: ValueKey('app-picker-${app.packageName}'),
                      title: Text(app.label),
                      subtitle: Text(
                        protected
                            ? 'Always allowed // never locked'
                            : isSuggestedPaymentApp(app.packageName)
                            ? 'Payment app // quick unlock path'
                            : app.packageName,
                        style: microStyle,
                      ),
                      value: !protected && _picked.containsKey(app.packageName),
                      onChanged: protected
                          ? null
                          : (value) => _toggle(app, value ?? false),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
