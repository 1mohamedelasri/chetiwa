# Chetiwa

**La pluie, avant qu’elle arrive.**

Chetiwa is a Flutter weather app built around one product rule: one opening should provide one useful answer. The current milestone implements the app foundation, live forecast and radar providers, and stale-while-revalidate caching.

## Run

```sh
flutter pub get
flutter run
```

Pour utiliser le backend Chetiwa local sur iOS Simulator :

```sh
cd backend && docker compose up --build
flutter run \
  --dart-define=CHETIWA_API_BASE_URL=http://127.0.0.1:8080 \
  --dart-define=CHETIWA_ALLOW_DIRECT_PROVIDER_FALLBACK=false
```

Sur Android Emulator, remplacer l’hôte par `http://10.0.2.2:8080`. Le trafic
HTTP local est autorisé uniquement par le manifeste Android `debug` ; une build
production Chetiwa exige HTTPS :

```sh
flutter build appbundle \
  --dart-define=CHETIWA_ENV=production \
  --dart-define=CHETIWA_API_BASE_URL=https://chetiwa-api.ezplatforms.com
```

Sans `CHETIWA_API_BASE_URL`, le profil développement conserve provisoirement
les appels directs existants. Ce fallback est automatiquement interdit lorsque
`CHETIWA_ENV=production`.

The free app uses OpenFreeMap. Esri World Imagery is an optional Chetiwa+
feature and stays disabled unless the remote cost switch and a licensed Esri
key are both configured:

```sh
flutter run --dart-define=ARCGIS_API_KEY=your_key
```

## Verify

```sh
flutter analyze
flutter test
```

## Implemented

- Material 3 Chetiwa design tokens and dark theme
- declarative routing for weather, onboarding, settings, subscription, and privacy
- feature-first Presentation → Application/BLoC → Domain → Repository → Data Source layers
- Weather Brief and live metrics
- interactive rain graph with 2-hour and 24-hour horizons
- interactive regional radar map with satellite imagery plus selectable dark,
  light, and road bases, RainViewer overlays, a compact regional-echo legend,
  point-specific rain status, default low-reflectivity noise suppression, an
  intensity-linked gray context halo, optional weak-echo view, source-palette
  and opacity controls, pan/pinch/double-tap city zoom/recenter, one-pass
  historical animation, and a draggable red time ruler with explicit
  Historical/Now status
- reserved adaptive banner slot between weather content and navigation so ads
  never cover Graph, Radar, Forecast, or their controls
- backend-ready Open-Meteo 15-minute forecast data through the Chetiwa API
- live hourly conditions and 10-day forecast tab
- city picker that refreshes Graph, Radar, and Forecast together
- worldwide city/postal-code search in French, recent locations, popular-city
  suggestions, and an explicit foreground-only current-location action
- Chetiwa-proxied radar metadata and live XYZ overlays
- private random installation identifier for API throttling, unrelated to ads
- mobile ETag reuse plus the existing disk stale-while-revalidate cache
- disk-backed stale-while-revalidate forecast and radar caches
- five provider-independent weather fixtures
- onboarding and settings foundations
- unit and widget tests for provider mapping and Graph/Radar/Forecast navigation

## Fixture scenarios

The default scenario is `light_rain`. Change `fixtureName` in `ChetiwaDependencies` through `FixtureForecastDataSource` to preview:

- `dry`
- `light_rain`
- `heavy_rain`
- `multiple_showers`
- `storm`

Widget tests still use the deterministic fixture dependencies. The normal app entry point uses live provider dependencies.

### Real-device notification test

To test the operating-system notification without waiting for rain, run a
development build with the notification fixture enabled:

```sh
flutter run --dart-define=CHETIWA_ENV=development \
  --dart-define=CHETIWA_NOTIFICATION_TEST_MODE=true
```

On the device, choose **Paris, France** as the main location, allow
notifications, and enable Smart Rain Alerts. The fixture contains moderate
rain beginning in about two minutes, so the app schedules a real local
notification. Close the app and wait for it. This switch is development-only
and is ignored when `CHETIWA_ENV=production`.

## Android network troubleshooting

The live app needs Internet access on a first launch. If an Android emulator
shows a Wi-Fi icon but the app cannot load, verify the emulator itself before
debugging Flutter:

```sh
adb -s <device-id> shell ping -c 1 10.0.2.2
```

If Android reports `Network is unreachable`, cold-boot or reboot that emulator
and retry. With the proxy enabled, also open `http://10.0.2.2:8080/healthz` in
the emulator browser. Once live data has been loaded, Chetiwa uses its disk
cache while it revalidates in the background.

See [the data-provider strategy](docs/data-provider-strategy.md) for licensing, production-provider, cost, and API-key guidance.

See [the production roadmap](ROADMAP.md) for the ordered plan covering product
completion, map-based location selection, notifications, monetization, privacy,
security, store readiness, release, and operations.

Accepted product and architecture decisions are indexed in
[the ADR register](docs/decisions/README.md). The initial Free/Premium split,
launch scope, cost guardrails, and provider compliance register live under
`docs/product`, `docs/business`, and `docs/compliance`.
