import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/location/active_location_controller.dart';
import '../../../core/location/location_repository.dart';
import '../../../features/forecast/presentation/widgets/weather_chrome.dart';
import '../application/saved_places_controller.dart';
import '../domain/premium_entitlement.dart';

final class SavedPlacesScreen extends StatelessWidget {
  const SavedPlacesScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final places = context.read<SavedPlacesController>();
    final selected = await showChetiwaLocationPicker(
      context,
      repository: context.read<LocationRepository>(),
    );
    if (selected == null || !context.mounted) return;
    final nameController = TextEditingController(text: selected.city);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nom du lieu'),
        content: TextField(controller: nameController, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => dialogContext.pop(nameController.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || !context.mounted) return;
    final added = await places.add(name: name, location: selected);
    if (!added && context.mounted) context.push('/subscription');
  }

  @override
  Widget build(BuildContext context) {
    final places = context.watch<SavedPlacesController>();
    final entitlement = context.watch<EntitlementController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Mes lieux')),
      floatingActionButton: FloatingActionButton(
        onPressed: places.canAdd
            ? () => _add(context)
            : () => context.push('/subscription'),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(
              entitlement.isPremium
                  ? '${places.places.length}/${places.limits.maxSavedPlaces} lieux utilisés'
                  : 'Free : ${places.places.length}/${places.limits.maxSavedPlaces} lieu principal',
            ),
            subtitle: Text(
              entitlement.isPremium
                  ? 'Lieux nommés Chetiwa+'
                  : 'Passez à Chetiwa+ pour ajouter des lieux.',
            ),
          ),
          for (final place in places.places)
            Card(
              child: ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(place.name),
                subtitle: Text(place.location.label),
                onTap: () => context.read<ActiveLocationController>().setActive(
                  place.location,
                ),
                trailing: IconButton(
                  tooltip: 'Supprimer',
                  onPressed: () => places.remove(place.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
