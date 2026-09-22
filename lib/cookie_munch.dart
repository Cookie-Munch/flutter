/// Cookie Munch Flutter/Dart SDK — self-hosted Consent Management Platform.
///
/// Full public surface: the pure-Dart consent core plus the [ConsentBanner]
/// Flutter widget. Targets every platform Flutter supports — Android, iOS, macOS,
/// Windows and Linux — because the consent logic is pure Dart and the default
/// storage uses no platform plugin.
///
/// For non-widget code that must stay Flutter-free (e.g. `dart test`, background
/// isolates), import `package:cookie_munch/cookie_munch_core.dart` instead.
library;

export 'src/client.dart';
export 'src/consent_state.dart';
export 'src/localized_copy.dart';
export 'src/storage.dart';
export 'src/consent_banner.dart';
