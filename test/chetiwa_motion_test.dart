import 'package:chetiwa/app/theme/chetiwa_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('removes non-essential motion when requested by the system', (
    tester,
  ) async {
    Duration? duration;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              duration = ChetiwaMotion.accessible(
                context,
                ChetiwaMotion.standard,
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(duration, Duration.zero);
  });
}
