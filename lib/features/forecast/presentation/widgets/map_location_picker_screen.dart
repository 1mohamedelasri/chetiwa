import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../app/theme/chetiwa_tokens.dart';
import '../../../../core/l10n/chetiwa_localizations.dart';
import '../../../../core/location/coordinates.dart';
import '../../../../core/location/location_repository.dart';
import '../../../../core/location/location_preferences_store.dart';
import '../../../../core/maps/open_free_map_layer.dart';

/// Full-screen map choice with a fixed centre marker. It stays useful when
/// reverse geocoding is unavailable: coordinates are still a valid weather
/// location and no additional geocoding provider is required.
final class MapLocationPickerScreen extends StatefulWidget {
  const MapLocationPickerScreen({required this.repository, super.key});

  final LocationRepository repository;

  @override
  State<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

final class _MapLocationPickerScreenState
    extends State<MapLocationPickerScreen> {
  static const _initialZoom = 7.0;
  static const _minZoom = 3.0;
  static const _maxZoom = 14.0;

  final MapController _mapController = MapController();
  Timer? _debounce;
  Coordinates _coordinates = Coordinates.paris;
  ChetiwaLocation? _location;
  bool _resolving = true;
  bool _locating = false;
  bool _mapReady = false;
  SavedMapView? _restoredView;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSavedView());
    _resolve(_coordinates);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapCamera position, bool hasGesture) {
    final center = position.center;
    if (!hasGesture) return;
    final coordinates = Coordinates(
      latitude: center.latitude,
      longitude: center.longitude,
    );
    setState(() {
      _coordinates = coordinates;
      _resolving = true;
      _error = null;
    });
    // The viewport is not the selected forecast location. Persisting it
    // separately means users can resume map exploration without silently
    // changing the place used by Graph, Radar, or alerts.
    unawaited(
      LocationPreferencesStore.setMapView(
        coordinates: coordinates,
        zoom: position.zoom,
      ),
    );
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _resolve(coordinates),
    );
  }

  Future<void> _restoreSavedView() async {
    final savedView = await LocationPreferencesStore.getMapView();
    final mainLocation = savedView == null
        ? await widget.repository.getMainLocation()
        : null;
    if (!mounted || (savedView == null && mainLocation == null)) return;
    final view =
        savedView ??
        SavedMapView(
          coordinates: mainLocation!.coordinates,
          zoom: _initialZoom,
        );
    _restoredView = view;
    setState(() {
      _coordinates = view.coordinates;
    });
    if (_mapReady) {
      _mapController.move(
        LatLng(view.coordinates.latitude, view.coordinates.longitude),
        view.zoom.clamp(_minZoom, _maxZoom).toDouble(),
      );
      unawaited(_resolve(view.coordinates));
    }
  }

  Future<void> _resolve(Coordinates coordinates) async {
    final generation = ++_generation;
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final location = await widget.repository.resolveCoordinates(coordinates);
      if (!mounted || generation != _generation) return;
      setState(() {
        _coordinates = coordinates;
        _location = location;
        _resolving = false;
      });
    } on LocationException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _location = ChetiwaLocation(
          city: context.l10n.selectedLocation,
          country: '',
          coordinates: coordinates,
        );
        _resolving = false;
        _error = context.l10n.locationIssue(error);
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final location = await widget.repository.getCurrentLocation();
      if (!mounted) return;
      _mapController.move(
        LatLng(location.coordinates.latitude, location.coordinates.longitude),
        12,
      );
      setState(() {
        _coordinates = location.coordinates;
        _location = location;
        _resolving = false;
        _locating = false;
      });
    } on LocationException catch (error) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _error = context.l10n.locationIssue(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        _location ??
        ChetiwaLocation(
          city: context.l10n.selectedLocation,
          country: '',
          coordinates: _coordinates,
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.chooseOnMap),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.search_rounded),
            label: Text(context.l10n.searchLocation),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(
                _coordinates.latitude,
                _coordinates.longitude,
              ),
              initialZoom: _initialZoom,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              onMapReady: () {
                _mapReady = true;
                final view = _restoredView;
                if (view != null) {
                  _mapController.move(
                    LatLng(
                      view.coordinates.latitude,
                      view.coordinates.longitude,
                    ),
                    view.zoom.clamp(_minZoom, _maxZoom).toDouble(),
                  );
                  unawaited(_resolve(view.coordinates));
                }
              },
              onPositionChanged: _onPositionChanged,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [const OpenFreeMapLayer()],
          ),
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 34),
                child: Icon(
                  Icons.location_pin,
                  color: ChetiwaColors.accentPrimary,
                  size: 54,
                ),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 16,
            right: 16,
            child: _MapHelpCard(
              location: selected,
              resolving: _resolving,
              error: _error,
            ),
          ),
          Positioned(
            right: 16,
            bottom: 180,
            child: FloatingActionButton.small(
              key: const Key('map-current-location-button'),
              tooltip: context.l10n.useCurrentLocation,
              onPressed: _locating ? null : _useCurrentLocation,
              child: _locating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 22,
            child: SafeArea(
              top: false,
              child: FilledButton.icon(
                key: const Key('confirm-map-location-button'),
                onPressed: _resolving
                    ? null
                    : () => Navigator.pop(context, selected),
                icon: const Icon(Icons.check_rounded),
                label: Text(context.l10n.confirmLocation),
              ),
            ),
          ),
          const Positioned(
            left: 8,
            bottom: 90,
            child: Text(
              OpenFreeMapLayer.attribution,
              style: TextStyle(color: ChetiwaColors.textSecondary, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

final class _MapHelpCard extends StatelessWidget {
  const _MapHelpCard({
    required this.location,
    required this.resolving,
    required this.error,
  });

  final ChetiwaLocation location;
  final bool resolving;
  final String? error;

  @override
  Widget build(BuildContext context) => Card(
    color: ChetiwaColors.backgroundPrimary.withValues(alpha: 0.94),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: ChetiwaColors.textPrimary),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            if (resolving)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.place_outlined,
                color: ChetiwaColors.accentPrimary,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    resolving ? context.l10n.moveMapToChoose : location.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    error ??
                        '${location.coordinates.latitude.toStringAsFixed(4)}, '
                            '${location.coordinates.longitude.toStringAsFixed(4)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ChetiwaColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
