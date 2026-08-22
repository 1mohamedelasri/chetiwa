import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/chetiwa_tokens.dart';
import '../../../core/l10n/chetiwa_localizations.dart';

final class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

final class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  var _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      (
        icon: Icons.umbrella_outlined,
        title: context.l10n.onboardingRainTitle,
        body: context.l10n.onboardingRainBody,
      ),
      (
        icon: Icons.location_on_outlined,
        title: context.l10n.onboardingLocationTitle,
        body: context.l10n.onboardingLocationBody,
      ),
      (
        icon: Icons.check_circle_outline,
        title: context.l10n.onboardingReadyTitle,
        body: context.l10n.onboardingReadyBody,
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ChetiwaSpacing.x6),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go('/weather'),
                  child: Text(context.l10n.skip),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  onPageChanged: (value) => setState(() => _page = value),
                  itemBuilder: (context, index) {
                    final page = pages[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: const BoxDecoration(
                            color: ChetiwaColors.surfaceSecondary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            page.icon,
                            size: 58,
                            color: ChetiwaColors.accentPrimary,
                          ),
                        ),
                        const SizedBox(height: ChetiwaSpacing.x8),
                        Text(
                          page.title,
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: ChetiwaSpacing.x4),
                        Text(
                          page.body,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: ChetiwaColors.textSecondary,
                                height: 1.5,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  pages.length,
                  (index) => AnimatedContainer(
                    duration: ChetiwaMotion.accessible(
                      context,
                      ChetiwaMotion.fast,
                    ),
                    width: index == _page ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: index == _page
                          ? ChetiwaColors.accentPrimary
                          : ChetiwaColors.borderDefault,
                      borderRadius: BorderRadius.circular(ChetiwaRadius.full),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: ChetiwaSpacing.x6),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    if (_page == pages.length - 1) {
                      context.go('/weather');
                    } else {
                      _controller.nextPage(
                        duration: ChetiwaMotion.accessible(
                          context,
                          ChetiwaMotion.standard,
                        ),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                  child: Text(
                    _page == pages.length - 1
                        ? context.l10n.seeGraph
                        : context.l10n.continueLabel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
