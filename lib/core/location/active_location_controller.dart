import 'dart:async';

import 'package:flutter/foundation.dart';

import 'coordinates.dart';
import 'location_repository.dart';

/// In-memory source of truth for the place currently used across app features.
/// The persisted default remains owned by [LocationRepository].
final class ActiveLocationController extends ChangeNotifier {
  ActiveLocationController(this._repository) {
    unawaited(_restore());
  }

  final LocationRepository _repository;
  ChetiwaLocation? _location;

  ChetiwaLocation? get location => _location;

  Future<void> _restore() async {
    final saved = await _repository.getMainLocation();
    if (saved == null) return;
    _location = saved;
    notifyListeners();
  }

  void setActive(ChetiwaLocation location) {
    _location = location;
    notifyListeners();
  }

  void clear() {
    _location = null;
    notifyListeners();
  }
}
