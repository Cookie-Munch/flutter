/// Pure-Dart core of the Cookie Munch SDK — the consent client, state model and
/// storage. **No Flutter imports**, so it runs on every platform (mobile and
/// desktop) and is testable with plain `dart test`.
///
/// Import this from non-widget code (services, background isolates, tests). For
/// the [ConsentBanner] widget, import `package:cookie_munch/cookie_munch.dart`.
library;

export 'src/client.dart';
export 'src/consent_state.dart';
export 'src/storage.dart';
