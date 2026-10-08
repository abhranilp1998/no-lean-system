/// Why the app shell is currently behind the PIN/biometric wall.
enum AppLockReason { riskWindow, relapseLogged }

/// In-memory unlock bookkeeping for the app-level lock.
///
/// Persisted facts (PIN enabled, risk-window wall toggle, post-relapse relock)
/// live in `RecoveryController`. This class only tracks whether the user has
/// already unlocked during the current risk-window occurrence, and expires
/// that unlock when the app returns from the background after [backgroundGrace]
/// (short system dialogs such as the biometric prompt do not re-lock).
class AppLockSession {
  AppLockSession({this.backgroundGrace = const Duration(seconds: 30)});

  final Duration backgroundGrace;
  bool _windowUnlocked = false;
  DateTime? _backgroundedAt;

  void onBackgrounded(DateTime now) => _backgroundedAt ??= now;

  void onResumed(DateTime now) {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since != null && now.difference(since) >= backgroundGrace) {
      _windowUnlocked = false;
    }
  }

  void onUnlocked() => _windowUnlocked = true;

  /// Returns the active lock reason, or null when the shell may be shown.
  ///
  /// Leaving the risk window forgets the previous unlock, so the next window
  /// occurrence locks again.
  AppLockReason? resolve({
    required bool relockPending,
    required bool riskWindowWallArmed,
    required bool inRiskWindow,
  }) {
    if (!inRiskWindow) _windowUnlocked = false;
    if (relockPending) return AppLockReason.relapseLogged;
    if (riskWindowWallArmed && inRiskWindow && !_windowUnlocked) {
      return AppLockReason.riskWindow;
    }
    return null;
  }
}
