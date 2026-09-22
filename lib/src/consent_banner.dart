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
    this.title,
    this.message,
    this.acceptLabel,
    this.rejectLabel,
    this.primaryColor = kCookieMunchPrimary,
  });

  /// The client to drive. Defaults to [CookieMunchConsent.instance].
  final CookieMunchConsent? consent;

  /// Copy overrides. Left null, the banner uses the words the server resolved for this
  /// device's language, and falls back to English until that answer arrives — a prompt that
  /// waits for the network is a prompt that does not ask.
  final String? title;
  final String? message;
  final String? acceptLabel;
  final String? rejectLabel;
  final Color primaryColor;

  @override
  State<ConsentBanner> createState() => _ConsentBannerState();
}

class _ConsentBannerState extends State<ConsentBanner> {
  StreamSubscription<ConsentState>? _sub;
  late CookieMunchConsent _consent;

  /// Caller's words, then the server's for this device's language, then English.
  String get _title => widget.title ?? _consent.copy?.title ?? 'We value your privacy';
  String get _message =>
      widget.message ??
      _consent.copy?.body ??
      'We use cookies and similar technologies to improve your experience. '
          'You decide what we use.';
  String get _acceptLabel => widget.acceptLabel ?? _consent.copy?.acceptAll ?? 'Allow all';
  String get _rejectLabel => widget.rejectLabel ?? _consent.copy?.rejectAll ?? 'Reject all';

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
    // Right-to-left copy laid out left-to-right puts the buttons on the wrong side of a
    // sentence the reader scans the other way.
    final rtl = _consent.copy?.rtl == true;
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : Directionality.of(context),
      child: Material(
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
                _title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _message,
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
                      child: Text(_rejectLabel),
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
                      child: Text(_acceptLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
