import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/location/coordinates.dart';
import '../data/saved_places_store.dart';
import '../domain/premium_entitlement.dart';
import '../domain/premium_limits.dart';
import '../domain/saved_place.dart';

final class SavedPlacesController extends ChangeNotifier {
  SavedPlacesController({
    required EntitlementController entitlement,
    SavedPlacesStore store = const SavedPlacesStore(),
    bool persist = true,
  }) : _entitlement = entitlement,
       _store = store,
       _persist = persist {
    _entitlement.addListener(_onEntitlementChanged);
    if (persist) unawaited(_restore());
  }

  final EntitlementController _entitlement;
  final SavedPlacesStore _store;
  final bool _persist;
  List<SavedPlace> _places = const [];

  List<SavedPlace> get places => List.unmodifiable(_places);
  PremiumLimits get limits => PremiumLimits.forEntitlement(_entitlement);
  bool get canAdd => _places.length < limits.maxSavedPlaces;

  Future<bool> add({
    required String name,
    required ChetiwaLocation location,
  }) async {
    if (!canAdd) return false;
    final normalized = name.trim();
    if (normalized.isEmpty) return false;
    final place = SavedPlace(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: normalized,
      location: location,
    );
    _places = [..._places, place];
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> rename(String id, String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    _places = _places
        .map(
          (place) => place.id == id
              ? SavedPlace(
                  id: place.id,
                  name: normalized,
                  location: place.location,
                )
              : place,
        )
        .toList(growable: false);
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _places = _places.where((place) => place.id != id).toList(growable: false);
    notifyListeners();
    await _save();
  }

  Future<void> setLocation(String id, ChetiwaLocation location) async {
    _places = _places
        .map(
          (place) => place.id == id
              ? SavedPlace(id: place.id, name: place.name, location: location)
              : place,
        )
        .toList(growable: false);
    notifyListeners();
    await _save();
  }

  Future<void> _restore() async {
    _places = await _store.read();
    notifyListeners();
  }

  Future<void> _save() async {
    if (_persist) await _store.write(_places);
  }

  void _onEntitlementChanged() {
    if (_places.length > limits.maxSavedPlaces) {
      _places = _places.take(limits.maxSavedPlaces).toList(growable: false);
      unawaited(_save());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _entitlement.removeListener(_onEntitlementChanged);
    super.dispose();
  }
}
