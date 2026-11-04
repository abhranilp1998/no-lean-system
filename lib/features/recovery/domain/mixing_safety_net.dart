import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// (B) What the mixing / overdose safety net offers. Contact first, always;
/// 112 only behind a second tap. No hotline buttons anywhere else.
enum MixingSafetyNet { off, contactOnly, contactAnd112 }

extension MixingSafetyNetCopy on MixingSafetyNet {
  String get label => switch (this) {
    MixingSafetyNet.off => 'Off',
    MixingSafetyNet.contactOnly => 'SOS contact only',
    MixingSafetyNet.contactAnd112 => 'SOS contact, then 112',
  };

  bool get showsContact => this != MixingSafetyNet.off;
  bool get shows112 => this == MixingSafetyNet.contactAnd112;
}

const mixingSafetyNetKey = 'mixing_safety_net_v1';
const defaultMixingSafetyNet = MixingSafetyNet.contactAnd112;

MixingSafetyNet parseMixingSafetyNet(String? raw) =>
    MixingSafetyNet.values.where((v) => v.name == raw).firstOrNull ??
    defaultMixingSafetyNet;

/// The ready text for "Ping my SOS contact now". Plain, no drama.
const mixingPingText =
    'Hey, I mixed / used and I want someone to know. '
    'Can you call me or come check on me now?';

class MixingSafetyNetNotifier extends AsyncNotifier<MixingSafetyNet> {
  @override
  Future<MixingSafetyNet> build() async {
    final prefs = await SharedPreferences.getInstance();
    return parseMixingSafetyNet(prefs.getString(mixingSafetyNetKey));
  }

  Future<void> set(MixingSafetyNet value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(mixingSafetyNetKey, value.name);
    state = AsyncData(value);
  }
}

final mixingSafetyNetProvider =
    AsyncNotifierProvider<MixingSafetyNetNotifier, MixingSafetyNet>(
      MixingSafetyNetNotifier.new,
    );
