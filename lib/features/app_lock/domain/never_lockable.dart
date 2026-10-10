// Apps that can never be locked, whatever the user picks: calling for help,
// emergency/SOS, getting somewhere, NO LEAN itself, system settings and the
// home screen. The native side adds the device's own default dialer,
// launcher, settings and map handlers at runtime (`AppLockProtected.kt`).

/// NO LEAN's own application IDs (release and side-by-side preview).
const noLeanPackages = {'com.nolean.no_lean', 'com.nolean.no_lean.preview'};

/// Known packages that are never lockable on any device.
const neverLockablePackages = <String>{
  ...noLeanPackages,
  // Phone / dialer / emergency calling.
  'com.android.dialer',
  'com.google.android.dialer',
  'com.samsung.android.dialer',
  'com.samsung.android.incallui',
  'com.android.phone',
  'com.android.server.telecom',
  'com.android.incallui',
  'com.android.contacts',
  'com.google.android.contacts',
  'com.samsung.android.app.contacts',
  'com.oneplus.dialer',
  'com.coloros.dialer',
  'com.oplus.dialer',
  'com.android.emergency',
  'com.google.android.apps.safetyhub',
  'com.samsung.android.emergencymode.service',
  'com.android.cellbroadcastreceiver',
  'com.google.android.cellbroadcastreceiver',
  // Maps / navigation.
  'com.google.android.apps.maps',
  'com.google.android.apps.mapslite',
  'com.waze',
  'net.osmand',
  'net.osmand.plus',
  'app.organicmaps',
  'com.mapswithme.maps.pro',
  'com.here.app.maps',
  'com.mmi.maps',
  'com.mappls.app.navigator',
  'com.sygic.aura',
  // System settings and core UI.
  'com.android.settings',
  'com.samsung.android.settings',
  'com.android.systemui',
  'com.google.android.permissioncontroller',
  'com.android.permissioncontroller',
  'com.android.packageinstaller',
  'com.google.android.packageinstaller',
  // Launchers / home screens.
  'com.android.launcher',
  'com.android.launcher2',
  'com.android.launcher3',
  'com.google.android.apps.nexuslauncher',
  'com.sec.android.app.launcher',
  'com.miui.home',
  'com.mi.android.globallauncher',
  'com.oppo.launcher',
  'com.coloros.launcher',
  'com.oplus.launcher',
  'net.oneplus.launcher',
  'com.realme.launcher',
  'com.vivo.launcher',
  'com.bbk.launcher2',
  'com.huawei.android.launcher',
  'com.motorola.launcher3',
  'com.teslacoilsw.launcher',
};

/// Package prefixes that are never lockable (vendor dialers/settings).
const _neverLockablePrefixes = ['com.android.settings.', 'com.nolean.no_lean.'];

/// Whether [packageName] can never be locked. [extra] carries the
/// device-specific packages the native side reports (default dialer,
/// launcher, settings, map handlers).
bool isNeverLockable(String packageName, {Set<String> extra = const {}}) {
  final name = packageName.trim();
  if (name.isEmpty) return true;
  if (neverLockablePackages.contains(name) || extra.contains(name)) {
    return true;
  }
  return _neverLockablePrefixes.any(name.startsWith);
}

/// Suggested "payment apps" (quick exit path), by package name.
const suggestedPaymentPackages = <String, String>{
  'com.google.android.apps.nbu.paisa.user': 'Google Pay',
  'com.phonepe.app': 'PhonePe',
  'net.one97.paytm': 'Paytm',
  'in.org.npci.upiapp': 'BHIM',
};

bool isSuggestedPaymentApp(String packageName) =>
    suggestedPaymentPackages.containsKey(packageName);
