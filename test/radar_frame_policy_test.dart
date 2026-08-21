import 'package:chetiwa/features/radar/domain/services/radar_frame_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps a bounded window centred on recent observations and nowcast', () {
    final observed = List.generate(20, (index) => 'past-$index');
    final nowcast = List.generate(20, (index) => 'next-$index');

    final selected = RadarFramePolicy.select(observed, nowcast);

    expect(selected, hasLength(RadarFramePolicy.maxFrames));
    expect(selected.first, 'past-8');
    expect(selected[11], 'past-19');
    expect(selected[12], 'next-0');
    expect(selected.last, 'next-11');
  });
}
