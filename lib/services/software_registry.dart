import 'package:flutter/foundation.dart';

/// Bumped by `PackageInstaller` after a successful install/uninstall so the
/// home row and the library grid re-read the `~/software` registry without a
/// app restart. Listeners are expected to be cheap: they re-run their load,
/// which is a quick directory scan.
class SoftwareRegistry extends ChangeNotifier {
  SoftwareRegistry._();

  static final SoftwareRegistry instance = SoftwareRegistry._();

  /// Monotonic revision — listeners that need to detect "did anything change
  /// since I last looked" (e.g. caching) can compare it instead of relying
  /// on listener ordering.
  int _revision = 0;

  int get revision => _revision;

  void notifyChanged() {
    _revision++;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    _revision = 0;
  }
}
