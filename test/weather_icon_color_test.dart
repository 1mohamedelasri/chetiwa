import 'package:chetiwa/app/theme/chetiwa_tokens.dart';
import 'package:chetiwa/features/forecast/presentation/widgets/forecast_pane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('neutral weather icons use the supplied surface contrast color', () {
    const neutralGray = ChetiwaColors.textSecondary;

    expect(weatherColor(1, neutralColor: neutralGray), neutralGray);
    expect(weatherColor(2, neutralColor: neutralGray), neutralGray);
    expect(weatherColor(3, neutralColor: neutralGray), neutralGray);
  });
}
