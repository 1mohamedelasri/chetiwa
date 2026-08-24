import 'package:chetiwa/app/theme/chetiwa_theme.dart';
import 'package:chetiwa/features/forecast/presentation/widgets/forecast_pane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('neutral weather icons use the supplied surface contrast color', () {
    final lightContrast = ChetiwaTheme.light.colorScheme.onSurface;

    expect(weatherColor(1, neutralColor: lightContrast), lightContrast);
    expect(weatherColor(2, neutralColor: lightContrast), lightContrast);
    expect(weatherColor(3, neutralColor: lightContrast), lightContrast);
  });
}
