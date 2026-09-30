import 'dart:io';

// Flutter's test font and icon rasterization differs between macOS and Linux.
// Keep exact comparisons against reviewed host baselines; do not relax pixel
// tolerances or regenerate references automatically in CI.
String platformGoldenFile(String fileName) =>
    switch (Platform.operatingSystem) {
      'macos' => 'goldens/$fileName',
      'linux' => 'goldens/linux/$fileName',
      final host => throw UnsupportedError(
        'No reviewed golden baseline for $host',
      ),
    };
