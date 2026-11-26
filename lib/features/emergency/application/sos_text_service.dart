import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_notice.dart';
import '../../companion/presentation/companion_common.dart';
import '../../settings/services/trusted_contact_service.dart';
import '../../zones/domain/zone_presence.dart';
import '../../zones/services/location_service.dart';
import '../domain/sos_text.dart';

/// The user-edited SOS text template, or the default when unset.
class SosTextTemplateNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizeSosTextTemplate(prefs.getString(sosTextTemplateKey));
  }

  /// Stores [value] as typed (may be blank, meaning "use the default").
  Future<void> set(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(sosTextTemplateKey);
      state = const AsyncData(defaultSosTextTemplate);
      return;
    }
    final saved = trimmed.length > sosTextTemplateMaxLength
        ? trimmed.substring(0, sosTextTemplateMaxLength)
        : trimmed;
    await prefs.setString(sosTextTemplateKey, saved);
    state = AsyncData(normalizeSosTextTemplate(saved));
  }
}

final sosTextTemplateProvider =
    AsyncNotifierProvider<SosTextTemplateNotifier, String>(
      SosTextTemplateNotifier.new,
    );

/// Fast location for a text: a current fix if it arrives quickly, otherwise
/// the last known one. Never throws. Does not prompt for permission — if we
/// don't already have it, the text just goes without a pin.
Future<LocationFix?> resolveSosFix(
  LocationService location, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    final access = await location.access();
    if (access != LocationAccess.whileInUse &&
        access != LocationAccess.always) {
      // A last-known pin can still be used if the platform will hand it
      // over without a prompt (cached). Otherwise we send no location.
      return await location.lastKnownFix();
    }
    return await location.quickFix(timeout: timeout);
  } catch (_) {
    try {
      return await location.lastKnownFix();
    } catch (_) {
      return null;
    }
  }
}

/// Opens the phone's SMS composer, prefilled, and never sends. Test seams
/// cover the contact, the template, the fix, and the launcher.
Future<bool> openSosTextComposer(
  BuildContext context, {
  TrustedContact? contact,
  String? template,
  LocationFix? fix,
  DateTime? now,
  Future<LocationFix?> Function()? resolveFix,
  Future<bool> Function(Uri uri)? launcher,
  LocationService? location,
}) async {
  final resolved =
      fix ??
      await (resolveFix ??
          () => resolveSosFix(
            location ??
                ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(locationServiceProvider),
          ))();
  if (!context.mounted) return false;
  final body = composeSosText(template: template, fix: resolved, now: now);
  final uri = sosTextUri(body: body, phone: contact?.phone);
  bool opened;
  try {
    opened =
        await (launcher ??
            (u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    AppNotice.show(
      context,
      'COULD NOT OPEN MESSAGES // TEXT SOMEONE YOU TRUST.',
      type: AppNoticeType.error,
    );
    return false;
  }
  if (contact == null && context.mounted) {
    AppNotice.show(
      context,
      'No SOS contact saved yet (Settings > Trusted contact). '
      'Pick someone you trust, then press Send.',
      type: AppNoticeType.info,
    );
  }
  return opened;
}

/// Resolves the saved contact and template, then opens the composer.
/// Safe to call from a lock screen, a zone alert, or the dashboard.
Future<bool> holdToTextSos(
  BuildContext context,
  WidgetRef ref, {
  Future<bool> Function(Uri uri)? launcher,
  Future<LocationFix?> Function()? resolveFix,
  LocationFix? fix,
  DateTime? now,
}) async {
  TrustedContact? contact;
  try {
    contact = await ref.read(trustedContactProvider.future);
  } catch (_) {
    contact = null;
  }
  if (!context.mounted) return false;
  final template =
      ref.read(sosTextTemplateProvider).valueOrNull ?? defaultSosTextTemplate;
  return openSosTextComposer(
    context,
    contact: contact,
    template: template,
    fix: fix,
    now: now,
    resolveFix: resolveFix,
    launcher: launcher,
    location: ref.read(locationServiceProvider),
  );
}
