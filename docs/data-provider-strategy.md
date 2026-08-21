# Chetiwa data-provider strategy

## Current development stack

| Product need | Development provider | Resolution | Authentication |
| --- | --- | --- | --- |
| Weather Brief, 2H and 24H Graph | Open-Meteo Forecast API | 15-minute precipitation around Paris, backed by models including Météo-France AROME | No key for evaluation |
| Radar observations and timeline | RainViewer Weather Maps API | Approximately 10-minute radar frames for the previous two hours | No key for personal/prototype use |

The application never exposes provider response models to the UI. Both integrations map into Chetiwa `Forecast`, `RainPoint`, `RainWindow`, `WeatherBrief`, and `RadarFrame` entities.

## Production recommendation

Before a public monetized beta:

1. Use Rainbow Nowcast for the signature 0–4 hour experience. It provides one-minute precipitation estimates and is a better fit for “rain in X minutes” than an hourly forecast.
2. Use Rainbow Tiles for current and forecast radar layers so the nowcast and map tell the same story.
3. Retain Open-Meteo for general 24-hour weather, or move that request to Rainbow Weather if a single commercial contract is operationally preferable.
4. Select a production basemap provider with explicit mobile/commercial terms. Chetiwa currently uses its local dark map artwork beneath the live radar layer and does not depend on OpenStreetMap's community tile servers.

## Cost timing

No payment is required while developing and validating the MVP. The current APIs are configured only for evaluation/prototype usage. Commercial API terms must be activated before monetization or public production traffic.

Open-Meteo commercial access can be enabled without code changes:

```sh
flutter run --dart-define=OPEN_METEO_API_KEY=your_key
```

When the key is present, Chetiwa automatically switches from `api.open-meteo.com` to `customer-api.open-meteo.com`.

## Stale-while-revalidate behavior

Forecasts are cached for immediate startup and considered stale after 30 minutes. Radar metadata is cached and considered stale after 15 minutes.

On launch:

1. Read the last Chetiwa domain model from local storage.
2. Render it immediately, even if stale.
3. Fetch fresh provider data in the background.
4. Silently replace the visible state.
5. If refresh fails, keep the cached state instead of showing a blank screen.
