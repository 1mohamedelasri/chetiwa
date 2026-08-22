import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../location/location_repository.dart';

final class ChetiwaLocalizations {
  const ChetiwaLocalizations(this.locale);

  final Locale locale;
  bool get _fr => locale.languageCode == 'fr';
  bool get isFrench => _fr;

  static const delegate = _ChetiwaLocalizationsDelegate();
  static const supportedLocales = [Locale('fr'), Locale('en')];

  static ChetiwaLocalizations of(BuildContext context) =>
      Localizations.of<ChetiwaLocalizations>(context, ChetiwaLocalizations) ??
      const ChetiwaLocalizations(Locale('fr'));

  String get appTitle => 'Chetiwa — ${_fr ? 'Pluie & Radar' : 'Rain & Radar'}';
  String get share => _fr ? 'Partager' : 'Share';
  String get settings => _fr ? 'Réglages' : 'Settings';
  String get graph => _fr ? 'Graph' : 'Graph';
  String get radar => 'Radar';
  String get forecasts => _fr ? 'Prévisions' : 'Forecast';
  String selectedNavigation(String label) =>
      _fr ? '$label, onglet sélectionné' : '$label, selected tab';
  String selectNavigation(String label) =>
      _fr ? 'Afficher $label' : 'Show $label';
  String selectedOption(String label) =>
      _fr ? '$label, sélectionné' : '$label, selected';
  String selectedLocationLabel(String location) => _fr
      ? 'Lieu sélectionné : $location. Ouvrir le choix du lieu'
      : 'Selected place: $location. Open place picker';
  String recenterOnSelectedLocation(String location) => _fr
      ? 'Recentrer la carte sur le lieu sélectionné : $location'
      : 'Recenter map on selected place: $location';
  String get loadingWeather =>
      _fr ? 'Chargement de la météo…' : 'Loading weather…';
  String get loadingRadar => _fr ? 'Chargement du radar…' : 'Loading radar…';
  String get retry => _fr ? 'Réessayer' : 'Retry';
  String get advertisement => _fr ? 'PUBLICITÉ' : 'ADVERTISEMENT';
  String get chooseCity => _fr ? 'Choisir une ville' : 'Choose a city';
  String get chooseOnMap => _fr ? 'Choisir sur la carte' : 'Choose on map';
  String get moveMapToChoose => _fr
      ? 'Déplacez la carte sous le repère pour choisir un lieu.'
      : 'Move the map under the marker to choose a place.';
  String get confirmLocation =>
      _fr ? 'Confirmer ce lieu' : 'Confirm this place';
  String get searchLocation => _fr ? 'Rechercher' : 'Search';
  String get selectedLocation => _fr ? 'Lieu sélectionné' : 'Selected place';
  String get close => _fr ? 'Fermer' : 'Close';
  String get searchHint => _fr
      ? 'Ville ou code postal dans le monde'
      : 'City or postal code anywhere in the world';
  String get clear => _fr ? 'Effacer' : 'Clear';
  String get clearLocalData =>
      _fr ? 'Effacer les données locales' : 'Clear local data';
  String get clearLocalDataDetail => _fr
      ? 'Lieux enregistrés, cache météo et préférences d’alertes sur cet appareil'
      : 'Saved places, weather cache and alert preferences on this device';
  String get clearLocalDataConfirm => _fr ? 'Effacer maintenant' : 'Clear now';
  String get useCurrentLocation =>
      _fr ? 'Utiliser ma position actuelle' : 'Use my current location';
  String get onDemandLocation => _fr
      ? 'Localisation utilisée uniquement à la demande'
      : 'Location is only used when requested';
  String locationIssue(LocationException error) => switch (error.issue) {
    LocationIssue.serviceDisabled =>
      _fr
          ? 'La localisation est désactivée sur cet appareil.'
          : 'Location services are disabled on this device.',
    LocationIssue.permissionDenied =>
      _fr
          ? 'Autorisation refusée. Autorisez Chetiwa dans les réglages.'
          : 'Permission denied. Allow Chetiwa in Settings.',
    LocationIssue.permissionBlocked =>
      _fr
          ? 'Localisation bloquée. Autorisez Chetiwa dans les réglages.'
          : 'Location is blocked. Allow Chetiwa in Settings.',
    LocationIssue.unavailable =>
      _fr
          ? 'Position indisponible. Activez le GPS puis réessayez.'
          : 'Location unavailable. Enable GPS and try again.',
    LocationIssue.searchUnavailable =>
      _fr
          ? 'Impossible de rechercher une ville pour le moment.'
          : 'City search is unavailable right now.',
    LocationIssue.unknown => error.message,
  };
  String get allowThenRetry => _fr
      ? 'Autorisez la localisation, revenez ici puis réessayez.'
      : 'Allow location access, return here, then try again.';
  String get enableGpsThenRetry => _fr
      ? 'Activez le GPS, revenez ici puis réessayez.'
      : 'Enable GPS, return here, then try again.';
  String get retryCurrentLocationHelp => _fr
      ? 'Après avoir modifié le réglage, touchez à nouveau “Utiliser ma position actuelle”.'
      : 'After changing the setting, tap “Use my current location” again.';
  String get lastKnownLocationNotice => _fr
      ? 'Dernière position connue utilisée. Vérifiez votre GPS si le lieu semble incorrect.'
      : 'The last known location was used. Check GPS if this place seems incorrect.';
  String get approximateLocationNotice => _fr
      ? 'Position approximative utilisée. Activez la localisation précise pour améliorer le résultat.'
      : 'An approximate location was used. Enable precise location to improve the result.';
  String get recent => _fr ? 'RÉCENTES' : 'RECENT';
  String get results => _fr ? 'RÉSULTATS' : 'RESULTS';
  String get popularCities => _fr ? 'VILLES POPULAIRES' : 'POPULAR CITIES';
  String get noCity => _fr
      ? 'Aucune ville trouvée. Essayez avec le pays ou un code postal.'
      : 'No city found. Try adding a country or postal code.';
  String get searchWorldwideHelp => _fr
      ? 'Utilisez la recherche pour trouver n’importe quelle ville ou code postal dans le monde.'
      : 'Use search to find any city or postal code in the world.';
  String get appearance => _fr ? 'Apparence' : 'Appearance';
  String get language => _fr ? 'Langue' : 'Language';
  String get system => _fr ? 'Système' : 'System';
  String get light => _fr ? 'Clair' : 'Light';
  String get dark => _fr ? 'Sombre' : 'Dark';
  String get french => _fr ? 'Français' : 'French';
  String get english => _fr ? 'Anglais' : 'English';
  String get preferences => _fr ? 'Préférences' : 'Preferences';
  String get information => _fr ? 'Informations' : 'Information';
  String get mainLocation => _fr ? 'Lieu principal' : 'Main location';
  String get temperature => _fr ? 'Température' : 'Temperature';
  String get privacy => _fr ? 'Confidentialité' : 'Privacy';
  String get analyticsTitle =>
      _fr ? 'Statistiques d’utilisation' : 'Usage analytics';
  String get analyticsDisabledDetail => _fr
      ? 'Désactivées · aucune statistique Firebase envoyée'
      : 'Off · no Firebase analytics is sent';
  String get analyticsEnabledDetail => _fr
      ? 'Activées · uniquement des événements d’usage anonymisés'
      : 'On · only anonymised usage events';
  String get analyticsEnableDetail => _fr
      ? 'Chetiwa enverra des statistiques d’usage limitées pour améliorer l’application. Elles ne contiennent ni adresse, ni recherche saisie, ni coordonnées précises. Vous pourrez désactiver ce choix à tout moment.'
      : 'Chetiwa will send limited usage statistics to improve the app. They contain no address, typed search, or precise coordinates. You can turn this off at any time.';
  String get analyticsEnable => _fr ? 'Activer' : 'Enable';
  String get analyticsUpdateFailed => _fr
      ? 'Impossible de modifier ce choix pour le moment.'
      : 'This choice could not be updated right now.';
  String get terms => _fr ? 'Conditions d’utilisation' : 'Terms of use';
  String get weatherData => _fr ? 'Données météo' : 'Weather data';
  String get sourcesLicenses =>
      _fr ? 'Sources et licences' : 'Sources and licences';
  String get sourcesLicensesIntro => _fr
      ? 'Chetiwa affiche les attributions des sources utilisées par le MVP. Chaque fournisseur reste soumis à ses propres conditions d’utilisation.'
      : 'Chetiwa displays attribution for the sources used by the MVP. Each provider remains subject to its own terms of use.';
  String get sourcesLicensesNotice => _fr
      ? 'Avant une distribution commerciale, Chetiwa vérifiera et archivera les droits de chaque fournisseur réellement activé.'
      : 'Before commercial distribution, Chetiwa will verify and archive the rights for every provider actually enabled.';
  String get sourceOpenMeteoPurpose =>
      _fr ? 'Prévisions et recherche de lieux' : 'Forecasts and place search';
  String get sourceRainViewerPurpose =>
      _fr ? 'Images radar de précipitations' : 'Precipitation radar imagery';
  String get sourceCartoPurpose => _fr
      ? 'Fond de carte Routes, Clair et Sombre'
      : 'Streets, light and dark map base';
  String get sourceEsriPurpose => _fr
      ? 'Fond satellite, lorsqu’il est sélectionné'
      : 'Satellite map base, when selected';
  String get chooseMainLocationHelp => _fr
      ? 'Choisissez une ville ou un point sur la carte.'
      : 'Choose a city or a point on the map.';
  String savedOnDevice(String location) => _fr
      ? '$location · enregistré sur cet appareil'
      : '$location · saved on this device';
  String get weatherDataSources => _fr
      ? 'Prévisions Open-Meteo · Radar RainViewer'
      : 'Open-Meteo forecast · RainViewer radar';
  String get version => 'Version';
  String get skip => _fr ? 'Passer' : 'Skip';
  String get continueLabel => _fr ? 'Continuer' : 'Continue';
  String get seeGraph => _fr ? 'Voir le Graph' : 'View Graph';
  String get onboardingRainTitle =>
      _fr ? 'La pluie, avant qu’elle arrive.' : 'Rain, before it arrives.';
  String get onboardingRainBody => _fr
      ? 'Chetiwa transforme les prévisions en une réponse simple et immédiate.'
      : 'Chetiwa turns forecasts into a simple, immediate answer.';
  String get onboardingLocationTitle =>
      _fr ? 'La météo là où vous êtes.' : 'Weather where you are.';
  String get onboardingLocationBody => _fr
      ? 'Autorisez votre position pour recevoir une prévision vraiment locale.'
      : 'Allow location access to receive a truly local forecast.';
  String get onboardingReadyTitle => _fr
      ? 'Prêt à sortir au bon moment.'
      : 'Ready to go out at the right time.';
  String get onboardingReadyBody => _fr
      ? 'Graph et Radar sont maintenant à portée de pouce.'
      : 'Graph and Radar are now at your fingertips.';
  String get smartAlertSubtitle => _fr
      ? 'Prévenir avant le début de la pluie'
      : 'Warn me before rain begins';
  String get premiumSubtitle => _fr
      ? 'Alertes intelligentes et zéro publicité'
      : 'Smart alerts and no advertising';
  String get hourlyForecast =>
      _fr ? 'PRÉVISIONS HEURE PAR HEURE' : 'HOURLY FORECAST';
  String get tenDayForecast =>
      _fr ? 'PRÉVISIONS SUR 10 JOURS' : '10-DAY FORECAST';
  String get hourlyUnavailable =>
      _fr ? 'Prévisions horaires indisponibles' : 'Hourly forecast unavailable';
  String get play => _fr ? 'Lecture' : 'Play';
  String get pause => 'Pause';
  String get mapLayers => _fr ? 'Couches de la carte' : 'Map layers';
  String get precipitationRadar =>
      _fr ? 'Radar de précipitations' : 'Precipitation radar';
  String get showRadarEchoes =>
      _fr ? 'Masquer ou afficher les échos radar' : 'Show or hide radar echoes';
  String get noiseReduction => _fr ? 'Réduction du bruit' : 'Noise reduction';
  String get weakEchoes => _fr ? 'Échos faibles' : 'Weak echoes';
  String get opacity => _fr ? 'Opacité' : 'Opacity';
  String mapStyle(String name) => switch (name) {
    'satellite' => 'Satellite',
    'dark' => _fr ? 'Sombre' : 'Dark',
    'light' => _fr ? 'Clair' : 'Light',
    _ => _fr ? 'Routes' : 'Streets',
  };
  String get returnLatestRadar => _fr
      ? 'Revenir à la dernière image radar'
      : 'Return to the latest radar image';
  String get restartPlayback =>
      _fr ? 'Relancer depuis le début' : 'Restart from the beginning';
  String get now => _fr ? 'MAINT.' : 'NOW';
  String get rain => _fr ? 'PLUIE' : 'RAIN';
  String get wind => _fr ? 'VENT O' : 'WIND W';
  String get currentEstimate => _fr ? 'EST. MAINT.' : 'EST. NOW';
  String get offlineCached => _fr
      ? 'Hors-ligne · dernières données enregistrées affichées'
      : 'Offline · showing the latest saved data';
  String get connectionUnavailable =>
      _fr ? 'Connexion indisponible' : 'Connection unavailable';
  String providerUnavailableCached(String provider) => _fr
      ? '$provider indisponible · dernières données conservées'
      : '$provider unavailable · keeping the latest data';
  String get noRadarCoverage => _fr
      ? 'Pas de couverture radar pour ce lieu'
      : 'No radar coverage for this location';
  String invalidProviderCached(String provider) => _fr
      ? 'Réponse $provider invalide · dernières données conservées'
      : 'Invalid $provider response · keeping the latest data';
  String get savedDataMayBeStale => _fr
      ? 'Données enregistrées potentiellement périmées'
      : 'Saved data may be out of date';
  String get cacheRefreshing => _fr
      ? 'Données en cache · actualisation en cours'
      : 'Cached data · refreshing';
  String get savedDataDisplayed =>
      _fr ? 'Données enregistrées affichées' : 'Showing saved data';
  String get refreshing => _fr ? 'Actualisation en cours' : 'Refreshing';
  String dataUpdated(String age) =>
      _fr ? 'Données mises à jour $age' : 'Data updated $age';
  String get offlineTitle => _fr ? 'Vous êtes hors-ligne' : 'You are offline';
  String offlineDetail(String provider) => _fr
      ? 'Reconnectez-vous pour charger les données $provider.'
      : 'Reconnect to load $provider data.';
  String get noCoverageTitle => _fr ? 'Radar non couvert' : 'No radar coverage';
  String get noCoverageDetail => _fr
      ? 'Aucune image radar n’est disponible pour ce lieu actuellement.'
      : 'No radar image is currently available for this location.';
  String get invalidDataTitle =>
      _fr ? 'Données temporairement invalides' : 'Temporarily invalid data';
  String invalidDataDetail(String provider) => _fr
      ? 'Le fournisseur $provider a renvoyé une réponse inutilisable.'
      : '$provider returned an unusable response.';
  String providerUnavailableTitle(String provider) =>
      _fr ? '$provider indisponible' : '$provider unavailable';
  String get providerUnavailableDetail => _fr
      ? 'Le fournisseur ne répond pas pour le moment.'
      : 'The provider is not responding right now.';
  String get modelForecast => _fr ? 'PRÉVISION MODÈLE' : 'MODEL FORECAST';
  String get modelEstimates =>
      _fr ? 'ESTIMATION ET PRÉVISIONS MODÈLE' : 'MODEL ESTIMATE AND FORECAST';
  String get noRainExpected => _fr ? 'AUCUNE PLUIE PRÉVUE' : 'NO RAIN EXPECTED';
  String get strong => _fr ? 'FORTE' : 'HEAVY';
  String get moderate => _fr ? 'MODÉRÉE' : 'MODERATE';
  String get weak => _fr ? 'FAIBLE' : 'LIGHT';
  String hoursAhead(int count) =>
      _fr ? '$count PROCHAINES H' : 'NEXT $count HOURS';
  String rainNear(String time) =>
      _fr ? 'PLUIE VERS $time' : 'RAIN AROUND $time';
  String maximumRainIntensity(String intensity, String timeZone, String time) =>
      _fr
      ? 'Intensité maximale prévue : $intensity · départ $time · fuseau $timeZone'
      : 'Maximum forecast intensity: $intensity · starts $time · time zone $timeZone';
  String rainIntensityName(String name) => switch (name) {
    'light' => _fr ? 'faible' : 'light',
    'moderate' => _fr ? 'modérée' : 'moderate',
    'heavy' => _fr ? 'forte' : 'heavy',
    _ => _fr ? 'aucune' : 'none',
  };
  String get subscriptionComing => _fr
      ? 'Les abonnements arrivent dans une prochaine étape.'
      : 'Subscriptions are coming in a future release.';
  String get privacyChoicesComing => _fr
      ? 'Vos choix de confidentialité resteront accessibles ici.'
      : 'Your privacy choices will remain available here.';
  String weatherCondition(int code) {
    if (_fr) {
      if (code == 0) return 'Ciel dégagé';
      if (code <= 3) return 'Partiellement nuageux';
      if (code <= 48) return 'Brouillard';
      if (code <= 57) return 'Bruine';
      if (code <= 67) return 'Pluie';
      if (code <= 77) return 'Neige';
      if (code <= 82) return 'Averses';
      if (code <= 86) return 'Averses de neige';
      return 'Orage';
    }
    if (code == 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 48) return 'Fog';
    if (code <= 57) return 'Drizzle';
    if (code <= 67) return 'Rain';
    if (code <= 77) return 'Snow';
    if (code <= 82) return 'Showers';
    if (code <= 86) return 'Snow showers';
    return 'Thunderstorm';
  }
}

final class _ChetiwaLocalizationsDelegate
    extends LocalizationsDelegate<ChetiwaLocalizations> {
  const _ChetiwaLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ChetiwaLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<ChetiwaLocalizations> load(Locale locale) =>
      SynchronousFuture(ChetiwaLocalizations(locale));

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<ChetiwaLocalizations> old,
  ) => false;
}

extension ChetiwaLocalizationsContext on BuildContext {
  ChetiwaLocalizations get l10n => ChetiwaLocalizations.of(this);
}
