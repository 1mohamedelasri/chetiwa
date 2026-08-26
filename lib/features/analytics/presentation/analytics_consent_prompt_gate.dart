import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/chetiwa_localizations.dart';
import '../../monetization/application/app_feature_flag_controller.dart';
import '../application/analytics_consent_controller.dart';

/// Shows the optional data choice once, only when the public rollout flag is
/// enabled. A refusal is persisted and is never treated as consent.
final class AnalyticsConsentPromptGate extends StatefulWidget {
  const AnalyticsConsentPromptGate({
    required this.child,
    required this.navigatorKey,
    super.key,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<AnalyticsConsentPromptGate> createState() =>
      _AnalyticsConsentPromptGateState();
}

final class _AnalyticsConsentPromptGateState
    extends State<AnalyticsConsentPromptGate> {
  bool _dialogScheduled = false;

  @override
  Widget build(BuildContext context) {
    final promptEnabled = context
        .watch<AppFeatureFlagController>()
        .analyticsConsentPromptEnabled;
    final consent = context.watch<AnalyticsConsentController>();
    if (promptEnabled && !consent.hasRecordedChoice && !_dialogScheduled) {
      _dialogScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showChoice());
    }
    return widget.child;
  }

  Future<void> _showChoice() async {
    if (!mounted) return;
    final consent = context.read<AnalyticsConsentController>();
    if (consent.hasRecordedChoice) return;
    final navigatorContext = widget.navigatorKey.currentState?.overlay?.context;
    if (navigatorContext == null) {
      if (mounted) setState(() => _dialogScheduled = false);
      return;
    }
    final allowed = await showDialog<bool>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.analyticsTitle),
        content: Text(context.l10n.analyticsEnableDetail),
        actions: [
          TextButton(
            key: const Key('analytics-consent-decline'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.analyticsDecline),
          ),
          FilledButton(
            key: const Key('analytics-consent-accept'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.analyticsEnable),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await consent.setEnabled(allowed == true);
  }
}
