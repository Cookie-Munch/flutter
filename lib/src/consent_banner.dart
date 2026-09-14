import 'dart:async';

import 'package:flutter/material.dart';

import 'client.dart';
import 'consent_state.dart';

/// Cookie Munch brand primary, matching the web/iOS/Android/RN banners.
const Color kCookieMunchPrimary = Color(0xFF0E6E5C);

/// A themed bottom consent banner wired to a [CookieMunchConsent] client.
///
/// It renders only until the user has responded (`!consent.hasResponse`) and
/// rebuilds itself by subscribing to the client's [CookieMunchConsent.changes]
/// stream. Works on mobile and desktop alike.
///
/// Place it at the bottom of your root scaffold, e.g. inside a [Stack]:
/// ```dart
/// Stack(children: [
///   child,
///   const Align(alignment: Alignment.bottomCenter, child: ConsentBanner()),
/// ]);
/// ```
class ConsentBanner extends StatefulWidget {
  const ConsentBanner({
    super.key,
    this.consent,
    this.title = 'We value your privacy',
    this.message =
        'We use cookies and similar technologies to improve your experience. '
            'You decide what we use.',
    this.acceptLabel = 'Allow all',
    this.rejectLabel = 'Reject all',
    this.primaryColor = kCookieMunchPrimary,
  });

  /// The client to drive. Defaults to [CookieMunchConsent.instance].
  final CookieMunchConsent? consent;

  final String title;
  final String message;
  final String acceptLabel;
  final String rejectLabel;
  final Color primaryColor;

  @override
  State<ConsentBanner> createState() => _ConsentBannerState();
}

class _ConsentBannerState extends State<ConsentBanner> {
  StreamSubscription<ConsentState>? _sub;
  late CookieMunchConsent _consent;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(ConsentBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.consent != oldWidget.consent) {
      _sub?.cancel();
      _bind();
    }
  }

  void _bind() {
    _consent = widget.consent ?? CookieMunchConsent.instance;
    _sub = _consent.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_consent.hasResponse) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                widget.message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _consent.rejectAll(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(widget.rejectLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _consent.acceptAll(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(widget.acceptLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
