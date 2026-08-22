import 'package:flutter_test/flutter_test.dart';

import 'package:chetiwa/features/radar/domain/services/radar_usage_policy.dart';

void main() {
  test('free and premium policies expose visible limits', () {
    expect(RadarUsagePolicy.freeDefault.maxFrames, 12);
    expect(RadarUsagePolicy.freeDefault.maxZoom, 10);
    expect(RadarUsagePolicy.premiumDefault.maxFrames, 24);
    expect(RadarUsagePolicy.premiumDefault.maxZoom, 12);
  });

  test('frame selection keeps the latest observation and bounded nowcast', () {
    final frames = List.generate(30, (index) => index);
    expect(
      RadarUsagePolicy.freeDefault.selectFrameIndexes(frames),
      orderedEquals(List.generate(12, (index) => index + 18)),
    );
  });
}
